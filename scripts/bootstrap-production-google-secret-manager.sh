#!/usr/bin/env bash
set -euo pipefail

project_id="${PROJECT_ID:-denmann-production}"
project_number="${PROJECT_NUMBER:-213644201491}"
pool_id="${POOL_ID:-denmann-selfhosted-k8s}"
provider_id="${PROVIDER_ID:-production-cluster}"
namespace="${NAMESPACE:-king-mongkut-social-production}"
eso_ksa="${ESO_KSA:-king-mongkut-social-secret-sync}"
expected_context="${EXPECTED_KUBE_CONTEXT:-}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

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

configured_project="$(gcloud config get-value project 2>/dev/null || true)"
if [[ "$configured_project" != "$project_id" ]]; then
  echo "gcloud project mismatch: expected ${project_id}, got ${configured_project:-<none>}" >&2
  exit 2
fi

actual_project_number="$(
  gcloud projects describe "$project_id" --format='value(projectNumber)' 2>/dev/null || echo "$project_number"
)"

echo "===> Enabling Google Secret Manager & IAM APIs..."
gcloud services enable secretmanager.googleapis.com iamcredentials.googleapis.com --project="$project_id"

echo "===> Checking Workload Identity Pool..."
if ! gcloud iam workload-identity-pools describe "$pool_id" --location="global" --project="$project_id" >/dev/null 2>&1; then
  echo "Creating Workload Identity Pool ${pool_id}..."
  gcloud iam workload-identity-pools create "$pool_id" \
    --location="global" \
    --description="Self-hosted K8s cluster pool" \
    --display-name="Denmann K8s Pool" \
    --project="$project_id"
fi

echo "===> Ensuring Google Secret Manager secret containers exist..."
for secret_name in king-mongkut-social-backend-secret king-mongkut-social-infra-secret; do
  if ! gcloud secrets describe "$secret_name" --project="$project_id" >/dev/null 2>&1; then
    echo "Creating Secret Manager container: ${secret_name}"
    gcloud secrets create "$secret_name" \
      --replication-policy="automatic" \
      --project="$project_id"
  fi
done

echo "===> Binding Secret Accessor role to Workload Identity..."
principal="principal://iam.googleapis.com/projects/${actual_project_number}/locations/global/workloadIdentityPools/${pool_id}/subject/system:serviceaccount:${namespace}:${eso_ksa}"

for secret_name in king-mongkut-social-backend-secret king-mongkut-social-infra-secret; do
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project="$project_id" \
    --role="roles/secretmanager.secretAccessor" \
    --member="$principal" >/dev/null
done

echo "Google Secret Manager and Workload Identity bootstrapping completed successfully."
