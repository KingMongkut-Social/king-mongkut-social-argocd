#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
verifier="${script_dir}/verify-production-secrets.sh"
fake_bin="${script_dir}/testdata/fake-bin"

success_output="$(
  PATH="${fake_bin}:${PATH}" \
    VERIFY_GHCR_PULL_SECRET=1 \
    "$verifier" test-namespace
)"

if [[ "$success_output" != *"no values were printed"* ]]; then
  echo "verifier did not report successful non-leaking validation" >&2
  exit 1
fi

set +e
failure_output="$(
  PATH="${fake_bin}:${PATH}" \
    FAKE_EMPTY_KEY=ACCESS_TOKEN_SECRET \
    "$verifier" test-namespace 2>&1
)"
failure_status=$?
set -e

if ((failure_status == 0)); then
  echo "verifier accepted an empty required key" >&2
  exit 1
fi

if [[ "$failure_output" != *"ACCESS_TOKEN_SECRET is absent or empty"* ]]; then
  echo "verifier did not identify the missing key" >&2
  exit 1
fi

if [[ "$failure_output" == *"bm90LWEtcmVhbC1zZWNyZXQ="* ]]; then
  echo "verifier leaked a Secret value" >&2
  exit 1
fi

echo "verify-production-secrets tests passed"
