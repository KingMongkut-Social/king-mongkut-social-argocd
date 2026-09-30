#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-king-mongkut-social-production}"
missing=0
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
production_dir="${script_dir}/../apps/production"
secrets_file="${production_dir}/secrets.yaml"
external_secret_file="${production_dir}/google-external-secrets.yaml"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to verify production Secrets" >&2
  exit 2
fi

if [[ -f "$secrets_file" ]]; then
  mapfile -t required_entries < <(
    awk '
      function reset_document() {
        is_secret = 0
        in_string_data = 0
        secret_name = ""
      }
      BEGIN { reset_document() }
      /^---$/ { reset_document(); next }
      /^kind: Secret$/ { is_secret = 1; next }
      is_secret && /^  name: / {
        secret_name = $2
        next
      }
      is_secret && /^stringData:$/ {
        in_string_data = 1
        next
      }
      is_secret && in_string_data && /^  [A-Z][A-Z0-9_]*:/ {
        key = $1
        sub(/:$/, "", key)
        print secret_name "/" key
        next
      }
      is_secret && in_string_data && !/^  / {
        in_string_data = 0
      }
    ' "$secrets_file"
  )
elif [[ -r "$external_secret_file" ]]; then
  mapfile -t required_entries < <(
    awk '
      function reset_document() {
        is_external_secret = 0
        in_target = 0
        in_template_data = 0
        target_name = ""
      }
      BEGIN { reset_document() }
      /^---$/ { reset_document(); next }
      /^kind: ExternalSecret$/ { is_external_secret = 1; next }
      is_external_secret && /^  target:$/ { in_target = 1; next }
      is_external_secret && in_target && /^    name: / {
        target_name = $2
        next
      }
      is_external_secret && /^      data:$/ {
        in_template_data = 1
        next
      }
      is_external_secret && in_template_data && /^        [A-Z][A-Z0-9_]*:/ {
        key = $1
        sub(/:$/, "", key)
        print target_name "/" key
        next
      }
      is_external_secret && in_template_data && !/^        / {
        in_template_data = 0
      }
    ' "$external_secret_file"
  )
else
  echo "Neither secrets.yaml nor google-external-secrets.yaml is available in ${production_dir}" >&2
  exit 2
fi

if ((${#required_entries[@]} == 0)); then
  echo "Secret definitions contain no required keys in ${production_dir}" >&2
  exit 2
fi

check_entry() {
  local entry="$1"
  local secret_name="${entry%%/*}"
  local key="${entry#*/}"
  local encoded_value

  if ! encoded_value="$(
    kubectl --namespace "$namespace" get secret "$secret_name" \
      --output "jsonpath={.data.${key}}" 2>/dev/null
  )"; then
    echo "MISSING: Secret/${secret_name} is unavailable" >&2
    missing=1
    return
  fi

  if [[ -z "$encoded_value" ]]; then
    echo "MISSING: Secret/${secret_name} key ${key} is absent or empty" >&2
    missing=1
  fi
}

for entry in "${required_entries[@]}"; do
  check_entry "$entry"
done

if [[ "${VERIFY_GHCR_PULL_SECRET:-0}" == "1" ]]; then
  docker_config="$(
    kubectl --namespace "$namespace" get secret ghcr-pull-secret \
      --output 'jsonpath={.data.\.dockerconfigjson}' 2>/dev/null || true
  )"
  if [[ -z "$docker_config" ]]; then
    echo "MISSING: Secret/ghcr-pull-secret key .dockerconfigjson is absent or empty" >&2
    missing=1
  fi
fi

if ((missing != 0)); then
  echo "Production Secret verification failed; no Secret values were printed." >&2
  exit 1
fi

echo "Production Secret names and required non-empty keys verified in namespace ${namespace}; no values were printed."
