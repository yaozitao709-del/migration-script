# S-UI 接管 sing-box 四协议节点

这个工具适合以下使用方式：

1. Ubuntu VPS 已经运行过 `eooce/sing-box` 四协议一键脚本；
2. 四个节点已经搭建完成；
3. 希望安装 S-UI，并在面板里自行添加、删除和管理用户。

迁移后会在 S-UI 中准备好：

- VLESS-Reality；
- VMess-WS + Cloudflare Argo 临时隧道；
- Hysteria2；
- TUIC；
- Reality TLS；
- Hysteria2/TUIC 共用 TLS；
- 原有 WARP、DNS 和路由配置；
- Argo 临时域名自动同步。

脚本不会把你的服务器 IP、节点密钥或管理员密码写进 GitHub。它只会在你的 VPS 上读取现有配置。

## 使用前

- 目前仅支持 Ubuntu；
- 使用 root 账号运行；
- 原脚本目录必须是 `/etc/sing-box`；
- 先确认原来的四协议节点可以运行；
- 建议先为 VPS 创建快照。

## 第一次先检查

```bash
sudo -i
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh) --plan
```

`--plan` 只检查，不会改服务器。

## 正式迁移

```bash
sudo -i
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh)
```

脚本会让你确认：

- 面板端口；
- 订阅端口；
- 管理员用户名；
- 管理员密码。

最后必须输入大写的：

```text
YES
```

才会开始迁移。

## 迁移完成以后

脚本会显示 S-UI 面板网址、用户名和密码。

登录后：

1. 打开“用户管理”；
2. 点击新增用户；
3. 输入用户名称；
4. 勾选这个用户可以使用的入站；
5. 设置流量、到期时间；
6. 保存；
7. 复制该用户的订阅链接。

你可以让不同用户拥有不同节点，不需要默认选四个。

## 安全组端口

脚本可以处理已启用的 UFW，但不能替你修改云服务商网站里的安全组。

需要放行：

- S-UI 面板 TCP 端口；
- S-UI 订阅 TCP 端口；
- VLESS TCP 端口；
- VMess-Argo 的 8001 端口只监听本机，不需要对公网开放；
- Hysteria2 UDP 端口；
- TUIC UDP 端口。

## Argo 临时域名

原脚本默认使用 `trycloudflare.com` 临时域名。域名改变时，本工具安装的同步服务会自动更新 S-UI 中的 VMess 地址。

检查状态：

```bash
systemctl status argo
systemctl status sui-argo-sync.timer
systemctl status sui-argo-sync.path
```

## 恢复旧节点

脚本运行前会把旧配置备份到：

```text
/root/sui-migration-backup/日期-时间/
```

恢复命令：

```bash
bash sui-singbox-migrate.sh --restore /root/sui-migration-backup/具体备份目录
```

## 重新导入基础配置

如果之后只想重新导入 TLS、入站和路由，同时保留 S-UI 中的用户：

```bash
bash sui-singbox-migrate.sh --force-reimport
```

如果你是用 GitHub Raw 一行命令运行的，也可以直接用：

```bash
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh) --force-reimport
```

`--force-reimport` 会修复已经导入过的基础配置，不会删除你在 S-UI 面板里创建的用户。这个版本会额外修复：

- IPv6 公开地址在 VLESS、Hysteria2、TUIC 订阅链接中缺少 `[]` 导致客户端提示“无效 URL 配置”；
- S-UI 缺少可用 `direct` 出站导致 VMess 能导入但实际访问超时；
- 健康检查只看端口、不检查订阅链接和路由出口的问题。

## 上传到 GitHub：最简单的网页操作

建议仓库设为 `Public`，这样 VPS 才能直接使用一行命令。公共仓库中的代码任何人都能看到，所以不要把密码、Token、服务器 IP 或密钥上传进去。

本工具本身不包含你的私人信息。

操作步骤：

1. 在 GitHub 创建一个 Public 仓库，例如 `migration-script`；
2. 打开仓库；
3. 点击 `Add file`；
4. 点击 `Upload files`；
5. 上传 `sui-singbox-migrate.sh` 和 `README.md`；
6. 点击 `Commit changes`；
7. 点击仓库中的 `sui-singbox-migrate.sh`；
8. 点击 `Raw`；
9. 复制地址。

最终命令通常是：

```bash
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh)
```

终端中不要复制 Markdown 的中括号或圆括号链接格式。

## 固定版本

- 来源配置：`eooce/sing-box@9b4a35d79944b41c57751ebcebc6ff55ada83df3`
- S-UI：`v1.4.1`
- S-UI 内嵌 sing-box：`v1.13.4`

S-UI 下载文件会经过 SHA-256 校验。
