#!/bin/bash
# Debian 首次启动初始化脚本
# 重装完成后以 root 登录执行
#
# 方式一：环境变量传入（默认）
#   curl -fsSL URL | env USER_PASSWORD='xxx' SSH_PUBLIC_KEY='ssh-rsa ...' bash
#   curl -fsSL URL | env USERNAME=yourname USER_PASSWORD='xxx' SSH_PUBLIC_KEY='ssh-rsa ...' REGION=overseas bash
#
# 方式二：交互输入（加 -i 参数）
#   bash <(curl -fsSL URL) -i
#
# 环境变量：
#   USER_PASSWORD    - 普通用户密码（必填）
#   SSH_PUBLIC_KEY   - root 与普通用户共用的 SSH 公钥（必填）
#   USERNAME         - 普通用户名，默认 yourname
#   REGION           - overseas(默认) | china
#   DOCKER_DATA_ROOT - Docker 数据目录，默认 /data/docker
#   INSTALL_NODEJS   - 是否安装 Node.js，默认 true
#   NODEJS_VERSION   - Node.js 大版本号，默认 24

set -euo pipefail

INTERACTIVE=false
while getopts "i" opt; do
    case "$opt" in
        i) INTERACTIVE=true ;;
        *) echo "用法: $0 [-i]"; exit 1 ;;
    esac
done

USERNAME="${USERNAME:-yourname}"
REGION="${REGION:-overseas}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/data/docker}"
INSTALL_NODEJS="${INSTALL_NODEJS:-true}"
NODEJS_VERSION="${NODEJS_VERSION:-24}"

has_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

read_from_tty() {
    local prompt="$1"
    local default_value="${2:-}"
    local input=""

    if ! has_tty; then
        return 1
    fi

    if [ -n "$default_value" ]; then
        printf "%s [%s]: " "$prompt" "$default_value" > /dev/tty
    else
        printf "%s: " "$prompt" > /dev/tty
    fi

    IFS= read -r input < /dev/tty || true

    if [ -z "$input" ]; then
        input="$default_value"
    fi

    printf '%s' "$input"
}

read_secret_from_tty() {
    local prompt="$1"
    local first=""
    local second=""

    if ! has_tty; then
        return 1
    fi

    while true; do
        printf "%s: " "$prompt" > /dev/tty
        IFS= read -r -s first < /dev/tty || true
        printf "\n" > /dev/tty

        printf "再次输入以确认: " > /dev/tty
        IFS= read -r -s second < /dev/tty || true
        printf "\n" > /dev/tty

        if [ -z "$first" ]; then
            echo "密码不能为空，请重新输入。" > /dev/tty
            continue
        fi

        if [ "$first" != "$second" ]; then
            echo "两次输入不一致，请重新输入。" > /dev/tty
            continue
        fi

        printf '%s' "$first"
        return 0
    done
}

require_value() {
    local var_name="$1"
    local description="$2"

    if [ -n "${!var_name:-}" ]; then
        return 0
    fi

    if ! $INTERACTIVE || ! has_tty; then
        echo "错误: 请设置环境变量 $var_name（$description）"
        exit 1
    fi

    if [ "$var_name" = "USER_PASSWORD" ]; then
        printf -v "$var_name" '%s' "$(read_secret_from_tty "$description")"
    else
        printf -v "$var_name" '%s' "$(read_from_tty "$description")"
    fi
}

validate_region() {
    case "$REGION" in
        overseas|china) ;;
        *)
            echo "错误: REGION 只能是 overseas 或 china"
            exit 1
            ;;
    esac
}

validate_ssh_public_key() {
    local key_type="${SSH_PUBLIC_KEY%% *}"

    if [ "$key_type" = "$SSH_PUBLIC_KEY" ]; then
        echo "错误: SSH_PUBLIC_KEY 格式不正确"
        exit 1
    fi

    case "$key_type" in
        ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *)
            echo "错误: SSH_PUBLIC_KEY 类型不受支持"
            exit 1
            ;;
    esac
}

validate_install_nodejs() {
    case "$INSTALL_NODEJS" in
        true|false) ;;
        *)
            echo "错误: INSTALL_NODEJS 只能是 true 或 false"
            exit 1
            ;;
    esac
}

validate_nodejs_version() {
    case "$NODEJS_VERSION" in
        ''|*[!0-9]*)
            echo "错误: NODEJS_VERSION 必须是纯数字（如 18、20、24）"
            exit 1
            ;;
    esac
}

validate_docker_data_root() {
    if [ -z "$DOCKER_DATA_ROOT" ]; then
        echo "错误: DOCKER_DATA_ROOT 不能为空"
        exit 1
    fi

    case "$DOCKER_DATA_ROOT" in
        /*)  ;;
        *)
            echo "错误: DOCKER_DATA_ROOT 必须是绝对路径"
            exit 1
            ;;
    esac

    if [ "$DOCKER_DATA_ROOT" = "/" ]; then
        echo "错误: DOCKER_DATA_ROOT 不能是根目录"
        exit 1
    fi
}

validate_username() {
    if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]{0,31}$'; then
        echo "错误: USERNAME 不符合 Linux 用户名规范"
        exit 1
    fi

    if [ "$USERNAME" = "root" ]; then
        echo "错误: USERNAME 不能是 root"
        exit 1
    fi
}

ensure_authorized_key() {
    local user_name="$1"
    local home_dir="$2"

    install -d -m 700 "$home_dir/.ssh"
    touch "$home_dir/.ssh/authorized_keys"
    chmod 600 "$home_dir/.ssh/authorized_keys"

    if ! grep -qxF "$SSH_PUBLIC_KEY" "$home_dir/.ssh/authorized_keys"; then
        printf '%s\n' "$SSH_PUBLIC_KEY" >> "$home_dir/.ssh/authorized_keys"
    fi

    chown -R "$user_name:$user_name" "$home_dir/.ssh"
}

prepend_path_in_environment() {
    local dir="$1"
    local env_file="/etc/environment"

    if grep -qF "$dir" "$env_file" 2>/dev/null; then
        return 0
    fi

    if grep -q '^PATH="' "$env_file" 2>/dev/null; then
        sed -i "s|^PATH=\"|PATH=\"${dir}:|" "$env_file"
        return 0
    fi

    printf 'PATH="%s:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' "$dir" >> "$env_file"
}

ensure_profile_path() {
    local profile_file="$1"
    local path_dir="$2"

    touch "$profile_file"

    if grep -qF "$path_dir" "$profile_file" 2>/dev/null; then
        return 0
    fi

    cat >> "$profile_file" <<EOF_PROFILE

if ! printf '%s' ":\$PATH:" | grep -q ":$path_dir:"; then
    export PATH="$path_dir:\$PATH"
fi
EOF_PROFILE
}

configure_docker_data_root() {
    local backup_dir=""

    mkdir -p /etc/docker "$DOCKER_DATA_ROOT"
    printf '{"data-root":"%s"}\n' "$DOCKER_DATA_ROOT" > /etc/docker/daemon.json

    if [ -d /var/lib/docker ] && [ -n "$(find /var/lib/docker -mindepth 1 -print -quit 2>/dev/null)" ]; then
        if [ -n "$(find "$DOCKER_DATA_ROOT" -mindepth 1 -print -quit 2>/dev/null)" ]; then
            echo "  检测到 $DOCKER_DATA_ROOT 已有数据，跳过 /var/lib/docker 迁移与清理"
            return 0
        fi

        echo "  检测到 /var/lib/docker 已有数据，正在迁移到 $DOCKER_DATA_ROOT ..."
        rsync -a /var/lib/docker/ "$DOCKER_DATA_ROOT/"
        backup_dir="/var/lib/docker.bak.$(date +%Y%m%d%H%M%S)"
        mv /var/lib/docker "$backup_dir"
        mkdir -p /var/lib/docker
        echo "  已保留旧数据备份: $backup_dir"
        return 0
    fi

    rm -rf /var/lib/docker
}

if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户执行此脚本"
    exit 1
fi

if $INTERACTIVE && has_tty; then
    USERNAME="$(read_from_tty "普通用户名" "$USERNAME")"
    REGION="$(read_from_tty "部署地区（overseas/china）" "$REGION")"
    DOCKER_DATA_ROOT="$(read_from_tty "Docker 数据目录" "$DOCKER_DATA_ROOT")"
    INSTALL_NODEJS="$(read_from_tty "安装 Node.js（true/false）" "$INSTALL_NODEJS")"
    if [ "$INSTALL_NODEJS" = "true" ]; then
        NODEJS_VERSION="$(read_from_tty "Node.js 版本" "$NODEJS_VERSION")"
    fi
fi

require_value "USER_PASSWORD" "普通用户密码"
require_value "SSH_PUBLIC_KEY" "root 和 $USERNAME 使用的 SSH 公钥"
validate_region
validate_username
validate_ssh_public_key
validate_docker_data_root
validate_install_nodejs
if [ "$INSTALL_NODEJS" = "true" ]; then
    validate_nodejs_version
fi

. /etc/os-release
if [ "$REGION" = "china" ]; then
    DOCKER_REPO="https://mirrors.aliyun.com/docker-ce/linux/$ID"
else
    DOCKER_REPO="https://download.docker.com/linux/$ID"
fi

TOTAL_STEPS=5
if [ "$INSTALL_NODEJS" = "true" ]; then
    TOTAL_STEPS=6
fi
STEP=0

echo ""
echo "===== Debian 初始化开始 ====="
echo ""

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] 修复 hostname 解析..."
sed -i '/^127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1 $(hostname)" >> /etc/hosts

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] 创建用户 $USERNAME..."
if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo "$USERNAME"
fi
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME"
chmod 440 "/etc/sudoers.d/90-$USERNAME"

USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
ensure_authorized_key "$USERNAME" "$USER_HOME"
ensure_authorized_key "root" "/root"

# 将用户私有 bin 目录加入 PATH（通过 /etc/environment，覆盖交互式和大部分 PAM 加载场景）
for _dir in "${USER_HOME}/.local/bin" "${USER_HOME}/bin"; do
    prepend_path_in_environment "$_dir"
done
install -d -o "$USERNAME" -g "$USERNAME" "$USER_HOME/.local/bin" "$USER_HOME/bin"

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] 安装 Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "$DOCKER_REPO/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF_DOCKER
Types: deb
URIs: $DOCKER_REPO
Suites: $VERSION_CODENAME
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl stop docker.service containerd.service 2>/dev/null || true
configure_docker_data_root
systemctl start docker.service containerd.service
usermod -aG docker "$USERNAME"

if [ "$INSTALL_NODEJS" = "true" ]; then
    STEP=$((STEP + 1))
    echo "[$STEP/$TOTAL_STEPS] 安装 Node.js ${NODEJS_VERSION}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODEJS_VERSION}.x" | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

    echo "  配置 $USERNAME 的 Node.js 用户环境..."
    install -d -o "$USERNAME" -g "$USERNAME" "$USER_HOME/.npm-global/bin" "$USER_HOME/.npm-global/lib"

    su - "$USERNAME" -c 'npm config set --location=user prefix "$HOME/.npm-global"'

    # 将 npm global prefix 的 bin 目录加入 PATH（/etc/environment 覆盖部分会话，~/.profile 保证登录 shell）
    prepend_path_in_environment "$USER_HOME/.npm-global/bin"
    ensure_profile_path "$USER_HOME/.profile" "$USER_HOME/.npm-global/bin"
    chown "$USERNAME:$USERNAME" "$USER_HOME/.profile"

    if command -v corepack >/dev/null 2>&1; then
        su - "$USERNAME" -c 'corepack enable --install-directory "$HOME/.npm-global/bin"' || echo "  警告: corepack 启用失败，可稍后手动执行"
    fi
fi

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] 配置 SSH 安全策略..."
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'PermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-root-key-only.conf
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/01-password-auth.conf
if ! sshd -t; then
    echo "错误: SSH 配置检测失败，跳过重启以避免锁定"
    echo "请手动检查 /etc/ssh/sshd_config.d/ 下的配置文件"
else
    systemctl restart ssh
fi

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] 清理..."
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/cache/apt/* /var/lib/apt/lists/*
rm -f /root/.bash_history "$USER_HOME/.bash_history"
history -c 2>/dev/null || true
truncate -s 0 /var/log/auth.log 2>/dev/null || true
truncate -s 0 /var/log/syslog 2>/dev/null || true

FAIL_COUNT=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✔ %s\n" "$desc"
    else
        printf "  ✘ %s\n" "$desc"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "===== 初始化结果 ====="
echo ""

echo "[hostname]"
check "127.0.1.1 解析已写入 /etc/hosts" grep -q "^127\.0\.1\.1" /etc/hosts

echo "[用户: $USERNAME]"
check "用户存在" id "$USERNAME"
check "shell 为 /bin/bash" test "$(getent passwd "$USERNAME" | cut -d: -f7)" = "/bin/bash"
check "home 目录存在" test -d "$USER_HOME"
check "sudoers 文件存在且权限正确" test -f "/etc/sudoers.d/90-$USERNAME" -a "$(stat -c %a "/etc/sudoers.d/90-$USERNAME" 2>/dev/null)" = "440"
check "在 sudo 组中" bash -c "id -nG '$USERNAME' | grep -qw sudo"

echo "[SSH 密钥]"
check "$USERNAME authorized_keys 含公钥" grep -qxF "$SSH_PUBLIC_KEY" "$USER_HOME/.ssh/authorized_keys"
check "root authorized_keys 含公钥" grep -qxF "$SSH_PUBLIC_KEY" /root/.ssh/authorized_keys

echo "[PATH (/etc/environment)]"
check "含 .local/bin" grep -q "${USER_HOME}/.local/bin" /etc/environment
check "含 ~/bin" grep -q "${USER_HOME}/bin" /etc/environment
check ".local/bin 目录存在" test -d "$USER_HOME/.local/bin"
check "~/bin 目录存在" test -d "$USER_HOME/bin"

echo "[Docker]"
check "docker 命令可用: $(docker --version 2>/dev/null | grep -oP 'Docker version \K[^,]+')" command -v docker
check "docker.service 运行中" systemctl is-active docker
check "containerd.service 运行中" systemctl is-active containerd
check "data-root 配置为 $DOCKER_DATA_ROOT" test "$(jq -r '."data-root"' /etc/docker/daemon.json 2>/dev/null)" = "$DOCKER_DATA_ROOT"
check "$USERNAME 在 docker 组中" bash -c "id -nG '$USERNAME' | grep -qw docker"

if [ "$INSTALL_NODEJS" = "true" ]; then
    echo "[Node.js]"
    check "node 命令可用: $(node --version 2>/dev/null)" command -v node
    check "npm prefix 已配置" bash -c "su - '$USERNAME' -c 'npm config get prefix 2>/dev/null' | grep -q '.npm-global'"
    check ".npm-global/bin 在 PATH 中" grep -q 'npm-global/bin' /etc/environment
    check ".npm-global/bin 目录存在" test -d "$USER_HOME/.npm-global/bin"
    check ".profile 含 .npm-global/bin" grep -qF "$USER_HOME/.npm-global/bin" "$USER_HOME/.profile"
    if command -v corepack >/dev/null 2>&1; then
        check "corepack shim 已生成" bash -c "test -x '$USER_HOME/.npm-global/bin/pnpm' || test -x '$USER_HOME/.npm-global/bin/yarn' || test -x '$USER_HOME/.npm-global/bin/yarnpkg'"
        check "登录 shell 可解析 pnpm/yarn shim" bash -c "su - '$USERNAME' -c 'command -v pnpm || command -v yarn || command -v yarnpkg'"
    fi
fi

echo "[SSH 安全策略]"
check "root 仅密钥登录配置存在" grep -q "^PermitRootLogin prohibit-password" /etc/ssh/sshd_config.d/00-root-key-only.conf
check "密码认证配置存在" grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config.d/01-password-auth.conf
check "sshd 配置语法正确" sshd -t
check "ssh 服务运行中" systemctl is-active ssh

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "===== 全部通过 ====="
else
    echo "===== $FAIL_COUNT 项失败，请检查 ====="
fi
if [ "$INSTALL_NODEJS" = "true" ]; then
    echo "提示: systemd 用户服务需在 Environment=PATH 中手动加入 ~/.npm-global/bin"
fi
