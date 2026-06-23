#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

DIRECT_PUBLIC_IP="198.51.100.45"
load_source_config "$ROOT_DIR/tests/fixtures/source/etc/sing-box"
SUI_DIR="/usr/local/s-ui"
REALITY_TLS_ID=11
SHARED_TLS_ID=12

reality="$(build_reality_tls_payload)"
shared="$(build_shared_tls_payload)"
vless="$(build_vless_payload)"
vmess="$(build_vmess_payload)"
hy2="$(build_hy2_payload)"
tuic="$(build_tuic_payload)"
warp="$(build_warp_endpoint_payload)"
base="$(build_base_config_payload)"
client="$(build_test_client_payload __check '[1,2,3,4]')"
direct="$(build_direct_outbound_payload)"

assert_json '.name' 'migrated-reality' "$reality" "Reality TLS 名称"
assert_json '.server.reality.private_key' 'FIXTURE_REALITY_PRIVATE_KEY' "$reality" "Reality 私钥"
assert_json '.client.reality.public_key' 'FIXTURE_REALITY_PUBLIC_KEY' "$reality" "Reality 公钥"
assert_json '.name' 'migrated-quic-tls' "$shared" "公共 TLS 名称"
assert_json '.tls_id' '11' "$vless" "VLESS 关联 Reality TLS"
assert_json '.addrs[0].server' '198.51.100.45' "$vless" "VLESS 发布 VPS IPv4"
assert_json '.listen_port' '8001' "$vmess" "VMess 监听 8001"
assert_json '.listen' '127.0.0.1' "$vmess" "VMess 仅监听本机"
assert_json '.addrs[0].server' 'cdns.doon.eu.org' "$vmess" "VMess 使用 CDN 地址"
assert_json '.addrs[0].tls.server_name' 'fixture-argo.trycloudflare.com' "$vmess" "VMess 使用 Argo SNI"
assert_json '.transport.headers.Host' 'fixture-argo.trycloudflare.com' "$vmess" "VMess 设置 WS Host"
assert_json '.tls_id' '12' "$hy2" "Hysteria2 关联公共 TLS"
assert_json '.addrs[0].server' '198.51.100.45' "$hy2" "Hysteria2 发布 VPS IPv4"
assert_json '.tls_id' '12' "$tuic" "TUIC 关联公共 TLS"
assert_json '.addrs[0].server' '198.51.100.45' "$tuic" "TUIC 发布 VPS IPv4"
assert_json '.tag' 'wireguard-out' "$warp" "读取 WARP endpoint"
assert_json '.type' 'direct' "$direct" "创建 direct 出站"
assert_json '.tag' 'direct' "$direct" "direct 出站标签"
assert_json '.route.final' 'direct' "$base" "保留基础路由"
assert_json '.route.rules | length' '0' "$base" "删除没有出口的空路由规则"
assert_json '.inbounds | length' '4' "$client" "测试用户关联四个入站"
assert_json '.config.vless.flow' 'xtls-rprx-vision' "$client" "测试用户包含 VLESS 配置"
finish_tests
