# 新手上传到 GitHub：一步一步操作

你不需要会写代码，也不需要使用 Git 命令。

## 一、创建仓库

1. 登录 GitHub。
2. 点击右上角的 `+`。
3. 点击 `New repository`。
4. `Repository name` 填：

   ```text
   migration-script
   ```

5. 选择 `Public`。
6. 勾选 `Add a README file` 也可以，不勾选也可以。
7. 点击绿色的 `Create repository`。

为什么选 Public：你的 VPS 才能直接使用一行命令下载脚本。

公共仓库任何人都能看到，但这个脚本里面没有你的服务器 IP、密码、Token 或节点密钥。你的私人配置只会在 VPS 本机读取。

## 二、上传文件

仓库创建完成后：

1. 点击 `Add file`。
2. 点击 `Upload files`。
3. 把下面两个文件拖进网页：

   ```text
   sui-singbox-migrate.sh
   README.md
   ```

4. 页面往下拉。
5. 点击绿色的 `Commit changes`。

## 三、找到你的一键命令

当前仓库：

- GitHub 用户名是 `yaozitao709-del`
- 仓库名称是 `migration-script`

那么检查命令是：

```bash
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh) --plan
```

正式运行命令是：

```bash
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh)
```

以上命令已经替换成当前仓库的真实地址，可以直接复制使用。

如果已经迁移过，但需要重新修复 S-UI 里的入站、出站和路由，可以运行：

```bash
bash <(curl -fsSL --connect-timeout 15 https://raw.githubusercontent.com/yaozitao709-del/migration-script/main/sui-singbox-migrate.sh) --force-reimport
```

## 四、先检查，再正式运行

登录 Ubuntu VPS 后，先执行：

```bash
sudo -i
```

再运行带有 `--plan` 的检查命令。

确认它识别出了：

- VLESS-Reality；
- VMess-WS-Argo；
- Hysteria2；
- TUIC；
- Argo 临时域名。

检查没有问题以后，再运行不带 `--plan` 的正式命令。

## 五、迁移后怎么用

脚本结束时会显示 S-UI 面板地址、用户名和密码。

进入面板后：

1. 打开“用户管理”；
2. 新增用户；
3. 勾选这个用户能用的入站；
4. 设置流量和到期时间；
5. 保存并复制订阅链接。

以后添加或删除用户都在 S-UI 面板里操作，不需要再修改脚本。
