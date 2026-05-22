#!/bin/bash
# Auto-fix CRLF
sed -i 's/\r$//' "$0" 2>/dev/null || true
# ============================================================
# VPS Toolbox - One-Click Deploy Script
# Features: DDNS/WARP/Vless/Hysteria2/SS/VMess/HTTPS代理
# Author: Kitaro-Loked
# Repo: https://github.com/Kitaro-Loked/VPS-Toolbox
# Version: 2.5.0
# Credit: Protocol scripts from yeahwu/v2ray-wss
#       https://github.com/yeahwu/v2ray-wss
#       This project provides menu wrapper, DDNS, WARP, subscription management
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
    echo -e "${CYAN}                   DDNS Domain Management${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}Select DDNS Provider:${NC}"
    echo "  1. DuckDNS (Recommended, Free)"
    echo "  2. Cloudflare (API Token needed)"
    echo "  3. No-IP (Account needed)"
    echo "  4. View DDNS Status"
    echo "  5. Back to Main"
    echo ""
    read -rp "Select [1-5]: " ddns_choice
    
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
    echo -e "${CYAN}                    DuckDNS Auto-Apply${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Generating random subdomain..."
    local RANDOM_SUB=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)
    local DUCK_DOMAIN="$RANDOM_SUB"
    local DDNS_DOMAIN="${RANDOM_SUB}.duckdns.org"
    local PUBLIC_IP=$(get_server_ip)
    
    echo -e "${GREEN}Generated subdomain:${NC} $DUCK_DOMAIN"
    echo -e "${CYAN}Full domain:${NC} $DDNS_DOMAIN"
    echo -e "${CYAN}Public IP:${NC} $PUBLIC_IP"
    echo ""
    
    echo -e "${YELLOW}DuckDNS requires Token。${NC}"
    echo "  1. I have DuckDNS Token"
    echo "  2. Open DuckDNS signup page"
    echo "  3. Go back"
    echo ""
    read -rp "请选择 [1-3]: " duck_choice
    
    case $duck_choice in
        1)
            duck_token=""
            while [[ -z "$duck_token" ]]; do
                read -rp "Enter DuckDNS Token: " duck_token
                duck_token=$(echo "$duck_token" | xargs)
                if [[ -z "$duck_token" ]]; then
                    warn "Token cannot be empty"
                fi
            done
            
            local RESULT=$(curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$duck_token&ip=$PUBLIC_IP")
            
            if [[ "$RESULT" == "OK" ]]; then
                log "DuckDNS 域名更新成功!"
            else
                warn "Domain update returned: $RESULT"
                warn "DuckDNS auto-creates if not exists"
            fi
            
            log "Waiting for DNS propagation，up to 60s..."
            local DNS_READY=0
            for i in {1..12}; do
                sleep 5
                if host "$DDNS_DOMAIN" >/dev/null 2>&1 || nslookup "$DDNS_DOMAIN" >/dev/null 2>&1; then
                    DNS_READY=1
                    log "DNS ready!"
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
            
            log "Config saved! DDNS update script configured (每5分钟检测)"
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
    read -rp "Press Enter to continue..."
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
    read -rp "Press Enter to continue..."
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
    read -rp "Press Enter to continue..."
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
        echo -e "${CYAN}当前Public IP:${NC} $(get_server_ip)"
        echo -e "${CYAN}DDNS日志:${NC}"
        tail -n 5 /var/log/ddns.log 2>/dev/null || echo "暂无日志"
    else
        warn "尚未配置 DDNS"
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== WARP 功能 ====================

setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      WARP Config${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Installing WARP..."
    
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update && apt-get install -y cloudflare-warp
    
    warp-cli register
    warp-cli connect
    
    log "WARP installed"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== 协议安装 - 直接调用 yeahwu 的脚本 ====================

install_vless() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}         正在Install Vless + Reality (yeahwu/v2ray-wss)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Downloading and running yeahwu/v2ray-wss reality.sh..."
    cd /tmp
    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh
    bash reality.sh
    
    echo ""
    read -rp "Press Enter to continue..."
}

install_hysteria2() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}           正在Install Hysteria2 (yeahwu/v2ray-wss)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Downloading and running yeahwu/v2ray-wss hy2.sh..."
    cd /tmp
    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/hy2.sh
    bash hy2.sh
    
    echo ""
    read -rp "Press Enter to continue..."
}

install_shadowsocks() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}        正在Install Shadowsocks-rust (yeahwu/v2ray-wss)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Downloading and running yeahwu/v2ray-wss ss-rust.sh..."
    cd /tmp
    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ss-rust.sh
    bash ss-rust.sh
    
    echo ""
    read -rp "Press Enter to continue..."
}

install_vmess() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}        正在Install VMess + WS + TLS (yeahwu/v2ray-wss)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Downloading and running yeahwu/v2ray-wss tcp-wss.sh..."
    cd /tmp
    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh
    bash tcp-wss.sh
    
    echo ""
    read -rp "Press Enter to continue..."
}

install_https_proxy() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}       正在Install HTTPS Forward Proxy (yeahwu/v2ray-wss)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Downloading and running yeahwu/v2ray-wss https.sh..."
    cd /tmp
    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/https.sh
    bash https.sh
    
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== 管理功能 ====================

view_config() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    View Installed Services${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if [[ -f "/usr/local/etc/xray/reclient.json" ]]; then
        echo -e "${GREEN}[Vless + Reality Config]${NC}"
        cat /usr/local/etc/xray/reclient.json
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "/etc/hysteria/hyclient.json" ]]; then
        echo -e "${GREEN}[Hysteria2 Config]${NC}"
        cat /etc/hysteria/hyclient.json
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "/etc/shadowsocks/config.json" ]]; then
        echo -e "${GREEN}[Shadowsocks-rust Config]${NC}"
        cat /etc/shadowsocks/config.json
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "/usr/local/etc/v2ray/client.json" ]]; then
        echo -e "${GREEN}[VMess Config]${NC}"
        cat /usr/local/etc/v2ray/client.json
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "/etc/caddy/https.json" ]]; then
        echo -e "${GREEN}[HTTPS Proxy Config]${NC}"
        cat /etc/caddy/https.json
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        echo -e "${GREEN}[DDNS Config]${NC}"
        cat "$CONFIG_DIR/ddns.conf"
        echo ""
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
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
    echo -e "${CYAN}                      Subscription${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local SUB_B64=$(generate_subscription)
    
    if [[ -z "$SUB_B64" ]]; then
        echo -e "${YELLOW}No proxy services installed${NC}"
        read -rp "Press Enter to continue..."
        return
    fi
    
    echo -e "${GREEN}Subscription (Base64):${NC}"
    echo ""
    echo "$SUB_B64"
    echo ""
    
    read -rp "Press Enter to continue..."
}

uninstall_service() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                        Uninstall${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo "  1. Uninstall Vless (Xray)"
    echo "  2. Uninstall Hysteria2"
    echo "  3. Uninstall Shadowsocks-rust"
    echo "  4. Uninstall VMess (V2Ray)"
    echo "  5. Uninstall HTTPS Proxy (Caddy)"
    echo "  6. Uninstall All"
    echo "  7. Back to Main"
    echo ""
    read -rp "Select [1-7]: " uninstall_choice
    
    case $uninstall_choice in
        1)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -rf /usr/local/etc/xray
            rm -f /usr/local/bin/xray
            log "Vless uninstalled"
            ;;
        2)
            systemctl stop hysteria-server 2>/dev/null || true
            systemctl disable hysteria-server 2>/dev/null || true
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            log "Hysteria2 uninstalled"
            ;;
        3)
            systemctl stop shadowsocks 2>/dev/null || true
            systemctl disable shadowsocks 2>/dev/null || true
            rm -f /usr/local/bin/ssserver
            log "Shadowsocks-rust uninstalled"
            ;;
        4)
            systemctl stop v2ray 2>/dev/null || true
            systemctl disable v2ray 2>/dev/null || true
            rm -rf /usr/local/etc/v2ray
            rm -f /usr/local/bin/v2ray
            log "VMess uninstalled"
            ;;
        5)
            systemctl stop caddy 2>/dev/null || true
            systemctl disable caddy 2>/dev/null || true
            rm -f /usr/local/bin/caddy
            log "HTTPS 正向代理uninstalled"
            ;;
        6)
            systemctl stop xray hysteria-server shadowsocks v2ray caddy nginx 2>/dev/null || true
            systemctl disable xray hysteria-server shadowsocks v2ray caddy nginx 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/hysteria /usr/local/etc/v2ray
            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/ssserver /usr/local/bin/v2ray /usr/local/bin/caddy
            log "所有服务uninstalled"
            ;;
        7) return ;;
    esac
    
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== 主菜单 ====================

show_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${GREEN}           VPS Toolbox - One-Click Deploy Tool v2.5.0${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "  ${YELLOW}Author${NC}: Kitaro-Loked"
    echo -e "  ${YELLOW}Repo${NC}: https://github.com/Kitaro-Loked/VPS-Toolbox"
    echo -e "  ${YELLOW}Credit${NC}: Protocol scripts from yeahwu/v2ray-wss"
    echo -e "          https://github.com/yeahwu/v2ray-wss"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

show_menu() {
    clear
    show_banner
    echo -e "  ${YELLOW}[DDNS & Network]${NC}"
    echo "    1. DDNS Domain (Auto-renew)"
    echo "    2. WARP Config"
    echo ""
    echo -e "  ${YELLOW}[Proxy Protocols - from yeahwu/v2ray-wss]${NC}"
    echo "    3. Install Vless + Reality"
    echo "    4. Install Hysteria2"
    echo "    5. Install Shadowsocks-rust"
    echo "    6. Install VMess + WS + TLS"
    echo "    7. Install HTTPS Forward Proxy"
    echo ""
    echo -e "  ${YELLOW}[Management]${NC}"
    echo "    8. View All Config"
    echo "    9. Generate Subscription"
    echo "    10. Uninstall"
    echo "    0. Exit"
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

main() {
    check_root
    check_system
    install_dependencies
    
    while true; do
        show_menu
        read -rp "Select [0-10]: " choice
        
        case $choice in
            1) setup_ddns ;;
            2) setup_warp ;;
            3) install_vless ;;
            4) install_hysteria2 ;;
            5) install_shadowsocks ;;
            6) install_vmess ;;
            7) install_https_proxy ;;
            8) view_config ;;
            9) show_subscription ;;
            10) uninstall_service ;;
            0)
                echo -e "${GREEN}Thanks for using VPS Toolbox!${NC}"
                exit 0
                ;;
            *)
                warn "Invalid selection"
                sleep 1
                ;;
        esac
    done
}

main "$@"
