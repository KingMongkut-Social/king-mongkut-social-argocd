#!/usr/bin/env bash
set -euo pipefail

project_id="${PROJECT_ID:-denmann-production}"
namespace="${NAMESPACE:-king-mongkut-social-production}"
expected_context="${EXPECTED_KUBE_CONTEXT:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  EXPECTED_KUBE_CONTEXT=<production-context> scripts/seed-production-google-secrets.sh

Optional overrides:
  PROJECT_ID, NAMESPACE

The script reads the live Kubernetes Secrets, validates non-empty payloads,
and streams canonical JSON directly to Google Secret Manager.
It never prints or writes decoded Secret values to disk or terminal.
EOF
}

if [[ -z "$expected_context" ]]; then
  usage
  echo "EXPECTED_KUBE_CONTEXT is required; refusing to guess a production cluster." >&2
  exit 2
fi

for command_name in kubectl gcloud jq openssl; do
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

configured_project="$(gcloud config get-value project 2>/dev/null || true)"
if [[ "$configured_project" != "$project_id" ]]; then
  echo "gcloud project mismatch: expected ${project_id}, got ${configured_project:-<none>}" >&2
  exit 2
fi

decode_secret_data() {
  local secret_name="$1"
  kubectl --namespace "$namespace" get secret "$secret_name" --output=json \
    | jq -ce '.data // {} | with_entries(.value |= @base64d)'
}

for secret_name in king-mongkut-social-backend-secret king-mongkut-social-infra-secret; do
  if ! kubectl --namespace "$namespace" get secret "$secret_name" >/dev/null 2>&1; then
    echo "Secret/${secret_name} not found in namespace ${namespace}" >&2
    exit 1
  fi
done

backend_json="$(decode_secret_data king-mongkut-social-backend-secret)"
infra_json="$(decode_secret_data king-mongkut-social-infra-secret)"

ensure_remote_secret() {
  local secret_name="$1"
  if ! gcloud secrets describe "$secret_name" --project="$project_id" >/dev/null 2>&1; then
    echo "Creating secret ${secret_name} in project ${project_id}..."
    gcloud secrets create "$secret_name" \
      --project="$project_id" \
      --replication-policy="automatic" >/dev/null
  fi
}

sync_secret_payload() {
  local secret_name="$1"
  local payload="$2"

  ensure_remote_secret "$secret_name"
  echo "Updating secret version for ${secret_name}..."
  printf '%s' "$payload" | gcloud secrets versions add "$secret_name" \
    --project="$project_id" \
    --data-file=- >/dev/null
}

sync_secret_payload "king-mongkut-social-backend-secret" "$backend_json"
sync_secret_payload "king-mongkut-social-infra-secret" "$infra_json"

echo "Successfully seeded production Google Secret Manager secrets from namespace ${namespace}; no values were printed."
