#!/bin/bash

# Auto-fix CRLF

sed -i 's/\r$//' "$0" 2>/dev/null || true

# ============================================================

# VPS Toolbox - 一键部署脚本

# 功能: DDNS/WARP/Vless/Hysteria2/SS/VMess/HTTPS代理

# 作者: Kitaro-Loked

# 仓库: https://github.com/Kitaro-Loked/VPS-Toolbox

# 版本: 3.3.0

# 致谢: 协议安装脚本全部来自 yeahwu/v2ray-wss

#       https://github.com/yeahwu/v2ray-wss

#       本项目仅提供菜单封装、DDNS、WARP、订阅链接等管理功能

# ============================================================

set -e

# 颜色定义

RED='\033[0;31m'

GREEN='\033[0;32m'

YELLOW='\033[1;33m'

BLUE='\033[0;34m'

CYAN='\033[0;36m'

NC='\033[0m'

# 全局变量

CONFIG_DIR="/etc/vps-toolbox"

LOG_FILE="/var/log/vps-toolbox.log"

# 日志函数

log() {

    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"

}

warn() {

    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1${NC}" | tee -a "$LOG_FILE"

}

error() {

    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" | tee -a "$LOG_FILE"

    exit 1

}

# 检查root权限

check_root() {

    if [[ $EUID -ne 0 ]]; then

        error "请使用 root 用户运行此脚本"

    fi

}

# 检查系统类型

check_system() {

    if [[ -f /etc/os-release ]]; then

        . /etc/os-release

        OS=$NAME

        VER=$VERSION_ID

    else

        error "无法检测操作系统类型"

    fi

    

    case $OS in

        "Ubuntu"|"Debian GNU/Linux")

            PKG_MANAGER="apt"

            ;;

        "CentOS Linux"|"CentOS Stream"|"AlmaLinux"|"Rocky Linux")

            PKG_MANAGER="yum"

            ;;

        "Fedora")

            PKG_MANAGER="dnf"

            ;;

        *)

            error "不支持的操作系统: $OS"

            ;;

    esac

    

    log "检测到系统: $OS $VER"

}

# 安装依赖

install_dependencies() {

    log "正在安装基础依赖..."

    

    if [[ "$PKG_MANAGER" == "apt" ]]; then

        apt-get update -y >/dev/null 2>&1

        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip nginx cronie >/dev/null 2>&1 || \

        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip nginx >/dev/null 2>&1

    else

        $PKG_MANAGER install -y curl wget git socat jq cronie openssl qrencode net-tools unzip nginx >/dev/null 2>&1 || \

        $PKG_MANAGER install -y curl wget git socat jq openssl qrencode net-tools unzip nginx >/dev/null 2>&1

    fi

    

    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1 || true

    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1 || true

    

    mkdir -p "$CONFIG_DIR"

    

    log "基础依赖安装完成"

}

# 获取服务器IP

get_server_ip() {

    local IP=$(curl -s -4 --max-time 10 http://www.cloudflare.com/cdn-cgi/trace | grep "^ip=" | awk -F= '{print $2}')

    if [[ -z "$IP" ]]; then

        IP=$(curl -s -4 --max-time 10 https://api.ipify.org)

    fi

    echo "$IP"

}

# ==================== DDNS 功能 ====================

setup_ddns() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                   DDNS 域名申请与管理${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    echo -e "${YELLOW}请选择 DDNS 提供商:${NC}"

    echo "  1. DuckDNS (推荐，免费，一键申请)"

    echo "  2. Cloudflare (需要 API Token)"

    echo "  3. No-IP (需要账号密码)"

    echo "  4. 查看当前 DDNS 状态"

    echo "  5. 返回主菜单"

    echo ""

    read -rp "请选择 [1-5]: " ddns_choice

    

    case $ddns_choice in

        1) setup_duckdns_auto ;;

        2) setup_cloudflare ;;

        3) setup_noip ;;

        4) view_ddns_status ;;

        5) return ;;

        *) warn "无效选择" ;;

    esac

}

setup_duckdns_auto() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    DuckDNS 一键申请${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "正在生成随机子域名..."

    local RANDOM_SUB=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)

    local DUCK_DOMAIN="$RANDOM_SUB"

    local DDNS_DOMAIN="${RANDOM_SUB}.duckdns.org"

    local PUBLIC_IP=$(get_server_ip)

    

    echo -e "${GREEN}已生成随机子域名:${NC} $DUCK_DOMAIN"

    echo -e "${CYAN}完整域名:${NC} $DDNS_DOMAIN"

    echo -e "${CYAN}公网IP:${NC} $PUBLIC_IP"

    echo ""

    

    echo -e "${YELLOW}DuckDNS 需要 Token 才能更新域名。${NC}"

    echo "  1. 我已经有 DuckDNS Token (直接输入)"

    echo "  2. 帮我打开 DuckDNS 注册页面 (获取 Token)"

    echo "  3. 返回上一级"

    echo ""

    read -rp "请选择 [1-3]: " duck_choice

    

    case $duck_choice in

        1)

            duck_token=""

            while [[ -z "$duck_token" ]]; do

                read -rp "请输入 DuckDNS Token: " duck_token

                duck_token=$(echo "$duck_token" | xargs)

                if [[ -z "$duck_token" ]]; then

                    warn "Token 不能为空，请重新输入"

                fi

            done

            

            local RESULT=$(curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$duck_token&ip=$PUBLIC_IP")

            

            if [[ "$RESULT" == "OK" ]]; then

                log "DuckDNS 域名更新成功!"

            else

                warn "域名更新返回: $RESULT"

                warn "如果域名不存在，DuckDNS 会自动创建"

            fi

            

            log "等待 DNS 传播，最多60秒..."

            local DNS_READY=0

            for i in {1..12}; do

                sleep 5

                if host "$DDNS_DOMAIN" >/dev/null 2>&1 || nslookup "$DDNS_DOMAIN" >/dev/null 2>&1; then

                    DNS_READY=1

                    log "DNS 已生效!"

                    break

                fi

                echo -n "."

            done

            echo ""

            

            cat > "$CONFIG_DIR/ddns.conf" <<EOF

DDNS_PROVIDER=duckdns

DUCK_TOKEN=$duck_token

DUCK_DOMAIN=$DUCK_DOMAIN

DDNS_DOMAIN=$DDNS_DOMAIN

EOF

            

            cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'

#!/bin/bash

CONFIG_DIR="/etc/vps-toolbox"

source "$CONFIG_DIR/ddns.conf"

PUBLIC_IP=$(curl -s -4 https://api.ipify.org)

curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$DUCK_TOKEN&ip=$PUBLIC_IP" >/dev/null

echo "[$(date)] DDNS updated: $DDNS_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log

EOF

            chmod +x "$CONFIG_DIR/update-ddns.sh"

            (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -

            

            log "配置已保存! DDNS 更新脚本已配置 (每5分钟检测)"

            ;;

        2)

            echo ""

            echo -e "${YELLOW}请在浏览器中打开: https://www.duckdns.org${NC}"

            echo "  1. 用 Google/GitHub/Amazon/Twitter 登录"

            echo "  2. 创建子域名"

            echo "  3. 复制 Token"

            echo "  4. 返回选 '1. 输入已有 Token'"

            echo ""

            read -rp "按回车键返回..."

            setup_duckdns_auto

            return

            ;;

        3) return ;;

        *) warn "无效选择" ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

setup_cloudflare() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    Cloudflare DDNS${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    read -rp "请输入 Cloudflare API Token: " cf_token

    read -rp "请输入域名 (例如: example.com): " cf_domain

    read -rp "请输入子域名前缀 (例如: vps): " cf_subdomain

    

    local DDNS_DOMAIN="${cf_subdomain}.${cf_domain}"

    local PUBLIC_IP=$(get_server_ip)

    local ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \

        -H "Authorization: Bearer $cf_token" -H "Content-Type: application/json" | jq -r '.result[0].id')

    

    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then

        error "获取 Zone ID 失败"

    fi

    

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \

        -H "Authorization: Bearer $cf_token" -H "Content-Type: application/json" \

        --data "{\"type\":\"A\",\"name\":\"$cf_subdomain\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null

    

    cat > "$CONFIG_DIR/ddns.conf" <<EOF

DDNS_PROVIDER=cloudflare

CF_TOKEN=$cf_token

CF_DOMAIN=$cf_domain

CF_SUBDOMAIN=$cf_subdomain

DDNS_DOMAIN=$DDNS_DOMAIN

ZONE_ID=$ZONE_ID

EOF

    

    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'

#!/bin/bash

CONFIG_DIR="/etc/vps-toolbox"

source "$CONFIG_DIR/ddns.conf"

PUBLIC_IP=$(curl -s -4 https://api.ipify.org)

RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DDNS_DOMAIN" -H "Authorization: Bearer $CF_TOKEN" | jq -r '.result[0].id')

curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"$DDNS_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120}" >/dev/null

echo "[$(date)] DDNS updated: $DDNS_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log

EOF

    chmod +x "$CONFIG_DIR/update-ddns.sh"

    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -

    

    log "Cloudflare DDNS 配置完成! 域名: $DDNS_DOMAIN"

    echo ""

    read -rp "按回车键继续..."

}

setup_noip() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                      No-IP DDNS${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    read -rp "请输入 No-IP 用户名: " noip_user

    read -rsp "请输入 No-IP 密码: " noip_pass

    echo ""

    read -rp "请输入主机名 (例如: yourname.ddns.net): " noip_host

    

    local DDNS_DOMAIN="$noip_host"

    local PUBLIC_IP=$(get_server_ip)

    

    curl -s -u "$noip_user:$noip_pass" "https://dynupdate.no-ip.com/nic/update?hostname=$noip_host&myip=$PUBLIC_IP" >/dev/null

    

    cat > "$CONFIG_DIR/ddns.conf" <<EOF

DDNS_PROVIDER=noip

NOIP_USER=$noip_user

NOIP_PASS=$noip_pass

NOIP_HOST=$noip_host

DDNS_DOMAIN=$DDNS_DOMAIN

EOF

    

    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'

#!/bin/bash

CONFIG_DIR="/etc/vps-toolbox"

source "$CONFIG_DIR/ddns.conf"

PUBLIC_IP=$(curl -s -4 https://api.ipify.org)

curl -s -u "$NOIP_USER:$NOIP_PASS" "https://dynupdate.no-ip.com/nic/update?hostname=$NOIP_HOST&myip=$PUBLIC_IP" >/dev/null

echo "[$(date)] DDNS updated: $DDNS_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log

EOF

    chmod +x "$CONFIG_DIR/update-ddns.sh"

    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -

    

    log "No-IP 配置完成! 域名: $DDNS_DOMAIN"

    echo ""

    read -rp "按回车键继续..."

}

view_ddns_status() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                      DDNS 状态${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then

        cat "$CONFIG_DIR/ddns.conf"

        echo ""

        echo -e "${CYAN}当前公网IP:${NC} $(get_server_ip)"

        echo -e "${CYAN}DDNS日志:${NC}"

        tail -n 5 /var/log/ddns.log 2>/dev/null || echo "暂无日志"

    else

        warn "尚未配置 DDNS"

    fi

    

    echo ""

    read -rp "按回车键继续..."

}

# ==================== WARP 功能 ====================

setup_warp() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                      WARP 一键配置${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "正在安装 WARP..."

    

    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

    apt-get update && apt-get install -y cloudflare-warp

    

    warp-cli register

    warp-cli connect

    

    log "WARP 安装完成"

    echo ""

    read -rp "按回车键继续..."

}

# ==================== 协议安装 - 直接调用 yeahwu 的脚本 ====================

install_vless() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}         正在安装 Vless + Reality (yeahwu/v2ray-wss)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "下载并执行 yeahwu/v2ray-wss reality.sh..."

    cd /tmp

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh

    bash reality.sh

    

    echo ""

    read -rp "按回车键继续..."

}

install_hysteria2() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}           正在安装 Hysteria2 (yeahwu/v2ray-wss)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "下载并执行 yeahwu/v2ray-wss hy2.sh..."

    cd /tmp

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/hy2.sh

    bash hy2.sh

    

    echo ""

    read -rp "按回车键继续..."

}

install_shadowsocks() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}        正在安装 Shadowsocks-rust (yeahwu/v2ray-wss)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "下载并执行 yeahwu/v2ray-wss ss-rust.sh..."

    cd /tmp

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ss-rust.sh

    bash ss-rust.sh

    

    echo ""

    read -rp "按回车键继续..."

}

install_vmess() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}        正在安装 VMess + WS + TLS (yeahwu/v2ray-wss)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "下载并执行 yeahwu/v2ray-wss tcp-wss.sh..."

    cd /tmp

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh

    bash tcp-wss.sh

    

    echo ""

    read -rp "按回车键继续..."

}

install_https_proxy() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}       正在安装 HTTPS 正向代理 (yeahwu/v2ray-wss)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    log "下载并执行 yeahwu/v2ray-wss https.sh..."

    cd /tmp

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/https.sh

    bash https.sh

    

    echo ""

    read -rp "按回车键继续..."

}

# ==================== 管理功能 ====================

view_config() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    查看已安装服务配置${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    if [[ -f "/usr/local/etc/xray/reclient.json" ]]; then

        echo -e "${GREEN}[Vless + Reality 配置]${NC}"

        cat /usr/local/etc/xray/reclient.json

        echo ""

        echo "----------------------------------------"

    fi

    

    if [[ -f "/etc/hysteria/hyclient.json" ]]; then

        echo -e "${GREEN}[Hysteria2 配置]${NC}"

        cat /etc/hysteria/hyclient.json

        echo ""

        echo "----------------------------------------"

    fi

    

    if [[ -f "/etc/shadowsocks/config.json" ]]; then

        echo -e "${GREEN}[Shadowsocks-rust 配置]${NC}"

        cat /etc/shadowsocks/config.json

        echo ""

        echo "----------------------------------------"

    fi

    

    if [[ -f "/usr/local/etc/v2ray/client.json" ]]; then

        echo -e "${GREEN}[VMess 配置]${NC}"

        cat /usr/local/etc/v2ray/client.json

        echo ""

        echo "----------------------------------------"

    fi

    

    if [[ -f "/etc/caddy/https.json" ]]; then

        echo -e "${GREEN}[HTTPS 正向代理配置]${NC}"

        cat /etc/caddy/https.json

        echo ""

        echo "----------------------------------------"

    fi

    

    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then

        echo -e "${GREEN}[DDNS 配置]${NC}"

        cat "$CONFIG_DIR/ddns.conf"

        echo ""

    fi

    

    echo ""

    read -rp "按回车键继续..."

}

generate_subscription() {

    local SUB_CONTENT=""

    

    # Vless

    if [[ -f "/usr/local/etc/xray/reclient.json" ]]; then

        local vless_link=$(grep '"连接链接"' /usr/local/etc/xray/reclient.json | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        [[ -n "$vless_link" ]] && SUB_CONTENT="${SUB_CONTENT}${vless_link}\n"

    fi

    

    # Hysteria2

    if [[ -f "/etc/hysteria/hyclient.json" ]]; then

        local hy2_server=$(jq -r '.server' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_auth=$(jq -r '.auth' /etc/hysteria/hyclient.json 2>/dev/null)

        if [[ -n "$hy2_server" && -n "$hy2_auth" ]]; then

            local hy2_link="hysteria2://${hy2_auth}@${hy2_server}/?insecure=1&sni=bing.com#Hysteria2"

            SUB_CONTENT="${SUB_CONTENT}${hy2_link}\n"

        fi

    fi

    

    # Shadowsocks

    if [[ -f "/etc/shadowsocks/config.json" ]]; then

        local ss_ip=$(get_server_ip)

        local ss_port=$(jq -r '.server_port' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_pass=$(jq -r '.password' /etc/shadowsocks/config.json 2>/dev/null)

        if [[ -n "$ss_port" && -n "$ss_pass" ]]; then

            local ss_link=$(echo -n "aes-128-gcm:${ss_pass}@${ss_ip}:${ss_port}" | base64 -w 0)

            SUB_CONTENT="${SUB_CONTENT}ss://${ss_link}\n"

        fi

    fi

    

    # VMess

    if [[ -f "/usr/local/etc/v2ray/client.json" ]]; then

        local vmess_domain=$(grep '地址' /usr/local/etc/v2ray/client.json | head -1 | sed 's/.*：\(.*\)/\1/')

        local vmess_port=$(grep '端口' /usr/local/etc/v2ray/client.json | head -1 | sed 's/.*：\(.*\)/\1/')

        local vmess_uuid=$(grep 'UUID' /usr/local/etc/v2ray/client.json | head -1 | sed 's/.*：\(.*\)/\1/')

        local vmess_path=$(grep '路径' /usr/local/etc/v2ray/client.json | head -1 | sed 's/.*：\(.*\)/\1/')

        if [[ -n "$vmess_domain" && -n "$vmess_uuid" ]]; then

            local vmess_json="{\"v\":\"2\",\"ps\":\"VMess\",\"add\":\"$vmess_domain\",\"port\":\"$vmess_port\",\"id\":\"$vmess_uuid\",\"aid\":0,\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$vmess_domain\",\"path\":\"$vmess_path\",\"tls\":\"tls\",\"sni\":\"$vmess_domain\"}"

            local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"

            SUB_CONTENT="${SUB_CONTENT}${vmess_link}\n"

        fi

    fi

    

    if [[ -z "$SUB_CONTENT" ]]; then

        echo ""

        return 1

    fi

    

    SUB_CONTENT=$(echo -e "$SUB_CONTENT" | sed '$d')

    echo -n "$SUB_CONTENT" | base64 -w 0

}

show_subscription() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                      订阅链接${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    local SUB_B64=$(generate_subscription)

    

    if [[ -z "$SUB_B64" ]]; then

        echo -e "${YELLOW}尚未安装任何代理服务${NC}"

        read -rp "按回车键继续..."

        return

    fi

    

    echo -e "${GREEN}订阅链接 (Base64):${NC}"

    echo ""

    echo "$SUB_B64"

    echo ""

    

    read -rp "按回车键继续..."

}

uninstall_service() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                        卸载服务${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    echo "  1. 卸载 Vless (Xray)"

    echo "  2. 卸载 Hysteria2"

    echo "  3. 卸载 Shadowsocks-rust"

    echo "  4. 卸载 VMess (V2Ray)"

    echo "  5. 卸载 HTTPS 正向代理 (Caddy)"

    echo "  6. 卸载所有服务"

    echo "  7. 返回主菜单"

    echo ""

    read -rp "请选择 [1-7]: " uninstall_choice

    

    case $uninstall_choice in

        1)

            systemctl stop xray 2>/dev/null || true

            systemctl disable xray 2>/dev/null || true

            rm -rf /usr/local/etc/xray

            rm -f /usr/local/bin/xray

            log "Vless 已卸载"

            ;;

        2)

            systemctl stop hysteria-server 2>/dev/null || true

            systemctl disable hysteria-server 2>/dev/null || true

            rm -rf /etc/hysteria

            rm -f /usr/local/bin/hysteria

            log "Hysteria2 已卸载"

            ;;

        3)

            systemctl stop shadowsocks 2>/dev/null || true

            systemctl disable shadowsocks 2>/dev/null || true

            rm -f /usr/local/bin/ssserver

            log "Shadowsocks-rust 已卸载"

            ;;

        4)

            systemctl stop v2ray 2>/dev/null || true

            systemctl disable v2ray 2>/dev/null || true

            rm -rf /usr/local/etc/v2ray

            rm -f /usr/local/bin/v2ray

            log "VMess 已卸载"

            ;;

        5)

            systemctl stop caddy 2>/dev/null || true

            systemctl disable caddy 2>/dev/null || true

            rm -f /usr/local/bin/caddy

            log "HTTPS 正向代理已卸载"

            ;;

        6)

            systemctl stop xray hysteria-server shadowsocks v2ray caddy nginx 2>/dev/null || true

            systemctl disable xray hysteria-server shadowsocks v2ray caddy nginx 2>/dev/null || true

            rm -rf /usr/local/etc/xray /etc/hysteria /usr/local/etc/v2ray

            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/ssserver /usr/local/bin/v2ray /usr/local/bin/caddy

            log "所有服务已卸载"

            ;;

        7) return ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

# ==================== 主菜单 ====================

# 流量统计功能

show_traffic_stats() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    流量使用统计${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    local has_data=false

    

    # Xray 协议流量统计 (Vless + VMess)

    if [[ -f /usr/local/bin/xray ]] && command -v xray &>/dev/null; then

        # 检查 xray API 是否可用

        local xray_api_port=""

        if [[ -f /usr/local/etc/xray/config.json ]]; then

            xray_api_port=$(jq -r '.api?.tag // empty' /usr/local/etc/xray/config.json 2>/dev/null)

        fi

        

        # 尝试通过 xray API 获取流量

        if [[ -n "$xray_api_port" ]] && timeout 2 xray api statsquery --server=127.0.0.1:10085 &>/dev/null; then

            echo -e "${GREEN}[Xray 协议流量]${NC}"

            local stats_output=$(timeout 3 xray api statsquery --server=127.0.0.1:10085 2>/dev/null | jq -r '.stat[]? | select(.value != "0") | "\(.name): \(.value)"' 2>/dev/null)

            if [[ -n "$stats_output" ]]; then

                echo "$stats_output" | while read -r line; do

                    local name=$(echo "$line" | cut -d: -f1)

                    local value=$(echo "$line" | cut -d: -f2-)

                    # Convert bytes to human readable

                    local bytes=$value

                    if [[ "$bytes" -gt 1073741824 ]]; then

                        printf "  %-30s %6.2f GB\n" "$name" $(echo "scale=2; $bytes/1073741824" | bc)

                    elif [[ "$bytes" -gt 1048576 ]]; then

                        printf "  %-30s %6.2f MB\n" "$name" $(echo "scale=2; $bytes/1048576" | bc)

                    elif [[ "$bytes" -gt 1024 ]]; then

                        printf "  %-30s %6.2f KB\n" "$name" $(echo "scale=2; $bytes/1024" | bc)

                    else

                        printf "  %-30s %6d B\n" "$name" "$bytes"

                    fi

                done

                has_data=true

            else

                echo -e "  ${YELLOW}暂无流量数据${NC}"

            fi

        else

            # 回退到日志解析方式

            if [[ -f /var/log/xray/access.log ]]; then

                echo -e "${GREEN}[Xray 协议流量 - 基于日志估算]${NC}"

                # 统计今日连接数作为活跃度参考

                local today=$(date +%Y/%m/%d)

                local today_connections=$(grep -c "$today" /var/log/xray/access.log 2>/dev/null)

                if [[ $? -ne 0 ]]; then

                    today_connections=0

                fi

                echo -e "  今日连接数: $today_connections"

                

                # 显示最近的访问记录

                echo -e "  ${YELLOW}最近 5 条访问记录:${NC}"

                tail -5 /var/log/xray/access.log 2>/dev/null | while read -r line; do

                    echo "    $line"

                done

                has_data=true

            else

                echo -e "  ${YELLOW}Xray 日志文件不存在${NC}"

            fi

        fi

        echo ""

    fi

    

    # Hysteria2 流量统计

    if [[ -f /usr/local/bin/hysteria ]] || [[ -f /usr/local/bin/hysteria2 ]]; then

        echo -e "${GREEN}[Hysteria2 流量]${NC}"

        

        # 检查 hysteria2 是否运行

        local hy_active=false

        if systemctl is-active --quiet hysteria-server 2>/dev/null; then

            hy_active=true

        elif systemctl is-active --quiet hysteria2 2>/dev/null; then

            hy_active=true

        fi

        

        if [[ "$hy_active" == true ]]; then

            echo -e "  ${GREEN}服务状态: 运行中${NC}"

            

            # 检查是否有流量日志

            local log_file=""

            if [[ -f /var/log/hysteria/server.log ]]; then

                log_file="/var/log/hysteria/server.log"

            elif [[ -f /var/log/hysteria2/server.log ]]; then

                log_file="/var/log/hysteria2/server.log"

            fi

            

            if [[ -n "$log_file" ]]; then

                local today_upload=$(grep -oE 'upload=[0-9]+' "$log_file" 2>/dev/null | tail -1 | cut -d= -f2)

                local today_download=$(grep -oE 'download=[0-9]+' "$log_file" 2>/dev/null | tail -1 | cut -d= -f2)

                

                if [[ -n "$today_upload" ]]; then

                    local upload_human=$(numfmt --to=iec "$today_upload" 2>/dev/null)

                    if [[ -z "$upload_human" ]]; then

                        upload_human="$today_upload bytes"

                    fi

                    echo -e "  上传: $upload_human"

                fi

                if [[ -n "$today_download" ]]; then

                    local download_human=$(numfmt --to=iec "$today_download" 2>/dev/null)

                    if [[ -z "$download_human" ]]; then

                        download_human="$today_download bytes"

                    fi

                    echo -e "  下载: $download_human"

                fi

            else

                echo -e "  ${YELLOW}Hysteria2 流量日志未启用${NC}"

            fi

        else

            echo -e "  ${YELLOW}Hysteria2 服务未运行${NC}"

        fi

        has_data=true

        echo ""

    fi

    

    # Shadowsocks 流量统计

    if [[ -f /usr/local/bin/ssserver ]] || [[ -f /usr/local/bin/ss-server ]]; then

        echo -e "${GREEN}[Shadowsocks-rust 流量]${NC}"

        

        local ss_active=false

        if systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then

            ss_active=true

        elif systemctl is-active --quiet shadowsocks 2>/dev/null; then

            ss_active=true

        fi

        

        if [[ "$ss_active" == true ]]; then

            echo -e "  ${GREEN}服务状态: 运行中${NC}"

            

            # 尝试从配置文件获取端口

            if [[ -f /etc/shadowsocks/config.json ]]; then

                local ss_port=$(jq -r '.server_port' /etc/shadowsocks/config.json 2>/dev/null)

                echo -e "  端口: $ss_port"

            fi

            

            # SS-rust 可以通过 verbose 日志查看流量，但默认可能未启用

            echo -e "  ${YELLOW}提示: Shadowsocks-rust 默认不记录流量统计${NC}"

            echo -e "  ${YELLOW}如需流量统计，建议配合 vnStat 使用${NC}"

        else

            echo -e "  ${YELLOW}Shadowsocks 服务未运行${NC}"

        fi

        has_data=true

        echo ""

    fi

    

    # 系统总流量 (vnStat)

    if command -v vnstat &>/dev/null; then

        echo -e "${GREEN}[系统总流量 (vnStat)]${NC}"

        local main_iface=$(ip route | grep default | awk '{print $5}' | head -1)

        if [[ -n "$main_iface" ]]; then

            echo -e "  接口: $main_iface"

            local vnstat_output=$(vnstat -i "$main_iface" --oneline 2>/dev/null)

            if [[ -n "$vnstat_output" ]]; then

                echo "$vnstat_output" | awk -F';' '{printf "  今日: %s  本月: %s\n", $4, $11}'

            else

                echo -e "  ${YELLOW}vnStat 数据不可用${NC}"

            fi

        fi

        has_data=true

        echo ""

    fi

    

    if [[ "$has_data" == false ]]; then

        echo -e "${YELLOW}尚未安装任何代理服务，无流量数据${NC}"

    fi

    

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    read -rp "按回车键继续..."

}

# 系统优化功能

optimize_system() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    系统网络优化${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    echo -e "${YELLOW}请选择优化项目:${NC}"

    echo ""

    echo "  1. 一键开启 BBR + FQ (推荐)"

    echo "  2. 开启 BBR + CAKE"

    echo "  3. 开启 BBR + FQ_CODEL"

    echo "  4. 还原为默认 CUBIC"

    echo "  5. 安装并配置 vnStat 流量监控"

    echo "  6. 优化系统参数 (文件描述符/缓冲区)"

    echo "  7. 返回主菜单"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    read -rp "请选择 [1-7]: " opt_choice

    

    case $opt_choice in

        1|2|3|4)

            local cc_algo="bbr"

            local qdisc="fq"

            

            case $opt_choice in

                1) qdisc="fq" ;;

                2) qdisc="cake" ;;

                3) qdisc="fq_codel" ;;

                4) cc_algo="cubic"; qdisc="fq_codel" ;;

            esac

            

            echo -e "${YELLOW}正在设置 TCP 拥塞控制: ${cc_algo}, 队列算法: ${qdisc}${NC}"

            

            # 检查内核版本是否支持 BBR

            local kernel_version=$(uname -r | cut -d. -f1-2)

            if [[ "$opt_choice" != "4" ]]; then

                if [[ $(echo "$kernel_version >= 4.9" | bc 2>/dev/null || echo "0") == "0" ]]; then

                    if [[ $(echo "$kernel_version < 4.9" | bc 2>/dev/null || echo "1") == "1" ]]; then

                        echo -e "${RED}错误: 当前内核版本 $(uname -r) 不支持 BBR，需要 4.9+${NC}"

                        read -rp "按回车键继续..."

                        return

                    fi

                fi

            fi

            

            # 加载 TCP BBR 模块

            if [[ "$cc_algo" == "bbr" ]]; then

                modprobe tcp_bbr 2>/dev/null || true

                if ! lsmod | grep -q tcp_bbr; then

                    echo -e "${YELLOW}警告: 无法加载 tcp_bbr 模块，尝试继续...${NC}"

                fi

            fi

            

            # 写入 sysctl 配置

            cat > /etc/sysctl.d/99-vps-toolbox.conf <<EOF

# VPS Toolbox 网络优化

net.core.default_qdisc=${qdisc}

net.ipv4.tcp_congestion_control=${cc_algo}

net.ipv4.tcp_notsent_lowat = 16384

EOF

            

            # 应用配置

            sysctl --system >/dev/null 2>&1

            

            # 验证

            local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

            local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

            

            echo ""

            echo -e "${GREEN}优化完成!${NC}"

            echo -e "  TCP 拥塞控制: ${GREEN}${current_cc}${NC}"

            echo -e "  队列算法: ${GREEN}${current_qdisc}${NC}"

            echo ""

            echo -e "${YELLOW}提示: 配置已写入 /etc/sysctl.d/99-vps-toolbox.conf${NC}"

            echo -e "${YELLOW}重启后依然生效${NC}"

            ;;

            

        5)

            echo -e "${YELLOW}正在安装 vnStat...${NC}"

            if command -v apt &>/dev/null; then

                apt update -qq && apt install -y -qq vnstat 2>/dev/null

            elif command -v yum &>/dev/null; then

                yum install -y vnstat 2>/dev/null

            elif command -v dnf &>/dev/null; then

                dnf install -y vnstat 2>/dev/null

            fi

            

            if command -v vnstat &>/dev/null; then

                # 配置 vnStat

                local main_iface=$(ip route | grep default | awk '{print $5}' | head -1)

                if [[ -n "$main_iface" ]]; then

                    systemctl enable vnstat 2>/dev/null || true

                    systemctl restart vnstat 2>/dev/null || true

                    echo -e "${GREEN}vnStat 安装完成!${NC}"

                    echo -e "  监控接口: ${GREEN}${main_iface}${NC}"

                    echo -e "  查看流量: ${YELLOW}vnstat -i ${main_iface}${NC}"

                fi

            else

                echo -e "${RED}vnStat 安装失败${NC}"

            fi

            ;;

            

        6)

            echo -e "${YELLOW}正在优化系统参数...${NC}"

            

            cat >> /etc/sysctl.d/99-vps-toolbox.conf <<EOF

# 系统参数优化

fs.file-max = 65535

net.core.rmem_max = 67108864

net.core.wmem_max = 67108864

net.core.netdev_max_backlog = 250000

net.core.somaxconn = 4096

net.ipv4.tcp_syncookies = 1

net.ipv4.tcp_tw_reuse = 1

net.ipv4.tcp_fin_timeout = 30

net.ipv4.tcp_keepalive_time = 1200

net.ipv4.ip_local_port_range = 10000 65000

net.ipv4.tcp_max_syn_backlog = 8192

net.ipv4.tcp_max_tw_buckets = 5000

net.ipv4.tcp_fastopen = 3

net.ipv4.tcp_mem = 25600 51200 102400

net.ipv4.tcp_rmem = 4096 87380 67108864

net.ipv4.tcp_wmem = 4096 65536 67108864

net.ipv4.tcp_mtu_probing = 1

net.ipv4.tcp_slow_start_after_idle = 0

EOF

            

            sysctl --system >/dev/null 2>&1

            

            # 优化文件描述符限制

            cat >> /etc/security/limits.conf <<EOF

# VPS Toolbox 文件描述符优化

* soft nofile 65535

* hard nofile 65535

root soft nofile 65535

root hard nofile 65535

EOF

            

            echo -e "${GREEN}系统参数优化完成!${NC}"

            echo -e "${YELLOW}提示: 部分参数需要重新登录或重启后完全生效${NC}"

            ;;

            

        7)

            return

            ;;

            

        *)

            warn "无效选择"

            ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

# 一键DD系统功能

dd_system() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    一键重装系统 (DD)${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    echo -e "${RED}警告: 此操作将完全抹除当前系统所有数据!${NC}"

    echo -e "${RED}警告: 请确保已备份重要数据!${NC}"

    echo ""

    echo -e "${YELLOW}支持的系统:${NC}"

    echo ""

    echo "  1. Debian 12 (推荐)"

    echo "  2. Debian 11"

    echo "  3. Ubuntu 24.04 LTS"

    echo "  4. Ubuntu 22.04 LTS"

    echo "  5. CentOS Stream 9"

    echo "  6. Alpine Linux"

    echo "  7. Windows Server 2022 (实验性)"

    echo ""

    echo "  8. 自定义镜像 URL"

    echo "  9. 返回主菜单"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    read -rp "请选择 [1-9]: " dd_choice

    

    local image_url=""

    local distro=""

    

    case $dd_choice in

        1) image_url="https://github.com/veip007/dd/raw/master/Debian_12.img.gz"; distro="Debian 12" ;;

        2) image_url="https://github.com/veip007/dd/raw/master/Debian_11.img.gz"; distro="Debian 11" ;;

        3) image_url="https://github.com/veip007/dd/raw/master/Ubuntu_2404.img.gz"; distro="Ubuntu 24.04" ;;

        4) image_url="https://github.com/veip007/dd/raw/master/Ubuntu_2204.img.gz"; distro="Ubuntu 22.04" ;;

        5) image_url="https://github.com/veip007/dd/raw/master/CentOS_9_Stream.img.gz"; distro="CentOS Stream 9" ;;

        6) image_url="https://github.com/veip007/dd/raw/master/Alpine_3_19.img.gz"; distro="Alpine Linux" ;;

        7) image_url="https://github.com/veip007/dd/raw/master/Windows_Server_2022.img.gz"; distro="Windows Server 2022" ;;

        8)

            echo ""

            read -rp "请输入自定义镜像 URL: " custom_url

            image_url="$custom_url"

            distro="自定义系统"

            ;;

        9)

            return

            ;;

        *)

            warn "无效选择"

            return

            ;;

    esac

    

    if [[ -z "$image_url" ]]; then

        return

    fi

    

    echo ""

    echo -e "${RED}============================================================${NC}"

    echo -e "${RED}                     最终确认${NC}"

    echo -e "${RED}============================================================${NC}"

    echo ""

    echo -e "目标系统: ${YELLOW}${distro}${NC}"

    echo -e "镜像地址: ${YELLOW}${image_url}${NC}"

    echo ""

    echo -e "${RED}此操作将:${NC}"

    echo -e "  ${RED}- 删除当前系统所有数据${NC}"

    echo -e "  ${RED}- 重新安装操作系统${NC}"

    echo -e "  ${RED}- 所有配置将丢失${NC}"

    echo ""

    

    read -rp "确认重装? 输入 [我确认重装] 继续: " confirm

    

    if [[ "$confirm" != "我确认重装" ]]; then

        echo -e "${YELLOW}已取消重装操作${NC}"

        read -rp "按回车键继续..."

        return

    fi

    

    echo ""

    echo -e "${YELLOW}正在准备重装环境...${NC}"

    

    # 安装必要工具

    if ! command -v wget &>/dev/null; then

        if command -v apt &>/dev/null; then

            apt update -qq && apt install -y -qq wget 2>/dev/null

        elif command -v yum &>/dev/null; then

            yum install -y wget 2>/dev/null

        elif command -v dnf &>/dev/null; then

            dnf install -y wget 2>/dev/null

        fi

    fi

    

    # 下载并执行 DD 脚本

    echo -e "${YELLOW}正在下载 DD 脚本...${NC}"

    cd /tmp

    

    # 使用成熟的 DD 脚本 (MoeClub 的 dd 脚本)

    wget -qO- https://raw.githubusercontent.com/fcurrk/reinstall/master/Network-Reinstall-System-Modify.sh | bash -s -- -dd "$image_url"

    

    # 如果上面的脚本失败，尝试备用方案

    if [[ $? -ne 0 ]]; then

        echo -e "${YELLOW}主脚本失败，尝试备用方案...${NC}"

        wget -qO /tmp/InstallNET.sh https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh

        chmod +x /tmp/InstallNET.sh

        bash /tmp/InstallNET.sh -debian 12

    fi

}

# 网络测速功能

speed_test() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    网络测速${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""



    echo -e "${YELLOW}请选择测速方式:${NC}"

    echo ""

    echo "  1. Speedtest (全球节点)"

    echo "  2. 国内三网测速 (电信/联通/移动)"

    echo "  3. 回程路由测试 (BestTrace)"

    echo "  4. 回程路由测试 (NextTrace)"

    echo "  5. 带宽测试 (iPerf3)"

    echo "  6. 返回主菜单"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    read -rp "请选择 [1-6]: " speed_choice



    case $speed_choice in

        1)

            echo -e "${YELLOW}正在安装 Speedtest...${NC}"

            if ! command -v speedtest &>/dev/null; then

                # 使用官方安装脚本
                local install_script="/tmp/speedtest-install.sh"
                if [[ "$PKG_MANAGER" == "apt" ]]; then
                    wget -qO "$install_script" https://install.speedtest.net/app/cli/install.deb.sh 2>/dev/null || \
                    curl -sL https://install.speedtest.net/app/cli/install.deb.sh -o "$install_script" 2>/dev/null || true
                    [[ -f "$install_script" ]] && bash "$install_script" 2>/dev/null && apt install -y speedtest 2>/dev/null || true
                else
                    wget -qO "$install_script" https://install.speedtest.net/app/cli/install.rpm.sh 2>/dev/null || \
                    curl -sL https://install.speedtest.net/app/cli/install.rpm.sh -o "$install_script" 2>/dev/null || true
                    [[ -f "$install_script" ]] && bash "$install_script" 2>/dev/null && \
                    (yum install -y speedtest 2>/dev/null || dnf install -y speedtest 2>/dev/null) || true
                fi
            fi



            if command -v speedtest &>/dev/null; then

                echo -e "${GREEN}开始测速...${NC}"

                speedtest --accept-license --accept-gdpr

            else

                # 备用方案: 直接下载官方二进制
                echo -e "${YELLOW}使用备用方案 (官方 Speedtest CLI)...${NC}"

                local arch=$(uname -m)
                local speedtest_url=""
                case "$arch" in
                    x86_64) speedtest_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" ;;
                    aarch64) speedtest_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz" ;;
                    *) speedtest_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" ;;
                esac

                wget -qO /tmp/speedtest.tgz "$speedtest_url" 2>/dev/null || \
                curl -sL "$speedtest_url" -o /tmp/speedtest.tgz 2>/dev/null || true

                if [[ -f /tmp/speedtest.tgz ]]; then
                    tar -xzf /tmp/speedtest.tgz -C /tmp 2>/dev/null
                    chmod +x /tmp/speedtest 2>/dev/null
                fi

                if [[ -x /tmp/speedtest ]]; then
                    echo -e "${GREEN}开始测速...${NC}"
                    /tmp/speedtest --accept-license --accept-gdpr
                else
                    echo -e "${RED}测速工具安装失败${NC}"
                fi
            fi

            ;;



        2)

            echo -e "${YELLOW}国内三网测速...${NC}"

            echo ""



            # 使用 superspeed 脚本
            echo -e "${GREEN}[电信节点]${NC}"

            bash <(curl -sL https://raw.githubusercontent.com/oooldking/script/master/superspeed.sh) 2>/dev/null || \

            bash <(curl -sL https://raw.githubusercontent.com/zq/superspeed/master/superspeed.sh) 2>/dev/null || \

            echo -e "${YELLOW}三网测速脚本暂时不可用，尝试单节点测试...${NC}"



            # 备用：使用 speedtest-go 测试国内节点
            local arch=$(uname -m)
            local go_arch="x86_64"
            [[ "$arch" == "aarch64" ]] && go_arch="arm64"

            # 使用固定版本号
            local version_num="1.7.10"

            local go_url="https://github.com/showwin/speedtest-go/releases/download/v${version_num}/speedtest-go_${version_num}_Linux_${go_arch}.tar.gz"

            wget -qO /tmp/speedtest-go.tar.gz "$go_url" 2>/dev/null || \
            curl -sL "$go_url" -o /tmp/speedtest-go.tar.gz 2>/dev/null || true

            if [[ -f /tmp/speedtest-go.tar.gz ]]; then
                tar -xzf /tmp/speedtest-go.tar.gz -C /tmp 2>/dev/null
                chmod +x /tmp/speedtest-go 2>/dev/null
            fi

            if [[ -x /tmp/speedtest-go ]]; then
                echo ""
                echo -e "${GREEN}使用 speedtest-go 测试附近节点...${NC}"
                /tmp/speedtest-go --server 5315 2>/dev/null || true   # 上海电信
                /tmp/speedtest-go --server 5505 2>/dev/null || true   # 北京联通
                /tmp/speedtest-go --server 4617 2>/dev/null || true   # 深圳移动
            fi

            ;;



        3)

            echo -e "${YELLOW}安装 BestTrace...${NC}"

            if ! command -v besttrace &>/dev/null; then

                cd /tmp

                wget -qO besttrace4linux.zip "https://cdn.ipip.net/17mon/besttrace4linux.zip" 2>/dev/null || \

                curl -sL "https://cdn.ipip.net/17mon/besttrace4linux.zip" -o besttrace4linux.zip 2>/dev/null || true

                if [[ -f besttrace4linux.zip ]]; then

                    unzip -o besttrace4linux.zip besttrace 2>/dev/null || true

                    chmod +x besttrace 2>/dev/null

                    mv besttrace /usr/local/bin/ 2>/dev/null || true

                fi

            fi



            if command -v besttrace &>/dev/null; then

                echo -e "${GREEN}回程路由测试 (到 223.5.5.5 阿里DNS)...${NC}"

                besttrace -q 1 223.5.5.5

                echo ""

                echo -e "${GREEN}回程路由测试 (到 119.29.29.29 腾讯DNS)...${NC}"

                besttrace -q 1 119.29.29.29

            else

                echo -e "${RED}BestTrace 安装失败，使用 mtr 代替...${NC}"

                if command -v mtr &>/dev/null; then

                    mtr -r -c 10 223.5.5.5

                else

                    traceroute 223.5.5.5

                fi

            fi

            ;;



        4)

            echo -e "${YELLOW}安装 NextTrace...${NC}"

            if ! command -v nexttrace &>/dev/null; then

                bash <(curl -Ls nxtrace.org/nt) 2>/dev/null || \

                wget -qO /tmp/nexttrace https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_amd64 && \

                chmod +x /tmp/nexttrace && mv /tmp/nexttrace /usr/local/bin/ 2>/dev/null || true

            fi



            if command -v nexttrace &>/dev/null; then

                echo -e "${GREEN}回程路由测试 (到 223.5.5.5)...${NC}"

                nexttrace 223.5.5.5

            else

                echo -e "${RED}NextTrace 安装失败${NC}"

            fi

            ;;



        5)

            echo -e "${YELLOW}iPerf3 带宽测试...${NC}"

            if ! command -v iperf3 &>/dev/null; then

                apt install -y iperf3 2>/dev/null || yum install -y iperf3 2>/dev/null || dnf install -y iperf3 2>/dev/null || true

            fi



            if command -v iperf3 &>/dev/null; then

                echo -e "${GREEN}公共 iPerf3 服务器列表:${NC}"

                echo "  iperf.he.net        (Hurricane Electric)"

                echo "  iperf.scottlinux.com"

                echo "  bouygues.iperf.fr"

                echo ""

                read -rp "请输入 iPerf3 服务器地址 (默认 iperf.he.net): " iperf_server

                [[ -z "$iperf_server" ]] && iperf_server="iperf.he.net"

                echo -e "${GREEN}正在测试到 ${iperf_server}...${NC}"

                iperf3 -c "$iperf_server" -t 10

            else

                echo -e "${RED}iPerf3 安装失败${NC}"

            fi

            ;;



        6)

            return

            ;;



        *)

            warn "无效选择"

            ;;

    esac



    echo ""

    read -rp "按回车键继续..."

}

# 证书管理功能

manage_cert() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    SSL 证书管理${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    # 检查 acme.sh 是否安装

    local acme_sh="$HOME/.acme.sh/acme.sh"

    [[ ! -f "$acme_sh" ]] && acme_sh="/root/.acme.sh/acme.sh"

    

    if [[ ! -f "$acme_sh" ]]; then

        echo -e "${YELLOW}acme.sh 未安装，正在安装...${NC}"

        curl https://get.acme.sh | bash 2>/dev/null || true

        acme_sh="$HOME/.acme.sh/acme.sh"

        [[ ! -f "$acme_sh" ]] && acme_sh="/root/.acme.sh/acme.sh"

    fi

    

    # 查找所有证书

    local cert_dir=""

    if [[ -d "$HOME/.acme.sh" ]]; then

        cert_dir="$HOME/.acme.sh"

    elif [[ -d "/root/.acme.sh" ]]; then

        cert_dir="/root/.acme.sh"

    fi

    

    echo -e "${GREEN}已安装的证书:${NC}"

    echo ""

    

    if [[ -d "$cert_dir" ]]; then

        local found_cert=false

        for cert_path in "$cert_dir"/*/*.cer; do

            [[ ! -f "$cert_path" ]] && continue

            found_cert=true

            local domain=$(basename "$cert_path" .cer)

            local cert_file="$cert_dir/${domain}/${domain}.cer"

            

            if [[ -f "$cert_file" ]]; then

                # 获取到期时间

                local end_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)

                local expire_ts=$(date -d "$end_date" +%s 2>/dev/null || echo "0")

                local now_ts=$(date +%s)

                local days_left=$(( (expire_ts - now_ts) / 86400 ))

                

                # 颜色标记

                local color="${GREEN}"

                [[ $days_left -lt 7 ]] && color="${RED}"

                [[ $days_left -lt 30 && $days_left -ge 7 ]] && color="${YELLOW}"

                

                echo -e "  域名: ${GREEN}${domain}${NC}"

                echo -e "  到期: ${color}${end_date}${NC}"

                echo -e "  剩余: ${color}${days_left} 天${NC}"

                echo ""

            fi

        done

        

        if [[ "$found_cert" == false ]]; then

            echo -e "  ${YELLOW}未找到证书${NC}"

        fi

    else

        echo -e "  ${YELLOW}证书目录不存在${NC}"

    fi

    

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    echo -e "${YELLOW}操作选项:${NC}"

    echo "  1. 手动续签所有证书"

    echo "  2. 强制重新申请证书"

    echo "  3. 查看证书详情"

    echo "  4. 删除证书"

    echo "  5. 设置自动续签 (cron)"

    echo "  6. 返回主菜单"

    echo ""

    read -rp "请选择 [1-6]: " cert_choice

    

    case $cert_choice in

        1)

            echo -e "${YELLOW}正在续签所有证书...${NC}"

            if [[ -f "$acme_sh" ]]; then

                "$acme_sh" --cron --home "$cert_dir" --server letsencrypt

                echo -e "${GREEN}续签完成!${NC}"

            else

                echo -e "${RED}acme.sh 未找到${NC}"

            fi

            ;;

            

        2)

            echo ""

            read -rp "请输入域名: " domain

            if [[ -n "$domain" ]]; then

                echo -e "${YELLOW}正在重新申请 ${domain} 的证书...${NC}"

                if [[ -f "$acme_sh" ]]; then

                    # 尝试使用 standalone 模式

                    "$acme_sh" --issue --standalone -d "$domain" --server letsencrypt --force 2>/dev/null || \

                    echo -e "${RED}申请失败，请确保:${NC}" && \

                    echo -e "  ${YELLOW}- 域名已解析到本机${NC}" && \

                    echo -e "  ${YELLOW}- 80 端口未被占用${NC}"

                fi

            fi

            ;;

            

        3)

            echo ""

            read -rp "请输入域名: " domain

            if [[ -n "$domain" && -f "$cert_dir/${domain}/${domain}.cer" ]]; then

                echo -e "${GREEN}证书详情:${NC}"

                openssl x509 -in "$cert_dir/${domain}/${domain}.cer" -noout -text 2>/dev/null | head -30

            else

                echo -e "${RED}证书不存在${NC}"

            fi

            ;;

            

        4)

            echo ""

            read -rp "请输入要删除的域名: " domain

            if [[ -n "$domain" ]]; then

                read -rp "确认删除 ${domain} 的证书? [y/N]: " confirm

                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then

                    "$acme_sh" --remove -d "$domain" 2>/dev/null || true

                    rm -rf "$cert_dir/${domain}" 2>/dev/null || true

                    echo -e "${GREEN}证书已删除${NC}"

                fi

            fi

            ;;

            

        5)

            echo -e "${YELLOW}设置自动续签...${NC}"

            if [[ -f "$acme_sh" ]]; then

                # 安装 cron 任务

                "$acme_sh" --install-cronjob 2>/dev/null || true

                

                # 验证 cron

                if crontab -l 2>/dev/null | grep -q acme; then

                    echo -e "${GREEN}自动续签已设置!${NC}"

                    echo -e "${YELLOW}Cron 任务:${NC}"

                    crontab -l | grep acme

                else

                    # 手动添加

                    (crontab -l 2>/dev/null; echo "0 2 * * * $acme_sh --cron --home $cert_dir --server letsencrypt > /dev/null 2>&1") | crontab -

                    echo -e "${GREEN}已添加每日 2:00 自动续签任务${NC}"

                fi

            fi

            ;;

            

        6)

            return

            ;;

            

        *)

            warn "无效选择"

            ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

# 端口占用一览

port_status() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    端口占用一览${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    # 系统监听端口

    echo -e "${GREEN}[系统监听端口]${NC}"

    echo ""

    printf "  %-8s %-8s %-20s %-15s %s\n" "协议" "端口" "服务" "进程" "状态"

    printf "  %-8s %-8s %-20s %-15s %s\n" "----" "----" "------" "------" "------"

    

    ss -tlnp 2>/dev/null | awk 'NR>1 {

        proto="TCP"

        port=$4

        gsub(/.*:/, "", port)

        proc=$6

        gsub(/users:/, "", proc)

        state=$1

        printf "  %-8s %-8s %-20s %-15s %s\n", proto, port, "-", proc, state

    }' | sort -n -k2 | head -30

    

    ss -ulnp 2>/dev/null | awk 'NR>1 {

        proto="UDP"

        port=$4

        gsub(/.*:/, "", port)

        proc=$6

        gsub(/users:/, "", proc)

        printf "  %-8s %-8s %-20s %-15s %s\n", proto, port, "-", proc, "LISTEN"

    }' | sort -n -k2 | head -20

    

    echo ""

    

    # 代理协议端口

    echo -e "${GREEN}[代理协议端口]${NC}"

    echo ""

    

    # Vless/Xray

    if [[ -f /usr/local/etc/xray/config.json ]]; then

        local xray_port=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/xray/config.json 2>/dev/null)

        local xray_proto=$(jq -r '.inbounds[0].protocol // empty' /usr/local/etc/xray/config.json 2>/dev/null)

        if [[ -n "$xray_port" ]]; then

            local status="${GREEN}运行中${NC}"

            systemctl is-active --quiet xray 2>/dev/null || status="${RED}未运行${NC}"

            printf "  %-15s %-8s %-15s %b\n" "Xray/Vless" "$xray_port" "$xray_proto" "$status"

        fi

    fi

    

    # Hysteria2

    if [[ -f /etc/hysteria/config.yaml ]] || [[ -f /etc/hysteria2/config.yaml ]]; then

        local hy_config=""

        [[ -f /etc/hysteria/config.yaml ]] && hy_config="/etc/hysteria/config.yaml"

        [[ -f /etc/hysteria2/config.yaml ]] && hy_config="/etc/hysteria2/config.yaml"

        if [[ -n "$hy_config" ]]; then

            local hy_port=$(grep -E '^listen:' "$hy_config" 2>/dev/null | grep -oE '[0-9]+' | head -1)

            if [[ -n "$hy_port" ]]; then

                local status="${GREEN}运行中${NC}"

                systemctl is-active --quiet hysteria-server 2>/dev/null || systemctl is-active --quiet hysteria2 2>/dev/null || status="${RED}未运行${NC}"

                printf "  %-15s %-8s %-15s %b\n" "Hysteria2" "$hy_port" "QUIC" "$status"

            fi

        fi

    fi

    

    # Shadowsocks

    if [[ -f /etc/shadowsocks/config.json ]]; then

        local ss_port=$(jq -r '.server_port // empty' /etc/shadowsocks/config.json 2>/dev/null)

        if [[ -n "$ss_port" ]]; then

            local status="${GREEN}运行中${NC}"

            systemctl is-active --quiet shadowsocks-rust 2>/dev/null || systemctl is-active --quiet shadowsocks 2>/dev/null || status="${RED}未运行${NC}"

            printf "  %-15s %-8s %-15s %b\n" "Shadowsocks" "$ss_port" "TCP/UDP" "$status"

        fi

    fi

    

    # Nginx (for VMess/HTTPS proxy)

    if command -v nginx &>/dev/null; then

        local nginx_ports=$(ss -tlnp | grep nginx | awk '{print $4}' | sed 's/.*://' | sort -u | tr '\n' ',' | sed 's/,$//')

        if [[ -n "$nginx_ports" ]]; then

            local status="${GREEN}运行中${NC}"

            systemctl is-active --quiet nginx 2>/dev/null || status="${RED}未运行${NC}"

            printf "  %-15s %-8s %-15s %b\n" "Nginx" "$nginx_ports" "HTTP/HTTPS" "$status"

        fi

    fi

    

    # Caddy

    if command -v caddy &>/dev/null; then

        local caddy_ports=$(ss -tlnp | grep caddy | awk '{print $4}' | sed 's/.*://' | sort -u | tr '\n' ',' | sed 's/,$//')

        if [[ -n "$caddy_ports" ]]; then

            local status="${GREEN}运行中${NC}"

            systemctl is-active --quiet caddy 2>/dev/null || status="${RED}未运行${NC}"

            printf "  %-15s %-8s %-15s %b\n" "Caddy" "$caddy_ports" "HTTP/HTTPS" "$status"

        fi

    fi

    

    echo ""

    

    # 防火墙状态

    echo -e "${GREEN}[防火墙状态]${NC}"

    echo ""

    if command -v ufw &>/dev/null; then

        echo -e "  UFW: $(ufw status numbered 2>/dev/null | head -5)"

    elif command -v firewall-cmd &>/dev/null; then

        echo -e "  Firewalld: $(firewall-cmd --state 2>/dev/null || echo '未运行')"

    elif command -v iptables &>/dev/null; then

        echo -e "  iptables: $(iptables -L -n 2>/dev/null | grep -c 'ACCEPT') 条 ACCEPT 规则"

    else

        echo -e "  ${YELLOW}未检测到防火墙${NC}"

    fi

    

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    echo -e "${YELLOW}操作选项:${NC}"

    echo "  1. 测试端口连通性"

    echo "  2. 一键开放所有代理端口"

    echo "  3. 返回主菜单"

    echo ""

    read -rp "请选择 [1-3]: " port_choice

    

    case $port_choice in

        1)

            echo ""

            read -rp "请输入要测试的端口: " test_port

            if [[ -n "$test_port" ]]; then

                if ss -tln | grep -q ":${test_port} "; then

                    echo -e "${GREEN}端口 ${test_port} 正在监听${NC}"

                else

                    echo -e "${RED}端口 ${test_port} 未监听${NC}"

                fi

                

                # 外部连通性测试

                echo -e "${YELLOW}测试外部连通性...${NC}"

                local server_ip=$(get_server_ip)

                echo -e "  服务器 IP: ${server_ip}"

                echo -e "  ${YELLOW}提示: 使用在线工具检测 ${server_ip}:${test_port} 是否可访问${NC}"

            fi

            ;;

            

        2)

            echo -e "${YELLOW}正在开放所有代理端口...${NC}"

            

            # 收集所有代理端口

            local ports_to_open=""

            

            if [[ -f /usr/local/etc/xray/config.json ]]; then

                local xport=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/xray/config.json 2>/dev/null)

                [[ -n "$xport" ]] && ports_to_open="$ports_to_open $xport"

            fi

            

            if [[ -f /etc/hysteria/config.yaml ]]; then

                local hport=$(grep -E '^listen:' /etc/hysteria/config.yaml 2>/dev/null | grep -oE '[0-9]+' | head -1)

                [[ -n "$hport" ]] && ports_to_open="$ports_to_open $hport"

            fi

            

            if [[ -f /etc/shadowsocks/config.json ]]; then

                local sport=$(jq -r '.server_port // empty' /etc/shadowsocks/config.json 2>/dev/null)

                [[ -n "$sport" ]] && ports_to_open="$ports_to_open $sport"

            fi

            

            # 开放端口

            for port in $ports_to_open; do

                if command -v ufw &>/dev/null; then

                    ufw allow "$port/tcp" 2>/dev/null || true

                    ufw allow "$port/udp" 2>/dev/null || true

                    echo -e "  ${GREEN}UFW 已开放端口 ${port}${NC}"

                elif command -v firewall-cmd &>/dev/null; then

                    firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null || true

                    firewall-cmd --permanent --add-port="${port}/udp" 2>/dev/null || true

                    firewall-cmd --reload 2>/dev/null || true

                    echo -e "  ${GREEN}Firewalld 已开放端口 ${port}${NC}"

                elif command -v iptables &>/dev/null; then

                    iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true

                    iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true

                    echo -e "  ${GREEN}iptables 已开放端口 ${port}${NC}"

                fi

            done

            

            # 同时开放常用端口

            if command -v ufw &>/dev/null; then

                ufw allow 22/tcp 2>/dev/null || true

                ufw allow 80/tcp 2>/dev/null || true

                ufw allow 443/tcp 2>/dev/null || true

            elif command -v firewall-cmd &>/dev/null; then

                firewall-cmd --permanent --add-service=ssh 2>/dev/null || true

                firewall-cmd --permanent --add-service=http 2>/dev/null || true

                firewall-cmd --permanent --add-service=https 2>/dev/null || true

                firewall-cmd --reload 2>/dev/null || true

            fi

            

            echo -e "${GREEN}端口开放完成!${NC}"

            ;;

            

        3)

            return

            ;;

            

        *)

            warn "无效选择"

            ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

# Telegram Bot 功能

setup_tgbot() {

    clear

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    Telegram Bot 配置${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    # 检查是否已配置

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    if [[ -f "$bot_config" ]]; then

        echo -e "${GREEN}Bot 已配置${NC}"

        source "$bot_config"

        echo -e "  Bot Token: ${TG_BOT_TOKEN:0:20}..."

        echo -e "  Chat ID: $TG_CHAT_ID"

        echo ""

        echo -e "${YELLOW}操作选项:${NC}"

        echo "  1. 重新配置"

        echo "  2. 测试发送消息"

        echo "  3. 启动 Bot 服务"

        echo "  4. 停止 Bot 服务"

        echo "  5. 查看 Bot 状态"

        echo "  6. 删除配置"

        echo "  7. 返回主菜单"

        echo ""

        read -rp "请选择 [1-7]: " bot_choice

    else

        bot_choice=1

    fi

    

    case $bot_choice in

        1)

            echo -e "${YELLOW}请从 @BotFather 获取 Bot Token${NC}"

            echo -e "${YELLOW}格式: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz${NC}"

            echo ""

            read -rp "请输入 Bot Token: " new_token

            

            if [[ -z "$new_token" ]]; then

                echo -e "${RED}Token 不能为空${NC}"

                read -rp "按回车键继续..."

                return

            fi

            

            # 获取 Chat ID

            echo -e "${YELLOW}正在获取 Chat ID...${NC}"

            echo -e "${YELLOW}请给 Bot 发送一条消息，然后按回车${NC}"

            read -rp "按回车键继续..."

            

            local updates=$(curl -s "https://api.telegram.org/bot${new_token}/getUpdates")

            local chat_id=$(echo "$updates" | grep -o '"chat":{"id":[0-9-]*' | grep -o '[0-9-]*' | tail -1)

            

            if [[ -z "$chat_id" ]]; then

                echo -e "${YELLOW}未检测到消息，请手动输入 Chat ID${NC}"

                echo -e "${YELLOW}获取方法: 访问 https://api.telegram.org/bot<TOKEN>/getUpdates${NC}"

                read -rp "请输入 Chat ID: " chat_id

            else

                echo -e "${GREEN}自动获取到 Chat ID: $chat_id${NC}"

            fi

            

            # 保存配置

            mkdir -p /etc/vps-toolbox

            cat > "$bot_config" <<EOF

TG_BOT_TOKEN="$new_token"

TG_CHAT_ID="$chat_id"

EOF

            

            echo -e "${GREEN}配置已保存!${NC}"

            

            # 测试发送

            echo -e "${YELLOW}正在发送测试消息...${NC}"

            local test_msg=$(cat <<'EOF'
🚀 *VPS Toolbox* 配置成功

服务器: $(hostname)

IP: $(get_server_ip)

时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

            

            if send_tg_message "$test_msg"; then

                echo -e "${GREEN}测试消息发送成功!${NC}"

            else

                echo -e "${RED}测试消息发送失败，请检查 Token 和 Chat ID${NC}"

            fi

            ;;

            

        2)

            if [[ -f "$bot_config" ]]; then

                source "$bot_config"

                local test_msg=$(cat <<'EOF'
🧪 *测试消息*

服务器: $(hostname)

IP: $(get_server_ip)

时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

                if send_tg_message "$test_msg"; then

                    echo -e "${GREEN}测试消息发送成功!${NC}"

                else

                    echo -e "${RED}发送失败${NC}"

                fi

            fi

            ;;

            

        3)

            start_tgbot_service

            ;;

            

        4)

            stop_tgbot_service

            ;;

            

        5)

            if systemctl is-active --quiet vps-toolbox-bot 2>/dev/null; then

                echo -e "${GREEN}Bot 服务运行中${NC}"

                systemctl status vps-toolbox-bot --no-pager 2>/dev/null | head -10

            else

                echo -e "${YELLOW}Bot 服务未运行${NC}"

            fi

            ;;

            

        6)

            read -rp "确认删除 Bot 配置? [y/N]: " confirm

            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then

                rm -f "$bot_config"

                systemctl stop vps-toolbox-bot 2>/dev/null || true

                systemctl disable vps-toolbox-bot 2>/dev/null || true

                rm -f /etc/systemd/system/vps-toolbox-bot.service

                echo -e "${GREEN}配置已删除${NC}"

            fi

            ;;

            

        7)

            return

            ;;

    esac

    

    echo ""

    read -rp "按回车键继续..."

}

# 发送 Telegram 消息

send_tg_message() {

    local message="$1"

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    

    if [[ ! -f "$bot_config" ]]; then

        return 1

    fi

    

    source "$bot_config"

    

    if [[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" ]]; then

        return 1

    fi

    

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \

        -d "chat_id=${TG_CHAT_ID}" \

        -d "text=${message}" \

        -d "parse_mode=Markdown" \

        -d "disable_web_page_preview=true" >/dev/null

    

    return 0

}

# 发送 Telegram 通知 (用于安装完成等)

send_tg_notify() {

    local title="$1"

    local content="$2"

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    

    [[ ! -f "$bot_config" ]] && return 1

    source "$bot_config"

    [[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" ]] && return 1

    

    local message=$(cat <<EOF
📢 *${title}*

${content}

服务器: \`$(hostname)\`

IP: \`$(get_server_ip)\`

时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

    

    send_tg_message "$message"

}

# 启动 Bot 服务

start_tgbot_service() {

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    

    if [[ ! -f "$bot_config" ]]; then

        echo -e "${RED}Bot 未配置，请先配置${NC}"

        return 1

    fi

    

    source "$bot_config"

    

    # 创建 Bot 处理脚本

    cat > /usr/local/bin/vps-toolbox-bot.sh <<'BOTSCRIPT'

#!/bin/bash

# VPS Toolbox Telegram Bot

source /etc/vps-toolbox/tgbot.conf

# 发送消息函数

bot_send() {

    local msg="$1"

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \

        -d "chat_id=${TG_CHAT_ID}" \

        -d "text=${msg}" \

        -d "parse_mode=Markdown" \

        -d "disable_web_page_preview=true" >/dev/null

}

# 获取服务器信息

get_server_info() {

    local hostname=$(hostname)

    local ip=$(curl -s ip.sb 2>/dev/null || echo "未知")

    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)

    local mem=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

    local disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    local uptime_info=$(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}')

    

    local msg=$(cat <<EOF
📊 *服务器状态*

主机名: \`${hostname}\`

IP: \`${ip}\`

负载: \`${load}\`

内存: \`${mem}\`

磁盘: \`${disk}\`

运行时间: ${uptime_info}
EOF
)
        echo "$msg"

}

# 获取代理状态

get_proxy_status() {

    local status=$(cat <<'EOF'
📡 *代理服务状态*

EOF
)
    status="${status}"

    

    # Xray

    if systemctl is-active --quiet xray 2>/dev/null; then

        local xray_port=$(jq -r '.inbounds[0].port // "未知"' /usr/local/etc/xray/config.json 2>/dev/null)

        status="${status}$(cat <<'EOF'
✅ Xray: 运行中 (端口: ${xray_port})
EOF
)"

    else

        status="${status}$(cat <<'EOF'
❌ Xray: 未运行
EOF
)"

    fi

    

    # Hysteria2

    if systemctl is-active --quiet hysteria-server 2>/dev/null || systemctl is-active --quiet hysteria2 2>/dev/null; then

        status="${status}$(cat <<'EOF'
✅ Hysteria2: 运行中
EOF
)"

    else

        status="${status}$(cat <<'EOF'
❌ Hysteria2: 未运行
EOF
)"

    fi

    

    # Shadowsocks

    if systemctl is-active --quiet shadowsocks-rust 2>/dev/null || systemctl is-active --quiet shadowsocks 2>/dev/null; then

        status="${status}$(cat <<'EOF'
✅ Shadowsocks: 运行中
EOF
)"

    else

        status="${status}$(cat <<'EOF'
❌ Shadowsocks: 未运行
EOF
)"

    fi

    

    echo "$status"

}

# 获取配置链接

get_config_links() {

    local links=$(cat <<'EOF'
🔗 *配置信息*

EOF
)
    links="${links}"

    

    if [[ -f /usr/local/etc/xray/reclient.json ]]; then

        local vless_link=$(grep '"连接链接"' /usr/local/etc/xray/reclient.json 2>/dev/null | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        [[ -n "$vless_link" ]] && links="${links}$(cat <<EOF
Vless:

\`${vless_link}\`

EOF
)"

    fi

    

    if [[ -f /etc/hysteria/hyclient.json ]]; then

        local hy2_server=$(jq -r '.server' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_auth=$(jq -r '.auth' /etc/hysteria/hyclient.json 2>/dev/null)

        if [[ -n "$hy2_server" && -n "$hy2_auth" ]]; then

            links="${links}$(cat <<EOF
Hysteria2:

\`hysteria2://${hy2_auth}@${hy2_server}/?insecure=1&sni=bing.com#Hysteria2\`

EOF
)"

        fi

    fi

    

    echo "$links"

}

# 处理命令

process_command() {

    local cmd="$1"

    local msg_id="$2"

    

    case "$cmd" in

        "/status"|"/状态")

            bot_send "$(get_server_info)"

            ;;

        "/proxy"|"/代理")

            bot_send "$(get_proxy_status)"

            ;;

        "/config"|"/配置")

            bot_send "$(get_config_links)"

            ;;

        "/traffic"|"/流量")

            local main_iface=$(ip route | grep default | awk '{print $5}' | head -1)

            if command -v vnstat &>/dev/null && [[ -n "$main_iface" ]]; then

                local traffic=$(vnstat -i "$main_iface" --oneline 2>/dev/null | awk -F';' '{print "今日: " $4 " | 本月: " $11}')

                local tg_msg=$(cat <<EOF
📊 *流量统计*

接口: ${main_iface}

${traffic}
EOF
)
            bot_send "$tg_msg"

            else

                local tg_msg2=$(cat <<'EOF'
📊 *流量统计*

vnStat 未安装或未配置
EOF
)
            bot_send "$tg_msg2"

            fi

            ;;

        "/restart_xray"|"/重启xray")

            systemctl restart xray 2>/dev/null

            if systemctl is-active --quiet xray 2>/dev/null; then

                bot_send "✅ Xray 重启成功"

            else

                bot_send "❌ Xray 重启失败"

            fi

            ;;

        "/restart_hy2"|"/重启hy2")

            systemctl restart hysteria-server 2>/dev/null || systemctl restart hysteria2 2>/dev/null

            if systemctl is-active --quiet hysteria-server 2>/dev/null || systemctl is-active --quiet hysteria2 2>/dev/null; then

                bot_send "✅ Hysteria2 重启成功"

            else

                bot_send "❌ Hysteria2 重启失败"

            fi

            ;;

        "/restart_ss"|"/重启ss")

            systemctl restart shadowsocks-rust 2>/dev/null || systemctl restart shadowsocks 2>/dev/null

            if systemctl is-active --quiet shadowsocks-rust 2>/dev/null || systemctl is-active --quiet shadowsocks 2>/dev/null; then

                bot_send "✅ Shadowsocks 重启成功"

            else

                bot_send "❌ Shadowsocks 重启失败"

            fi

            ;;

        "/help"|"/帮助"|"/start")

            local help_msg=$(cat <<'EOF'
🤖 *VPS Toolbox Bot 命令列表*

📊 状态查询

\`/status\` - 服务器状态

\`/proxy\` - 代理服务状态

\`/traffic\` - 流量统计

🔗 配置管理

\`/config\` - 查看配置链接

🔄 服务控制

\`/restart_xray\` - 重启 Xray

\`/restart_hy2\` - 重启 Hysteria2

\`/restart_ss\` - 重启 Shadowsocks

❓ 帮助

\`/help\` - 显示此帮助
EOF
)
            bot_send "$help_msg"

            ;;

    esac

}

# 主循环

last_update_id=0

while true; do

    updates=$(curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates?offset=$((last_update_id + 1))&limit=10")

    

    # 解析更新

    echo "$updates" | grep -o '"update_id":[0-9]*' | grep -o '[0-9]*' | while read -r update_id; do

        [[ "$update_id" -le "$last_update_id" ]] && continue

        last_update_id=$update_id

        

        # 获取消息文本

        msg_text=$(echo "$updates" | grep -o '"text":"[^"]*"' | grep -o '":"[^"]*' | sed 's/":"//' | tail -1)

        msg_id=$(echo "$updates" | grep -o '"message_id":[0-9]*' | grep -o '[0-9]*' | tail -1)

        

        if [[ -n "$msg_text" ]]; then

            process_command "$msg_text" "$msg_id"

        fi

    done

    

    sleep 3

done

BOTSCRIPT

    

    chmod +x /usr/local/bin/vps-toolbox-bot.sh

    

    # 创建 systemd 服务

    cat > /etc/systemd/system/vps-toolbox-bot.service <<EOF

[Unit]

Description=VPS Toolbox Telegram Bot

After=network.target

[Service]

Type=simple

ExecStart=/usr/local/bin/vps-toolbox-bot.sh

Restart=always

RestartSec=10

[Install]

WantedBy=multi-user.target

EOF

    

    systemctl daemon-reload

    systemctl enable vps-toolbox-bot

    systemctl start vps-toolbox-bot

    

    if systemctl is-active --quiet vps-toolbox-bot; then

        echo -e "${GREEN}Bot 服务已启动!${NC}"

        echo -e "${YELLOW}发送 /help 给 Bot 查看命令列表${NC}"

    else

        echo -e "${RED}Bot 服务启动失败${NC}"

        systemctl status vps-toolbox-bot --no-pager 2>/dev/null | tail -20

    fi

}

# 停止 Bot 服务

stop_tgbot_service() {

    systemctl stop vps-toolbox-bot 2>/dev/null || true

    systemctl disable vps-toolbox-bot 2>/dev/null || true

    echo -e "${GREEN}Bot 服务已停止${NC}"

}

# 在安装完成后发送通知

notify_install_complete() {

    local protocol="$1"

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    

    [[ ! -f "$bot_config" ]] && return 0

    

    local content=$(cat <<EOF
✅ *${protocol}* 安装完成

服务器: \`$(hostname)\`

IP: \`$(get_server_ip)\`

时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

    

    send_tg_notify "安装完成" "$content"

}

# 节点订阅管理功能

# 自动聚合所有协议配置，生成标准订阅链接，支持TG Bot推送

AIRPORT_DIR="/etc/vps-toolbox/airport"

SUBSCRIPTION_FILE="$AIRPORT_DIR/subscription.txt"

SUBSCRIPTION_B64="$AIRPORT_DIR/subscription.b64"

SUBSCRIPTION_MD5="$AIRPORT_DIR/subscription.md5"

# 初始化订阅目录

init_airport() {

    mkdir -p "$AIRPORT_DIR"

    [[ ! -f "$SUBSCRIPTION_FILE" ]] && touch "$SUBSCRIPTION_FILE"

}

# 生成节点订阅内容 (非Base64，原始链接)

generate_airport_sub() {

    init_airport

    

    local sub_content=""

    local node_count=0

    

    # Vless + Reality

    if [[ -f /usr/local/etc/xray/reclient.json ]]; then

        local vless_link=$(grep '"连接链接"' /usr/local/etc/xray/reclient.json 2>/dev/null | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        if [[ -n "$vless_link" ]]; then

            sub_content="${sub_content}${vless_link}\n"

            ((node_count++))

        fi

    fi

    

    # VMess + WS + TLS

    if [[ -f /usr/local/etc/xray/client.json ]]; then

        local vmess_link=$(grep '"连接链接"' /usr/local/etc/xray/client.json 2>/dev/null | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        if [[ -n "$vmess_link" ]]; then

            sub_content="${sub_content}${vmess_link}\n"

            ((node_count++))

        fi

    fi

    

    # Hysteria2

    if [[ -f /etc/hysteria/hyclient.json ]]; then

        local hy2_server=$(jq -r '.server' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_auth=$(jq -r '.auth' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_sni=$(jq -r '.tls.sni // "bing.com"' /etc/hysteria/hyclient.json 2>/dev/null)

        if [[ -n "$hy2_server" && -n "$hy2_auth" ]]; then

            local hy2_link="hysteria2://${hy2_auth}@${hy2_server}/?insecure=1&sni=${hy2_sni}#Hysteria2-$(hostname)"

            sub_content="${sub_content}${hy2_link}\n"

            ((node_count++))

        fi

    fi

    

    # Shadowsocks

    if [[ -f /etc/shadowsocks/config.json ]]; then

        local ss_ip=$(get_server_ip)

        local ss_port=$(jq -r '.server_port' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_pass=$(jq -r '.password' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_method=$(jq -r '.method' /etc/shadowsocks/config.json 2>/dev/null)

        if [[ -n "$ss_port" && -n "$ss_pass" && -n "$ss_method" ]]; then

            local ss_link="ss://$(echo -n "${ss_method}:${ss_pass}" | base64 -w 0)@${ss_ip}:${ss_port}#SS-$(hostname)"

            sub_content="${sub_content}${ss_link}\n"

            ((node_count++))

        fi

    fi

    

    # Trojan (如果存在)

    if [[ -f /usr/local/etc/xray/trojan.json ]]; then

        local trojan_pass=$(jq -r '.inbounds[0].settings.clients[0].password // empty' /usr/local/etc/xray/trojan.json 2>/dev/null)

        local trojan_port=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/xray/trojan.json 2>/dev/null)

        if [[ -n "$trojan_pass" && -n "$trojan_port" ]]; then

            local trojan_link="trojan://${trojan_pass}@$(get_server_ip):${trojan_port}#Trojan-$(hostname)"

            sub_content="${sub_content}${trojan_link}\n"

            ((node_count++))

        fi

    fi

    

    # 保存原始订阅内容

    echo -e "$sub_content" > "$SUBSCRIPTION_FILE"

    

    # 生成 Base64 订阅

    local sub_b64=$(echo -e "$sub_content" | base64 -w 0)

    echo "$sub_b64" > "$SUBSCRIPTION_B64"

    

    # 计算 MD5 用于检测变化

    local new_md5=$(echo -e "$sub_content" | md5sum | awk '{print $1}')

    echo "$new_md5" > "$SUBSCRIPTION_MD5"

    

    echo "$node_count"

}

# 显示节点订阅管理菜单

airport_manager() {

    init_airport

    

    while true; do

        clear

        echo ""

        echo -e "${CYAN}============================================================${NC}"

        echo -e "${CYAN}                    节点订阅管理${NC}"

        echo -e "${CYAN}============================================================${NC}"

        echo ""

        

        # 生成最新订阅

        local node_count=$(generate_airport_sub)

        local sub_b64=$(cat "$SUBSCRIPTION_B64" 2>/dev/null)

        local server_ip=$(get_server_ip)

        

        echo -e "${GREEN}当前节点数: ${node_count}${NC}"

        echo ""

        echo -e "${YELLOW}订阅链接:${NC}"

        echo -e "  ${GREEN}http://${server_ip}/sub${NC} (需配合 Nginx/Caddy)"

        echo -e "  ${GREEN}http://${server_ip}:8080/sub${NC} (内置 HTTP 服务)"

        echo ""

        echo -e "${YELLOW}Base64 订阅内容 (前100字符):${NC}"

        echo "  ${sub_b64:0:100}..."

        echo ""

        echo -e "${CYAN}============================================================${NC}"

        echo ""

        echo -e "${YELLOW}操作选项:${NC}"

        echo "  1. 查看所有节点详情"

        echo "  2. 复制订阅链接到剪贴板 (SSH终端显示)"

        echo "  3. 通过 Telegram Bot 推送订阅"

        echo "  4. 设置自动更新推送 (cron)"

        echo "  5. 启动内置 HTTP 订阅服务"

        echo "  6. 配置 Nginx/Caddy 订阅路径"

        echo "  7. 测试订阅链接可用性"

        echo "  8. 返回主菜单"

        echo ""

        read -rp "请选择 [1-8]: " airport_choice

        

        case $airport_choice in

            1)

                show_nodes_detail

                ;;

            2)

                echo ""

                echo -e "${GREEN}订阅链接 (Base64):${NC}"

                echo ""

                echo "$sub_b64"

                echo ""

                echo -e "${YELLOW}完整链接:${NC}"

                echo "http://${server_ip}:8080/sub"

                ;;

            3)

                push_sub_to_telegram

                ;;

            4)

                setup_auto_update_push

                ;;

            5)

                start_sub_http_server

                ;;

            6)

                setup_nginx_sub_path

                ;;

            7)

                test_subscription

                ;;

            8)

                return

                ;;

            *)

                warn "无效选择"

                ;;

        esac

        

        echo ""

        read -rp "按回车键继续..."

    done

}

# 显示节点详情

show_nodes_detail() {

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${CYAN}                    节点详情${NC}"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    

    local idx=1

    

    # Vless

    if [[ -f /usr/local/etc/xray/reclient.json ]]; then

        echo -e "${GREEN}[$idx] Vless + Reality${NC}"

        local addr=$(jq -r '.地址 // empty' /usr/local/etc/xray/reclient.json 2>/dev/null)

        local port=$(jq -r '.端口 // empty' /usr/local/etc/xray/reclient.json 2>/dev/null)

        local id=$(jq -r '.UUID // empty' /usr/local/etc/xray/reclient.json 2>/dev/null)

        local sni=$(jq -r '.SNI // empty' /usr/local/etc/xray/reclient.json 2>/dev/null)

        echo "  地址: $addr"

        echo "  端口: $port"

        echo "  UUID: ${id:0:8}..."

        echo "  SNI: $sni"

        echo ""

        ((idx++))

    fi

    

    # VMess

    if [[ -f /usr/local/etc/xray/client.json ]]; then

        echo -e "${GREEN}[$idx] VMess + WS + TLS${NC}"

        local vm_addr=$(jq -r '.地址 // empty' /usr/local/etc/xray/client.json 2>/dev/null)

        local vm_port=$(jq -r '.端口 // empty' /usr/local/etc/xray/client.json 2>/dev/null)

        echo "  地址: $vm_addr"

        echo "  端口: $vm_port"

        echo ""

        ((idx++))

    fi

    

    # Hysteria2

    if [[ -f /etc/hysteria/hyclient.json ]]; then

        echo -e "${GREEN}[$idx] Hysteria2${NC}"

        local hy_srv=$(jq -r '.server' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy_sni=$(jq -r '.tls.sni // "bing.com"' /etc/hysteria/hyclient.json 2>/dev/null)

        echo "  服务器: $hy_srv"

        echo "  SNI: $hy_sni"

        echo ""

        ((idx++))

    fi

    

    # Shadowsocks

    if [[ -f /etc/shadowsocks/config.json ]]; then

        echo -e "${GREEN}[$idx] Shadowsocks${NC}"

        local ss_port=$(jq -r '.server_port' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_method=$(jq -r '.method' /etc/shadowsocks/config.json 2>/dev/null)

        echo "  端口: $ss_port"

        echo "  加密: $ss_method"

        echo ""

        ((idx++))

    fi

}

# 推送订阅到 Telegram

push_sub_to_telegram() {

    local bot_config="/etc/vps-toolbox/tgbot.conf"

    

    if [[ ! -f "$bot_config" ]]; then

        echo -e "${RED}Telegram Bot 未配置${NC}"

        echo -e "${YELLOW}请先配置 Bot: 主菜单 -> 工具 -> Telegram Bot 配置${NC}"

        return 1

    fi

    

    source "$bot_config"

    

    if [[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" ]]; then

        echo -e "${RED}Bot Token 或 Chat ID 为空${NC}"

        return 1

    fi

    

    # 生成最新订阅

    local node_count=$(generate_airport_sub)

    local sub_b64=$(cat "$SUBSCRIPTION_B64" 2>/dev/null)

    local server_ip=$(get_server_ip)

    

    if [[ -z "$sub_b64" ]]; then

        echo -e "${RED}订阅内容为空，请先安装代理协议${NC}"

        return 1

    fi

    

    # 构建消息

    local message=$(cat <<'EOF'
✈️ *节点订阅更新*

📊 *节点信息:*

EOF
)
    message="${message}"

    

    # 添加节点列表

    local idx=1

    [[ -f /usr/local/etc/xray/reclient.json ]] && message="${message}  ${idx}. Vless + Reality\n" && ((idx++))

    [[ -f /usr/local/etc/xray/client.json ]] && message="${message}  ${idx}. VMess + WS + TLS\n" && ((idx++))

    [[ -f /etc/hysteria/hyclient.json ]] && message="${message}  ${idx}. Hysteria2\n" && ((idx++))

    [[ -f /etc/shadowsocks/config.json ]] && message="${message}  ${idx}. Shadowsocks\n" && ((idx++))

    

    message="${message}$(cat <<EOF

📡 *订阅链接:*

\`http://${server_ip}:8080/sub\`

📋 *Base64 订阅:*

\`${sub_b64}\`

⏰ 更新时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)"

    

    # 发送消息

    local response=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \

        -d "chat_id=${TG_CHAT_ID}" \

        -d "text=${message}" \

        -d "parse_mode=Markdown" \

        -d "disable_web_page_preview=true")

    

    if echo "$response" | grep -q '"ok":true'; then

        echo -e "${GREEN}订阅已推送到 Telegram!${NC}"

    else

        echo -e "${RED}推送失败: $response${NC}"

        return 1

    fi

}

# 设置自动更新推送

setup_auto_update_push() {

    echo ""

    echo -e "${YELLOW}设置自动推送...${NC}"

    echo ""

    echo "  1. 每小时检查更新并推送"

    echo "  2. 每天检查更新并推送"

    echo "  3. 每周检查更新并推送"

    echo "  4. 关闭自动推送"

    echo "  5. 返回"

    echo ""

    read -rp "请选择 [1-5]: " auto_choice

    

    local cron_expr=""

    case $auto_choice in

        1) cron_expr="0 * * * *" ;;

        2) cron_expr="0 8 * * *" ;;

        3) cron_expr="0 8 * * 1" ;;

        4)

            crontab -l 2>/dev/null | grep -v "vps-toolbox-airport" | crontab -

            echo -e "${GREEN}自动推送已关闭${NC}"

            return

            ;;

        5) return ;;

        *) warn "无效选择"; return ;;

    esac

    

    # 创建自动推送脚本

    cat > /usr/local/bin/vps-toolbox-airport-push.sh <<'PUSHSCRIPT'

#!/bin/bash

# VPS Toolbox 节点订阅自动推送

AIRPORT_DIR="/etc/vps-toolbox/airport"

SUBSCRIPTION_FILE="$AIRPORT_DIR/subscription.txt"

SUBSCRIPTION_MD5="$AIRPORT_DIR/subscription.md5"

BOT_CONFIG="/etc/vps-toolbox/tgbot.conf"

# 加载 Bot 配置

[[ ! -f "$BOT_CONFIG" ]] && exit 0

source "$BOT_CONFIG"

[[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" ]] && exit 0

# 加载订阅函数

source /usr/local/bin/vps-toolbox-airport-lib.sh 2>/dev/null || exit 0

# 生成新订阅

node_count=$(generate_airport_sub)

new_md5=$(cat "$SUBSCRIPTION_MD5" 2>/dev/null)

old_md5=$(cat "$SUBSCRIPTION_MD5.old" 2>/dev/null)

# 如果内容变化或首次运行，推送更新

if [[ "$new_md5" != "$old_md5" ]]; then

    server_ip=$(curl -s ip.sb 2>/dev/null || echo "127.0.0.1")

    sub_b64=$(cat "$SUBSCRIPTION_B64" 2>/dev/null)

    

    message=$(cat <<EOF
✈️ *节点订阅自动更新*

📊 *节点数: ${node_count}*

EOF
)
    message="${message}"

    

    # 检测变化类型

    if [[ -z "$old_md5" ]]; then

        message="${message}\n🆕 *首次推送*"

    else

        message="${message}\n🔄 *配置已变更*"

    fi

    

    message="${message}$(cat <<EOF

📡 *订阅链接:*

\`http://${server_ip}:8080/sub\`

📋 *Base64 订阅:*

\`${sub_b64}\`

⏰ 更新时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)"

    

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \

        -d "chat_id=${TG_CHAT_ID}" \

        -d "text=${message}" \

        -d "parse_mode=Markdown" \

        -d "disable_web_page_preview=true" >/dev/null

    

    # 保存旧 MD5

    cp "$SUBSCRIPTION_MD5" "$SUBSCRIPTION_MD5.old"

fi

PUSHSCRIPT

    

    chmod +x /usr/local/bin/vps-toolbox-airport-push.sh

    

    # 创建库文件

    cat > /usr/local/bin/vps-toolbox-airport-lib.sh <<'LIBSCRIPT'

#!/bin/bash

# 节点订阅库函数

AIRPORT_DIR="/etc/vps-toolbox/airport"

SUBSCRIPTION_FILE="$AIRPORT_DIR/subscription.txt"

SUBSCRIPTION_B64="$AIRPORT_DIR/subscription.b64"

SUBSCRIPTION_MD5="$AIRPORT_DIR/subscription.md5"

get_server_ip() {

    curl -s ip.sb 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "127.0.0.1"

}

generate_airport_sub() {

    mkdir -p "$AIRPORT_DIR"

    local sub_content=""

    local node_count=0

    

    if [[ -f /usr/local/etc/xray/reclient.json ]]; then

        local vless_link=$(grep '"连接链接"' /usr/local/etc/xray/reclient.json 2>/dev/null | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        [[ -n "$vless_link" ]] && sub_content="${sub_content}${vless_link}\n" && ((node_count++))

    fi

    

    if [[ -f /usr/local/etc/xray/client.json ]]; then

        local vmess_link=$(grep '"连接链接"' /usr/local/etc/xray/client.json 2>/dev/null | sed 's/.*"连接链接": "\(.*\)".*/\1/')

        [[ -n "$vmess_link" ]] && sub_content="${sub_content}${vmess_link}\n" && ((node_count++))

    fi

    

    if [[ -f /etc/hysteria/hyclient.json ]]; then

        local hy2_server=$(jq -r '.server' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_auth=$(jq -r '.auth' /etc/hysteria/hyclient.json 2>/dev/null)

        local hy2_sni=$(jq -r '.tls.sni // "bing.com"' /etc/hysteria/hyclient.json 2>/dev/null)

        if [[ -n "$hy2_server" && -n "$hy2_auth" ]]; then

            sub_content="${sub_content}hysteria2://${hy2_auth}@${hy2_server}/?insecure=1&sni=${hy2_sni}#Hysteria2-$(hostname)\n"

            ((node_count++))

        fi

    fi

    

    if [[ -f /etc/shadowsocks/config.json ]]; then

        local ss_ip=$(get_server_ip)

        local ss_port=$(jq -r '.server_port' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_pass=$(jq -r '.password' /etc/shadowsocks/config.json 2>/dev/null)

        local ss_method=$(jq -r '.method' /etc/shadowsocks/config.json 2>/dev/null)

        if [[ -n "$ss_port" && -n "$ss_pass" && -n "$ss_method" ]]; then

            sub_content="${sub_content}ss://$(echo -n "${ss_method}:${ss_pass}" | base64 -w 0)@${ss_ip}:${ss_port}#SS-$(hostname)\n"

            ((node_count++))

        fi

    fi

    

    echo -e "$sub_content" > "$SUBSCRIPTION_FILE"

    echo -e "$sub_content" | base64 -w 0 > "$SUBSCRIPTION_B64"

    echo -e "$sub_content" | md5sum | awk '{print $1}' > "$SUBSCRIPTION_MD5"

    

    echo "$node_count"

}

LIBSCRIPT

    

    chmod +x /usr/local/bin/vps-toolbox-airport-lib.sh

    

    # 添加 cron 任务

    (crontab -l 2>/dev/null | grep -v "vps-toolbox-airport"; echo "$cron_expr /usr/local/bin/vps-toolbox-airport-push.sh >/dev/null 2>&1") | crontab -

    

    echo -e "${GREEN}自动推送已设置!${NC}"

    echo -e "${YELLOW}Cron 表达式: $cron_expr${NC}"

    echo -e "${YELLOW}推送脚本: /usr/local/bin/vps-toolbox-airport-push.sh${NC}"

}

# 启动内置 HTTP 订阅服务

start_sub_http_server() {

    local server_ip=$(get_server_ip)

    

    echo ""

    echo -e "${YELLOW}启动内置 HTTP 订阅服务...${NC}"

    

    # 检查是否已有服务在运行

    if ss -tlnp | grep -q ":8080"; then

        echo -e "${YELLOW}端口 8080 已被占用${NC}"

        ss -tlnp | grep ":8080"

        echo ""

        echo -e "${YELLOW}是否强制重启? [y/N]:${NC} "

        read -r confirm

        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then

            local pid=$(ss -tlnp | grep ":8080" | grep -o 'pid=[0-9]*' | cut -d= -f2)

            [[ -n "$pid" ]] && kill "$pid" 2>/dev/null

        else

            return

        fi

    fi

    

    # 创建简单的 HTTP 服务脚本

    cat > /usr/local/bin/vps-toolbox-sub-server.py <<'PYSCRIPT'

#!/usr/bin/env python3

import http.server

import socketserver

import os

PORT = 8080

SUB_FILE = "/etc/vps-toolbox/airport/subscription.b64"

class SubHandler(http.server.SimpleHTTPRequestHandler):

    def do_GET(self):

        if self.path == '/sub' or self.path == '/subscribe':

            self.send_response(200)

            self.send_header('Content-type', 'text/plain; charset=utf-8')

            self.send_header('Subscription-Userinfo', 'upload=0; download=0; total=0; expire=0')

            self.send_header('Profile-Update-Interval', '1')

            self.end_headers()

            

            if os.path.exists(SUB_FILE):

                with open(SUB_FILE, 'r') as f:

                    self.wfile.write(f.read().encode())

            else:

                self.wfile.write(b"")

        elif self.path == '/':

            self.send_response(200)

            self.send_header('Content-type', 'text/html')

            self.end_headers()

            self.wfile.write(b"""

<!DOCTYPE html>

<html>

<head><title>VPS Toolbox Airport</title></head>

<body>

<h1>VPS Toolbox Airport</h1>

<p>订阅路径: /sub</p>

<p>示例: http://this-server:8080/sub</p>

</body>

</html>

""")

        else:

            self.send_response(404)

            self.end_headers()

    

    def log_message(self, format, *args):

        pass  # 静默日志

with socketserver.TCPServer(("0.0.0.0", PORT), SubHandler) as httpd:

    httpd.serve_forever()

PYSCRIPT

    

    chmod +x /usr/local/bin/vps-toolbox-sub-server.py

    

    # 使用 nohup 启动

    nohup python3 /usr/local/bin/vps-toolbox-sub-server.py >/dev/null 2>&1 &

    sleep 1

    

    if ss -tlnp | grep -q ":8080"; then

        echo -e "${GREEN}HTTP 订阅服务已启动!${NC}"

        echo -e "  订阅地址: ${GREEN}http://${server_ip}:8080/sub${NC}"

        echo -e "  网页地址: ${GREEN}http://${server_ip}:8080/${NC}"

        echo ""

        echo -e "${YELLOW}提示: 重启后需要手动重新启动${NC}"

        echo -e "${YELLOW}或使用 systemd 服务保持运行${NC}"

    else

        echo -e "${RED}启动失败${NC}"

    fi

}

# 配置 Nginx/Caddy 订阅路径

setup_nginx_sub_path() {

    local server_ip=$(get_server_ip)

    

    echo ""

    echo -e "${YELLOW}配置 Web 服务器订阅路径...${NC}"

    

    if command -v nginx &>/dev/null; then

        # Nginx 配置

        local nginx_conf="/etc/nginx/conf.d/vps-toolbox-sub.conf"

        cat > "$nginx_conf" <<EOF

server {

    listen 80;

    server_name ${server_ip};

    

    location /sub {

        alias /etc/vps-toolbox/airport/subscription.b64;

        default_type text/plain;

        add_header Subscription-Userinfo "upload=0; download=0; total=0; expire=0";

        add_header Profile-Update-Interval "1";

    }

    

    location / {

        return 200 'VPS Toolbox Airport\n订阅路径: /sub\n';

        default_type text/plain;

    }

}

EOF

        nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null

        echo -e "${GREEN}Nginx 配置已添加${NC}"

        echo -e "  订阅地址: ${GREEN}http://${server_ip}/sub${NC}"

        

    elif command -v caddy &>/dev/null; then

        # Caddy 配置

        local caddy_conf="/etc/caddy/Caddyfile.vps-toolbox"

        cat > "$caddy_conf" <<EOF

${server_ip} {

    route /sub {

        header Content-Type text/plain

        header Subscription-Userinfo "upload=0; download=0; total=0; expire=0"

        header Profile-Update-Interval "1"

        file_server {

            root /etc/vps-toolbox/airport

        }

        rewrite * /subscription.b64

    }

    

    respond / "VPS Toolbox Airport\n订阅路径: /sub\n"

}

EOF

        echo -e "${GREEN}Caddy 配置已生成: $caddy_conf${NC}"

        echo -e "${YELLOW}请手动将配置导入主 Caddyfile${NC}"

        

    else

        echo -e "${YELLOW}未检测到 Nginx 或 Caddy${NC}"

        echo -e "${YELLOW}将使用内置 HTTP 服务 (端口 8080)${NC}"

        start_sub_http_server

    fi

}

# 测试订阅链接

test_subscription() {

    local server_ip=$(get_server_ip)

    

    echo ""

    echo -e "${YELLOW}测试订阅链接...${NC}"

    echo ""

    

    # 测试本地

    echo -e "${GREEN}1. 本地测试:${NC}"

    local local_sub=$(curl -s "http://127.0.0.1:8080/sub" 2>/dev/null | head -c 100)

    if [[ -n "$local_sub" ]]; then

        echo -e "  ${GREEN}✓ 127.0.0.1:8080/sub 正常${NC}"

        echo "  内容前100字符: ${local_sub}"

    else

        echo -e "  ${RED}✗ 127.0.0.1:8080/sub 无法访问${NC}"

    fi

    

    # 测试公网

    echo ""

    echo -e "${GREEN}2. 公网测试:${NC}"

    local public_sub=$(curl -s "http://${server_ip}:8080/sub" 2>/dev/null | head -c 100)

    if [[ -n "$public_sub" ]]; then

        echo -e "  ${GREEN}✓ ${server_ip}:8080/sub 正常${NC}"

    else

        echo -e "  ${RED}✗ ${server_ip}:8080/sub 无法访问${NC}"

        echo -e "  ${YELLOW}可能原因: 防火墙未开放 8080 端口${NC}"

    fi

    

    # 解码测试

    echo ""

    echo -e "${GREEN}3. Base64 解码测试:${NC}"

    local decoded=$(curl -s "http://127.0.0.1:8080/sub" 2>/dev/null | base64 -d 2>/dev/null | head -5)

    if [[ -n "$decoded" ]]; then

        echo -e "  ${GREEN}✓ Base64 解码正常${NC}"

        echo "  解码内容:"

        echo "$decoded" | sed 's/^/    /'

    else

        echo -e "  ${RED}✗ Base64 解码失败${NC}"

    fi

}

# 使用统计功能
# 记录脚本总使用次数和当日使用次数

STATS_DIR="/etc/vps-toolbox/stats"
STATS_FILE="$STATS_DIR/usage.stats"

# 初始化统计目录
init_stats() {
    mkdir -p "$STATS_DIR"
    if [[ ! -f "$STATS_FILE" ]]; then
        echo "total:0" > "$STATS_FILE"
        echo "today:0" >> "$STATS_FILE"
        echo "last_date:$(date +%Y%m%d)" >> "$STATS_FILE"
        echo "daily_record:" >> "$STATS_FILE"
    fi
}

# 记录一次使用
record_usage() {
    init_stats
    
    local today=$(date +%Y%m%d)
    local total=$(grep "^total:" "$STATS_FILE" | cut -d: -f2)
    local today_count=$(grep "^today:" "$STATS_FILE" | cut -d: -f2)
    local last_date=$(grep "^last_date:" "$STATS_FILE" | cut -d: -f2)
    local daily_record=$(grep "^daily_record:" "$STATS_FILE" | cut -d: -f2-)
    
    # 检查是否跨天
    if [[ "$today" != "$last_date" ]]; then
        # 保存昨天的记录
        if [[ -n "$daily_record" ]]; then
            daily_record="${daily_record};${last_date}:${today_count}"
        else
            daily_record="${last_date}:${today_count}"
        fi
        # 重置今日计数
        today_count=0
        last_date="$today"
    fi
    
    # 增加计数
    total=$((total + 1))
    today_count=$((today_count + 1))
    
    # 写回文件
    cat > "$STATS_FILE" <<EOF
total:${total}
today:${today_count}
last_date:${today}
daily_record:${daily_record}
EOF
}

# 获取统计数据
get_stats() {
    init_stats
    
    local total=$(grep "^total:" "$STATS_FILE" | cut -d: -f2)
    local today_count=$(grep "^today:" "$STATS_FILE" | cut -d: -f2)
    local last_date=$(grep "^last_date:" "$STATS_FILE" | cut -d: -f2)
    local daily_record=$(grep "^daily_record:" "$STATS_FILE" | cut -d: -f2-)
    
    # 检查是否跨天（可能脚本一直没运行，但日期变了）
    local today=$(date +%Y%m%d)
    if [[ "$today" != "$last_date" ]]; then
        today_count=0
    fi
    
    echo "${total}|${today_count}|${daily_record}"
}

# 显示统计信息（在 banner 中调用）
show_usage_stats() {
    local stats=$(get_stats)
    local total=$(echo "$stats" | cut -d'|' -f1)
    local today=$(echo "$stats" | cut -d'|' -f2)
    
    echo -e "  ${YELLOW}使用统计${NC}: 总次数 ${GREEN}${total}${NC} | 今日 ${GREEN}${today}${NC}"
}

# 查看详细统计菜单
view_stats_menu() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    使用统计详情${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local stats=$(get_stats)
    local total=$(echo "$stats" | cut -d'|' -f1)
    local today=$(echo "$stats" | cut -d'|' -f2)
    local daily_record=$(echo "$stats" | cut -d'|' -f3-)
    
    echo -e "${GREEN}总使用次数:${NC} ${total}"
    echo -e "${GREEN}今日使用:${NC} ${today}"
    echo ""
    
    if [[ -n "$daily_record" ]]; then
        echo -e "${YELLOW}历史记录:${NC}"
        # 解析 daily_record (格式: 20250120:5;20250121:3)
        IFS=';' read -ra records <<< "$daily_record"
        for record in "${records[@]}"; do
            [[ -z "$record" ]] && continue
            local r_date=$(echo "$record" | cut -d: -f1)
            local r_count=$(echo "$record" | cut -d: -f2)
            local formatted_date=$(date -d "${r_date:0:4}-${r_date:4:2}-${r_date:6:2}" "+%Y-%m-%d" 2>/dev/null || echo "$r_date")
            echo "  ${formatted_date}: ${r_count} 次"
        done | tail -10
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    read -rp "按回车键继续..."
}

# 多 VPS 负载均衡/故障转移功能
# 管理多台 VPS，自动检测健康状态，订阅中只暴露一个入口

MULTI_VPS_DIR="/etc/vps-toolbox/multivps"
MULTI_VPS_CONFIG="$MULTI_VPS_DIR/nodes.conf"
HEALTH_LOG="$MULTI_VPS_DIR/health.log"

# 初始化多 VPS 目录
init_multivps() {
    mkdir -p "$MULTI_VPS_DIR"
    if [[ ! -f "$MULTI_VPS_CONFIG" ]]; then
        cat > "$MULTI_VPS_CONFIG" <<'EOF'
# VPS Toolbox 多节点配置文件
# 格式: 名称|IP:端口|协议类型|权重|状态
# 协议类型: vless/vmess/hysteria2/shadowsocks
# 权重: 1-10，越大分配越多流量
# 状态: active/backup/down
EOF
    fi
}

# 添加节点
add_vps_node() {
    init_multivps
    
    echo ""
    echo -e "${YELLOW}添加节点:${NC}"
    read -rp "节点名称 (如: 香港-1): " node_name
    read -rp "节点 IP: " node_ip
    read -rp "节点端口: " node_port
    echo "协议类型:"
    echo "  1. Vless + Reality"
    echo "  2. VMess + WS"
    echo "  3. Hysteria2"
    echo "  4. Shadowsocks"
    read -rp "请选择 [1-4]: " proto_choice
    
    local proto=""
    case $proto_choice in
        1) proto="vless" ;;
        2) proto="vmess" ;;
        3) proto="hysteria2" ;;
        4) proto="shadowsocks" ;;
        *) proto="vless" ;;
    esac
    
    read -rp "权重 (1-10, 默认5): " node_weight
    [[ -z "$node_weight" ]] && node_weight=5
    
    read -rp "角色 (1.主节点 2.备用节点): " role_choice
    local status="active"
    [[ "$role_choice" == "2" ]] && status="backup"
    
    # 测试节点连通性
    echo -e "${YELLOW}测试节点连通性...${NC}"
    if timeout 3 bash -c "</dev/tcp/${node_ip}/${node_port}" 2>/dev/null; then
        echo -e "${GREEN}节点连通正常${NC}"
    else
        echo -e "${YELLOW}节点端口不通，可能防火墙未开放${NC}"
        read -rp "仍要添加? [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi
    
    # 保存配置
    echo "${node_name}|${node_ip}:${node_port}|${proto}|${node_weight}|${status}" >> "$MULTI_VPS_CONFIG"
    echo -e "${GREEN}节点已添加!${NC}"
}

# 删除节点
remove_vps_node() {
    init_multivps
    
    echo ""
    echo -e "${YELLOW}当前节点列表:${NC}"
    list_vps_nodes
    
    echo ""
    read -rp "输入要删除的节点名称: " node_name
    
    if grep -q "^${node_name}|" "$MULTI_VPS_CONFIG"; then
        grep -v "^${node_name}|" "$MULTI_VPS_CONFIG" > "$MULTI_VPS_CONFIG.tmp"
        mv "$MULTI_VPS_CONFIG.tmp" "$MULTI_VPS_CONFIG"
        echo -e "${GREEN}节点已删除${NC}"
    else
        echo -e "${RED}节点不存在${NC}"
    fi
}

# 列出所有节点
list_vps_nodes() {
    init_multivps
    
    echo ""
    printf "  %-15s %-20s %-12s %-6s %-10s %-10s\n" "名称" "地址" "协议" "权重" "状态" "延迟"
    printf "  %-15s %-20s %-12s %-6s %-10s %-10s\n" "----" "----" "----" "----" "----" "----"
    
    while IFS='|' read -r name addr proto weight status; do
        [[ "$name" == "#"* || -z "$name" ]] && continue
        
        # 测试延迟
        local ip=$(echo "$addr" | cut -d: -f1)
        local port=$(echo "$addr" | cut -d: -f2)
        local latency=$(timeout 2 ping -c 1 -W 1 "$ip" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "timeout")
        
        # 状态颜色
        local status_color="${GREEN}"
        [[ "$status" == "backup" ]] && status_color="${YELLOW}"
        [[ "$status" == "down" ]] && status_color="${RED}"
        
        printf "  %-15s %-20s %-12s %-6s %b%-10s%b %-10s\n" "$name" "$addr" "$proto" "$weight" "$status_color" "$status" "$NC" "${latency}ms"
    done < "$MULTI_VPS_CONFIG"
}

# 健康检查所有节点
check_vps_health() {
    init_multivps
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    节点健康检查${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local changed=false
    local new_config=""
    
    while IFS='|' read -r name addr proto weight status; do
        [[ "$name" == "#"* || -z "$name" ]] && continue
        
        local ip=$(echo "$addr" | cut -d: -f1)
        local port=$(echo "$addr" | cut -d: -f2)
        
        echo -n "  检查 $name ($addr) ... "
        
        if timeout 3 bash -c "</dev/tcp/${ip}/${port}" 2>/dev/null; then
            local latency=$(timeout 2 ping -c 1 -W 1 "$ip" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "?")
            echo -e "${GREEN}正常${NC} (${latency}ms)"
            
            # 如果之前是 down，恢复为 active
            if [[ "$status" == "down" ]]; then
                status="active"
                changed=true
                echo -e "    ${GREEN}→ 节点已恢复${NC}"
            fi
        else
            echo -e "${RED}异常${NC} (端口不通)"
            
            # 如果之前是 active/backup，标记为 down
            if [[ "$status" != "down" ]]; then
                status="down"
                changed=true
                echo -e "    ${RED}→ 节点已标记为故障${NC}"
                
                # 发送 Telegram 告警
                local bot_config="/etc/vps-toolbox/tgbot.conf"
                if [[ -f "$bot_config" ]]; then
                    source "$bot_config"
                    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
                        local msg=$(cat <<EOF
🚨 *节点故障告警*

节点: ${name}
地址: ${addr}
协议: ${proto}
时间: $(date '+%Y-%m-%d %H:%M:%S')

请检查节点状态!
EOF
)
                        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                            -d "chat_id=${TG_CHAT_ID}" \
                            -d "text=${msg}" \
                            -d "parse_mode=Markdown" >/dev/null
                    fi
                fi
            fi
        fi
        
        new_config="${new_config}${name}|${addr}|${proto}|${weight}|${status}\n"
    done < "$MULTI_VPS_CONFIG"
    
    # 如果有变化，更新配置
    if [[ "$changed" == true ]]; then
        echo -e "${new_config}" > "$MULTI_VPS_CONFIG"
        echo ""
        echo -e "${YELLOW}节点状态已更新${NC}"
        
        # 重新生成订阅
        generate_multivps_sub
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
}

# 生成多节点聚合订阅
generate_multivps_sub() {
    init_multivps
    
    local sub_content=""
    local active_count=0
    
    while IFS='|' read -r name addr proto weight status; do
        [[ "$name" == "#"* || -z "$name" ]] && continue
        [[ "$status" == "down" ]] && continue
        
        local ip=$(echo "$addr" | cut -d: -f1)
        local port=$(echo "$addr" | cut -d: -f2)
        
        # 根据协议生成链接
        case "$proto" in
            vless)
                # 需要用户输入 UUID 等信息，简化处理
                sub_content="${sub_content}# ${name} (${status})\n"
                ;;
            hysteria2)
                sub_content="${sub_content}# ${name} (${status})\n"
                ;;
            shadowsocks)
                sub_content="${sub_content}# ${name} (${status})\n"
                ;;
            *)
                sub_content="${sub_content}# ${name} (${status})\n"
                ;;
        esac
        ((active_count++))
    done < "$MULTI_VPS_CONFIG"
    
    echo ""
    echo -e "${GREEN}活跃节点: ${active_count}${NC}"
    
    # 保存到机场订阅目录
    mkdir -p /etc/vps-toolbox/airport
    echo -e "$sub_content" > /etc/vps-toolbox/airport/multivps.txt
}

# 设置自动健康检查
setup_health_check() {
    echo ""
    echo -e "${YELLOW}设置自动健康检查...${NC}"
    echo ""
    echo "  1. 每 5 分钟检查"
    echo "  2. 每 15 分钟检查"
    echo "  3. 每 30 分钟检查"
    echo "  4. 关闭自动检查"
    echo "  5. 返回"
    echo ""
    read -rp "请选择 [1-5]: " hc_choice
    
    local cron_expr=""
    case $hc_choice in
        1) cron_expr="*/5 * * * *" ;;
        2) cron_expr="*/15 * * * *" ;;
        3) cron_expr="*/30 * * * *" ;;
        4)
            crontab -l 2>/dev/null | grep -v "multivps-health" | crontab -
            echo -e "${GREEN}自动健康检查已关闭${NC}"
            return
            ;;
        5) return ;;
        *) warn "无效选择"; return ;;
    esac
    
    # 创建健康检查脚本
    cat > /usr/local/bin/multivps-health.sh <<'HEALTHSCRIPT'
#!/bin/bash
# 多 VPS 健康检查脚本

MULTI_VPS_CONFIG="/etc/vps-toolbox/multivps/nodes.conf"
[[ ! -f "$MULTI_VPS_CONFIG" ]] && exit 0

changed=false
new_config=""

while IFS='|' read -r name addr proto weight status; do
    [[ "$name" == "#"* || -z "$name" ]] && continue
    
    ip=$(echo "$addr" | cut -d: -f1)
    port=$(echo "$addr" | cut -d: -f2)
    
    if timeout 3 bash -c "</dev/tcp/${ip}/${port}" 2>/dev/null; then
        if [[ "$status" == "down" ]]; then
            status="active"
            changed=true
        fi
    else
        if [[ "$status" != "down" ]]; then
            status="down"
            changed=true
            
            # Telegram 告警
            bot_config="/etc/vps-toolbox/tgbot.conf"
            if [[ -f "$bot_config" ]]; then
                source "$bot_config"
                if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
                    msg="🚨 *节点故障告警*\n\n节点: ${name}\n地址: ${addr}\n时间: $(date '+%Y-%m-%d %H:%M:%S')"
                    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                        -d "chat_id=${TG_CHAT_ID}" \
                        -d "text=${msg}" \
                        -d "parse_mode=Markdown" >/dev/null
                fi
            fi
        fi
    fi
    
    new_config="${new_config}${name}|${addr}|${proto}|${weight}|${status}\n"
done < "$MULTI_VPS_CONFIG"

if [[ "$changed" == true ]]; then
    echo -e "$new_config" > "$MULTI_VPS_CONFIG"
fi
HEALTHSCRIPT
    
    chmod +x /usr/local/bin/multivps-health.sh
    
    # 添加 cron
    (crontab -l 2>/dev/null | grep -v "multivps-health"; echo "$cron_expr /usr/local/bin/multivps-health.sh >/dev/null 2>&1") | crontab -
    
    echo -e "${GREEN}自动健康检查已设置!${NC}"
    echo -e "${YELLOW}检查频率: $cron_expr${NC}"
}

# 多 VPS 管理主菜单
multivps_manager() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}                    多节点负载均衡${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        echo -e "${YELLOW}功能说明:${NC}"
        echo "  管理多台 VPS 节点，自动检测健康状态"
        echo "  订阅中聚合所有可用节点，故障自动切换"
        echo ""
        echo -e "${YELLOW}操作选项:${NC}"
        echo "  1. 添加节点"
        echo "  2. 删除节点"
        echo "  3. 查看所有节点"
        echo "  4. 健康检查"
        echo "  5. 设置自动健康检查"
        echo "  6. 生成聚合订阅"
        echo "  7. 返回主菜单"
        echo ""
        read -rp "请选择 [1-7]: " mv_choice
        
        case $mv_choice in
            1) add_vps_node ;;
            2) remove_vps_node ;;
            3) list_vps_nodes ;;
            4) check_vps_health ;;
            5) setup_health_check ;;
            6) generate_multivps_sub ;;
            7) return ;;
            *) warn "无效选择" ;;
        esac
        
        echo ""
        read -rp "按回车键继续..."
    done
}


# 安全配置审计功能
# 检查代理配置的安全性，给出修复建议

SECURITY_CHECK_ITEMS=(
    "check_ssh_port:SSH端口是否为默认22"
    "check_root_password:Root密码是否强密码"
    "check_firewall:防火墙是否启用"
    "check_fail2ban:Fail2ban是否安装"
    "check_xray_api:Xray API是否暴露"
    "check_cert_expiry:SSL证书是否即将过期"
    "check_port_exposure:端口暴露范围是否过大"
    "check_udp_amp:是否存在UDP放大攻击风险"
    "check_dns_leak:DNS是否泄露"
    "check_timezone:时区是否设置正确"
)

# 检查 SSH 端口
check_ssh_port() {
    local ssh_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [[ -z "$ssh_port" ]] && ssh_port=22
    
    if [[ "$ssh_port" == "22" ]]; then
        echo "WARN|SSH使用默认端口22|建议修改为非标准端口，减少暴力破解"
        return 1
    else
        echo "OK|SSH端口为 $ssh_port|已使用非标准端口"
        return 0
    fi
}

# 检查 Root 密码强度
check_root_password() {
    # 检查是否使用密钥登录
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        echo "OK|已禁用密码登录，使用密钥|最佳实践"
        return 0
    fi
    
    # 检查密码哈希（仅检查是否存在）
    local pass_hash=$(grep "^root:" /etc/shadow 2>/dev/null | cut -d: -f2)
    if [[ -z "$pass_hash" || "$pass_hash" == "*" || "$pass_hash" == "!" ]]; then
        echo "WARN|Root密码未设置或已锁定|检查登录方式"
        return 1
    fi
    
    echo "INFO|Root密码已设置|建议使用密钥登录并禁用密码"
    return 0
}

# 检查防火墙
check_firewall() {
    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            echo "OK|UFW防火墙已启用|良好"
            return 0
        else
            echo "WARN|UFW防火墙未启用|建议启用防火墙"
            return 1
        fi
    elif command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            echo "OK|Firewalld已运行|良好"
            return 0
        else
            echo "WARN|Firewalld未运行|建议启用防火墙"
            return 1
        fi
    elif iptables -L -n 2>/dev/null | grep -q "DROP"; then
        echo "OK|iptables有DROP规则|基本防护存在"
        return 0
    else
        echo "WARN|未检测到活跃防火墙|强烈建议配置防火墙"
        return 1
    fi
}

# 检查 Fail2ban
check_fail2ban() {
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            local banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")
            echo "OK|Fail2ban运行中|当前封禁IP: $banned"
            return 0
        else
            echo "WARN|Fail2ban已安装但未运行|建议启动"
            return 1
        fi
    else
        echo "WARN|Fail2ban未安装|建议安装以防止暴力破解"
        return 1
    fi
}

# 检查 Xray API 暴露
check_xray_api() {
    if [[ -f /usr/local/etc/xray/config.json ]]; then
        local api_tag=$(jq -r '.api.tag // empty' /usr/local/etc/xray/config.json 2>/dev/null)
        if [[ -n "$api_tag" ]]; then
            # 检查 API 是否绑定到 127.0.0.1
            local api_listen=$(jq -r '.inbounds[] | select(.tag=="api") | .listen // empty' /usr/local/etc/xray/config.json 2>/dev/null)
            if [[ "$api_listen" == "127.0.0.1" ]]; then
                echo "OK|Xray API仅本地监听|安全"
                return 0
            elif [[ -z "$api_listen" || "$api_listen" == "0.0.0.0" ]]; then
                echo "CRITICAL|Xray API暴露到公网|立即修改配置，绑定到127.0.0.1"
                return 2
            fi
        else
            echo "INFO|Xray API未启用|无需检查"
            return 0
        fi
    else
        echo "INFO|未安装Xray|跳过"
        return 0
    fi
}

# 检查证书过期
check_cert_expiry() {
    local certs_found=false
    local warn_count=0
    
    # 检查 acme.sh 证书
    for cert in /root/.acme.sh/*/*.cer /home/*/.acme.sh/*/*.cer; do
        [[ ! -f "$cert" ]] && continue
        certs_found=true
        
        local end_date=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expire_ts=$(date -d "$end_date" +%s 2>/dev/null || echo "0")
        local now_ts=$(date +%s)
        local days_left=$(( (expire_ts - now_ts) / 86400 ))
        
        local domain=$(basename "$cert" .cer)
        if [[ $days_left -lt 7 ]]; then
            echo "CRITICAL|证书 $domain 将在 ${days_left} 天后过期|立即续签"
            ((warn_count++))
        elif [[ $days_left -lt 30 ]]; then
            echo "WARN|证书 $domain 将在 ${days_left} 天后过期|建议续签"
            ((warn_count++))
        fi
    done
    
    # 检查 letsencrypt
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        [[ ! -f "$cert" ]] && continue
        certs_found=true
        
        local end_date=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expire_ts=$(date -d "$end_date" +%s 2>/dev/null || echo "0")
        local now_ts=$(date +%s)
        local days_left=$(( (expire_ts - now_ts) / 86400 ))
        
        local domain=$(basename $(dirname "$cert"))
        if [[ $days_left -lt 7 ]]; then
            echo "CRITICAL|证书 $domain 将在 ${days_left} 天后过期|立即续签"
            ((warn_count++))
        elif [[ $days_left -lt 30 ]]; then
            echo "WARN|证书 $domain 将在 ${days_left} 天后过期|建议续签"
            ((warn_count++))
        fi
    done
    
    if [[ "$certs_found" == false ]]; then
        echo "INFO|未找到证书|无需检查"
        return 0
    elif [[ $warn_count -eq 0 ]]; then
        echo "OK|所有证书有效期内|良好"
        return 0
    else
        return 1
    fi
}

# 检查端口暴露
check_port_exposure() {
    local exposed_ports=$(ss -tln | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -u | wc -l)
    
    if [[ $exposed_ports -gt 10 ]]; then
        echo "WARN|暴露端口过多 (${exposed_ports}个)|检查是否有不必要的端口开放"
        return 1
    else
        echo "OK|暴露端口 ${exposed_ports} 个|正常范围"
        return 0
    fi
}

# 检查 UDP 放大攻击风险
check_udp_amp() {
    # 检查是否开放 DNS/NTPS 等 UDP 服务
    local risky_udp=$(ss -ulnp | grep -E ':53|:123|:161|:1900' | wc -l)
    
    if [[ $risky_udp -gt 0 ]]; then
        echo "WARN|发现可能用于UDP放大的服务 (${risky_udp}个)|确认是否需要开放"
        return 1
    else
        echo "OK|未发现高风险UDP服务|良好"
        return 0
    fi
}

# 检查 DNS 泄露
check_dns_leak() {
    local dns_servers=$(cat /etc/resolv.conf 2>/dev/null | grep "^nameserver" | awk '{print $2}')
    
    if echo "$dns_servers" | grep -qE "(8\.8\.|1\.1\.|9\.9\.)"; then
        echo "INFO|使用公共DNS|正常"
        return 0
    elif echo "$dns_servers" | grep -q "127\.0\.0"; then
        echo "OK|使用本地DNS|可能通过代理解析"
        return 0
    else
        echo "INFO|DNS: $(echo $dns_servers | tr '\n' ' ')|检查是否符合预期"
        return 0
    fi
}

# 检查时区
check_timezone() {
    local tz=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || date +%Z)
    if [[ "$tz" == "UTC" ]]; then
        echo "WARN|时区为UTC|建议设置为本地时区便于日志查看"
        return 1
    else
        echo "OK|时区: $tz|正常"
        return 0
    fi
}

# 运行所有安全检查
run_security_audit() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    安全配置审计${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local ok_count=0
    local warn_count=0
    local critical_count=0
    local info_count=0
    
    # 运行所有检查
    local checks=(
        check_ssh_port
        check_root_password
        check_firewall
        check_fail2ban
        check_xray_api
        check_cert_expiry
        check_port_exposure
        check_udp_amp
        check_dns_leak
        check_timezone
    )
    
    for check_func in "${checks[@]}"; do
        echo -n "  检查 ${check_func/check_/} ... "
        local result=$($check_func)
        local level=$(echo "$result" | cut -d'|' -f1)
        local detail=$(echo "$result" | cut -d'|' -f2)
        local advice=$(echo "$result" | cut -d'|' -f3)
        
        case "$level" in
            OK)
                echo -e "${GREEN}[✓]${NC} $detail"
                ((ok_count++))
                ;;
            WARN)
                echo -e "${YELLOW}[!]${NC} $detail"
                echo -e "      ${YELLOW}→ $advice${NC}"
                ((warn_count++))
                ;;
            CRITICAL)
                echo -e "${RED}[✗]${NC} $detail"
                echo -e "      ${RED}→ $advice${NC}"
                ((critical_count++))
                ;;
            INFO)
                echo -e "${CYAN}[i]${NC} $detail"
                ((info_count++))
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "审计结果: ${GREEN}${ok_count} 通过${NC} | ${YELLOW}${warn_count} 警告${NC} | ${RED}${critical_count} 严重${NC} | ${CYAN}${info_count} 信息${NC}"
    echo -e "${CYAN}============================================================${NC}"
    
    # 如果有严重问题，给出修复建议
    if [[ $critical_count -gt 0 ]]; then
        echo ""
        echo -e "${RED}发现严重安全问题，建议立即修复!${NC}"
        echo ""
        echo -e "${YELLOW}快速修复:${NC}"
        echo "  1. 修改 SSH 端口: sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config"
        echo "  2. 禁用密码登录: sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
        echo "  3. 安装 Fail2ban: apt install fail2ban"
        echo "  4. 启用 UFW: ufw enable"
    fi
    
    echo ""
    read -rp "按回车键继续..."
}

# 一键修复安全问题
auto_fix_security() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    一键修复安全问题${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${RED}警告: 此操作将修改系统配置!${NC}"
    echo ""
    echo "将执行以下操作:"
    echo "  1. 修改 SSH 端口 (2222)"
    echo "  2. 禁用 Root 密码登录 (仅密钥)"
    echo "  3. 安装并启用 Fail2ban"
    echo "  4. 启用 UFW 防火墙"
    echo "  5. 限制 SSH 登录尝试"
    echo ""
    read -rp "确认执行? 输入 [我确认修复] : " confirm
    
    if [[ "$confirm" != "我确认修复" ]]; then
        echo -e "${YELLOW}已取消${NC}"
        return
    fi
    
    # 1. 修改 SSH 端口
    echo -e "${YELLOW}[1/5] 修改 SSH 端口...${NC}"
    local current_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [[ -z "$current_port" ]] && current_port=22
    
    if [[ "$current_port" == "22" ]]; then
        sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config 2>/dev/null || \
        sed -i 's/^Port 22/Port 2222/' /etc/ssh/sshd_config 2>/dev/null || \
        echo "Port 2222" >> /etc/ssh/sshd_config
        echo -e "  ${GREEN}SSH 端口已改为 2222${NC}"
    else
        echo -e "  ${YELLOW}SSH 端口已是 $current_port，跳过${NC}"
    fi
    
    # 2. 禁用密码登录
    echo -e "${YELLOW}[2/5] 禁用 Root 密码登录...${NC}"
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config 2>/dev/null
    echo -e "  ${GREEN}已禁用密码登录，请确保已配置 SSH 密钥${NC}"
    
    # 3. 安装 Fail2ban
    echo -e "${YELLOW}[3/5] 安装 Fail2ban...${NC}"
    if ! command -v fail2ban-client &>/dev/null; then
        apt update -qq && apt install -y -qq fail2ban 2>/dev/null || \
        yum install -y fail2ban 2>/dev/null || \
        dnf install -y fail2ban 2>/dev/null || true
    fi
    
    if command -v fail2ban-client &>/dev/null; then
        cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh,2222
filter = sshd
logpath = /var/log/auth.log
backend = systemd
EOF
        systemctl enable fail2ban 2>/dev/null
        systemctl restart fail2ban 2>/dev/null
        echo -e "  ${GREEN}Fail2ban 已启用${NC}"
    else
        echo -e "  ${RED}Fail2ban 安装失败${NC}"
    fi
    
    # 4. 启用 UFW
    echo -e "${YELLOW}[4/5] 配置防火墙...${NC}"
    if command -v ufw &>/dev/null; then
        ufw default deny incoming 2>/dev/null
        ufw default allow outgoing 2>/dev/null
        ufw allow 2222/tcp 2>/dev/null
        ufw allow 443/tcp 2>/dev/null
        ufw allow 80/tcp 2>/dev/null
        echo "y" | ufw enable 2>/dev/null
        echo -e "  ${GREEN}UFW 已启用${NC}"
    else
        echo -e "  ${YELLOW}UFW 未安装，跳过${NC}"
    fi
    
    # 5. 重启 SSH
    echo -e "${YELLOW}[5/5] 重启 SSH 服务...${NC}"
    systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null
    echo -e "  ${GREEN}SSH 已重启${NC}"
    
    echo ""
    echo -e "${GREEN}修复完成!${NC}"
    echo -e "${YELLOW}注意: SSH 端口已改为 2222，请使用新端口连接${NC}"
    echo -e "${YELLOW}ssh -p 2222 root@你的IP${NC}"
    
    echo ""
    read -rp "按回车键继续..."
}

# 安全审计主菜单
security_audit_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}                    安全配置审计${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        echo -e "${YELLOW}功能说明:${NC}"
        echo "  全面检查 VPS 安全配置，发现潜在风险"
        echo "  提供一键修复功能，快速加固服务器"
        echo ""
        echo -e "${YELLOW}检查项目:${NC}"
        echo "  • SSH 端口和密码策略"
        echo "  • 防火墙状态"
        echo "  • Fail2ban 防护"
        echo "  • Xray API 暴露风险"
        echo "  • SSL 证书有效期"
        echo "  • 端口暴露范围"
        echo "  • UDP 放大攻击风险"
        echo "  • DNS 泄露"
        echo "  • 时区设置"
        echo ""
        echo -e "${YELLOW}操作选项:${NC}"
        echo "  1. 运行安全审计"
        echo "  2. 一键修复安全问题"
        echo "  3. 查看上次审计结果"
        echo "  4. 返回主菜单"
        echo ""
        read -rp "请选择 [1-4]: " audit_choice
        
        case $audit_choice in
            1) run_security_audit ;;
            2) auto_fix_security ;;
            3)
                if [[ -f "$MULTI_VPS_DIR/audit.log" ]]; then
                    cat "$MULTI_VPS_DIR/audit.log"
                else
                    echo -e "${YELLOW}暂无审计记录${NC}"
                fi
                read -rp "按回车键继续..."
                ;;
            4) return ;;
            *) warn "无效选择" ;;
        esac
    done
}

# 一键部署伪装网站功能
# 部署静态网站作为代理的伪装层，让服务器看起来像正常网站

WEBSITE_DIR="/var/www/vps-toolbox-site"
WEBSITE_NGINX="/etc/nginx/conf.d/vps-toolbox-site.conf"
WEBSITE_CADDY="/etc/caddy/vps-toolbox-site.conf"

# 初始化网站目录
init_website() {
    mkdir -p "$WEBSITE_DIR"
    mkdir -p "$WEBSITE_DIR/images"
    mkdir -p "$WEBSITE_DIR/css"
    mkdir -p "$WEBSITE_DIR/js"
}

# 生成伪装网站内容
generate_website_content() {
    local site_type="$1"
    local domain="$2"
    
    init_website
    
    case "$site_type" in
        blog)
            generate_blog_template "$domain"
            ;;
        gallery)
            generate_gallery_template "$domain"
            ;;
        portfolio)
            generate_portfolio_template "$domain"
            ;;
        docs)
            generate_docs_template "$domain"
            ;;
        *)
            generate_blog_template "$domain"
            ;;
    esac
    
    # 生成 robots.txt
    cat > "$WEBSITE_DIR/robots.txt" <<EOF
User-agent: *
Allow: /
Sitemap: https://${domain}/sitemap.xml
EOF
    
    # 生成 sitemap.xml
    cat > "$WEBSITE_DIR/sitemap.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>https://${domain}/</loc>
        <lastmod>$(date +%Y-%m-%d)</lastmod>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
</urlset>
EOF
    
    # 生成 favicon
    generate_favicon
}

# 生成博客模板
generate_blog_template() {
    local domain="$1"
    local title="$(hostname) Blog"
    
    cat > "$WEBSITE_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta name="description" content="个人技术博客，分享生活与技术的点滴">
    <link rel="stylesheet" href="/css/style.css">
    <link rel="icon" type="image/x-icon" href="/favicon.ico">
</head>
<body>
    <header>
        <nav>
            <div class="logo">${title}</div>
            <ul>
                <li><a href="/">首页</a></li>
                <li><a href="/about.html">关于</a></li>
                <li><a href="/archive.html">归档</a></li>
            </ul>
        </nav>
    </header>
    
    <main>
        <article class="post">
            <h1>欢迎来到我的博客</h1>
            <div class="meta">发布于 $(date +%Y-%m-%d) | 分类: 生活</div>
            <p>这是一个记录技术学习和生活的个人博客。在这里，我会分享一些编程心得、服务器运维经验，以及生活中的点滴感悟。</p>
            <p>博客使用静态站点生成器构建，部署在 ${domain} 上。</p>
            <h2>最近更新</h2>
            <ul>
                <li><a href="#">$(date +%Y-%m-%d) - 服务器性能优化笔记</a></li>
                <li><a href="#">$(date -d '1 day ago' +%Y-%m-%d) - Docker 容器化实践</a></li>
                <li><a href="#">$(date -d '2 days ago' +%Y-%m-%d) - Nginx 配置技巧分享</a></li>
                <li><a href="#">$(date -d '3 days ago' +%Y-%m-%d) - Linux 系统调优心得</a></li>
            </ul>
        </article>
        
        <aside class="sidebar">
            <div class="widget">
                <h3>关于我</h3>
                <p>热爱技术的开发者，喜欢折腾服务器和网络。</p>
            </div>
            <div class="widget">
                <h3>标签云</h3>
                <div class="tags">
                    <span class="tag">Linux</span>
                    <span class="tag">Nginx</span>
                    <span class="tag">Docker</span>
                    <span class="tag">Python</span>
                    <span class="tag">网络安全</span>
                </div>
            </div>
        </aside>
    </main>
    
    <footer>
        <p>&copy; $(date +%Y) ${title}. All rights reserved.</p>
        <p>Powered by VPS Toolbox</p>
    </footer>
</body>
</html>
HTML
    
    # 生成关于页面
    cat > "$WEBSITE_DIR/about.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>关于 - ${title}</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <header>
        <nav>
            <div class="logo">${title}</div>
            <ul>
                <li><a href="/">首页</a></li>
                <li><a href="/about.html">关于</a></li>
                <li><a href="/archive.html">归档</a></li>
            </ul>
        </nav>
    </header>
    
    <main>
        <article class="post">
            <h1>关于我</h1>
            <p>你好，我是一名热爱技术的开发者。</p>
            <p>这个博客用于记录我的技术学习和生活感悟。</p>
            <h2>联系方式</h2>
            <p>Email: admin@${domain}</p>
            <p>GitHub: https://github.com/tech-blogger</p>
        </article>
    </main>
    
    <footer>
        <p>&copy; $(date +%Y) ${title}. All rights reserved.</p>
    </footer>
</body>
</html>
HTML
    
    # 生成 CSS
    generate_css
}

# 生成图库模板
generate_gallery_template() {
    local domain="$1"
    local title="$(hostname) Gallery"
    
    cat > "$WEBSITE_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta name="description" content="个人摄影作品分享">
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <header>
        <nav>
            <div class="logo">${title}</div>
            <ul>
                <li><a href="/">首页</a></li>
                <li><a href="/about.html">关于</a></li>
            </ul>
        </nav>
    </header>
    
    <main>
        <h1>我的摄影集</h1>
        <p class="subtitle">记录生活中的美好瞬间</p>
        
        <div class="gallery">
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
                    <span>风景摄影</span>
                </div>
                <p>自然风光</p>
            </div>
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">
                    <span>城市街拍</span>
                </div>
                <p>城市印象</p>
            </div>
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                    <span>人像摄影</span>
                </div>
                <p>人物纪实</p>
            </div>
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%);">
                    <span>美食记录</span>
                </div>
                <p>美食探店</p>
            </div>
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #fa709a 0%, #fee140 100%);">
                    <span>旅行日记</span>
                </div>
                <p>旅途风景</p>
            </div>
            <div class="gallery-item">
                <div class="placeholder" style="background: linear-gradient(135deg, #a8edea 0%, #fed6e3 100%);">
                    <span>生活随拍</span>
                </div>
                <p>日常记录</p>
            </div>
        </div>
    </main>
    
    <footer>
        <p>&copy; $(date +%Y) ${title}. All rights reserved.</p>
    </footer>
</body>
</html>
HTML
    
    generate_css
}

# 生成作品集模板
generate_portfolio_template() {
    local domain="$1"
    local title="$(hostname) Portfolio"
    
    cat > "$WEBSITE_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta name="description" content="个人作品集，展示项目和技术能力">
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <header class="hero">
        <div class="hero-content">
            <h1>全栈开发者</h1>
            <p>热爱技术，专注于构建高性能 Web 应用</p>
            <div class="skills">
                <span class="skill">Linux</span>
                <span class="skill">Nginx</span>
                <span class="skill">Docker</span>
                <span class="skill">Python</span>
                <span class="skill">Go</span>
                <span class="skill">React</span>
            </div>
        </div>
    </header>
    
    <main>
        <section class="projects">
            <h2>项目展示</h2>
            <div class="project-grid">
                <div class="project-card">
                    <h3>高性能代理服务</h3>
                    <p>基于 Xray 的高性能代理解决方案，支持多种协议。</p>
                    <div class="tech-tags">
                        <span>Go</span>
                        <span>WebSocket</span>
                        <span>TLS</span>
                    </div>
                </div>
                <div class="project-card">
                    <h3>自动化运维平台</h3>
                    <p>服务器自动化管理和监控平台，支持批量操作。</p>
                    <div class="tech-tags">
                        <span>Python</span>
                        <span>Ansible</span>
                        <span>Prometheus</span>
                    </div>
                </div>
                <div class="project-card">
                    <h3>个人博客系统</h3>
                    <p>基于静态生成的博客系统，支持 Markdown。</p>
                    <div class="tech-tags">
                        <span>Hugo</span>
                        <span>Nginx</span>
                        <span>CDN</span>
                    </div>
                </div>
            </div>
        </section>
    </main>
    
    <footer>
        <p>&copy; $(date +%Y) ${title}. All rights reserved.</p>
    </footer>
</body>
</html>
HTML
    
    generate_css
}

# 生成文档模板
generate_docs_template() {
    local domain="$1"
    local title="$(hostname) Docs"
    
    cat > "$WEBSITE_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta name="description" content="技术文档和教程">
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <header>
        <nav>
            <div class="logo">${title}</div>
            <ul>
                <li><a href="/">首页</a></li>
                <li><a href="/guide.html">指南</a></li>
                <li><a href="/api.html">API</a></li>
            </ul>
        </nav>
    </header>
    
    <main>
        <div class="docs-layout">
            <aside class="sidebar">
                <h3>文档目录</h3>
                <ul>
                    <li><a href="#">快速开始</a></li>
                    <li><a href="#">安装指南</a></li>
                    <li><a href="#">配置说明</a></li>
                    <li><a href="#">常见问题</a></li>
                    <li><a href="#">更新日志</a></li>
                </ul>
            </aside>
            
            <article class="content">
                <h1>欢迎使用</h1>
                <p>这是一套完整的技术文档，帮助你快速上手和使用相关工具。</p>
                
                <h2>快速开始</h2>
                <pre><code># 安装
curl -fsSL https://${domain}/install.sh | bash

# 启动
systemctl start myapp

# 查看状态
systemctl status myapp</code></pre>
                
                <h2>特性</h2>
                <ul>
                    <li>高性能 - 基于最新技术栈构建</li>
                    <li>易用 - 简单的配置即可运行</li>
                    <li>安全 - 内置多种安全防护</li>
                    <li>开源 - 代码完全开源</li>
                </ul>
            </article>
        </div>
    </main>
    
    <footer>
        <p>&copy; $(date +%Y) ${title}. All rights reserved.</p>
    </footer>
</body>
</html>
HTML
    
    generate_css
}

# 生成 CSS 样式
generate_css() {
    cat > "$WEBSITE_DIR/css/style.css" <<'CSS'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    line-height: 1.6;
    color: #333;
    background: #f5f5f5;
}

header {
    background: #fff;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    position: sticky;
    top: 0;
    z-index: 100;
}

nav {
    max-width: 1200px;
    margin: 0 auto;
    padding: 1rem 2rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.logo {
    font-size: 1.5rem;
    font-weight: bold;
    color: #2563eb;
}

nav ul {
    display: flex;
    list-style: none;
    gap: 2rem;
}

nav a {
    text-decoration: none;
    color: #666;
    transition: color 0.3s;
}

nav a:hover {
    color: #2563eb;
}

main {
    max-width: 1200px;
    margin: 2rem auto;
    padding: 0 2rem;
    display: grid;
    grid-template-columns: 1fr 300px;
    gap: 2rem;
}

.post {
    background: #fff;
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.post h1 {
    color: #1a1a1a;
    margin-bottom: 0.5rem;
}

.meta {
    color: #999;
    font-size: 0.9rem;
    margin-bottom: 1rem;
}

.post p {
    margin-bottom: 1rem;
    color: #555;
}

.post h2 {
    color: #1a1a1a;
    margin: 1.5rem 0 1rem;
}

.post ul {
    margin-left: 1.5rem;
    color: #555;
}

.post li {
    margin-bottom: 0.5rem;
}

.post a {
    color: #2563eb;
    text-decoration: none;
}

.sidebar {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.widget {
    background: #fff;
    padding: 1.5rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.widget h3 {
    color: #1a1a1a;
    margin-bottom: 1rem;
    font-size: 1.1rem;
}

.tags {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
}

.tag {
    background: #e0e7ff;
    color: #4338ca;
    padding: 0.25rem 0.75rem;
    border-radius: 9999px;
    font-size: 0.85rem;
}

footer {
    text-align: center;
    padding: 2rem;
    color: #999;
    margin-top: 2rem;
}

/* Gallery styles */
.gallery {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1.5rem;
    margin-top: 2rem;
}

.gallery-item {
    background: #fff;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.placeholder {
    height: 200px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    font-size: 1.2rem;
    font-weight: bold;
}

.gallery-item p {
    padding: 1rem;
    text-align: center;
    color: #666;
}

.subtitle {
    text-align: center;
    color: #666;
    margin-bottom: 2rem;
}

/* Portfolio styles */
.hero {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: #fff;
    padding: 4rem 2rem;
    text-align: center;
}

.hero-content h1 {
    font-size: 3rem;
    margin-bottom: 1rem;
}

.hero-content p {
    font-size: 1.2rem;
    margin-bottom: 2rem;
    opacity: 0.9;
}

.skills {
    display: flex;
    justify-content: center;
    gap: 1rem;
    flex-wrap: wrap;
}

.skill {
    background: rgba(255,255,255,0.2);
    padding: 0.5rem 1rem;
    border-radius: 9999px;
    font-size: 0.9rem;
}

.projects {
    margin-top: 3rem;
}

.projects h2 {
    text-align: center;
    margin-bottom: 2rem;
}

.project-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1.5rem;
}

.project-card {
    background: #fff;
    padding: 1.5rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.project-card h3 {
    color: #1a1a1a;
    margin-bottom: 0.5rem;
}

.project-card p {
    color: #666;
    margin-bottom: 1rem;
}

.tech-tags {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
}

.tech-tags span {
    background: #e0e7ff;
    color: #4338ca;
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    font-size: 0.8rem;
}

/* Docs styles */
.docs-layout {
    display: grid;
    grid-template-columns: 250px 1fr;
    gap: 2rem;
}

.docs-layout .sidebar {
    background: #fff;
    padding: 1.5rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    height: fit-content;
}

.docs-layout .sidebar h3 {
    margin-bottom: 1rem;
    color: #1a1a1a;
}

.docs-layout .sidebar ul {
    list-style: none;
}

.docs-layout .sidebar li {
    margin-bottom: 0.5rem;
}

.docs-layout .sidebar a {
    color: #666;
    text-decoration: none;
}

.docs-layout .sidebar a:hover {
    color: #2563eb;
}

.docs-layout .content {
    background: #fff;
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.docs-layout .content h1 {
    color: #1a1a1a;
    margin-bottom: 1rem;
}

.docs-layout .content h2 {
    color: #1a1a1a;
    margin: 1.5rem 0 1rem;
}

pre {
    background: #1e1e1e;
    color: #d4d4d4;
    padding: 1rem;
    border-radius: 8px;
    overflow-x: auto;
    margin: 1rem 0;
}

code {
    font-family: "Consolas", "Monaco", "Courier New", monospace;
    font-size: 0.9rem;
}

@media (max-width: 768px) {
    main {
        grid-template-columns: 1fr;
    }
    
    nav {
        flex-direction: column;
        gap: 1rem;
    }
    
    .docs-layout {
        grid-template-columns: 1fr;
    }
}
CSS
}

# 生成 favicon
generate_favicon() {
    # 创建一个简单的 SVG favicon
    cat > "$WEBSITE_DIR/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
    <rect width="100" height="100" rx="20" fill="#2563eb"/>
    <text x="50" y="65" font-size="45" text-anchor="middle" fill="white" font-family="Arial">V</text>
</svg>
SVG
    
    # 复制为 favicon.ico (使用 svg 作为备用)
    cp "$WEBSITE_DIR/favicon.svg" "$WEBSITE_DIR/favicon.ico" 2>/dev/null || true
}

# 配置 Nginx
generate_nginx_conf() {
    local domain="$1"
    local proxy_path="$2"
    
    cat > "$WEBSITE_NGINX" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    
    # 自动跳转到 HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};
    
    # SSL 证书路径 (由 acme.sh 管理)
    ssl_certificate /root/.acme.sh/${domain}/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/${domain}/${domain}.key;
    
    # SSL 优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    
    # 静态网站根目录
    root ${WEBSITE_DIR};
    index index.html;
    
    # 伪装网站内容
    location / {
        try_files \$uri \$uri/ =404;
        
        # 添加缓存头
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1M;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # 代理路径 (用于代理协议)
    location ${proxy_path} {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 日志
    access_log /var/log/nginx/${domain}-access.log;
    error_log /var/log/nginx/${domain}-error.log;
}
EOF
}

# 配置 Caddy
generate_caddy_conf() {
    local domain="$1"
    local proxy_path="$2"
    
    cat > "$WEBSITE_CADDY" <<EOF
${domain} {
    root * ${WEBSITE_DIR}
    file_server
    
    # 自动 HTTPS
    tls admin@${domain}
    
    # 代理路径
    handle_path ${proxy_path}/* {
        reverse_proxy 127.0.0.1:10000
    }
    
    # 安全头
    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
    }
    
    # 日志
    log {
        output file /var/log/caddy/${domain}-access.log
    }
}
EOF
}

# 一键部署伪装网站主菜单
website_manager() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}                    伪装网站部署${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        
        # 显示当前状态
        if [[ -d "$WEBSITE_DIR" && -f "$WEBSITE_DIR/index.html" ]]; then
            echo -e "${GREEN}当前状态: 已部署${NC}"
            local site_size=$(du -sh "$WEBSITE_DIR" 2>/dev/null | cut -f1)
            echo -e "  网站大小: ${site_size}"
            
            if command -v nginx &>/dev/null && [[ -f "$WEBSITE_NGINX" ]]; then
                local nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "未运行")
                echo -e "  Nginx: ${nginx_status}"
            fi
            
            if command -v caddy &>/dev/null && [[ -f "$WEBSITE_CADDY" ]]; then
                local caddy_status=$(systemctl is-active caddy 2>/dev/null || echo "未运行")
                echo -e "  Caddy: ${caddy_status}"
            fi
        else
            echo -e "${YELLOW}当前状态: 未部署${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}操作选项:${NC}"
        echo "  1. 部署博客模板"
        echo "  2. 部署图库模板"
        echo "  3. 部署作品集模板"
        echo "  4. 部署文档模板"
        echo "  5. 自定义网站内容"
        echo "  6. 配置 Web 服务器 (Nginx/Caddy)"
        echo "  7. 更新网站内容"
        echo "  8. 查看网站状态"
        echo "  9. 删除网站"
        echo "  0. 返回主菜单"
        echo ""
        read -rp "请选择 [0-9]: " web_choice
        
        case $web_choice in
            1|2|3|4)
                deploy_website "$web_choice"
                ;;
            5)
                custom_website_content
                ;;
            6)
                setup_web_server
                ;;
            7)
                update_website_content
                ;;
            8)
                view_website_status
                ;;
            9)
                remove_website
                ;;
            0)
                return
                ;;
            *)
                warn "无效选择"
                ;;
        esac
        
        echo ""
        read -rp "按回车键继续..."
    done
}

# 部署网站
deploy_website() {
    local site_type="$1"
    local type_name=""
    
    case "$site_type" in
        1) type_name="博客" ;;
        2) type_name="图库" ;;
        3) type_name="作品集" ;;
        4) type_name="文档" ;;
    esac
    
    echo ""
    echo -e "${YELLOW}部署${type_name}模板...${NC}"
    
    # 获取域名
    local domain=""
    read -rp "请输入你的域名 (如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        error "域名不能为空"
        return 1
    fi
    
    # 生成网站内容
    case "$site_type" in
        1) generate_blog_template "$domain" ;;
        2) generate_gallery_template "$domain" ;;
        3) generate_portfolio_template "$domain" ;;
        4) generate_docs_template "$domain" ;;
    esac
    
    echo -e "${GREEN}网站内容已生成!${NC}"
    echo -e "  目录: ${WEBSITE_DIR}"
    echo -e "  域名: ${domain}"
    
    # 询问是否配置 Web 服务器
    echo ""
    read -rp "是否配置 Web 服务器? [Y/n]: " setup_web
    if [[ "$setup_web" != "n" && "$setup_web" != "N" ]]; then
        setup_web_server "$domain"
    fi
    
    # 询问是否申请 SSL 证书
    echo ""
    read -rp "是否申请 SSL 证书? [Y/n]: " setup_ssl
    if [[ "$setup_ssl" != "n" && "$setup_ssl" != "N" ]]; then
        setup_website_ssl "$domain"
    fi
}

# 配置 Web 服务器
setup_web_server() {
    local domain="${1:-}"
    
    if [[ -z "$domain" ]]; then
        read -rp "请输入域名: " domain
    fi
    
    echo ""
    echo -e "${YELLOW}选择 Web 服务器:${NC}"
    echo "  1. Nginx (推荐)"
    echo "  2. Caddy (自动 HTTPS)"
    echo "  3. 返回"
    echo ""
    read -rp "请选择 [1-3]: " server_choice
    
    case "$server_choice" in
        1)
            if ! command -v nginx &>/dev/null; then
                echo -e "${YELLOW}安装 Nginx...${NC}"
                apt update -qq && apt install -y -qq nginx 2>/dev/null || \
                yum install -y nginx 2>/dev/null || \
                dnf install -y nginx 2>/dev/null || true
            fi
            
            if command -v nginx &>/dev/null; then
                generate_nginx_conf "$domain" "/proxy"
                nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
                systemctl enable nginx 2>/dev/null
                echo -e "${GREEN}Nginx 配置完成!${NC}"
                echo -e "  配置: ${WEBSITE_NGINX}"
            else
                error "Nginx 安装失败"
            fi
            ;;
        2)
            if ! command -v caddy &>/dev/null; then
                echo -e "${YELLOW}安装 Caddy...${NC}"
                apt install -y -qq caddy 2>/dev/null || \
                yum install -y caddy 2>/dev/null || \
                dnf install -y caddy 2>/dev/null || \
                apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https 2>/dev/null && \
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' 2>/dev/null | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null && \
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' 2>/dev/null | tee /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null && \
                apt update -qq && apt install -y caddy 2>/dev/null || true
            fi
            
            if command -v caddy &>/dev/null; then
                generate_caddy_conf "$domain" "/proxy"
                systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null
                systemctl enable caddy 2>/dev/null
                echo -e "${GREEN}Caddy 配置完成!${NC}"
                echo -e "  配置: ${WEBSITE_CADDY}"
            else
                error "Caddy 安装失败"
            fi
            ;;
        3)
            return
            ;;
        *)
            warn "无效选择"
            ;;
    esac
}

# 申请 SSL 证书
setup_website_ssl() {
    local domain="$1"
    
    echo ""
    echo -e "${YELLOW}申请 SSL 证书...${NC}"
    
    # 检查 acme.sh
    local acme_sh="$HOME/.acme.sh/acme.sh"
    [[ ! -f "$acme_sh" ]] && acme_sh="/root/.acme.sh/acme.sh"
    
    if [[ ! -f "$acme_sh" ]]; then
        echo -e "${YELLOW}安装 acme.sh...${NC}"
        curl https://get.acme.sh | bash 2>/dev/null || true
        acme_sh="$HOME/.acme.sh/acme.sh"
        [[ ! -f "$acme_sh" ]] && acme_sh="/root/.acme.sh/acme.sh"
    fi
    
    if [[ -f "$acme_sh" ]]; then
        "$acme_sh" --issue --standalone -d "$domain" --server letsencrypt 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}证书申请成功!${NC}"
        else
            echo -e "${RED}证书申请失败，请确保:${NC}"
            echo -e "  ${YELLOW}- 域名已解析到本机${NC}"
            echo -e "  ${YELLOW}- 80 端口未被占用${NC}"
        fi
    else
        error "acme.sh 安装失败"
    fi
}

# 自定义网站内容
custom_website_content() {
    echo ""
    echo -e "${YELLOW}自定义网站内容${NC}"
    echo -e "${YELLOW}网站目录: ${WEBSITE_DIR}${NC}"
    echo ""
    echo "你可以:"
    echo "  1. 直接编辑 ${WEBSITE_DIR}/index.html"
    echo "  2. 上传自己的静态网站文件到 ${WEBSITE_DIR}"
    echo "  3. 使用 Hugo/Hexo 等工具生成后部署"
    echo ""
    
    if [[ -f "$WEBSITE_DIR/index.html" ]]; then
        echo -e "${GREEN}当前 index.html 存在${NC}"
        ls -la "$WEBSITE_DIR"
    fi
}

# 更新网站内容
update_website_content() {
    echo ""
    echo -e "${YELLOW}更新网站内容...${NC}"
    
    if [[ ! -f "$WEBSITE_DIR/index.html" ]]; then
        error "网站未部署"
        return 1
    fi
    
    # 更新日期等信息
    sed -i "s/$(date -d '1 day ago' +%Y-%m-%d)/$(date +%Y-%m-%d)/g" "$WEBSITE_DIR/index.html" 2>/dev/null || true
    
    echo -e "${GREEN}网站内容已更新${NC}"
}

# 查看网站状态
view_website_status() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    网站状态${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if [[ -d "$WEBSITE_DIR" ]]; then
        echo -e "${GREEN}网站目录: ${WEBSITE_DIR}${NC}"
        echo -e "  大小: $(du -sh "$WEBSITE_DIR" 2>/dev/null | cut -f1)"
        echo -e "  文件数: $(find "$WEBSITE_DIR" -type f | wc -l)"
        echo ""
        
        if [[ -f "$WEBSITE_DIR/index.html" ]]; then
            echo -e "${GREEN}首页存在${NC}"
        fi
        
        if command -v nginx &>/dev/null; then
            echo ""
            echo -e "${YELLOW}Nginx 状态:${NC}"
            systemctl status nginx --no-pager 2>/dev/null | head -5 || echo "  未运行"
        fi
        
        if command -v caddy &>/dev/null; then
            echo ""
            echo -e "${YELLOW}Caddy 状态:${NC}"
            systemctl status caddy --no-pager 2>/dev/null | head -5 || echo "  未运行"
        fi
    else
        echo -e "${YELLOW}网站未部署${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
}

# 删除网站
remove_website() {
    echo ""
    read -rp "确认删除伪装网站? [y/N]: " confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -rf "$WEBSITE_DIR"
        rm -f "$WEBSITE_NGINX"
        rm -f "$WEBSITE_CADDY"
        
        systemctl reload nginx 2>/dev/null || true
        systemctl reload caddy 2>/dev/null || true
        
        echo -e "${GREEN}网站已删除${NC}"
    fi
}

show_banner() {

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${GREEN}           VPS Toolbox - 多功能一键部署工具 v3.3.0${NC}"

    echo -e "${CYAN}============================================================${NC}"

    show_usage_stats

    echo -e "  ${YELLOW}作者${NC}: Kitaro-Loked"

    echo -e "  ${YELLOW}仓库${NC}: https://github.com/Kitaro-Loked/VPS-Toolbox"

    echo -e "  ${YELLOW}致谢${NC}: 协议安装脚本来自 yeahwu/v2ray-wss"

    echo -e "          https://github.com/yeahwu/v2ray-wss"

    echo -e "${CYAN}============================================================${NC}"

    echo ""

}

show_menu() {

    clear

    show_banner

    echo -e "  ${YELLOW}[DDNS & 网络]${NC}"

    echo "    1. DDNS 域名申请与管理 (自动续签)"

    echo "    2. WARP 一键配置"

    echo ""

    echo -e "  ${YELLOW}[代理协议 - 全部来自 yeahwu/v2ray-wss]${NC}"

    echo "    3. 安装 Vless + Reality"

    echo "    4. 安装 Hysteria2"

    echo "    5. 安装 Shadowsocks-rust"

    echo "    6. 安装 VMess + WS + TLS"

    echo "    7. 安装 HTTPS 正向代理"

    echo ""

    echo -e "  ${YELLOW}[系统优化]${NC}"

    echo "    8. 网络优化 (BBR/系统参数)"

    echo "    9. 一键重装系统 (DD)"

    echo ""

    echo -e "  ${YELLOW}[工具]${NC}"

    echo "    10. 网络测速"

    echo "    11. SSL 证书管理"

    echo "    12. 端口占用一览"

    echo "    13. Telegram Bot 配置"

    echo ""

    echo -e "  ${YELLOW}[节点订阅]${NC}"

    echo "    14. 节点订阅管理"

    echo "    15. 推送订阅到 Telegram"

    echo "    16. 启动 HTTP 订阅服务"

    echo -e "  ${YELLOW}[高级]${NC}"

    echo "    17. 多节点负载均衡"

    echo "    18. 安全配置审计"

    echo -e "  ${YELLOW}[伪装网站]${NC}"

    echo "    19. 部署伪装网站"

    echo -e "  ${YELLOW}[管理]${NC}"

    echo "    20. 查看所有配置"

    echo "    21. 生成订阅链接"

    echo "    22. 流量统计"

    echo "    23. 使用统计详情"

    echo "    24. 卸载服务"

    echo "    0. 退出脚本"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

}

main() {

    check_root

    check_system

    record_usage

    install_dependencies

    

    while true; do

        show_menu

        read -rp "请选择操作 [0-24]: " choice

        

        case $choice in

            1) setup_ddns ;;

            2) setup_warp ;;

            3) install_vless ;;

            4) install_hysteria2 ;;

            5) install_shadowsocks ;;

            6) install_vmess ;;

            7) install_https_proxy ;;

            8) optimize_system ;;

            9) dd_system ;;

            10) speed_test ;;

            11) manage_cert ;;

            12) port_status ;;

            13) setup_tgbot ;;

            14) airport_manager ;;

            15) push_sub_to_telegram ;;

            16) start_sub_http_server ;;

            17) multivps_manager ;;

            18) security_audit_menu ;;

            19) website_manager ;;

            20) view_config ;;

            21) show_subscription ;;

            22) show_traffic_stats ;;

            23) view_stats_menu ;;

            24) uninstall_service ;;

            0)

                echo -e "${GREEN}感谢使用 VPS Toolbox，再见!${NC}"

                exit 0

                ;;

            *)

                warn "无效选择，请重新输入"

                sleep 1

                ;;

        esac

    done

}

main "$@"

