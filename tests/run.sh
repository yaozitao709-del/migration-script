#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  printf '\n==> %s\n' "$(basename "$test_file")"
  if ! bash "$test_file"; then
    status=1
  fi
done

exit "$status"

