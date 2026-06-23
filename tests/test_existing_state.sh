#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers.sh"
export SUI_MIGRATE_LIBRARY_MODE=1
source "$ROOT_DIR/sui-singbox-migrate.sh"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

STATE_DIR="$temp_dir"
cat >"$STATE_DIR/completed.env" <<'EOF'
SCRIPT_VERSION=0.1.0
SUI_VERSION=1.4.1
BACKUP_DIR=/root/sui-migration-backup/old
PANEL_PORT=2095
PANEL_PATH=/panel/
SUB_PORT=2096
SUB_PATH=/subscription/
EOF
cat >"$STATE_DIR/credentials.txt" <<'EOF'
管理员用户名：existing_admin
管理员密码：existing_password
EOF

current_version="$SCRIPT_VERSION"
ADMIN_USER=""
ADMIN_PASS=""
load_existing_state

assert_eq "$current_version" "$SCRIPT_VERSION" "重新导入保留当前脚本版本"
assert_eq "existing_admin" "$ADMIN_USER" "读取现有管理员用户名"
assert_eq "existing_password" "$ADMIN_PASS" "读取现有管理员密码"
assert_eq "http://127.0.0.1:2095/panel/" "$PANEL_BASE_URL" "恢复面板 API 地址"
assert_eq "http://127.0.0.1:2096/subscription/" "$SUB_BASE_URL" "恢复订阅 API 地址"

finish_tests
