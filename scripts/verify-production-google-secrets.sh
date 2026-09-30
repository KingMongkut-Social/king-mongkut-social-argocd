#!/usr/bin/env bash
set -euo pipefail

project_id="${PROJECT_ID:-denmann-production}"
namespace="${NAMESPACE:-king-mongkut-social-production}"
expected_context="${EXPECTED_KUBE_CONTEXT:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
external_secret_file="${script_dir}/../apps/production/google-external-secrets.yaml"

if [[ -z "$expected_context" ]]; then
  echo "EXPECTED_KUBE_CONTEXT is required; refusing to guess a production cluster." >&2
  exit 2
fi

for command_name in kubectl gcloud jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "${command_name} is required" >&2
    exit 2
  fi
done

current_context="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$current_context" != "$expected_context" ]]; then
  echo "Kubernetes context mismatch: expected ${expected_context}, got ${current_context:-<none>}" >&2
  exit 2
fi

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

if ((${#required_entries[@]} == 0)); then
  echo "ExternalSecret key inventory is empty" >&2
  exit 2
fi

resources=(
  secretstore/google-secret-manager
  externalsecret/king-mongkut-social-backend-secret-sync
  externalsecret/king-mongkut-social-infra-secret-sync
)

for resource in "${resources[@]}"; do
  if ! kubectl --namespace "$namespace" get "$resource" --output=json \
    | jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null 2>&1; then
    echo "NOT READY: ${resource}" >&2
    exit 1
  fi
done

failed=0

backend_payload="$(
  gcloud secrets versions access latest \
    --secret=king-mongkut-social-backend-secret \
    --project="$project_id"
)"

infra_payload="$(
  gcloud secrets versions access latest \
    --secret=king-mongkut-social-infra-secret \
    --project="$project_id"
)"

# Validate tokens minimum length and distinction
if ! jq -e '(.ACCESS_TOKEN_SECRET | type == "string" and length >= 32)' <<<"$backend_payload" >/dev/null 2>&1; then
  echo "INVALID: king-mongkut-social-backend-secret/ACCESS_TOKEN_SECRET must be at least 32 characters" >&2
  failed=1
fi

if ! jq -e '(.REFRESH_TOKEN_SECRET | type == "string" and length >= 32)' <<<"$backend_payload" >/dev/null 2>&1; then
  echo "INVALID: king-mongkut-social-backend-secret/REFRESH_TOKEN_SECRET must be at least 32 characters" >&2
  failed=1
fi

if jq -e '.ACCESS_TOKEN_SECRET == .REFRESH_TOKEN_SECRET' <<<"$backend_payload" >/dev/null 2>&1; then
  echo "INVALID: king-mongkut-social-backend-secret ACCESS_TOKEN_SECRET and REFRESH_TOKEN_SECRET must differ" >&2
  failed=1
fi

for entry in "${required_entries[@]}"; do
  secret_name="${entry%%/*}"
  key="${entry#*/}"
  payload="$backend_payload"
  if [[ "$secret_name" == "king-mongkut-social-infra-secret" ]]; then
    payload="$infra_payload"
  fi

  if ! jq -e --arg k "$key" '.[$k] | type == "string" and length > 0' <<<"$payload" >/dev/null 2>&1; then
    echo "MISSING OR EMPTY: remote Secret ${secret_name} key ${key}" >&2
    failed=1
  fi
done

if ((failed != 0)); then
  echo "Remote Google Secret Manager validation failed; no Secret values were printed." >&2
  exit 1
fi

echo "Remote Google Secret Manager and reconciled Kubernetes Secrets verified in namespace ${namespace}; no values were printed."
