#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

VLESS_PORT=41001
VMESS_PORT=41002
HY2_PORT=41003
TUIC_PORT=41004

listener_attempt=0
sleep_count=0
# shellcheck disable=SC2329
port_is_listening() {
  local port="$1"
  if (( listener_attempt >= 2 )); then
    return 0
  fi
  [[ "$port" == "$VMESS_PORT" ]]
}
run_sleep() {
  sleep_count=$((sleep_count + 1))
  listener_attempt=$((listener_attempt + 1))
}

wait_for_listeners 4
assert_eq "2" "$sleep_count" "监听检查会等待异步启动"

listener_attempt=0
sleep_count=0
# shellcheck disable=SC2329
port_is_listening() {
  [[ "$1" != "$TUIC_PORT" ]]
}
assert_fails "端口持续缺失时监听检查超时" wait_for_listeners 3
assert_eq "2" "$sleep_count" "超时前按次数重试"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
SOURCE_DIR="$temp_dir/source"
SUI_DIR="$temp_dir/s-ui"
STATE_DIR="$temp_dir/state"
ARGO_SYNC_DIR="$temp_dir/argo-sync-state"
SYSTEMD_DIR="$temp_dir/systemd"
backup="$temp_dir/backup"
mkdir -p \
  "$SOURCE_DIR" \
  "$SUI_DIR" \
  "$STATE_DIR" \
  "$ARGO_SYNC_DIR" \
  "$SYSTEMD_DIR" \
  "$backup/sing-box"
printf 'old\n' >"$SOURCE_DIR/runtime.log"
printf 'restored\n' >"$backup/sing-box/config.json"
printf 'unit\n' >"$backup/sing-box.service"
printf 'unit\n' >"$backup/argo.service"
cat >"$backup/service-state.tsv" <<'EOF'
sing-box	enabled	active
argo	enabled	active
s-ui	not-found	inactive
EOF

events=""
record_event() {
  events+="$1"$'\n'
}
run_systemctl() {
  record_event "systemctl $*"
  return 0
}
run_pkill() {
  record_event "pkill $*"
  return 0
}
run_sleep() {
  record_event "sleep $*"
}
port_is_listening() {
  return 1
}
restore_source_tree() {
  record_event "restore source"
  rm -rf "$SOURCE_DIR"
  cp -a "$backup/sing-box" "$SOURCE_DIR"
}

restore_backup "$backup"

stop_line="$(grep -n 'systemctl stop sing-box argo' <<<"$events" | head -n1 | cut -d: -f1)"
kill_line="$(grep -n '^pkill ' <<<"$events" | head -n1 | cut -d: -f1)"
restore_line="$(grep -n '^restore source$' <<<"$events" | head -n1 | cut -d: -f1)"
start_line="$(grep -n 'systemctl start sing-box' <<<"$events" | head -n1 | cut -d: -f1)"

assert_eq "true" "$([[ -n "$stop_line" && -n "$restore_line" && "$stop_line" -lt "$restore_line" ]] && echo true || echo false)" \
  "回滚复制前停止旧核心和 Argo"
assert_eq "true" "$([[ -n "$kill_line" && -n "$restore_line" && "$kill_line" -lt "$restore_line" ]] && echo true || echo false)" \
  "回滚复制前清理残留进程"
assert_eq "true" "$([[ -n "$restore_line" && -n "$start_line" && "$restore_line" -lt "$start_line" ]] && echo true || echo false)" \
  "回滚复制完成后才启动旧核心"
assert_eq "restored" "$(cat "$SOURCE_DIR/config.json")" "回滚恢复源配置"

finish_tests
