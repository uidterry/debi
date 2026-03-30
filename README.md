# Debian VPS 重装与初始化

基于 [debi](https://github.com/bohanwood/debi) 的 VPS 远程重装方案，分两步完成：先重装系统，再手动初始化。

## 为什么分两步

原先通过 cloud-init 在首次启动时自动完成所有配置，但在部分机器上会出现：
- cloud-init 接管网络导致 SSH 无法连接
- runcmd 阶段网络未就绪导致软件安装失败
- SSH 配置冲突导致连接被拒

拆分后，重装只做基础系统 + 常用运维工具安装，初始化在手动 SSH 登录后执行，完全避免了 cloud-init 的不可控问题。

## 快速开始

> **安全提示**：通过命令行传入的密码会记录在 shell 历史中，仅适合即将被擦除的临时环境。正式使用建议交互模式（`-i`）输入敏感信息。

### 第一步：重装系统

```bash
# 最简用法（仅必填参数）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh | env ROOT_PASSWORD='xxx' bash

# 自定义全部参数（海外示例）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh | env \
  ROOT_PASSWORD='xxx' \
  DEBIAN_VERSION=13 \
  REGION=overseas \
  SSH_PORT=2222 \
  TIMEZONE=Asia/Shanghai \
  bash

# 国内示例（需自备 GitHub 代理）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh | env \
  ROOT_PASSWORD='xxx' \
  DEBIAN_VERSION=13 \
  REGION=china \
  SSH_PORT=2222 \
  TIMEZONE=Asia/Shanghai \
  GITHUB_PROXY='https://your-proxy.example.com' \
  bash

# 显式透传 debi 可选参数（示例：启用 firmware）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh | env \
  ROOT_PASSWORD='xxx' \
  bash -s -- --firmware

# 显式透传 debi 可选参数（示例：关闭 apt source 仓库）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh | env \
  ROOT_PASSWORD='xxx' \
  bash -s -- --no-apt-src

# 交互模式
bash <(curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/reinstall.sh) -i
```

执行完成后手动 `reboot`，等待 5-15 分钟。安装期间可通过 `ssh installer@服务器IP`（端口 22）观察进度。

### 第二步：初始化配置

重装完成后以 root 密码登录新系统（"root 仅密钥登录"在 init.sh 执行完成后才生效）：

```bash
# 最简用法（仅必填参数）
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/init.sh | env \
  USER_PASSWORD='xxx' \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAA...' \
  bash

# 自定义全部参数
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/init.sh | env \
  USERNAME=yourname \
  USER_PASSWORD='xxx' \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAA...' \
  REGION=overseas \
  DOCKER_DATA_ROOT=/data/docker \
  INSTALL_NODEJS=true \
  NODEJS_VERSION=24 \
  bash

# 不安装 Node.js
curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/init.sh | env \
  USER_PASSWORD='xxx' \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAA...' \
  INSTALL_NODEJS=false \
  bash

# 交互模式
bash <(curl -fsSL https://raw.githubusercontent.com/uidterry/debi/main/init.sh) -i
```

## 参数说明

### reinstall.sh

| 环境变量 | 必填 | 默认值 | 说明 |
|----------|------|--------|------|
| ROOT_PASSWORD | 是 | - | root 密码。用于控制台登录和重装后首次 SSH 登录（init.sh 执行后 root 改为仅密钥登录） |
| DEBIAN_VERSION | 否 | 13 | Debian 版本号（纯数字），对应 debi 的 `--version` 参数，如 `12`（bookworm）、`13`（trixie）。实际可用版本以 [debi 上游](https://github.com/bohanwood/debi) 支持范围为准 |
| REGION | 否 | overseas | 部署地区。`overseas` = 海外（debi `--cloudflare` 预设，镜像源 deb.debian.org），`china` = 国内（debi `--ustc` 预设，镜像源中科大） |
| SSH_PORT | 否 | 22 | 重装后新系统的 SSH 端口（1-65535），建议非 22 以减少扫描 |
| TIMEZONE | 否 | Asia/Shanghai | 系统时区，格式为 [tz 数据库名称](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)，如 `Asia/Tokyo`、`UTC` |
| GITHUB_PROXY | 否 | -（直连） | GitHub 反代地址，仅 `REGION=china` 时生效。格式：`https://your-proxy.com`，脚本会拼接为 `代理地址/原始URL` |

`reinstall.sh` 默认不再强制传 `--firmware` 和 `--no-apt-src` 给上游 debi，会保留上游默认行为。如需启用这两个参数，请在执行脚本时显式透传，例如 `bash -s -- --firmware` 或 `bash -s -- --no-apt-src`。

### init.sh

| 环境变量 | 必填 | 默认值 | 说明 |
|----------|------|--------|------|
| USER_PASSWORD | 是 | - | 普通用户密码，用于 SSH 密码登录和 `su` 切换 |
| SSH_PUBLIC_KEY | 是 | - | SSH 公钥，root 和普通用户共用。格式：`ssh-ed25519 AAAA...` 或 `ssh-rsa AAAA...`（完整公钥字符串） |
| USERNAME | 否 | yourname | 普通用户名，须符合 Linux 规范（小写字母开头，仅含小写字母/数字/下划线/连字符，最长 32 位） |
| REGION | 否 | overseas | 部署地区，影响 Docker 源选择。`overseas` = Docker 官方源，`china` = 阿里云镜像源 |
| DOCKER_DATA_ROOT | 否 | /data/docker | Docker 数据存储目录，必须是绝对路径且不能为 `/`。如有独立数据盘可指向挂载点（如 `/mnt/data/docker`） |
| INSTALL_NODEJS | 否 | true | 是否安装 Node.js，仅接受 `true` 或 `false` |
| NODEJS_VERSION | 否 | 24 | Node.js 大版本号（纯数字，如 18、20、24），通过 [NodeSource](https://github.com/nodesource/distributions) 安装 |

## 初始化内容

### reinstall.sh 做了什么

| 项目 | 配置 |
|------|------|
| 系统版本 | 由 `DEBIAN_VERSION` 指定，默认 Debian 13 (trixie) |
| 安装期 SSH | `--network-console`，可在安装过程中连入 |
| TCP BBR | 启用 |
| 软件源 | 海外 deb.debian.org（`--cloudflare` 预设） / 国内中科大（`--ustc` 预设） |
| 时区 | 默认 Asia/Shanghai（可自定义） |
| NTP | 海外 time.cloudflare.com / 国内 ntp.aliyun.com |
| 非自由固件 / apt source | 默认跟随上游 debi；如需覆盖，可显式透传 `--firmware` 或 `--no-apt-src` |
| 预装软件 | 见下方清单 |

### init.sh 做了什么

| 步骤 | 内容 |
|------|------|
| hostname 修复 | 防止 sudo 报 "unable to resolve host" |
| 创建普通用户 | sudo 免密码，设置密码，注入 SSH 公钥 |
| 安装 Docker | DEB822 格式，可自定义数据目录 |
| 安装 Node.js（可选） | 通过 `INSTALL_NODEJS=false` 跳过，版本通过 `NODEJS_VERSION` 自定义。同时为普通用户配置 npm prefix（`~/.npm-global`）、corepack（如可用），并将 `~/.npm-global/bin`、`~/.local/bin`、`~/bin` 写入 `/etc/environment` 的 PATH |
| SSH 安全策略 | root 仅密钥，普通用户密码+密钥 |
| 清理 | apt 缓存和 bash 历史 |

### 预装软件包

| 分类 | 包名 |
|------|------|
| 基础 | ca-certificates sudo vim nano wget curl git unzip xz-utils gnupg less locales dbus systemd-resolved |
| 网络 | net-tools iproute2 mtr-tiny iputils-ping dnsutils |
| 监控 | htop iftop ncdu vnstat |
| 终端 | tmux bash-completion |
| 编程 | python3 python3-pip jq |
| 服务 | rsyslog logrotate fail2ban rsync |

## 海外 vs 国内

设置 `REGION=china` 可切换大部分源，但国内场景可能还需要额外配置：

| 参数 | overseas | china |
|------|---------|-------|
| Debian 镜像 | deb.debian.org（`--cloudflare` 预设） | 中科大（`--ustc` 预设） |
| NTP | time.cloudflare.com | ntp.aliyun.com |
| Docker 源 | download.docker.com | mirrors.aliyun.com |
| debi.sh 下载 | GitHub 直连 | 需设置 `GITHUB_PROXY` 代理，否则仍走 GitHub 直连 |
| NodeSource（Node.js） | deb.nodesource.com | **未适配**，仍从 deb.nodesource.com 拉取，国内网络可能失败 |

> **国内注意**：如果 NodeSource 不可达，建议设置 `INSTALL_NODEJS=false` 跳过，安装后自行通过 [nvm](https://github.com/nvm-sh/nvm) 或其他方式安装 Node.js。

## Node.js 用户环境

当 `INSTALL_NODEJS=true` 时，除了通过 NodeSource 安装 Node.js，脚本还会为普通用户自动完成以下配置：

| 配置项 | 说明 |
|--------|------|
| npm prefix | 设为 `~/.npm-global`，普通用户 `npm i -g` 无需 sudo |
| PATH | 将 `~/.npm-global/bin`、`~/.local/bin`、`~/bin` 前置写入 `/etc/environment` 的 PATH，覆盖交互式和大部分 PAM 加载场景 |
| corepack | 如可用，启用并将 shim（pnpm/yarn）安装到 `~/.npm-global/bin` |

普通用户 SSH 登录后即可直接使用 `npm`、`pnpm`、`yarn`，无需额外操作。

> 说明：systemd 用户服务不会自动继承 shell PATH；如果服务内需要使用 `pnpm`、`yarn` 或其他 npm 全局命令，需要在 unit 的 `Environment=PATH=...` 中手动加入 `~/.npm-global/bin`。

## 安全措施

| 环节 | 措施 |
|------|------|
| 敏感信息传入 | 环境变量或交互输入，不硬编码 |
| root SSH | 仅允许密钥登录（prohibit-password） |
| 普通用户 SSH | 密码 + 密钥均可 |
| debi.sh 下载 | 使用临时目录，脚本退出自动清理 |

## 已知限制

- debi 不支持 OpenVZ / LXC 容器，需要完整虚拟化（KVM/Xen/Hyper-V）
- debi 不自动重启，配置完成后需手动 `reboot`
- debi 只能创建一个用户，普通用户通过 init.sh 创建
