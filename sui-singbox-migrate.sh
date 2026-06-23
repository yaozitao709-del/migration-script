#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_VERSION="0.1.4"
SOURCE_PROFILE="eooce/sing-box@9b4a35d79944b41c57751ebcebc6ff55ada83df3"
SUI_VERSION="v1.4.1"
SUI_SINGBOX_VERSION="v1.13.4"

SOURCE_DIR="${SOURCE_DIR:-/etc/sing-box}"
SUI_DIR="${SUI_DIR:-/usr/local/s-ui}"
STATE_DIR="${STATE_DIR:-/var/lib/sui-singbox-migrate}"
ARGO_SYNC_DIR="${ARGO_SYNC_DIR:-/var/lib/sui-argo-sync}"
BACKUP_BASE="${BACKUP_BASE:-/root/sui-migration-backup}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"

PANEL_PORT="${PANEL_PORT:-2095}"
SUB_PORT="${SUB_PORT:-2096}"
PANEL_PATH="${PANEL_PATH:-}"
SUB_PATH="${SUB_PATH:-}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASS="${ADMIN_PASS:-}"
DIRECT_PUBLIC_IP="${DIRECT_PUBLIC_IP:-}"

ASSUME_YES=0
PLAN_ONLY=0
FORCE_REIMPORT=0
RESTORE_PATH=""
ALLOW_NON_ROOT="${SUI_MIGRATE_ALLOW_NON_ROOT:-0}"

TMP_DIR=""
COOKIE_JAR=""
BACKUP_DIR=""
PANEL_BASE_URL=""
SUB_BASE_URL=""
ARCH=""
DIRECT_PUBLIC_SERVER=""
DIRECT_ADDRESS_SOURCE=""
MUTATION_STARTED=0
MIGRATION_COMMITTED=0

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

info() { printf "${green}[信息]${plain} %s\n" "$*"; }
warn() { printf "${yellow}[提醒]${plain} %s\n" "$*" >&2; }
error() { printf "${red}[错误]${plain} %s\n" "$*" >&2; }
die() { error "$*"; return 1; }

run_curl() { curl "$@"; }
run_systemctl() { systemctl "$@"; }
run_ss() { ss "$@"; }

usage() {
  cat <<'EOF'
S-UI 接管现有 sing-box 四协议节点

用法：
  bash sui-singbox-migrate.sh [选项]

选项：
  --plan              只检查并展示迁移方案，不修改服务器
  --yes               使用默认/环境变量设置，跳过最终确认
  --force-reimport    再次导入 TLS、入站和路由，不删除面板用户
  --restore 备份目录  恢复指定备份
  --version           显示版本
  --help              显示帮助

可选环境变量：
  PANEL_PORT=2095
  SUB_PORT=2096
  PANEL_PATH=/随机路径/
  SUB_PATH=/随机路径/
  ADMIN_USER=管理员用户名
  ADMIN_PASS=管理员密码
  DIRECT_PUBLIC_IP=VPS公网IPv4

前提：
  1. Ubuntu VPS
  2. 已运行 eooce/sing-box 四协议脚本
  3. /etc/sing-box/conf/inbounds.json 存在
EOF
}

version() {
  cat <<EOF
sui-singbox-migrate ${SCRIPT_VERSION}
source profile: ${SOURCE_PROFILE}
target panel: admin8800/s-ui@${SUI_VERSION}
embedded sing-box: ${SUI_SINGBOX_VERSION}
EOF
}

random_text() {
  local length="${1:-24}"
  if command -v openssl >/dev/null 2>&1; then
    { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length"; } || true
  else
    { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"; } || true
  fi
}

normalize_path() {
  local value="$1"
  [[ "$value" == /* ]] || value="/$value"
  [[ "$value" == */ ]] || value="$value/"
  printf '%s' "$value"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

require_file() {
  [[ -f "$1" ]] || die "缺少文件：$1"
}

detect_arch() {
  local machine="${1:-$(uname -m)}"
  case "$machine" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    i386|i686|x86) printf '386' ;;
    armv5*) printf 'armv5' ;;
    armv6*) printf 'armv6' ;;
    armv7*) printf 'armv7' ;;
    s390x) printf 's390x' ;;
    *) die "不支持的 CPU 架构：$machine" ;;
  esac
}

release_checksum() {
  case "$1" in
    386) printf '232201186738fa8c37b32418a1b4e8608629568ae66518d51439369a0599a367' ;;
    amd64) printf '44739d35fbf59c1c6b71787aa92d07665caa5c5b8fb1f4f51dec69d13a74a952' ;;
    arm64) printf 'c2052405277c94928fa25074e74a76de5250d5415877b596350d191e5ef9d03a' ;;
    armv5) printf 'c4b58e79e6c26832633e36127387a31586e5e50a23753b33460a270a184791a8' ;;
    armv6) printf 'cacbed2c14e2862f4c8bf8d082a6c507cd1e49267e779d2c52982fa5d16a0744' ;;
    armv7) printf '06a246773d43d5a65c29f37306e7a027c9ad80884b456e5280f304dd8c87e945' ;;
    s390x) printf 'b8481dd1b661b4ff2c196564e890be23b8e5c95362ff708654923eda2c1bdad0' ;;
    *) die "没有该架构的 S-UI 校验值：$1" ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

decode_base64() {
  base64 -d 2>/dev/null || base64 -D 2>/dev/null
}

extract_uri_host() {
  sed -nE 's#^[a-zA-Z0-9]+://[^@]+@(\[[^]]+\]|[^:]+):[0-9]+.*#\1#p' |
    sed -E 's/^\[//; s/\]$//'
}

format_url_host() {
  local host="$1"
  if [[ "$host" == \[*\] ]]; then
    printf '%s' "$host"
  elif [[ "$host" == *:* ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

extract_uri_port() {
  sed -nE 's#^[a-zA-Z0-9]+://[^@]+@(\[[^]]+\]|[^:]+):([0-9]+).*#\2#p'
}

is_ipv4() {
  local ip="$1" octet
  local -a octets
  [[ "$ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
  IFS='.' read -r -a octets <<<"$ip"
  (( ${#octets[@]} == 4 )) || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

detect_public_ipv4() {
  local endpoint candidate
  for endpoint in \
    https://api.ipify.org \
    https://ipv4.icanhazip.com \
    https://api4.ipify.org \
    https://ip.sb; do
    candidate="$(
      run_curl -4fsS --connect-timeout 4 --max-time 8 "$endpoint" 2>/dev/null ||
        true
    )"
    candidate="${candidate//$'\r'/}"
    candidate="${candidate//$'\n'/}"
    if is_ipv4 "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_direct_public_address() {
  local detected=""
  if [[ -n "$DIRECT_PUBLIC_IP" ]]; then
    if ! is_ipv4 "$DIRECT_PUBLIC_IP"; then
      die "DIRECT_PUBLIC_IP 必须是合法的 IPv4 地址"
      return 1
    fi
    DIRECT_PUBLIC_SERVER="$DIRECT_PUBLIC_IP"
    DIRECT_ADDRESS_SOURCE="DIRECT_PUBLIC_IP"
    return
  fi

  detected="$(detect_public_ipv4 || true)"
  if [[ -n "$detected" ]]; then
    DIRECT_PUBLIC_SERVER="$detected"
    DIRECT_ADDRESS_SOURCE="自动探测 IPv4"
  else
    DIRECT_PUBLIC_SERVER=""
    DIRECT_ADDRESS_SOURCE="原订阅地址"
  fi
}

load_source_config() {
  local source_dir="${1:-$SOURCE_DIR}"
  local inbounds="$source_dir/conf/inbounds.json"
  local vmess_encoded vmess_json

  SOURCE_DIR="$source_dir"
  require_file "$inbounds"
  require_file "$source_dir/conf/endpoints.json"
  require_file "$source_dir/conf/route.json"
  require_file "$source_dir/cert.pem"
  require_file "$source_dir/private.key"
  require_file "$source_dir/url.txt"

  VLESS_PORT="$(jq -er '.inbounds[] | select(.type=="vless") | .listen_port' "$inbounds")"
  VMESS_PORT="$(jq -er '.inbounds[] | select(.type=="vmess") | .listen_port' "$inbounds")"
  HY2_PORT="$(jq -er '.inbounds[] | select(.type=="hysteria2") | .listen_port' "$inbounds")"
  TUIC_PORT="$(jq -er '.inbounds[] | select(.type=="tuic") | .listen_port' "$inbounds")"

  REALITY_SERVER_NAME="$(jq -er '.inbounds[] | select(.type=="vless") | .tls.server_name' "$inbounds")"
  REALITY_HANDSHAKE_SERVER="$(jq -er '.inbounds[] | select(.type=="vless") | .tls.reality.handshake.server' "$inbounds")"
  REALITY_HANDSHAKE_PORT="$(jq -er '.inbounds[] | select(.type=="vless") | .tls.reality.handshake.server_port' "$inbounds")"
  REALITY_PRIVATE_KEY="$(jq -er '.inbounds[] | select(.type=="vless") | .tls.reality.private_key' "$inbounds")"
  REALITY_SHORT_IDS="$(jq -c '.inbounds[] | select(.type=="vless") | .tls.reality.short_id // [""]' "$inbounds")"
  REALITY_PUBLIC_KEY="$(sed -nE 's/.*[?&]pbk=([^&#]+).*/\1/p' "$source_dir/url.txt" | head -n1)"

  VLESS_LINK="$(grep -m1 '^vless://' "$source_dir/url.txt" || true)"
  HY2_LINK="$(grep -m1 '^hysteria2://' "$source_dir/url.txt" || true)"
  TUIC_LINK="$(grep -m1 '^tuic://' "$source_dir/url.txt" || true)"
  VLESS_PUBLIC_SERVER="$(printf '%s\n' "$VLESS_LINK" | extract_uri_host)"
  HY2_PUBLIC_SERVER="$(printf '%s\n' "$HY2_LINK" | extract_uri_host)"
  TUIC_PUBLIC_SERVER="$(printf '%s\n' "$TUIC_LINK" | extract_uri_host)"

  [[ -n "$VLESS_PUBLIC_SERVER" ]] || die "无法从旧订阅读取服务器地址"
  [[ -n "$HY2_PUBLIC_SERVER" ]] || HY2_PUBLIC_SERVER="$VLESS_PUBLIC_SERVER"
  [[ -n "$TUIC_PUBLIC_SERVER" ]] || TUIC_PUBLIC_SERVER="$VLESS_PUBLIC_SERVER"

  resolve_direct_public_address
  if [[ -n "$DIRECT_PUBLIC_SERVER" ]]; then
    VLESS_PUBLIC_SERVER="$DIRECT_PUBLIC_SERVER"
    HY2_PUBLIC_SERVER="$DIRECT_PUBLIC_SERVER"
    TUIC_PUBLIC_SERVER="$DIRECT_PUBLIC_SERVER"
  fi

  vmess_encoded="$(sed -n 's#^vmess://##p' "$source_dir/url.txt" | head -n1)"
  [[ -n "$vmess_encoded" ]] || die "旧订阅中缺少 VMess 链接"
  vmess_json="$(printf '%s' "$vmess_encoded" | decode_base64)" || die "无法解析旧 VMess 链接"
  ARGO_PUBLIC_SERVER="$(jq -er '.add' <<<"$vmess_json")"
  ARGO_PUBLIC_PORT="$(jq -er '.port | tonumber' <<<"$vmess_json")"
  ARGO_DOMAIN="$(jq -r '.host // .sni // empty' <<<"$vmess_json")"

  if [[ -f "$source_dir/argo.log" ]]; then
    local log_domain
    log_domain="$(sed -nE 's#.*https://([^/ ]+\.trycloudflare\.com).*#\1#p' "$source_dir/argo.log" | tail -n1)"
    [[ -z "$log_domain" ]] || ARGO_DOMAIN="$log_domain"
  fi

  [[ "$VMESS_PORT" == "8001" ]] || die "原 VMess-Argo 入站不是 8001，暂不支持自动迁移"
  [[ -n "$REALITY_PUBLIC_KEY" ]] || die "无法从旧 VLESS 链接读取 Reality public key"
  [[ "$ARGO_DOMAIN" == *.trycloudflare.com ]] || die "未检测到 Argo 临时域名"

  SOURCE_ENDPOINT="$(jq -cer '.endpoints[0]' "$source_dir/conf/endpoints.json")"
}

build_reality_tls_payload() {
  jq -n \
    --arg name "migrated-reality" \
    --arg server_name "$REALITY_SERVER_NAME" \
    --arg hs_server "$REALITY_HANDSHAKE_SERVER" \
    --argjson hs_port "$REALITY_HANDSHAKE_PORT" \
    --arg private_key "$REALITY_PRIVATE_KEY" \
    --arg public_key "$REALITY_PUBLIC_KEY" \
    --argjson short_ids "$REALITY_SHORT_IDS" \
    '{
      id: 0,
      name: $name,
      server: {
        enabled: true,
        server_name: $server_name,
        reality: {
          enabled: true,
          handshake: {server: $hs_server, server_port: $hs_port},
          private_key: $private_key,
          short_id: $short_ids
        }
      },
      client: {
        enabled: true,
        server_name: $server_name,
        utls: {enabled: true, fingerprint: "firefox"},
        reality: {
          enabled: true,
          public_key: $public_key,
          short_id: ($short_ids[0] // "")
        }
      }
    }'
}

build_shared_tls_payload() {
  jq -n \
    --arg name "migrated-quic-tls" \
    --arg cert "${SUI_DIR}/cert/migrated/cert.pem" \
    --arg key "${SUI_DIR}/cert/migrated/private.key" \
    '{
      id: 0,
      name: $name,
      server: {
        enabled: true,
        server_name: "www.bing.com",
        alpn: ["h3"],
        min_version: "1.3",
        max_version: "1.3",
        certificate_path: $cert,
        key_path: $key
      },
      client: {
        enabled: true,
        server_name: "www.bing.com",
        insecure: true,
        alpn: ["h3"]
      }
    }'
}

build_vless_payload() {
  local public_server
  public_server="$(format_url_host "$VLESS_PUBLIC_SERVER")"
  jq -n \
    --argjson tls_id "$REALITY_TLS_ID" \
    --argjson port "$VLESS_PORT" \
    --arg server "$public_server" \
    '{
      id: 0, type: "vless", tag: "vless-reality",
      listen: "::", listen_port: $port, tls_id: $tls_id,
      multiplex: {enabled: false},
      transport: {},
      addrs: [{server: $server, server_port: $port, remark: "-Reality"}],
      out_json: {}
    }'
}

build_vmess_payload() {
  jq -n \
    --argjson port "$VMESS_PORT" \
    --arg server "$ARGO_PUBLIC_SERVER" \
    --argjson server_port "$ARGO_PUBLIC_PORT" \
    --arg domain "$ARGO_DOMAIN" \
    '{
      id: 0, type: "vmess", tag: "vmess-ws-argo",
      listen: "127.0.0.1", listen_port: $port, tls_id: 0,
      transport: {
        type: "ws",
        path: "/vmess-argo",
        headers: {Host: $domain},
        max_early_data: 2560,
        early_data_header_name: "Sec-WebSocket-Protocol"
      },
      addrs: [{
        server: $server,
        server_port: $server_port,
        remark: "-Argo",
        tls: {
          enabled: true,
          server_name: $domain,
          insecure: false,
          utls: {enabled: true, fingerprint: "firefox"}
        }
      }],
      out_json: {}
    }'
}

build_hy2_payload() {
  local public_server
  public_server="$(format_url_host "$HY2_PUBLIC_SERVER")"
  jq -n \
    --argjson tls_id "$SHARED_TLS_ID" \
    --argjson port "$HY2_PORT" \
    --arg server "$public_server" \
    '{
      id: 0, type: "hysteria2", tag: "hysteria2",
      listen: "::", listen_port: $port, tls_id: $tls_id,
      ignore_client_bandwidth: false,
      masquerade: "https://bing.com",
      addrs: [{server: $server, server_port: $port, remark: "-Hysteria2"}],
      out_json: {}
    }'
}

build_tuic_payload() {
  local public_server
  public_server="$(format_url_host "$TUIC_PUBLIC_SERVER")"
  jq -n \
    --argjson tls_id "$SHARED_TLS_ID" \
    --argjson port "$TUIC_PORT" \
    --arg server "$public_server" \
    '{
      id: 0, type: "tuic", tag: "tuic",
      listen: "::", listen_port: $port, tls_id: $tls_id,
      congestion_control: "bbr",
      zero_rtt_handshake: false,
      addrs: [{server: $server, server_port: $port, remark: "-TUIC"}],
      out_json: {}
    }'
}

build_warp_endpoint_payload() {
  jq '. + {id: 0, ext: {}}' <<<"$SOURCE_ENDPOINT"
}

build_base_config_payload() {
  jq -s '
    reduce .[] as $doc ({}; . * $doc)
    | del(.inbounds, .outbounds, .endpoints, .services)
    | .log.level = "info"
    | .route.final = (
        if (.route.final // "" | type) == "string" and (.route.final // "") != "" then
          .route.final
        else
          "direct"
        end
      )
    | .route.rules = [
        (.route.rules // [])[]
        | if has("outbound") and ((.outbound // "") == "") then
            del(.outbound)
          else
            .
          end
        | select(
            ((.outbound? // "") != "")
            or (((.action? // "") != "") and ((.action? // "") != "route"))
            or (((.action? // "") == "route") and ((.outbound? // "") != ""))
          )
      ]
  ' \
    "$SOURCE_DIR/conf/log.json" \
    "$SOURCE_DIR/conf/ntp.json" \
    "$SOURCE_DIR/conf/dns.json" \
    "$SOURCE_DIR/conf/route.json"
}

build_direct_outbound_payload() {
  jq -n '{id: 0, type: "direct", tag: "direct"}'
}

print_plan() {
  cat <<EOF

将要执行的内容
----------------
系统：Ubuntu / ${ARCH}
来源：${SOURCE_DIR}
S-UI：${SUI_VERSION}（内置 sing-box ${SUI_SINGBOX_VERSION}）

准备导入：
  VLESS-Reality  TCP ${VLESS_PORT}  地址 ${VLESS_PUBLIC_SERVER}
  VMess-WS-Argo  TCP ${VMESS_PORT}  CDN ${ARGO_PUBLIC_SERVER}:${ARGO_PUBLIC_PORT}
  Hysteria2      UDP ${HY2_PORT}  地址 ${HY2_PUBLIC_SERVER}
  TUIC           UDP ${TUIC_PORT}  地址 ${TUIC_PUBLIC_SERVER}
  直连地址来源    ${DIRECT_ADDRESS_SOURCE}
  Argo 临时域名  ${ARGO_DOMAIN}

面板端口：${PANEL_PORT}
订阅端口：${SUB_PORT}
面板路径：${PANEL_PATH:-运行时生成}
订阅路径：${SUB_PATH:-运行时生成}

迁移完成后，面板中的 "用户管理" 可以为空。
你登录面板后自行新增用户，并自由勾选需要的入站。
EOF
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --plan) PLAN_ONLY=1 ;;
      --yes) ASSUME_YES=1 ;;
      --force-reimport) FORCE_REIMPORT=1 ;;
      --restore)
        shift
        [[ $# -gt 0 ]] || die "--restore 后需要备份目录"
        RESTORE_PATH="$1"
        ;;
      --version) version; exit 0 ;;
      --help|-h) usage; exit 0 ;;
      *) die "未知选项：$1" ;;
    esac
    shift
  done
}

preflight() {
  if [[ "$ALLOW_NON_ROOT" != "1" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "请先执行 sudo -i，再运行本脚本"
  fi

  if [[ "$ALLOW_NON_ROOT" != "1" ]]; then
    require_file /etc/os-release
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "目前仅支持 Ubuntu"
  fi

  require_command jq
  require_command curl
  require_command tar
  require_command openssl
  require_command base64

  ARCH="$(detect_arch "$(uname -m)")"
  load_source_config "$SOURCE_DIR"
}

prompt_settings() {
  local value
  PANEL_PATH="${PANEL_PATH:-/$(random_text 12)/}"
  SUB_PATH="${SUB_PATH:-/$(random_text 16)/}"
  ADMIN_USER="${ADMIN_USER:-admin_$(random_text 6)}"
  ADMIN_PASS="${ADMIN_PASS:-$(random_text 28)}"

  if (( ASSUME_YES == 0 )); then
    printf '面板端口 [%s]：' "$PANEL_PORT"; read -r value || true
    [[ -z "$value" ]] || PANEL_PORT="$value"
    printf '订阅端口 [%s]：' "$SUB_PORT"; read -r value || true
    [[ -z "$value" ]] || SUB_PORT="$value"
    printf '管理员用户名 [%s]：' "$ADMIN_USER"; read -r value || true
    [[ -z "$value" ]] || ADMIN_USER="$value"
    printf '管理员密码 [直接回车使用随机强密码]：'; read -r -s value || true; printf '\n'
    [[ -z "$value" ]] || ADMIN_PASS="$value"
  fi

  PANEL_PATH="$(normalize_path "$PANEL_PATH")"
  SUB_PATH="$(normalize_path "$SUB_PATH")"

  if ! [[ "$PANEL_PORT" =~ ^[0-9]+$ ]] ||
    (( PANEL_PORT < 1 || PANEL_PORT > 65535 )); then
    die "面板端口无效"
  fi
  if ! [[ "$SUB_PORT" =~ ^[0-9]+$ ]] ||
    (( SUB_PORT < 1 || SUB_PORT > 65535 )); then
    die "订阅端口无效"
  fi
  [[ "$PANEL_PORT" != "$SUB_PORT" ]] || die "面板端口和订阅端口不能相同"

  PANEL_BASE_URL="http://127.0.0.1:${PANEL_PORT}${PANEL_PATH}"
  SUB_BASE_URL="http://127.0.0.1:${SUB_PORT}${SUB_PATH}"
}

load_existing_state() {
  local credentials="$STATE_DIR/credentials.txt"
  local running_script_version="$SCRIPT_VERSION"
  # shellcheck disable=SC1090,SC1091
  . "$STATE_DIR/completed.env"
  SCRIPT_VERSION="$running_script_version"
  ADMIN_USER="${ADMIN_USER:-$(sed -n 's/^管理员用户名：//p' "$credentials" | head -n1)}"
  ADMIN_PASS="${ADMIN_PASS:-$(sed -n 's/^管理员密码：//p' "$credentials" | head -n1)}"
  [[ -n "$ADMIN_USER" && -n "$ADMIN_PASS" ]] ||
    die "无法读取现有面板凭据，请通过 ADMIN_USER 和 ADMIN_PASS 提供"
  PANEL_PATH="$(normalize_path "$PANEL_PATH")"
  SUB_PATH="$(normalize_path "$SUB_PATH")"
  PANEL_BASE_URL="http://127.0.0.1:${PANEL_PORT}${PANEL_PATH}"
  SUB_BASE_URL="http://127.0.0.1:${SUB_PORT}${SUB_PATH}"
}

port_is_listening() {
  local port="$1"
  run_ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)$port$"
}

check_management_ports() {
  local port
  for port in "$PANEL_PORT" "$SUB_PORT"; do
    case "$port" in
      "$VLESS_PORT"|"$VMESS_PORT"|"$HY2_PORT"|"$TUIC_PORT")
        die "管理端口 $port 与节点端口冲突"
        ;;
    esac
    if port_is_listening "$port" && [[ ! -d "$SUI_DIR" ]]; then
      die "端口 $port 已被占用。请用 PANEL_PORT 或 SUB_PORT 换一个端口"
    fi
  done
}

create_backup() {
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${BACKUP_BASE}/${stamp}"
  install -d -m 0700 "$BACKUP_DIR"

  cp -a "$SOURCE_DIR" "$BACKUP_DIR/sing-box"
  [[ ! -f "$SYSTEMD_DIR/sing-box.service" ]] ||
    cp -a "$SYSTEMD_DIR/sing-box.service" "$BACKUP_DIR/"
  [[ ! -f "$SYSTEMD_DIR/argo.service" ]] ||
    cp -a "$SYSTEMD_DIR/argo.service" "$BACKUP_DIR/"
  [[ ! -f /etc/nginx/conf.d/sing-box.conf ]] ||
    cp -a /etc/nginx/conf.d/sing-box.conf "$BACKUP_DIR/nginx-sing-box.conf"

  if [[ -d "$SUI_DIR" ]]; then
    cp -a "$SUI_DIR" "$BACKUP_DIR/s-ui"
    : >"$BACKUP_DIR/had-s-ui"
  fi

  {
    printf 'sing-box\t%s\t%s\n' \
      "$(run_systemctl is-enabled sing-box 2>/dev/null || true)" \
      "$(run_systemctl is-active sing-box 2>/dev/null || true)"
    printf 'argo\t%s\t%s\n' \
      "$(run_systemctl is-enabled argo 2>/dev/null || true)" \
      "$(run_systemctl is-active argo 2>/dev/null || true)"
    printf 's-ui\t%s\t%s\n' \
      "$(run_systemctl is-enabled s-ui 2>/dev/null || true)" \
      "$(run_systemctl is-active s-ui 2>/dev/null || true)"
  } >"$BACKUP_DIR/service-state.tsv"

  info "备份已保存：$BACKUP_DIR"
}

install_dependencies() {
  info "安装必要组件"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl jq tar openssl ca-certificates iproute2
}

install_sui_release() {
  local asset expected actual archive extract_dir
  asset="s-ui-linux-${ARCH}.tar.gz"
  archive="$TMP_DIR/$asset"
  extract_dir="$TMP_DIR/release"
  expected="$(release_checksum "$ARCH")"

  info "下载并校验 S-UI ${SUI_VERSION}"
  run_curl -fL --retry 3 --connect-timeout 15 \
    -o "$archive" \
    "https://github.com/admin8800/s-ui/releases/download/${SUI_VERSION}/${asset}"
  actual="$(sha256_file "$archive")"
  [[ "$actual" == "$expected" ]] || die "S-UI 下载文件校验失败"

  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  [[ -x "$extract_dir/s-ui/sui" ]] || die "S-UI 安装包结构异常"

  run_systemctl stop s-ui >/dev/null 2>&1 || true
  rm -rf "$SUI_DIR"
  install -d -m 0700 "$SUI_DIR"
  cp -a "$extract_dir/s-ui/." "$SUI_DIR/"
  chmod 0755 "$SUI_DIR/sui" "$SUI_DIR/s-ui.sh"
  install -m 0755 "$SUI_DIR/s-ui.sh" /usr/bin/s-ui
  install -m 0644 "$SUI_DIR/s-ui.service" "$SYSTEMD_DIR/s-ui.service"

  install -d -m 0700 "$SUI_DIR/cert/migrated"
  install -m 0600 "$SOURCE_DIR/cert.pem" "$SUI_DIR/cert/migrated/cert.pem"
  install -m 0600 "$SOURCE_DIR/private.key" "$SUI_DIR/cert/migrated/private.key"
  run_systemctl daemon-reload
}

initialize_sui() {
  info "初始化 S-UI 面板"
  (
    cd "$SUI_DIR"
    ./sui migrate
    ./sui setting \
      -port "$PANEL_PORT" \
      -path "$PANEL_PATH" \
      -subPort "$SUB_PORT" \
      -subPath "$SUB_PATH"
    ./sui admin -username "$ADMIN_USER" -password "$ADMIN_PASS"
  )
}

wait_for_panel() {
  local _
  for _ in $(seq 1 30); do
    if run_curl -fsS --connect-timeout 2 "${PANEL_BASE_URL}login" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  die "S-UI 面板启动超时"
}

api_request() {
  local method="$1" path="$2"
  shift 2
  local response
  response="$(run_curl -fsS -X "$method" \
    -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H 'X-Requested-With: XMLHttpRequest' \
    "$@" "${PANEL_BASE_URL}${path}")" || die "无法连接 S-UI API：$path"
  jq -e '.success == true' <<<"$response" >/dev/null ||
    die "S-UI API 失败：$(jq -r '.msg // "unknown error"' <<<"$response")"
  printf '%s' "$response"
}

api_login() {
  api_request POST api/login \
    --data-urlencode "user=$ADMIN_USER" \
    --data-urlencode "pass=$ADMIN_PASS" >/dev/null
}

api_get() {
  api_request GET "api/$1"
}

api_get_id() {
  local object="$1" id="$2"
  api_request GET "api/${object}?id=${id}"
}

api_save() {
  local object="$1" action="$2" data="$3" init_users="${4:-}"
  api_request POST api/save \
    --data-urlencode "object=$object" \
    --data-urlencode "action=$action" \
    --data-urlencode "data=$data" \
    --data-urlencode "initUsers=$init_users"
}

find_object_id() {
  local object="$1" key="$2" value="$3" response array_name
  case "$object" in
    tls) array_name="tls" ;;
    inbounds) array_name="inbounds" ;;
    outbounds) array_name="outbounds" ;;
    endpoints) array_name="endpoints" ;;
    clients) array_name="clients" ;;
    *) die "不支持查找对象：$object" ;;
  esac
  response="$(api_get "$object")"
  jq -r --arg array "$array_name" --arg key "$key" --arg value "$value" '
    .obj[$array][]? | select(.[$key] == $value) | .id
  ' <<<"$response" | head -n1
}

upsert_named_object() {
  local object="$1" key="$2" value="$3" payload="$4" id action response
  id="$(find_object_id "$object" "$key" "$value")"
  if [[ -n "$id" ]]; then
    action="edit"
    payload="$(jq --argjson id "$id" '.id = $id' <<<"$payload")"
  else
    action="new"
  fi
  response="$(api_save "$object" "$action" "$payload")"
  printf '%s' "$response" >/dev/null
  id="$(find_object_id "$object" "$key" "$value")"
  [[ -n "$id" ]] || die "S-UI 未保存对象：$value"
  printf '%s' "$id"
}

save_base_config() {
  local payload
  payload="$(build_base_config_payload)"
  api_save config set "$payload" >/dev/null
  sleep 2
  wait_for_panel
  api_login
}

import_sui_objects() {
  local payload
  info "导入 DNS、路由和 WARP"
  save_base_config

  payload="$(build_direct_outbound_payload)"
  upsert_named_object outbounds tag direct "$payload" >/dev/null

  payload="$(build_reality_tls_payload)"
  REALITY_TLS_ID="$(upsert_named_object tls name migrated-reality "$payload")"

  payload="$(build_shared_tls_payload)"
  SHARED_TLS_ID="$(upsert_named_object tls name migrated-quic-tls "$payload")"

  payload="$(build_warp_endpoint_payload)"
  upsert_named_object endpoints tag wireguard-out "$payload" >/dev/null

  info "导入四个入站"
  upsert_named_object inbounds tag vless-reality "$(build_vless_payload)" >/dev/null
  upsert_named_object inbounds tag vmess-ws-argo "$(build_vmess_payload)" >/dev/null
  upsert_named_object inbounds tag hysteria2 "$(build_hy2_payload)" >/dev/null
  upsert_named_object inbounds tag tuic "$(build_tuic_payload)" >/dev/null
}

create_api_token() {
  local response token
  response="$(api_request POST api/addToken \
    --data-urlencode "expiry=0" \
    --data-urlencode "desc=sui-argo-sync")"
  token="$(jq -er '.obj' <<<"$response")"
  printf '%s' "$token"
}

stop_legacy_core() {
  info "停止旧 sing-box，由 S-UI 接管"
  run_systemctl stop sing-box
  run_systemctl disable sing-box >/dev/null 2>&1 || true
}

start_sui_panel() {
  run_systemctl enable s-ui >/dev/null
  run_systemctl restart s-ui
  wait_for_panel
}

configure_firewall() {
  command -v ufw >/dev/null 2>&1 || return 0
  ufw status 2>/dev/null | grep -q '^Status: active' || return 0
  ufw allow "${PANEL_PORT}/tcp" >/dev/null
  ufw allow "${SUB_PORT}/tcp" >/dev/null
  ufw allow "${VLESS_PORT}/tcp" >/dev/null
  ufw allow "${HY2_PORT}/udp" >/dev/null
  ufw allow "${TUIC_PORT}/udp" >/dev/null
}

write_argo_sync_script() {
  local target="$1"
  cat >"$target" <<'SYNC'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="/var/lib/sui-argo-sync"
ARGO_LOG="/etc/sing-box/argo.log"
TOKEN_FILE="$STATE_DIR/token"
ENV_FILE="$STATE_DIR/panel.env"
LAST_DOMAIN_FILE="$STATE_DIR/last-domain"

[[ -r "$TOKEN_FILE" && -r "$ENV_FILE" && -r "$ARGO_LOG" ]] || exit 0
# shellcheck disable=SC1090
. "$ENV_FILE"
API_TOKEN="$(cat "$TOKEN_FILE")"
current="$(sed -nE 's#.*https://([^/ ]+\.trycloudflare\.com).*#\1#p' "$ARGO_LOG" | tail -n1)"
[[ "$current" == *.trycloudflare.com ]] || exit 0
previous="$(cat "$LAST_DOMAIN_FILE" 2>/dev/null || true)"
[[ "$current" != "$previous" ]] || exit 0

summary="$(curl -fsS -H "Token: $API_TOKEN" "${PANEL_BASE_URL}apiv2/inbounds")"
jq -e '.success == true' <<<"$summary" >/dev/null
id="$(jq -r '.obj.inbounds[]? | select(.tag=="vmess-ws-argo") | .id' <<<"$summary" | head -n1)"
[[ -n "$id" ]] || exit 1

detail="$(curl -fsS -H "Token: $API_TOKEN" "${PANEL_BASE_URL}apiv2/inbounds?id=${id}")"
jq -e '.success == true' <<<"$detail" >/dev/null
inbound="$(jq -c '.obj.inbounds[0]' <<<"$detail")"

updated="$(jq --arg domain "$current" '
  .addrs[0].tls.enabled = true
  | .addrs[0].tls.server_name = $domain
  | .transport.headers = ((.transport.headers // {}) + {"Host": $domain})
' <<<"$inbound")"

response="$(curl -fsS -X POST \
  -H "Token: $API_TOKEN" \
  --data-urlencode "object=inbounds" \
  --data-urlencode "action=edit" \
  --data-urlencode "data=$updated" \
  "${PANEL_BASE_URL}apiv2/save")"
jq -e '.success == true' <<<"$response" >/dev/null
printf '%s\n' "$current" >"$LAST_DOMAIN_FILE"
SYNC
  chmod 0700 "$target"
}

install_argo_sync() {
  local api_token
  info "安装 Argo 临时域名自动同步"
  api_token="$(create_api_token)"
  install -d -m 0700 "$ARGO_SYNC_DIR" /usr/local/lib/sui-argo-sync
  printf '%s' "$api_token" >"$ARGO_SYNC_DIR/token"
  chmod 0600 "$ARGO_SYNC_DIR/token"
  {
    printf 'PANEL_BASE_URL=%q\n' "$PANEL_BASE_URL"
  } >"$ARGO_SYNC_DIR/panel.env"
  chmod 0600 "$ARGO_SYNC_DIR/panel.env"

  write_argo_sync_script /usr/local/lib/sui-argo-sync/sync.sh

  cat >"$SYSTEMD_DIR/sui-argo-sync.service" <<'EOF'
[Unit]
Description=Synchronize temporary Cloudflare Argo domain into S-UI
After=s-ui.service argo.service
Wants=s-ui.service argo.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/sui-argo-sync/sync.sh
User=root
Group=root
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/sui-argo-sync
EOF

  cat >"$SYSTEMD_DIR/sui-argo-sync.timer" <<'EOF'
[Unit]
Description=Run S-UI Argo synchronization every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Persistent=true
Unit=sui-argo-sync.service

[Install]
WantedBy=timers.target
EOF

  cat >"$SYSTEMD_DIR/sui-argo-sync.path" <<'EOF'
[Unit]
Description=Watch Cloudflare Argo log for domain changes

[Path]
PathChanged=/etc/sing-box/argo.log
Unit=sui-argo-sync.service

[Install]
WantedBy=multi-user.target
EOF

  run_systemctl daemon-reload
  run_systemctl enable argo >/dev/null 2>&1 || true
  run_systemctl enable --now sui-argo-sync.timer sui-argo-sync.path >/dev/null
  run_systemctl restart argo
  sleep 4
  run_systemctl start sui-argo-sync.service
}

object_count() {
  local object="$1" array="$2"
  api_get "$object" | jq -r --arg array "$array" '.obj[$array] | length'
}

validate_listeners() {
  local missing=0
  for port in "$VLESS_PORT" "$VMESS_PORT" "$HY2_PORT" "$TUIC_PORT"; do
    if ! port_is_listening "$port"; then
      error "端口没有监听：$port"
      missing=1
    fi
  done
  (( missing == 0 ))
}

validate_argo_mapping() {
  local id detail domain
  id="$(find_object_id inbounds tag vmess-ws-argo)"
  detail="$(api_get_id inbounds "$id")"
  domain="$(jq -r '.obj.inbounds[0].addrs[0].tls.server_name' <<<"$detail")"
  [[ "$domain" == *.trycloudflare.com ]] || die "VMess 的 Argo 域名无效"
}

validate_outbound_route() {
  local response tags config final missing invalid_rules
  response="$(api_get outbounds)"
  tags="$(jq -r '.obj.outbounds[]?.tag' <<<"$response")"
  grep -Fxq 'direct' <<<"$tags" || die "缺少 direct 出站，节点无法访问外网"

  response="$(api_get config)"
  config="$(jq -c '.obj.config // .config // .obj // .' <<<"$response")"
  final="$(jq -r '.route.final // "direct"' <<<"$config")"
  [[ -n "$final" ]] || final="direct"
  if ! grep -Fxq "$final" <<<"$tags" &&
    ! api_get endpoints | jq -e --arg tag "$final" '.obj.endpoints[]? | select(.tag == $tag)' >/dev/null; then
    die "路由最终出口不存在：$final"
  fi

  invalid_rules="$(jq -c '
    (.route.rules // [])[]
    | select(
        ((.outbound? // "") == "")
        and (((.action? // "") == "") or ((.action? // "") == "route"))
      )
  ' <<<"$config")"
  [[ -z "$invalid_rules" ]] || die "路由中存在没有出口的空规则"

  missing="$(jq -r '
    (.route.rules // [])[]
    | .outbound? // empty
  ' <<<"$config" | while read -r tag; do
    [[ -z "$tag" ]] && continue
    grep -Fxq "$tag" <<<"$tags" && continue
    api_get endpoints | jq -e --arg tag "$tag" '.obj.endpoints[]? | select(.tag == $tag)' >/dev/null && continue
    printf '%s\n' "$tag"
  done | sort -u)"
  [[ -z "$missing" ]] || die "路由规则引用了不存在的出口：$(tr '\n' ' ' <<<"$missing")"
}

new_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    local hex
    hex="$(openssl rand -hex 16)"
    printf '%s-%s-4%s-%x%s-%s\n' \
      "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
      "$(( (0x${hex:16:1} & 3) | 8 ))" "${hex:17:3}" "${hex:20:12}"
  fi
}

build_test_client_payload() {
  local name="$1" inbound_ids="$2" uuid password
  uuid="$(new_uuid)"
  password="$(random_text 18)"
  jq -n \
    --arg name "$name" \
    --arg uuid "$uuid" \
    --arg password "$password" \
    --argjson inbounds "$inbound_ids" \
    '{
      enable: true,
      name: $name,
      config: {
        vmess: {name: $name, uuid: $uuid, alterId: 0},
        vless: {name: $name, uuid: $uuid, flow: "xtls-rprx-vision"},
        hysteria2: {name: $name, password: $password},
        tuic: {name: $name, uuid: $uuid, password: $password}
      },
      inbounds: $inbounds,
      links: [],
      volume: 0,
      expiry: 0,
      up: 0,
      down: 0,
      desc: "temporary migration health check",
      group: "",
      delayStart: false,
      autoReset: false,
      resetDays: 0,
      nextReset: 0,
      totalUp: 0,
      totalDown: 0
    }'
}

validate_disposable_subscription() (
  local name inbound_ids payload client_id raw decoded
  name="__migration_check_$(random_text 8)"
  client_id=""
  trap '[[ -z "$client_id" ]] || api_save clients del "$client_id" >/dev/null 2>&1 || true' EXIT

  inbound_ids="$(api_get inbounds | jq -c '
    [.obj.inbounds[]
      | select(.tag=="vless-reality" or .tag=="vmess-ws-argo" or .tag=="hysteria2" or .tag=="tuic")
      | .id] | sort
  ')"
  [[ "$(jq 'length' <<<"$inbound_ids")" -eq 4 ]] || die "无法取得四个入站 ID"

  payload="$(build_test_client_payload "$name" "$inbound_ids")"
  api_save clients new "$payload" >/dev/null
  client_id="$(find_object_id clients name "$name")"
  [[ -n "$client_id" ]] || die "临时测试用户创建失败"

  raw=""
  for _ in $(seq 1 10); do
    raw="$(run_curl -fsS "${SUB_BASE_URL}${name}" 2>/dev/null || true)"
    [[ -n "$raw" ]] && break
    sleep 1
  done
  [[ -n "$raw" ]] || die "无法读取临时测试订阅"

  decoded="$(printf '%s' "$raw" | tr -d '\r\n' | decode_base64 2>/dev/null || true)"
  [[ -n "$decoded" ]] || decoded="$raw"
  grep -q 'vless://' <<<"$decoded" || die "测试订阅缺少 VLESS"
  grep -q 'vmess://' <<<"$decoded" || die "测试订阅缺少 VMess"
  grep -q 'hysteria2://' <<<"$decoded" || die "测试订阅缺少 Hysteria2"
  grep -q 'tuic://' <<<"$decoded" || die "测试订阅缺少 TUIC"
  validate_subscription_links "$decoded"
)

validate_subscription_links() {
  local decoded="$1" line scheme authority colon_count
  while IFS= read -r line; do
    case "$line" in
      vless://*|hysteria2://*|tuic://*)
        scheme="${line%%://*}"
        if [[ "$line" =~ ^[a-zA-Z0-9]+://[^@]+@([^/?#]+) ]]; then
          authority="${BASH_REMATCH[1]}"
        else
          die "测试订阅链接无法解析：$scheme"
        fi
        colon_count="$(tr -cd ':' <<<"$authority" | wc -c | tr -d ' ')"
        if [[ "$authority" == \[*\]:* ]]; then
          :
        elif (( colon_count == 1 )); then
          :
        else
          die "测试订阅 IPv6 地址缺少方括号：$scheme"
        fi
        ;;
    esac
  done <<<"$decoded"
}

validate_migration() {
  info "执行迁移健康检查"
  run_systemctl is-active --quiet s-ui || die "S-UI 服务未运行"
  run_systemctl is-active --quiet argo || die "Argo 服务未运行"
  api_login

  [[ "$(object_count tls tls)" -ge 2 ]] || die "TLS 配置数量不足"
  [[ "$(object_count inbounds inbounds)" -eq 4 ]] || die "四个入站没有全部导入"
  validate_outbound_route
  validate_listeners
  validate_argo_mapping
  validate_disposable_subscription

  run_systemctl restart s-ui
  wait_for_panel
  api_login
  validate_listeners
}

write_credentials() {
  install -d -m 0700 "$STATE_DIR"
  cat >"$STATE_DIR/credentials.txt" <<EOF
面板地址：http://服务器IP:${PANEL_PORT}${PANEL_PATH}
订阅前缀：http://服务器IP:${SUB_PORT}${SUB_PATH}
管理员用户名：${ADMIN_USER}
管理员密码：${ADMIN_PASS}
备份目录：${BACKUP_DIR}
EOF
  chmod 0600 "$STATE_DIR/credentials.txt"
  cat >"$STATE_DIR/completed.env" <<EOF
SCRIPT_VERSION=${SCRIPT_VERSION}
SUI_VERSION=${SUI_VERSION}
BACKUP_DIR=${BACKUP_DIR}
PANEL_PORT=${PANEL_PORT}
PANEL_PATH=${PANEL_PATH}
SUB_PORT=${SUB_PORT}
SUB_PATH=${SUB_PATH}
EOF
  chmod 0600 "$STATE_DIR/completed.env"
}

public_ip() {
  run_curl -4fsS --connect-timeout 4 https://api64.ipify.org 2>/dev/null ||
    run_curl -6fsS --connect-timeout 4 https://api64.ipify.org 2>/dev/null ||
    printf '你的服务器IP'
}

print_success() {
  local ip
  ip="$(public_ip)"
  cat <<EOF

${green}迁移成功。${plain}

S-UI 面板：
  http://${ip}:${PANEL_PORT}${PANEL_PATH}

管理员用户名：
  ${ADMIN_USER}

管理员密码：
  ${ADMIN_PASS}

订阅地址格式：
  http://${ip}:${SUB_PORT}${SUB_PATH}用户名

直连节点地址：
  ${VLESS_PUBLIC_SERVER}（${DIRECT_ADDRESS_SOURCE}）

VMess CDN：
  ${ARGO_PUBLIC_SERVER}:${ARGO_PUBLIC_PORT}

下一步：
  1. 打开上面的面板地址并登录。
  2. 进入 "用户管理"。
  3. 新增用户。
  4. 勾选 VLESS-Reality、VMess-Argo、Hysteria2、TUIC 中需要的入站。
  5. 按需设置流量和到期时间。

凭据也保存在：
  ${STATE_DIR}/credentials.txt

原配置备份在：
  ${BACKUP_DIR}
EOF
}

restore_backup() {
  local path="$1"
  [[ -d "$path" ]] || die "备份目录不存在：$path"
  [[ -d "$path/sing-box" ]] || die "备份中缺少 sing-box 目录"

  warn "正在恢复备份：$path"
  run_systemctl stop s-ui >/dev/null 2>&1 || true
  run_systemctl disable s-ui >/dev/null 2>&1 || true

  rm -rf "$SOURCE_DIR"
  cp -a "$path/sing-box" "$SOURCE_DIR"
  [[ ! -f "$path/sing-box.service" ]] ||
    cp -a "$path/sing-box.service" "$SYSTEMD_DIR/sing-box.service"
  [[ ! -f "$path/argo.service" ]] ||
    cp -a "$path/argo.service" "$SYSTEMD_DIR/argo.service"
  [[ ! -f "$path/nginx-sing-box.conf" ]] ||
    cp -a "$path/nginx-sing-box.conf" /etc/nginx/conf.d/sing-box.conf

  if [[ -d "$path/s-ui" ]]; then
    rm -rf "$SUI_DIR"
    cp -a "$path/s-ui" "$SUI_DIR"
  elif [[ ! -f "$path/had-s-ui" ]]; then
    rm -rf "$SUI_DIR"
    rm -f "$SYSTEMD_DIR/s-ui.service" /usr/bin/s-ui
  fi

  run_systemctl disable --now sui-argo-sync.timer sui-argo-sync.path >/dev/null 2>&1 || true
  rm -f \
    "$SYSTEMD_DIR/sui-argo-sync.service" \
    "$SYSTEMD_DIR/sui-argo-sync.timer" \
    "$SYSTEMD_DIR/sui-argo-sync.path"
  rm -rf /usr/local/lib/sui-argo-sync "$ARGO_SYNC_DIR"

  run_systemctl daemon-reload
  run_systemctl enable sing-box >/dev/null 2>&1 || true
  run_systemctl restart sing-box
  run_systemctl enable argo >/dev/null 2>&1 || true
  run_systemctl restart argo
  if command -v nginx >/dev/null 2>&1 && nginx -t; then
    run_systemctl reload nginx || true
  fi
  info "备份恢复完成"
}

rollback_migration() {
  error "迁移失败，正在恢复原节点"
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0
  restore_backup "$BACKUP_DIR"
}

cleanup() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 && MUTATION_STARTED == 1 && MIGRATION_COMMITTED == 0 )); then
    rollback_migration || true
  fi
  [[ -z "$TMP_DIR" ]] || rm -rf "$TMP_DIR"
  exit "$rc"
}

confirm_migration() {
  (( ASSUME_YES == 1 )) && return 0
  printf '\n确认开始迁移吗？输入 YES 继续：'
  local answer
  read -r answer
  [[ "$answer" == "YES" ]] || die "已取消"
}

perform_migration() {
  TMP_DIR="$(mktemp -d)"
  COOKIE_JAR="$TMP_DIR/cookies.txt"
  trap cleanup EXIT

  if [[ -f "$STATE_DIR/completed.env" ]]; then
    [[ "$FORCE_REIMPORT" == "1" ]] ||
      die "检测到已经迁移完成。需要重新导入时使用 --force-reimport"
    info "进入重新导入模式；现有用户不会删除"
    create_backup
    MUTATION_STARTED=1
    wait_for_panel
    api_login
    import_sui_objects
    configure_firewall
    install_argo_sync
    validate_migration
    write_credentials
    MIGRATION_COMMITTED=1
    print_success
    return
  fi

  install_dependencies
  create_backup
  install_sui_release
  initialize_sui

  MUTATION_STARTED=1
  stop_legacy_core
  start_sui_panel
  api_login
  import_sui_objects
  configure_firewall
  install_argo_sync
  validate_migration
  write_credentials
  MIGRATION_COMMITTED=1
  print_success
}

main() {
  parse_args "$@"

  if [[ -n "$RESTORE_PATH" ]]; then
    if [[ "$ALLOW_NON_ROOT" != "1" && "${EUID:-$(id -u)}" -ne 0 ]]; then
      die "恢复操作需要 root"
    fi
    restore_backup "$RESTORE_PATH"
    return
  fi

  preflight
  if [[ -f "$STATE_DIR/completed.env" && "$FORCE_REIMPORT" == "1" ]]; then
    load_existing_state
  else
    prompt_settings
  fi
  check_management_ports
  print_plan

  if (( PLAN_ONLY == 1 )); then
    info "当前是 --plan 模式，没有修改服务器"
    return
  fi

  confirm_migration
  perform_migration
}

if [[ "${SUI_MIGRATE_LIBRARY_MODE:-0}" != "1" ]]; then
  main "$@"
fi
