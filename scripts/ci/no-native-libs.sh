#!/usr/bin/env bash
# Fail if the prod build contains a native library (*.so): the release is NIF-free.
# Prod only: the test-only dep lazy_html builds a .so into _build/test.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
found="$(find _build/prod -name "*.so" -print)"
if [ -n "$found" ]; then
  echo "no-native-libs: native libraries in the prod build:" >&2
  echo "$found" >&2
  exit 1
fi
echo "no-native-libs: ok"
