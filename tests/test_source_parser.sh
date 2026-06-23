#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

FIXTURE="$ROOT_DIR/tests/fixtures/source/etc/sing-box"
load_source_config "$FIXTURE"

assert_eq "21001" "$VLESS_PORT" "读取 VLESS 端口"
assert_eq "8001" "$VMESS_PORT" "读取 VMess 端口"
assert_eq "21004" "$HY2_PORT" "读取 Hysteria2 端口"
assert_eq "21003" "$TUIC_PORT" "读取 TUIC 端口"
assert_eq "www.iij.ad.jp" "$REALITY_SERVER_NAME" "读取 Reality SNI"
assert_eq "FIXTURE_REALITY_PRIVATE_KEY" "$REALITY_PRIVATE_KEY" "读取 Reality 私钥"
assert_eq "FIXTURE_REALITY_PUBLIC_KEY" "$REALITY_PUBLIC_KEY" "读取 Reality 公钥"
assert_eq "fixture-argo.trycloudflare.com" "$ARGO_DOMAIN" "读取 Argo 临时域名"
assert_eq "cdns.doon.eu.org" "$ARGO_PUBLIC_SERVER" "读取 Argo 公网地址"
assert_eq "443" "$ARGO_PUBLIC_PORT" "读取 Argo 公网端口"
assert_eq "amd64" "$(detect_arch x86_64)" "识别 amd64"
assert_eq "arm64" "$(detect_arch aarch64)" "识别 arm64"
finish_tests

