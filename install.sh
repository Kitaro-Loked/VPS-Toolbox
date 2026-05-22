#!/bin/bash
# Auto-fix CRLF
sed -i 's/\r$//' "$0" 2>/dev/null || true
# ============================================================
# VPS Toolbox - 一键部署脚本
# 功能: DDNS/WARP/Vless/Hysteria2/SS/VMess/HTTPS代理
# 作者: Kitaro-Loked
# 仓库: https://github.com/Kitaro-Loked/VPS-Toolbox
# 版本: 2.7.0
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

show_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${GREEN}           VPS Toolbox - 多功能一键部署工具 v2.7.0${NC}"
    echo -e "${CYAN}============================================================${NC}"
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
    echo -e "  ${YELLOW}[管理]${NC}"
    echo "    10. 查看所有配置"
    echo "    11. 生成订阅链接"
    echo "    12. 流量统计"
    echo "    13. 卸载服务"
    echo "    0. 退出脚本"
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
        read -rp "请选择操作 [0-13]: " choice
        
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
            10) view_config ;;
            11) show_subscription ;;
            12) show_traffic_stats ;;
            13) uninstall_service ;;
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
