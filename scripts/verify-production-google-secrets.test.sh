#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
verifier="${script_dir}/verify-production-google-secrets.sh"
test_dir="$(mktemp -d)"
fake_bin="${test_dir}/bin"
backend_payload_file="${test_dir}/backend.json"
infra_payload_file="${test_dir}/infra.json"
mkdir -p "$fake_bin"
trap 'rm -rf "$test_dir"' EXIT

cat >"$backend_payload_file" <<'EOF'
{
  "MONGODB_URI": "mongodb://king_user:pass@mongodb:27017/king_mongkut_social?authSource=admin",
  "ACCESS_TOKEN_SECRET": "access_token_secret_32_characters_minimum_len",
  "REFRESH_TOKEN_SECRET": "refresh_token_secret_32_characters_minimum_len",
  "GOOGLE_CLIENT_ID": "mock-client-id.apps.googleusercontent.com",
  "GOOGLE_CLIENT_SECRET": "mock-client-secret"
}
EOF

cat >"$infra_payload_file" <<'EOF'
{
  "MONGO_INITDB_ROOT_USERNAME": "king_user",
  "MONGO_INITDB_ROOT_PASSWORD": "mock-infra-password"
}
EOF

cat >"${fake_bin}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "config current-context" ]]; then
  echo production-test
  exit 0
fi
if [[ "$*" == *"get secretstore/"* || "$*" == *"get externalsecret/"* ]]; then
  echo '{"status":{"conditions":[{"type":"Ready","status":"True"}]}}'
  exit 0
fi
exit 0
EOF

cat >"${fake_bin}/gcloud" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\$*" == *"king-mongkut-social-backend-secret"* ]]; then
  cat "$backend_payload_file"
  exit 0
fi
if [[ "\$*" == *"king-mongkut-social-infra-secret"* ]]; then
  cat "$infra_payload_file"
  exit 0
fi
exit 1
EOF

chmod +x "${fake_bin}/kubectl" "${fake_bin}/gcloud"

success_output="$(
  PATH="${fake_bin}:${PATH}" \
    EXPECTED_KUBE_CONTEXT=production-test \
    "$verifier"
)"

if [[ "$success_output" != *"no values were printed"* ]]; then
  echo "verifier did not report successful non-leaking validation" >&2
  exit 1
fi

set +e
failure_output="$(
  PATH="${fake_bin}:${PATH}" \
    EXPECTED_KUBE_CONTEXT=wrong-context \
    "$verifier" 2>&1
)"
failure_status=$?
set -e

if ((failure_status == 0)); then
  echo "verifier accepted context mismatch" >&2
  exit 1
fi

echo "verify-production-google-secrets tests passed"
