#!/bin/bash

# ==============================================================
# Xray REALITY 一键安装 (Adi自用版本)
# ==============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. 卸载函数
function uninstall_xray() {
    echo -e "${YELLOW}正在准备卸载 Xray...${NC}"
    read -p "确定要删除 Xray 及其所有配置吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop xray >/dev/null 2>&1
        systemctl disable xray >/dev/null 2>&1
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
        rm -rf /usr/local/etc/xray
        rm -rf /var/log/xray
        echo -e "${GREEN}Xray 已成功卸载。${NC}"
    else
        echo "操作已取消。"
    fi
}

# 2. 端口检查函数
function check_port() {
    local port=$1
    # 检查端口是否被非 xray 进程占用
    local pid_info=$(netstat -lnpt | grep ":$port " | awk '{print $7}')
    if [ -z "$pid_info" ]; then
        return 0 # 端口可用
    else
        local process_name=$(echo "$pid_info" | cut -d'/' -f2)
        if [[ "$process_name" == "xray" ]]; then
            return 0 # 是 xray 自己占用的，视为可用
        else
            return 1 # 被其他进程占用
        fi
    fi
}

# 3. 安装函数
function install_xray() {
    echo -e "${CYAN}正在初始化环境...${NC}"
    if [[ -f /usr/bin/apt ]]; then
        apt-get update && apt-get install -y curl qrencode openssl net-tools
    elif [[ -f /usr/bin/yum ]]; then
        yum install -y epel-release && yum install -y curl qrencode openssl net-tools
    fi

    # 检测主端口 443
    LISTEN_PORT=443
    if ! check_port $LISTEN_PORT; then
        echo -e "${RED}警告：443 端口已被占用！${NC}"
        read -p "是否使用随机端口？(y/n): " p_choice
        [[ "$p_choice" != "y" ]] && exit 1
        LISTEN_PORT=$((RANDOM % 55536 + 10000))
    fi

    # 检测回落端口 4431 (优先使用 4431)
    FALLBACK_PORT=4431
    if ! check_port $FALLBACK_PORT; then
        echo -e "${YELLOW}检测到 4431 端口被占用，正在分配随机回落端口...${NC}"
        FALLBACK_PORT=$((RANDOM % 55536 + 10000))
        # 确保不跟主端口撞车
        [[ "$FALLBACK_PORT" == "$LISTEN_PORT" ]] && FALLBACK_PORT=$((FALLBACK_PORT + 1))
    fi

    # 安装 Xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    # 生成参数
    UUID=$(/usr/local/bin/xray uuid)
    KEYPAIR=$(/usr/local/bin/xray x25519)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    SHORT_ID=$(openssl rand -hex 8)
    DEST_DOMAIN="speed.cloudflare.com"
    IP=$(curl -s -4 https://api.ipify.org)
    [ -z "$IP" ] && IP=$(curl -s -4 https://ifconfig.me)

    # 写入配置 (关键点：dest 端口与 dokodemo 端口保持同步)
    cat <<EOF > /usr/local/etc/xray/config.json
{
    "log": { "loglevel": "debug" },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "tag": "dokodemo-in",
            "port": $FALLBACK_PORT,
            "protocol": "dokodemo-door",
            "settings": { "address": "$DEST_DOMAIN", "port": 443, "network": "tcp" },
            "sniffing": { "enabled": true, "destOverride": ["tls"], "routeOnly": true }
        },
        {
            "listen": "0.0.0.0",
            "port": $LISTEN_PORT,
            "protocol": "vless",
            "settings": {
                "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "127.0.0.1:$FALLBACK_PORT",
                    "serverNames": ["$DEST_DOMAIN"],
                    "privateKey": "$PRIVATE_KEY",
                    "shortIds": ["", "$SHORT_ID"]
                }
            },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "tag": "direct" },
        { "protocol": "blackhole", "tag": "block" }
    ],
    "routing": {
        "rules": [
            { "inboundTag": ["dokodemo-in"], "domain": ["$DEST_DOMAIN"], "outboundTag": "direct" },
            { "inboundTag": ["dokodemo-in"], "outboundTag": "block" }
        ]
    }
}
EOF

    systemctl restart xray
    systemctl enable xray

    # 输出结果
    CLIENT_LINK="vless://$UUID@$IP:$LISTEN_PORT?security=reality&sni=$DEST_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#REALITY_$(date +%m%d%H%M)"
    clear
    echo -e "${PURPLE}==============================================================${NC}"
    echo -e "${GREEN}          Xray REALITY (双端口智能版) 部署完成！             ${NC}"
    echo -e "${PURPLE}==============================================================${NC}"
    echo -e "${BLUE}[ 节点参数 ]${NC}"
    echo -e " UUID:                 $UUID"
    echo -e " Password (PublicKey): $PUBLIC_KEY"
    echo -e " 监听端口 (主):        $LISTEN_PORT"
    echo -e " 回落端口 (内部):      $FALLBACK_PORT"
    echo -e " 服务器 IP (IPv4):     $IP"
    echo -e "${PURPLE}--------------------------------------------------------------${NC}"
    echo -e "${BLUE}[ 客户端一键链接 ]${NC}"
    echo -e "${YELLOW}$CLIENT_LINK${NC}"
    echo -e "${PURPLE}--------------------------------------------------------------${NC}"
    qrencode -t ANSIUTF8 "$CLIENT_LINK"
}

# 主菜单
clear
echo -e "${CYAN}Xray REALITY 管理脚本${NC}"
echo "----------------------------"
echo "1. 安装 / 更新 Xray"
echo "2. 卸载 Xray"
echo "3. 退出"
echo "----------------------------"
read -p "选择 [1-3]: " menu_choice
case $menu_choice in
    1) install_xray ;;
    2) uninstall_xray ;;
    3) exit 0 ;;
esac
