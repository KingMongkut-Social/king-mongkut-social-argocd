#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
production_dir="${repo_root}/apps/production"
secrets_file="${production_dir}/secrets.yaml"
external_secret_file="${production_dir}/google-external-secrets.yaml"

for command_name in kubectl awk grep; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "${command_name} is required to validate the production Secret contract" >&2
    exit 2
  fi
done

referenced_output="$(
  kubectl kustomize "$production_dir" | awk '
    /^[[:space:]]*secretKeyRef:$/ {
      in_reference = 1
      secret_name = ""
      key = ""
      next
    }
    in_reference && /^[[:space:]]*name:/ {
      secret_name = $2
    }
    in_reference && /^[[:space:]]*key:/ {
      key = $2
    }
    in_reference && secret_name != "" && key != "" {
      print secret_name "/" key
      in_reference = 0
    }
  ' | sort -u
)"

# Extract available keys from secrets.yaml (or google-external-secrets.yaml)
if [[ -f "$secrets_file" ]]; then
  declared_output="$(
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
    ' "$secrets_file" | sort -u
  )"
else
  declared_output="$(
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
    ' "$external_secret_file" | sort -u
  )"
fi

if [[ -z "$referenced_output" || -z "$declared_output" ]]; then
  echo "Declared secret inventory or rendered secretKeyRef inventory is empty" >&2
  exit 1
fi

mapfile -t referenced_entries <<<"$referenced_output"
mapfile -t declared_entries <<<"$declared_output"

declare -A referenced=()
declare -A declared=()
failed=0

for entry in "${declared_entries[@]}"; do
  declared["$entry"]=1
done

for entry in "${referenced_entries[@]}"; do
  referenced["$entry"]=1
  if [[ -z "${declared[$entry]:-}" ]]; then
    echo "UNMAPPED: rendered workload requires ${entry}" >&2
    failed=1
  fi
done

for entry in "${declared_entries[@]}"; do
  if [[ -z "${referenced[$entry]:-}" ]]; then
    echo "STALE: Declared Secret key is not consumed by a rendered workload: ${entry}" >&2
    failed=1
  fi
done

if ((failed != 0)); then
  exit 1
fi

echo "Production Secret declarations match all rendered Secret consumers."
