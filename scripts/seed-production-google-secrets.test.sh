#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
seeder="${script_dir}/seed-production-google-secrets.sh"
test_dir="$(mktemp -d)"
fake_bin="${test_dir}/bin"
mkdir -p "$fake_bin"
trap 'rm -rf "$test_dir"' EXIT

cat >"${fake_bin}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "config current-context" ]]; then
  echo production-test
  exit 0
fi
if [[ "$*" == *"get secret king-mongkut-social-backend-secret"* ]]; then
  echo '{"data":{"ACCESS_TOKEN_SECRET":"YWNjZXNzX3NlY3JldF8zMl9jaGFyc19taW5pbXVtX2xlbmd0aA==","REFRESH_TOKEN_SECRET":"cmVmcmVzaF9zZWNyZXRfMzJfY2hhcnNfbWluaW11bV9sZW5ndGg=","MONGODB_URI":"bW9uZ29kYjovL21vbmdvOjI3MDE3L2tpbmdfbW9uZ2t1dF9zb2NpYWw=","GOOGLE_CLIENT_ID":"bW9jay1pZA==","GOOGLE_CLIENT_SECRET":"bW9jay1zZWNyZXQ="}}'
  exit 0
fi
if [[ "$*" == *"get secret king-mongkut-social-infra-secret"* ]]; then
  echo '{"data":{"MONGO_INITDB_ROOT_USERNAME":"a2luZ191c2Vy","MONGO_INITDB_ROOT_PASSWORD":"cGFzc3dvcmQ="}}'
  exit 0
fi
exit 0
EOF

cat >"${fake_bin}/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "config get-value project" ]]; then
  echo denmann-production
  exit 0
fi
if [[ "$*" == *"secrets describe"* ]]; then
  exit 0
fi
if [[ "$*" == *"secrets versions add"* ]]; then
  # Consume stdin
  cat >/dev/null
  exit 0
fi
exit 0
EOF

chmod +x "${fake_bin}/kubectl" "${fake_bin}/gcloud"

success_output="$(
  PATH="${fake_bin}:${PATH}" \
    EXPECTED_KUBE_CONTEXT=production-test \
    "$seeder"
)"

if [[ "$success_output" != *"Successfully seeded production Google Secret Manager"* ]]; then
  echo "seeder did not report success" >&2
  exit 1
fi

echo "seed-production-google-secrets tests passed"
