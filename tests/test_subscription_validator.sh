#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

good_links=$'vless://uuid@[2400:8d60:8::91d5:2f81]:2317?type=tcp#ok\nhysteria2://pass@[2400:8d60:8::91d5:2f81]:2320?sni=www.bing.com#ok\ntuic://uuid:pass@[2400:8d60:8::91d5:2f81]:2319?sni=www.bing.com#ok'
bad_links=$'vless://uuid@2400:8d60:8::91d5:2f81:2317?type=tcp#bad\nhysteria2://pass@2400:8d60:8::91d5:2f81:2320?sni=www.bing.com#bad\ntuic://uuid:pass@2400:8d60:8::91d5:2f81:2319?sni=www.bing.com#bad'

validate_subscription_links "$good_links"
assert_eq "0" "$?" "合法 IPv6 订阅链接通过检查"
assert_fails "未加方括号的 IPv6 订阅链接会失败" validate_subscription_links "$bad_links"

finish_tests
