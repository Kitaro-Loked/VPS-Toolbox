#!/bin/bash
# ============================================================
# VPS Toolbox - 一键部署脚本
# 功能: DDNS/WARP/Vless/Hysteria2/SS/VMess/Trojan
# Author: Kitaro-Loked
# Repo: https://github.com/Kitaro-Loked/VPS-Toolbox
# 版本: 2.0.0
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
DDNS_DOMAIN=""
DDNS_PROVIDER=""
DDNS_PASS=""

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Please run as root"
    fi
}

# 检查系统类型
check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "Cannot detect OS"
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
            error "Unsupported OS: $OS"
            ;;
    esac
    
    log "Detected OS: $OS $VER"
}

# 安装依赖
install_dependencies() {
    log "Installing dependencies..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip >/dev/null 2>&1
    else
        $PKG_MANAGER install -y curl wget git socat jq cronie openssl qrencode net-tools unzip >/dev/null 2>&1
    fi
    
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    mkdir -p "$CONFIG_DIR"
    
    log "Dependencies installed"
}

# ==================== DDNS 功能 ====================

setup_ddns() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                   DDNS Setup${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}Select DDNS provider:${NC}"
    echo ""
    echo -e "  ${GREEN}1. scritch.org (推荐 - Easiest)${NC}"
    echo "     No signup, one command gets a domain"
    echo ""
    echo "  2. Cloudflare"
    echo "  3. DuckDNS"
    echo "  4. No-IP"
    echo "  5. 返回主菜单"
    echo ""
    read -rp "请选择 [1-5]: " ddns_choice
    
    case $ddns_choice in
        1) setup_scritch ;;
        2) setup_cloudflare_ddns ;;
        3) setup_duckdns ;;
        4) setup_noip ;;
        5) return ;;
        *) warn "Invalid choice"; sleep 2; setup_ddns ;;
    esac
}

# scritch.org - EasiestDDNS
setup_scritch() {
    echo ""
    info "Applying for free domain via scritch.org..."
    echo "----------------------------------------"
    
    local SCRITCH_OUTPUT=$(curl -sS https://scritch.org/new)
    
    if [[ -z "$SCRITCH_OUTPUT" ]]; then
        error "Cannot connect to scritch.org"
    fi
    
    # 解析输出
    DDNS_DOMAIN=$(echo "$SCRITCH_OUTPUT" | grep "Domain:" | awk '{print $2}')
    DDNS_PASS=$(echo "$SCRITCH_OUTPUT" | grep "Password:" | awk '{print $2}')
    local UPDATE_URL=$(echo "$SCRITCH_OUTPUT" | grep "Update:" | sed 's/Update:   //')
    
    if [[ -z "$DDNS_DOMAIN" || -z "$DDNS_PASS" ]]; then
        error "Failed to parse scritch.org response"
    fi
    
    log "Domain application successful!"
    log "Domain: $DDNS_DOMAIN"
    log "Password: $DDNS_PASS"
    
    # 保存Configuring
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=scritch
DDNS_DOMAIN=$DDNS_DOMAIN
DDNS_PASS=$DDNS_PASS
UPDATE_URL=$UPDATE_URL
EOF
    
    # 创建更新脚本
    cat > "$CONFIG_DIR/update-ddns.sh" <<EOF
#!/bin/bash
CONFIG_DIR="/etc/vps-toolbox"
source "\$CONFIG_DIR/ddns.conf"

PUBLIC_IP=\$(curl -s -4 https://api.ipify.org)
CURRENT_IP=\$(dig +short "\$DDNS_DOMAIN" | tail -n1)

if [[ "\$PUBLIC_IP" != "\$CURRENT_IP" ]]; then
    curl -s "https://scritch.org/update?domain=\$DDNS_DOMAIN&password=\$DDNS_PASS" >/dev/null
    echo "[\$(date)] DDNS updated: \$DDNS_DOMAIN -> \$PUBLIC_IP" >> /var/log/ddns.log
fi
EOF
    chmod +x "$CONFIG_DIR/update-ddns.sh"
    
    # 添加定时任务
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      scritch.org DDNS configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}Domain:${NC} $DDNS_DOMAIN"
    echo -e "${CYAN}Password:${NC} $DDNS_PASS"
    echo -e "${CYAN}Update command:${NC}"
    echo "$UPDATE_URL"
    echo ""
    log "Auto-update cron job added (每5分钟)"
    
    echo ""
    read -rp "Press Enter to continue..."
}

# Cloudflare DDNS
setup_cloudflare_ddns() {
    echo ""
    info "Cloudflare DDNS Setup"
    echo "----------------------------------------"
    read -rp "Enter Cloudflare API Token: " cf_token
    read -rp "请输入Domain (例如: example.com): " cf_domain
    read -rp "请输入子Domain前缀 (例如: vps，留空使用根Domain): " cf_subdomain
    
    if [[ -z "$cf_token" || -z "$cf_domain" ]]; then
        error "API Token 和Domain不能为空"
    fi
    
    log "Getting Zone ID..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error "无法获取 Zone ID，请检查 API Token 和Domain"
    fi
    
    log "Zone ID: $ZONE_ID"
    
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "Cannot get public IP"
    fi
    
    if [[ -n "$cf_subdomain" ]]; then
        FULL_DOMAIN="${cf_subdomain}.${cf_domain}"
    else
        FULL_DOMAIN="$cf_domain"
    fi
    
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FULL_DOMAIN" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
        log "Creating DNS record..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    else
        log "Updating DNS record..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    fi
    
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=cloudflare
CF_TOKEN=$cf_token
CF_DOMAIN=$cf_domain
CF_SUBDOMAIN=$cf_subdomain
ZONE_ID=$ZONE_ID
DDNS_DOMAIN=$FULL_DOMAIN
EOF
    
    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'
#!/bin/bash
CONFIG_DIR="/etc/vps-toolbox"
source "$CONFIG_DIR/ddns.conf"

PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
CURRENT_IP=$(dig +short "$DDNS_DOMAIN" | tail -n1)

if [[ "$PUBLIC_IP" != "$CURRENT_IP" ]]; then
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DDNS_DOMAIN" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DDNS_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    
    echo "[$(date)] DDNS updated: $DDNS_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log
fi
EOF
    chmod +x "$CONFIG_DIR/update-ddns.sh"
    
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    DDNS_DOMAIN="$FULL_DOMAIN"
    
    log "DDNS configured!"
    log "Domain: $FULL_DOMAIN"
    log "Current IP: $PUBLIC_IP"
    log "Auto-update cron job added (每5分钟)"
    
    echo ""
    read -rp "Press Enter to continue..."
}

# DuckDNS
setup_duckdns() {
    echo ""
    info "DuckDNS Setup"
    echo "----------------------------------------"
    read -rp "Enter DuckDNS Token: " duck_token
    read -rp "请输入子Domain (例如: myvps): " duck_domain
    
    if [[ -z "$duck_token" || -z "$duck_domain" ]]; then
        error "Token 和Domain不能为空"
    fi
    
    DDNS_DOMAIN="${duck_domain}.duckdns.org"
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
    
    curl -s "https://www.duckdns.org/update?domains=$duck_domain&token=$duck_token&ip=$PUBLIC_IP" >/dev/null
    
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=duckdns
DUCK_TOKEN=$duck_token
DUCK_DOMAIN=$duck_domain
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
    
    log "DuckDNS Setup完成! Domain: $DDNS_DOMAIN"
    echo ""
    read -rp "Press Enter to continue..."
}

# No-IP
setup_noip() {
    echo ""
    info "No-IP Setup"
    echo "----------------------------------------"
    read -rp "Enter No-IP username: " noip_user
    read -rsp "请输入 No-IP Password: " noip_pass
    echo ""
    read -rp "Enter hostname (例如: myvps.ddns.net): " noip_host
    
    if [[ -z "$noip_user" || -z "$noip_pass" || -z "$noip_host" ]]; then
        error "All fields are required"
    fi
    
    DDNS_DOMAIN="$noip_host"
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
    
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
    
    log "No-IP Setup完成! Domain: $DDNS_DOMAIN"
    echo ""
    read -rp "Press Enter to continue..."
}

# 获取或输入Domain
get_domain() {
    local PROTOCOL_NAME=$1
    local NEED_DOMAIN=${2:-"yes"}
    
    # 如果协议不需要Domain，直接返回IP
    if [[ "$NEED_DOMAIN" == "no" ]]; then
        local SERVER_IP=$(curl -s -4 https://api.ipify.org)
        echo "$SERVER_IP"
        return 0
    fi
    
    # 检查是否已有DDNSConfiguring
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        if [[ -n "$DDNS_DOMAIN" ]]; then
            echo -e "${GREEN}检测到已ConfiguringDomain: $DDNS_DOMAIN${NC}"
            read -rp "使用此Domain? [Y/n]: " use_existing
            if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            fi
        fi
    fi
    
    # 提供选择
    echo ""
    echo -e "${YELLOW}请选择Domain来源:${NC}"
    echo "  1. Auto-apply via scritch.org (Easiest)"
    echo "  2. 使用自己的Domain"
    echo "  3. Go back"
    echo ""
    read -rp "请选择 [1-3]: " domain_choice
    
    case $domain_choice in
        1)
            setup_scritch
            if [[ -n "$DDNS_DOMAIN" ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            else
                error "Domain申请失败"
            fi
            ;;
        2)
            read -rp "请输入您的Domain: " custom_domain
            if [[ -n "$custom_domain" ]]; then
                echo "$custom_domain"
                return 0
            else
                error "Domain不能为空"
            fi
            ;;
        3)
            return 1
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
}

# ==================== WARP 功能 ====================

setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      WARP Setup${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if command -v warp-cli &>/dev/null; then
        info "WARP already installed"
        echo ""
        echo "  1. Start WARP"
        echo "  2. Stop WARP"
        echo "  3. Check status"
        echo "  4. Uninstall WARP"
        echo "  5. 返回主菜单"
        echo ""
        read -rp "请选择 [1-5]: " warp_choice
        
        case $warp_choice in
            1) warp-cli connect; log "WARP 已Starting" ;;
            2) warp-cli disconnect; log "WARP 已停止" ;;
            3) warp-cli status ;;
            4) uninstall_warp ;;
            5) return ;;
        esac
        return
    fi
    
    echo -e "${YELLOW}Select installation method:${NC}"
    echo "  1. Official Cloudflare WARP (推荐)"
    echo "  2. WireGuard mode (wgcf)"
    echo "  3. 返回主菜单"
    echo ""
    read -rp "请选择 [1-3]: " warp_install_choice
    
    case $warp_install_choice in
        1) install_warp_official ;;
        2) install_warp_wgcf ;;
        3) return ;;
        *) warn "Invalid choice"; sleep 2; setup_warp ;;
    esac
}

install_warp_official() {
    log "Installing Cloudflare WARP..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        apt-get update && apt-get install -y cloudflare-warp
    else
        curl -s https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
        $PKG_MANAGER install -y cloudflare-warp
    fi
    
    warp-cli registration new
    warp-cli connect
    warp-cli set-mode warp
    
    log "WARP 安装并Starting成功!"
    warp-cli status
    
    echo ""
    read -rp "Press Enter to continue..."
}

install_warp_wgcf() {
    log "Installing wgcf (WireGuard WARP)..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get install -y wireguard wireguard-tools
    else
        $PKG_MANAGER install -y wireguard-tools
    fi
    
    WGCF_VERSION=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION//v/}_linux_amd64"
    chmod +x /usr/local/bin/wgcf
    
    cd /etc/wireguard
    wgcf register --accept-tos
    wgcf generate
    
    cp wgcf-profile.conf /etc/wireguard/warp.conf
    
    systemctl enable wg-quick@warp
    systemctl start wg-quick@warp
    
    log "wgcf WARP installed!"
    
    echo ""
    read -rp "Press Enter to continue..."
}

uninstall_warp() {
    log "正在Uninstall WARP..."
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get remove -y cloudflare-warp
    else
        $PKG_MANAGER remove -y cloudflare-warp
    fi
    
    log "WARP uninstalled"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== Xray Core安装 ====================

install_xray() {
    if command -v xray &>/dev/null; then
        log "Xray already installed: $(xray version | head -n1)"
        return 0
    fi
    
    log "正在安装 Xray Core..."
    
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    log "Xray installed"
}

# ==================== Vless 安装 (需要Domain) ====================

install_vless() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Vless + Reality Install${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Vless")
    if [[ $? -ne 0 ]]; then return; fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local PRIVATE_KEY=$(xray x25519 | grep "Private key:" | awk '{print $3}')
    local PUBLIC_KEY=$(xray x25519 -i "$PRIVATE_KEY" | grep "Public key:" | awk '{print $3}')
    local SHORT_ID=$(openssl rand -hex 4)
    
    log "Applying for SSL certificate..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /usr/local/etc/xray/private.key \
        --fullchain-file /usr/local/etc/xray/cert.crt
    
    cat > /usr/local/etc/xray/config.json <<EOF
{
    "log": {
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.cloudflare.com:443",
                    "xver": 0,
                    "serverNames": [
                        "www.cloudflare.com",
                        "cloudflare.com"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "publicKey": "$PUBLIC_KEY",
                    "shortIds": [
                        "$SHORT_ID"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing": {
        "rules": [
            {
                "protocol": ["bittorrent"],
                "outboundTag": "block",
                "type": "field"
            }
        ]
    }
}
EOF
    
    mkdir -p /usr/local/etc/xray
    
    systemctl restart xray
    
    cat > "$CONFIG_DIR/vless-info.txt" <<EOF
========== Vless Configuring信息 ==========
协议: Vless + Reality
服务器地址: $DOMAIN
端口: $PORT
UUID: $UUID
流控: xtls-rprx-vision
传输协议: tcp
安全: reality
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: www.cloudflare.com
====================================
EOF
    
    local VLESS_LINK="vless://${UUID}@${DOMAIN}:${PORT}?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Vless-Reality-$(hostname)"
    
    echo "$VLESS_LINK" > "$CONFIG_DIR/vless-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$VLESS_LINK"
        qrencode -o "$CONFIG_DIR/vless-qr.png" "$VLESS_LINK"
    fi
    
    (crontab -l 2>/dev/null | grep -v "acme.sh"; echo "0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh >/dev/null 2>&1 && systemctl restart xray") | crontab -
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Vless installed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vless-info.txt"
    echo ""
    echo -e "${CYAN}Share link:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-qr.png" ]]; then
        echo -e "${CYAN}QR saved to: $CONFIG_DIR/vless-qr.png${NC}"
    fi
    
    echo ""
    log "Vless installation complete!"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== Hysteria2 Install (需要Domain) ====================

install_hysteria2() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      Hysteria2 Install${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Hysteria2")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "Installing Hysteria2..."
    
    bash <(curl -fsSL https://get.hy2.sh/)
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local PASSWORD=$(openssl rand -base64 16)
    
    mkdir -p /etc/hysteria
    openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key
    openssl req -new -x509 -days 3650 -key /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN"
    
    cat > /etc/hysteria/config.yaml <<EOF
listen: :$PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://www.cloudflare.com
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 100 mbps

outbounds:
  - name: direct
    type: direct
EOF
    
    systemctl enable hysteria-server
    systemctl restart hysteria-server
    
    cat > "$CONFIG_DIR/hysteria2-info.txt" <<EOF
========== Hysteria2 Configuring信息 ==========
服务器地址: $DOMAIN
端口: $PORT
Password: $PASSWORD
传输协议: udp
TLS: 自签名证书
SNI: $DOMAIN
=======================================
EOF
    
    local HY2_LINK="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}?sni=${DOMAIN}&insecure=1#Hysteria2-$(hostname)"
    echo "$HY2_LINK" > "$CONFIG_DIR/hysteria2-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$HY2_LINK"
        qrencode -o "$CONFIG_DIR/hysteria2-qr.png" "$HY2_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Hysteria2 Install成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/hysteria2-info.txt"
    echo ""
    echo -e "${CYAN}Share link:${NC}"
    echo "$HY2_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/hysteria2-qr.png" ]]; then
        echo -e "${CYAN}QR saved to: $CONFIG_DIR/hysteria2-qr.png${NC}"
    fi
    
    echo ""
    log "Hysteria2 Install完成!"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== Shadowsocks Install (不需要Domain) ====================

install_shadowsocks() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Shadowsocks Install${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "Installing Shadowsocks..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get install -y shadowsocks-libev
    else
        $PKG_MANAGER install -y shadowsocks-libev
    fi
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local PASSWORD=$(openssl rand -base64 16)
    local METHOD="aes-256-gcm"
    local SERVER_IP=$(curl -s -4 https://api.ipify.org)
    
    cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server":"0.0.0.0",
    "server_port":$PORT,
    "password":"$PASSWORD",
    "timeout":300,
    "method":"$METHOD",
    "fast_open":true,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp"
}
EOF
    
    systemctl enable shadowsocks-libev
    systemctl restart shadowsocks-libev
    
    cat > "$CONFIG_DIR/ss-info.txt" <<EOF
========== Shadowsocks Configuring信息 ==========
服务器地址: $SERVER_IP
端口: $PORT
Password: $PASSWORD
加密方式: $METHOD
=========================================
EOF
    
    local SS_LINK="ss://$(echo -n "$METHOD:$PASSWORD" | base64 -w 0)@${SERVER_IP}:$PORT#SS-$(hostname)"
    echo "$SS_LINK" > "$CONFIG_DIR/ss-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$SS_LINK"
        qrencode -o "$CONFIG_DIR/ss-qr.png" "$SS_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Shadowsocks Install成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/ss-info.txt"
    echo ""
    echo -e "${CYAN}Share link:${NC}"
    echo "$SS_LINK"
    echo ""
    
    log "Shadowsocks Install完成!"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== VMess 安装 (需要Domain) ====================

install_vmess() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    VMess + WebSocket Install${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "VMess")
    if [[ $? -ne 0 ]]; then return; fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "Applying for SSL certificate..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /usr/local/etc/xray/vmess-private.key \
        --fullchain-file /usr/local/etc/xray/vmess-cert.crt
    
    cat > /usr/local/etc/xray/vmess.json <<EOF
{
    "log": {
        "access": "/var/log/xray/vmess-access.log",
        "error": "/var/log/xray/vmess-error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$WS_PATH"
                },
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/usr/local/etc/xray/vmess-cert.crt",
                            "keyFile": "/usr/local/etc/xray/vmess-private.key"
                        }
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF
    
    cp /usr/local/etc/xray/vmess.json /usr/local/etc/xray/config.json
    systemctl restart xray
    
    cat > "$CONFIG_DIR/vmess-info.txt" <<EOF
========== VMess Configuring信息 ==========
服务器地址: $DOMAIN
端口: $PORT
UUID: $UUID
额外ID: 0
传输协议: ws
WebSocket路径: $WS_PATH
TLS: 开启
====================================
EOF
    
    local VMESS_JSON='{"v":"2","ps":"VMess-'$(hostname)'","add":"'$DOMAIN'","port":"'$PORT'","id":"'$UUID'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$DOMAIN'","path":"'$WS_PATH'","tls":"tls","sni":"'$DOMAIN'"}'
    local VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    echo "$VMESS_LINK" > "$CONFIG_DIR/vmess-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$VMESS_LINK"
        qrencode -o "$CONFIG_DIR/vmess-qr.png" "$VMESS_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      VMess installed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vmess-info.txt"
    echo ""
    echo -e "${CYAN}Share link:${NC}"
    echo "$VMESS_LINK"
    echo ""
    
    log "VMess installation complete!"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== Trojan 安装 (需要Domain) ====================

install_trojan() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Trojan + WebSocket Install${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Trojan")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "Installing Trojan..."
    
    local TROJAN_VERSION=$(curl -s https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -qO /tmp/trojan-go.tar.gz "https://github.com/p4gefau1t/trojan-go/releases/download/${TROJAN_VERSION}/trojan-go-linux-amd64.zip"
    
    mkdir -p /tmp/trojan-go
    cd /tmp/trojan-go
    unzip -o /tmp/trojan-go.tar.gz
    cp trojan-go /usr/local/bin/
    chmod +x /usr/local/bin/trojan-go
    
    local PORT=443
    local PASSWORD=$(openssl rand -base64 16)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "Applying for SSL certificate..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/trojan/private.key \
        --fullchain-file /etc/trojan/cert.crt
    
    mkdir -p /etc/trojan
    
    cat > /etc/trojan/config.json <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": $PORT,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "/etc/trojan/cert.crt",
        "key": "/etc/trojan/private.key",
        "sni": "$DOMAIN"
    },
    "websocket": {
        "enabled": true,
        "path": "$WS_PATH",
        "hostname": "$DOMAIN"
    }
}
EOF
    
    cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable trojan-go
    systemctl restart trojan-go
    
    cat > "$CONFIG_DIR/trojan-info.txt" <<EOF
========== Trojan Configuring信息 ==========
服务器地址: $DOMAIN
端口: $PORT
Password: $PASSWORD
传输协议: websocket
WebSocket路径: $WS_PATH
TLS: 开启
SNI: $DOMAIN
=====================================
EOF
    
    local TROJAN_LINK="trojan://${PASSWORD}@${DOMAIN}:${PORT}?security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH}#Trojan-$(hostname)"
    echo "$TROJAN_LINK" > "$CONFIG_DIR/trojan-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$TROJAN_LINK"
        qrencode -o "$CONFIG_DIR/trojan-qr.png" "$TROJAN_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Trojan installed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/trojan-info.txt"
    echo ""
    echo -e "${CYAN}Share link:${NC}"
    echo "$TROJAN_LINK"
    echo ""
    
    log "Trojan installation complete!"
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== 查看Configuring ====================

view_config() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    查看已安装服务Configuring${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-info.txt" ]]; then
        echo -e "${GREEN}[Vless Configuring]${NC}"
        cat "$CONFIG_DIR/vless-info.txt"
        echo ""
        echo -e "${CYAN}Share link:${NC}"
        cat "$CONFIG_DIR/vless-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-info.txt" ]]; then
        echo -e "${GREEN}[Hysteria2 Configuring]${NC}"
        cat "$CONFIG_DIR/hysteria2-info.txt"
        echo ""
        echo -e "${CYAN}Share link:${NC}"
        cat "$CONFIG_DIR/hysteria2-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-info.txt" ]]; then
        echo -e "${GREEN}[Shadowsocks Configuring]${NC}"
        cat "$CONFIG_DIR/ss-info.txt"
        echo ""
        echo -e "${CYAN}Share link:${NC}"
        cat "$CONFIG_DIR/ss-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-info.txt" ]]; then
        echo -e "${GREEN}[VMess Configuring]${NC}"
        cat "$CONFIG_DIR/vmess-info.txt"
        echo ""
        echo -e "${CYAN}Share link:${NC}"
        cat "$CONFIG_DIR/vmess-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-info.txt" ]]; then
        echo -e "${GREEN}[Trojan Configuring]${NC}"
        cat "$CONFIG_DIR/trojan-info.txt"
        echo ""
        echo -e "${CYAN}Share link:${NC}"
        cat "$CONFIG_DIR/trojan-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        echo -e "${GREEN}[DDNS Configuring]${NC}"
        cat "$CONFIG_DIR/ddns.conf"
        echo ""
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

# ==================== Uninstall Service ====================

uninstall_service() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                        Uninstall Service${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo "  1. Uninstall Vless"
    echo "  2. Uninstall Hysteria2"
    echo "  3. Uninstall Shadowsocks"
    echo "  4. Uninstall VMess"
    echo "  5. Uninstall Trojan"
    echo "  6. Uninstall All"
    echo "  7. 返回主菜单"
    echo ""
    read -rp "请选择 [1-7]: " uninstall_choice
    
    case $uninstall_choice in
        1)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/config.json
            rm -f "$CONFIG_DIR"/vless-*
            log "Vless uninstalled"
            ;;
        2)
            systemctl stop hysteria-server 2>/dev/null || true
            systemctl disable hysteria-server 2>/dev/null || true
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            rm -f "$CONFIG_DIR"/hysteria2-*
            log "Hysteria2 uninstalled"
            ;;
        3)
            systemctl stop shadowsocks-libev 2>/dev/null || true
            systemctl disable shadowsocks-libev 2>/dev/null || true
            rm -f "$CONFIG_DIR"/ss-*
            log "Shadowsocks uninstalled"
            ;;
        4)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/vmess.json
            rm -f "$CONFIG_DIR"/vmess-*
            log "VMess uninstalled"
            ;;
        5)
            systemctl stop trojan-go 2>/dev/null || true
            systemctl disable trojan-go 2>/dev/null || true
            rm -rf /etc/trojan
            rm -f /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/trojan-*
            log "Trojan uninstalled"
            ;;
        6)
            systemctl stop xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            systemctl disable xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/hysteria /etc/trojan
            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/*-info.txt "$CONFIG_DIR"/*-link.txt "$CONFIG_DIR"/*-qr.png
            log "All services uninstalled"
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
    echo -e "${GREEN}           VPS Toolbox - All-in-One Deploy Tool v2.0.0${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "  ${YELLOW}Author${NC}: Kitaro-Loked"
    echo -e "  ${YELLOW}Repo${NC}: https://github.com/Kitaro-Loked/VPS-Toolbox"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

show_menu() {
    clear
    show_banner
    echo -e "  ${YELLOW}[DDNS & Network]${NC}"
    echo "    1. DDNS Setup (自动续签)"
    echo "    2. WARP Setup"
    echo ""
    echo -e "  ${YELLOW}[Proxy Protocols]${NC}"
    echo "    3. Install Vless + Reality (需要Domain)"
    echo "    4. Install Hysteria2 (需要Domain)"
    echo "    5. Install Shadowsocks (无需Domain)"
    echo "    6. Install VMess + WebSocket (需要Domain)"
    echo "    7. Install Trojan + WebSocket (需要Domain)"
    echo ""
    echo -e "  ${YELLOW}[Management]${NC}"
    echo "    8. 查看所有Configuring"
    echo "    9. Uninstall Service"
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
        read -rp "Select operation [0-9]: " choice
        
        case $choice in
            1) setup_ddns ;;
            2) setup_warp ;;
            3) install_vless ;;
            4) install_hysteria2 ;;
            5) install_shadowsocks ;;
            6) install_vmess ;;
            7) install_trojan ;;
            8) view_config ;;
            9) uninstall_service ;;
            0)
                echo -e "${GREEN}Thanks for using VPS Toolbox, goodbye!${NC}"
                exit 0
                ;;
            *)
                warn "Invalid choice, please try again"
                sleep 1
                ;;
        esac
    done
}

main "$@"
