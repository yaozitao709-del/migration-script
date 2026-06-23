# Prefer IPv4 for Direct Nodes

## Goal

VLESS-Reality、Hysteria2 和 TUIC 默认发布 VPS 公网 IPv4，避免继承原订阅中速度较慢的 IPv6；VMess-Argo 继续使用原有 CDN 地址和端口。

## Behavior

- `DIRECT_PUBLIC_IP` 有值时，必须是合法 IPv4，并作为三个直连节点的公开地址。
- 未指定时，脚本通过多个只返回 IPv4 的公共查询端点自动探测。
- 自动探测失败时，保留原订阅中的各协议地址，不阻断迁移。
- VMess 的 `ARGO_PUBLIC_SERVER`、`ARGO_PUBLIC_PORT`、Host、SNI 和 WebSocket 路径保持不变。
- `--force-reimport` 更新三个直连入站的公开地址，但保留 S-UI 用户。
- 计划输出明确显示三个直连节点将使用的地址及其来源。

## Validation

- 自动 IPv4、手动 IPv4和探测失败回退都要有测试。
- 测试必须证明三个直连节点使用 IPv4，VMess 仍使用 CDN。
- 完整测试、Bash 语法、ShellCheck 和 SHA-256 校验必须通过。
