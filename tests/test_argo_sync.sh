#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
write_argo_sync_script "$tmp/sync.sh"

content="$(cat "$tmp/sync.sh")"
assert_contains 'vmess-ws-argo' "$content" "同步脚本定位 VMess 入站"
assert_contains '.transport.headers' "$content" "同步 WS Host"
assert_contains '.addrs[0].tls.server_name' "$content" "同步 TLS SNI"
assert_contains '*.trycloudflare.com' "$content" "仅接受临时 Argo 域名"
assert_eq "700" "$(stat -f '%Lp' "$tmp/sync.sh" 2>/dev/null || stat -c '%a' "$tmp/sync.sh")" "同步脚本权限"
finish_tests

