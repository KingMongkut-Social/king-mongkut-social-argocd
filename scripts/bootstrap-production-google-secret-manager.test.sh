#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bootstrapper="${script_dir}/bootstrap-production-google-secret-manager.sh"
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
exit 0
EOF

cat >"${fake_bin}/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "config get-value project" ]]; then
  echo denmann-production
  exit 0
fi
if [[ "$*" == *"projects describe"* ]]; then
  echo 213644201491
  exit 0
fi
exit 0
EOF

chmod +x "${fake_bin}/kubectl" "${fake_bin}/gcloud"

success_output="$(
  PATH="${fake_bin}:${PATH}" \
    EXPECTED_KUBE_CONTEXT=production-test \
    "$bootstrapper"
)"

if [[ "$success_output" != *"bootstrapping completed successfully"* ]]; then
  echo "bootstrapper did not report success" >&2
  exit 1
fi

echo "bootstrap-production-google-secret-manager tests passed"
