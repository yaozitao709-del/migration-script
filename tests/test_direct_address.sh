#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

DIRECT_PUBLIC_IP=""
detect_public_ipv4() { printf '198.51.100.77'; }
resolve_direct_public_address
assert_eq "198.51.100.77" "$DIRECT_PUBLIC_SERVER" "自动探测 VPS 公网 IPv4"
assert_eq "自动探测 IPv4" "$DIRECT_ADDRESS_SOURCE" "记录自动探测来源"

DIRECT_PUBLIC_IP=""
detect_public_ipv4() { return 1; }
resolve_direct_public_address
assert_eq "" "$DIRECT_PUBLIC_SERVER" "探测失败时允许保留原订阅地址"
assert_eq "原订阅地址" "$DIRECT_ADDRESS_SOURCE" "记录回退来源"

DIRECT_PUBLIC_IP="203.0.113.25"
resolve_direct_public_address
assert_eq "203.0.113.25" "$DIRECT_PUBLIC_SERVER" "手动 IPv4 优先于自动探测"
assert_eq "DIRECT_PUBLIC_IP" "$DIRECT_ADDRESS_SOURCE" "记录手动配置来源"

DIRECT_PUBLIC_IP="2400:8d60:8::1"
assert_fails "DIRECT_PUBLIC_IP 拒绝 IPv6" resolve_direct_public_address

DIRECT_PUBLIC_IP="999.1.1.1"
assert_fails "DIRECT_PUBLIC_IP 拒绝非法 IPv4" resolve_direct_public_address

finish_tests
