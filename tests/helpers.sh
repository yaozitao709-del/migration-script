#!/usr/bin/env bash
set -Eeuo pipefail

pass_count=0
fail_count=0

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok - %s\n' "$label"
    pass_count=$((pass_count + 1))
  else
    printf 'not ok - %s\nexpected: %s\nactual:   %s\n' \
      "$label" "$expected" "$actual" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_json() {
  local filter="$1" expected="$2" json="$3" label="$4"
  assert_eq "$expected" "$(jq -r "$filter" <<<"$json")" "$label"
}

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'ok - %s\n' "$label"
    pass_count=$((pass_count + 1))
  else
    printf 'not ok - %s\nmissing: %s\n' "$label" "$needle" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'not ok - %s\ncommand unexpectedly succeeded\n' "$label" >&2
    fail_count=$((fail_count + 1))
  else
    printf 'ok - %s\n' "$label"
    pass_count=$((pass_count + 1))
  fi
}

finish_tests() {
  printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
  (( fail_count == 0 ))
}
