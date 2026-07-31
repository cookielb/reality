#!/bin/bash

# ==============================================================
# Xray REALITY 一键安装 (Adi自用版本 - 增强版)
# ==============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

ENV_FILE="/usr/local/etc/xray/client.env"

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
        # 同时移除快捷键
        rm -f /usr/local/bin/a
        echo -e "${GREEN}Xray 已成功卸载。${NC}"
    else
        echo "操作已取消。"
    fi
}

# 2. 端口检查函数
function check_port() {
    local port=$1
    local pid_info=$(netstat -lnpt | grep ":$port " | awk '{print $7}')
    if [ -z "$pid_info" ]; then
        return 0 
    else
        local process_name=$(echo "$pid_info" | cut -d'/' -f2)
        if [[ "$process_name" == "xray" ]]; then
            return 0 
        else
            return 1 
        fi
    fi
}

# 3. 安装函数
function install_xray() {
    # 检测是否已安装
    if [ -f "/usr/local/bin/xray" ]; then
        echo -e "${YELLOW}检测到系统已安装 Xray。${NC}"
        read -p "是否需要重新安装（这将覆盖现有配置）？(y/n): " re_install
        if [[ "$re_install" != "y" ]]; then
            echo -e "${GREEN}已取消安装操作。${NC}"
            return
        fi
    fi

    echo -e "${CYAN}正在初始化环境...${NC}"
    if [[ -f /usr/bin/apt ]]; then
        apt-get update && apt-get install -y curl qrencode openssl net-tools
    elif [[ -f /usr/bin/yum ]]; then
        yum install -y epel-release && yum install -y curl qrencode openssl net-tools
    fi

    LISTEN_PORT=443
    if ! check_port $LISTEN_PORT; then
        echo -e "${RED}警告：443 端口已被占用！${NC}"
        read -p "是否使用随机端口？(y/n): " p_choice
        [[ "$p_choice" != "y" ]] && exit 1
        LISTEN_PORT=$((RANDOM % 55536 + 10000))
    fi

    FALLBACK_PORT=4431
    if ! check_port $FALLBACK_PORT; then
        echo -e "${YELLOW}检测到 4431 端口被占用，正在分配随机回落端口...${NC}"
        FALLBACK_PORT=$((RANDOM % 55536 + 10000))
        [[ "$FALLBACK_PORT" == "$LISTEN_PORT" ]] && FALLBACK_PORT=$((FALLBACK_PORT + 1))
    fi

    # 安装 Xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    # 随机选择 SNI
    SNI_LIST=("speed.cloudflare.com" "www.bing.com" "www.microsoft.com"  "www.amazon.com")
    DEST_DOMAIN=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

    # 生成参数
    UUID=$(/usr/local/bin/xray uuid)
    KEYPAIR=$(/usr/local/bin/xray x25519)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    SHORT_ID=$(openssl rand -hex 8)
    IP=$(curl -s -4 https://api.ipify.org)
    [ -z "$IP" ] && IP=$(curl -s -4 https://ifconfig.me)

    # 保存配置到 env 文件以便后续读取
    mkdir -p /usr/local/etc/xray
    cat <<EOF > $ENV_FILE
UUID=$UUID
PUBLIC_KEY=$PUBLIC_KEY
LISTEN_PORT=$LISTEN_PORT
FALLBACK_PORT=$FALLBACK_PORT
IP=$IP
SHORT_ID=$SHORT_ID
DEST_DOMAIN=$DEST_DOMAIN
EOF

    # 写入配置
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
    
    # 配置全局快捷键 a
    SCRIPT_PATH=$(readlink -f "$0")
    cp -f "$SCRIPT_PATH" /usr/local/bin/a
    chmod +x /usr/local/bin/a

    view_config
}

# 4. 更新内核
function update_core() {
    echo -e "${CYAN}正在更新 Xray 内核...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    systemctl restart xray
    echo -e "${GREEN}Xray 内核更新完成！当前运行状态：${NC}"
    systemctl status xray --no-pager | grep Active
}

# 5. 查看配置
function view_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}未找到配置信息，请确认是否已通过本脚本安装。${NC}"
        return
    fi
    
    source $ENV_FILE
    CLIENT_LINK="vless://$UUID@$IP:$LISTEN_PORT?security=reality&sni=$DEST_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#REALITY_$(date +%m%d%H%M)"
    
    clear
    echo -e "${PURPLE}==============================================================${NC}"
    echo -e "${GREEN}                 Xray REALITY 节点信息                       ${NC}"
    echo -e "${PURPLE}==============================================================${NC}"
    echo -e "${BLUE}[ 节点参数 ]${NC}"
    echo -e " UUID:                 $UUID"
    echo -e " Password (PublicKey): $PUBLIC_KEY"
    echo -e " 监听端口 (主):        $LISTEN_PORT"
    echo -e " 回落端口 (内部):      $FALLBACK_PORT"
    echo -e " 伪装域名 (SNI):       $DEST_DOMAIN"
    echo -e " 服务器 IP (IPv4):     $IP"
    echo -e "${PURPLE}--------------------------------------------------------------${NC}"
    echo -e "${BLUE}[ 快捷命令 ]${NC}"
    echo -e " 全局管理菜单快捷键:   ${YELLOW}输入 a 并回车即可随时拉起本脚本${NC}"
    echo -e "${PURPLE}--------------------------------------------------------------${NC}"
    echo -e "${BLUE}[ 客户端一键链接 ]${NC}"
    echo -e "${YELLOW}$CLIENT_LINK${NC}"
    echo -e "${PURPLE}--------------------------------------------------------------${NC}"
    qrencode -t ANSIUTF8 "$CLIENT_LINK"
}

# 6. 更换 SNI
function change_sni() {
    if [ ! -f "$ENV_FILE" ] || [ ! -f "/usr/local/etc/xray/config.json" ]; then
        echo -e "${RED}未找到配置信息，请确认是否已安装。${NC}"
        return
    fi
    
    source $ENV_FILE
    echo -e "当前 SNI 为: ${YELLOW}$DEST_DOMAIN${NC}"
    read -p "请输入新的 SNI (如 www.bing.com，留空则取消): " NEW_SNI
    
    if [ -z "$NEW_SNI" ]; then
        echo -e "${GREEN}已取消更改。${NC}"
        return
    fi

    # 替换 config.json 和 env 文件中的域名
    sed -i "s/\"$DEST_DOMAIN\"/\"$NEW_SNI\"/g" /usr/local/etc/xray/config.json
    sed -i "s/DEST_DOMAIN=$DEST_DOMAIN/DEST_DOMAIN=$NEW_SNI/g" $ENV_FILE
    
    systemctl restart xray
    echo -e "${GREEN}SNI 已成功更换为 $NEW_SNI 并重启了服务！${NC}"
    echo -e "正在加载新配置..."
    sleep 2
    view_config
}

# 主菜单循环
while true; do
    clear
    echo -e "${CYAN}Xray REALITY 管理脚本${NC}"
    echo "----------------------------"
    echo "1. 安装 / 重新安装"
    echo "2. 更新 Xray 内核"
    echo "3. 查看当前配置"
    echo "4. 手动更换 SNI"
    echo "5. 卸载 Xray"
    echo "0. 退出"
    echo "----------------------------"
    read -p "选择 [0-5]: " menu_choice
    case $menu_choice in
        1) install_xray ;;
        2) update_core ;;
        3) view_config ;;
        4) change_sni ;;
        5) uninstall_xray ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项，请重新运行脚本。${NC}" ;;
    esac
    
    # 执行完毕后暂停，等待用户确认再返回主菜单
    echo -e "\n${YELLOW}按任意键返回主菜单...${NC}"
    read -n 1 -s -r
done
