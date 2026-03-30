#!/bin/bash
# Debian 一键重装 - 基于 debi
# 纯净系统安装，不使用 cloud-init
# 推荐流程：先执行本脚本完成重装，再执行 init.sh 完成初始化
#
# 方式一：环境变量传入（默认）
#   curl -fsSL URL | env ROOT_PASSWORD='xxx' bash
#   curl -fsSL URL | env ROOT_PASSWORD='xxx' REGION=overseas SSH_PORT=2222 TIMEZONE=Asia/Shanghai bash
#   curl -fsSL URL | env ROOT_PASSWORD='xxx' bash -s -- --firmware
#
# 方式二：交互输入（加 -i 参数）
#   bash <(curl -fsSL URL) -i
#
# 环境变量：
#   ROOT_PASSWORD   - root 密码（必填）
#   DEBIAN_VERSION  - Debian 版本号，默认 13
#   REGION          - overseas(默认) | china
#   SSH_PORT        - SSH 端口，默认 22
#   TIMEZONE        - 时区，默认 Asia/Shanghai
#   GITHUB_PROXY    - GitHub 代理地址（可选，国内使用）

set -euo pipefail

INTERACTIVE=false
OPTIONAL_DEBI_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -i)
            INTERACTIVE=true
            ;;
        --firmware|--no-apt-src)
            OPTIONAL_DEBI_ARGS+=("$1")
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "用法: $0 [-i] [--firmware] [--no-apt-src]"
            exit 1
            ;;
    esac
    shift
done

DEBIAN_VERSION="${DEBIAN_VERSION:-13}"
REGION="${REGION:-overseas}"
SSH_PORT="${SSH_PORT:-22}"
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"

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

confirm_from_tty() {
    local answer=""

    if ! has_tty; then
        return 1
    fi

    printf "确认继续？(y/N): " > /dev/tty
    IFS= read -r answer < /dev/tty || true

    case "$answer" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
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

    if [ "$var_name" = "ROOT_PASSWORD" ]; then
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

validate_debian_version() {
    case "$DEBIAN_VERSION" in
        ''|*[!0-9]*)
            echo "错误: DEBIAN_VERSION 必须是纯数字（如 12、13）"
            exit 1
            ;;
    esac
}

validate_port() {
    case "$SSH_PORT" in
        ''|*[!0-9]*)
            echo "错误: SSH_PORT 必须是 1-65535 的数字"
            exit 1
            ;;
    esac

    if [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
        echo "错误: SSH_PORT 必须是 1-65535 的数字"
        exit 1
    fi
}

if $INTERACTIVE && has_tty; then
    DEBIAN_VERSION="$(read_from_tty "Debian 版本号" "$DEBIAN_VERSION")"
    REGION="$(read_from_tty "部署地区（overseas/china）" "$REGION")"
    SSH_PORT="$(read_from_tty "SSH 端口" "$SSH_PORT")"
    TIMEZONE="$(read_from_tty "时区" "$TIMEZONE")"
    if [ "$REGION" = "china" ]; then
        GITHUB_PROXY="$(read_from_tty "GitHub 代理地址（留空则直连）" "${GITHUB_PROXY:-}")"
    fi
fi

require_value "ROOT_PASSWORD" "root 密码"
validate_debian_version
validate_region
validate_port

DEBI_RAW_URL="https://raw.githubusercontent.com/bohanwood/debi/master/debi.sh"

if [ "$REGION" = "china" ]; then
    MIRROR_PRESET="--ustc"
    NTP_SERVER="ntp.aliyun.com"
    if [ -n "${GITHUB_PROXY:-}" ]; then
        DEBI_URL="${GITHUB_PROXY}/${DEBI_RAW_URL}"
    else
        DEBI_URL="$DEBI_RAW_URL"
    fi
else
    MIRROR_PRESET="--cloudflare"
    NTP_SERVER="time.cloudflare.com"
    DEBI_URL="$DEBI_RAW_URL"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "正在下载 debi.sh ..."
curl -fsSL -o "$WORK_DIR/debi.sh" "$DEBI_URL"
chmod +x "$WORK_DIR/debi.sh"

echo ""
echo "========================================="
echo "  Debian $DEBIAN_VERSION 重装"
echo "  地区: $REGION ($MIRROR_PRESET)"
echo "  SSH 端口: $SSH_PORT"
echo "  时区: $TIMEZONE"
echo "  警告: 将擦除整个硬盘！"
echo "========================================="
echo ""
echo "  重装流程："
echo "  1. 执行本脚本 → 手动 reboot"
echo "  2. 等待安装（约 5-15 分钟）"
echo "  3. ssh -p $SSH_PORT root@服务器IP 登录"
echo "  4. 再执行 init.sh 完成初始化"
echo ""

if has_tty; then
    if ! confirm_from_tty; then
        echo "已取消"
        exit 0
    fi
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

DEBI_ARGS=(
    --version "$DEBIAN_VERSION"
    --network-console
    --ethx
    --bbr
    $MIRROR_PRESET
    --user root
    --password "$ROOT_PASSWORD"
    --ssh-port "$SSH_PORT"
    --timezone "$TIMEZONE"
    --ntp "$NTP_SERVER"
    --install 'ca-certificates sudo vim nano wget curl git unzip xz-utils python3 python3-pip jq vnstat htop iftop ncdu tmux mtr-tiny iputils-ping dnsutils fail2ban rsync less rsyslog logrotate gnupg locales iproute2 bash-completion net-tools dbus'
)

DEBI_ARGS+=("${OPTIONAL_DEBI_ARGS[@]}")

if has_tty; then
    $SUDO bash "$WORK_DIR/debi.sh" "${DEBI_ARGS[@]}" < /dev/tty
else
    $SUDO bash "$WORK_DIR/debi.sh" "${DEBI_ARGS[@]}"
fi

echo ""
echo "========================================="
echo "  debi 已配置完成，执行 reboot 开始安装"
echo "  安装完成后以 root 登录，再执行 init.sh"
echo "========================================="
