#!/bin/bash
# ============================================================
# VPS Toolbox - 涓€閿儴缃茶剼鏈?# 鍔熻兘: DDNS鍩熷悕鐢宠/Warp閰嶇疆/Vless/Hysteria2/SS/VMess/Trojan
# 浣滆€? VPS-Toolbox
# 鐗堟湰: 1.0.0
# ============================================================

set -e

# 棰滆壊瀹氫箟
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 鍏ㄥ眬鍙橀噺
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/vps-toolbox"
LOG_FILE="/var/log/vps-toolbox.log"
DDNS_DOMAIN=""
DDNS_TOKEN=""

# 鏃ュ織鍑芥暟
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 璀﹀憡: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 閿欒: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# 妫€鏌oot鏉冮檺
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "璇蜂娇鐢?root 鐢ㄦ埛杩愯姝よ剼鏈?
    fi
}

# 妫€鏌ョ郴缁熺被鍨?check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "鏃犳硶妫€娴嬫搷浣滅郴缁熺被鍨?
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
            error "涓嶆敮鎸佺殑鎿嶄綔绯荤粺: $OS"
            ;;
    esac
    
    log "妫€娴嬪埌绯荤粺: $OS $VER"
}

# 瀹夎渚濊禆
install_dependencies() {
    log "姝ｅ湪瀹夎鍩虹渚濊禆..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip >/dev/null 2>&1
    else
        $PKG_MANAGER install -y curl wget git socat jq cronie openssl qrencode net-tools unzip >/dev/null 2>&1
    fi
    
    # 鍚姩cron鏈嶅姟
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    # 鍒涘缓閰嶇疆鐩綍
    mkdir -p "$CONFIG_DIR"
    
    log "鍩虹渚濊禆瀹夎瀹屾垚"
}

# ==================== DDNS 鍔熻兘 ====================

# 鐢宠DDNS鍩熷悕
setup_ddns() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         DDNS 鍩熷悕鐢宠涓庣鐞?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}璇烽€夋嫨 DDNS 鏈嶅姟鍟?${NC}"
    echo "  1. Cloudflare (鎺ㄨ崘)"
    echo "  2. DuckDNS"
    echo "  3. No-IP"
    echo "  4. 杩斿洖涓昏彍鍗?
    echo ""
    read -rp "璇烽€夋嫨 [1-4]: " ddns_choice
    
    case $ddns_choice in
        1) setup_cloudflare_ddns ;;
        2) setup_duckdns ;;
        3) setup_noip ;;
        4) return ;;
        *) warn "鏃犳晥閫夋嫨"; sleep 2; setup_ddns ;;
    esac
}

# Cloudflare DDNS
setup_cloudflare_ddns() {
    echo ""
    info "Cloudflare DDNS 閰嶇疆"
    echo "----------------------------------------"
    read -rp "璇疯緭鍏?Cloudflare API Token: " cf_token
    read -rp "璇疯緭鍏ュ煙鍚?(渚嬪: example.com): " cf_domain
    read -rp "璇疯緭鍏ュ瓙鍩熷悕鍓嶇紑 (渚嬪: vps锛岀暀绌轰娇鐢ㄦ牴鍩熷悕): " cf_subdomain
    
    if [[ -z "$cf_token" || -z "$cf_domain" ]]; then
        error "API Token 鍜屽煙鍚嶄笉鑳戒负绌?
    fi
    
    # 鑾峰彇Zone ID
    log "姝ｅ湪鑾峰彇 Zone ID..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error "鏃犳硶鑾峰彇 Zone ID锛岃妫€鏌?API Token 鍜屽煙鍚?
    fi
    
    log "Zone ID: $ZONE_ID"
    
    # 鑾峰彇鍏綉IP
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "鏃犳硶鑾峰彇鍏綉IP鍦板潃"
    fi
    
    # 璁剧疆瀹屾暣鍩熷悕
    if [[ -n "$cf_subdomain" ]]; then
        FULL_DOMAIN="${cf_subdomain}.${cf_domain}"
    else
        FULL_DOMAIN="$cf_domain"
    fi
    
    # 妫€鏌ヨ褰曟槸鍚﹀瓨鍦?    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FULL_DOMAIN" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
        # 鍒涘缓鏂拌褰?        log "鍒涘缓 DNS 璁板綍..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    else
        # 鏇存柊璁板綍
        log "鏇存柊 DNS 璁板綍..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    fi
    
    # 淇濆瓨閰嶇疆
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=cloudflare
CF_TOKEN=$cf_token
CF_DOMAIN=$cf_domain
CF_SUBDOMAIN=$cf_subdomain
ZONE_ID=$ZONE_ID
FULL_DOMAIN=$FULL_DOMAIN
EOF
    
    # 鍒涘缓DDNS鏇存柊鑴氭湰
    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'
#!/bin/bash
CONFIG_DIR="/etc/vps-toolbox"
source "$CONFIG_DIR/ddns.conf"

PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
CURRENT_IP=$(dig +short "$FULL_DOMAIN" | tail -n1)

if [[ "$PUBLIC_IP" != "$CURRENT_IP" ]]; then
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FULL_DOMAIN" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    
    echo "[$(date)] DDNS updated: $FULL_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log
fi
EOF
    chmod +x "$CONFIG_DIR/update-ddns.sh"
    
    # 娣诲姞瀹氭椂浠诲姟 (姣?鍒嗛挓妫€鏌ヤ竴娆?
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    DDNS_DOMAIN="$FULL_DOMAIN"
    
    log "DDNS 閰嶇疆瀹屾垚!"
    log "鍩熷悕: $FULL_DOMAIN"
    log "褰撳墠IP: $PUBLIC_IP"
    log "宸叉坊鍔犺嚜鍔ㄦ洿鏂板畾鏃朵换鍔?(姣?鍒嗛挓)"
    
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# DuckDNS
setup_duckdns() {
    echo ""
    info "DuckDNS 閰嶇疆"
    echo "----------------------------------------"
    read -rp "璇疯緭鍏?DuckDNS Token: " duck_token
    read -rp "璇疯緭鍏ュ瓙鍩熷悕 (渚嬪: myvps): " duck_domain
    
    if [[ -z "$duck_token" || -z "$duck_domain" ]]; then
        error "Token 鍜屽煙鍚嶄笉鑳戒负绌?
    fi
    
    FULL_DOMAIN="${duck_domain}.duckdns.org"
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
    
    # 鏇存柊DuckDNS
    curl -s "https://www.duckdns.org/update?domains=$duck_domain&token=$duck_token&ip=$PUBLIC_IP" >/dev/null
    
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=duckdns
DUCK_TOKEN=$duck_token
DUCK_DOMAIN=$duck_domain
FULL_DOMAIN=$FULL_DOMAIN
EOF
    
    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'
#!/bin/bash
CONFIG_DIR="/etc/vps-toolbox"
source "$CONFIG_DIR/ddns.conf"
PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$DUCK_TOKEN&ip=$PUBLIC_IP" >/dev/null
echo "[$(date)] DDNS updated: $FULL_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log
EOF
    chmod +x "$CONFIG_DIR/update-ddns.sh"
    
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    DDNS_DOMAIN="$FULL_DOMAIN"
    
    log "DuckDNS 閰嶇疆瀹屾垚! 鍩熷悕: $FULL_DOMAIN"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# No-IP
setup_noip() {
    echo ""
    info "No-IP 閰嶇疆"
    echo "----------------------------------------"
    read -rp "璇疯緭鍏?No-IP 鐢ㄦ埛鍚? " noip_user
    read -rsp "璇疯緭鍏?No-IP 瀵嗙爜: " noip_pass
    echo ""
    read -rp "璇疯緭鍏ヤ富鏈哄悕 (渚嬪: myvps.ddns.net): " noip_host
    
    if [[ -z "$noip_user" || -z "$noip_pass" || -z "$noip_host" ]]; then
        error "鎵€鏈夊瓧娈甸兘涓嶈兘涓虹┖"
    fi
    
    FULL_DOMAIN="$noip_host"
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
    
    curl -s -u "$noip_user:$noip_pass" "https://dynupdate.no-ip.com/nic/update?hostname=$noip_host&myip=$PUBLIC_IP" >/dev/null
    
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=noip
NOIP_USER=$noip_user
NOIP_PASS=$noip_pass
NOIP_HOST=$noip_host
FULL_DOMAIN=$FULL_DOMAIN
EOF
    
    cat > "$CONFIG_DIR/update-ddns.sh" <<'EOF'
#!/bin/bash
CONFIG_DIR="/etc/vps-toolbox"
source "$CONFIG_DIR/ddns.conf"
PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
curl -s -u "$NOIP_USER:$NOIP_PASS" "https://dynupdate.no-ip.com/nic/update?hostname=$NOIP_HOST&myip=$PUBLIC_IP" >/dev/null
echo "[$(date)] DDNS updated: $FULL_DOMAIN -> $PUBLIC_IP" >> /var/log/ddns.log
EOF
    chmod +x "$CONFIG_DIR/update-ddns.sh"
    
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    DDNS_DOMAIN="$FULL_DOMAIN"
    
    log "No-IP 閰嶇疆瀹屾垚! 鍩熷悕: $FULL_DOMAIN"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== Warp 鍔熻兘 ====================

setup_warp() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         WARP 涓€閿厤缃?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    if command -v warp-cli &>/dev/null; then
        info "WARP 宸插畨瑁?
        echo ""
        echo "  1. 鍚姩 WARP"
        echo "  2. 鍋滄 WARP"
        echo "  3. 鏌ョ湅鐘舵€?
        echo "  4. 鍗歌浇 WARP"
        echo "  5. 杩斿洖涓昏彍鍗?
        echo ""
        read -rp "璇烽€夋嫨 [1-5]: " warp_choice
        
        case $warp_choice in
            1) warp-cli connect; log "WARP 宸插惎鍔? ;;
            2) warp-cli disconnect; log "WARP 宸插仠姝? ;;
            3) warp-cli status ;;
            4) uninstall_warp ;;
            5) return ;;
        esac
        return
    fi
    
    echo -e "${YELLOW}璇烽€夋嫨瀹夎鏂瑰紡:${NC}"
    echo "  1. 瀹樻柟 Cloudflare WARP (鎺ㄨ崘)"
    echo "  2. WireGuard 妯″紡 (wgcf)"
    echo "  3. 杩斿洖涓昏彍鍗?
    echo ""
    read -rp "璇烽€夋嫨 [1-3]: " warp_install_choice
    
    case $warp_install_choice in
        1) install_warp_official ;;
        2) install_warp_wgcf ;;
        3) return ;;
        *) warn "鏃犳晥閫夋嫨"; sleep 2; setup_warp ;;
    esac
}

install_warp_official() {
    log "姝ｅ湪瀹夎 Cloudflare WARP..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        apt-get update && apt-get install -y cloudflare-warp
    else
        # CentOS/RHEL/Fedora
        curl -s https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
        $PKG_MANAGER install -y cloudflare-warp
    fi
    
    # 娉ㄥ唽骞惰繛鎺?    warp-cli registration new
    warp-cli connect
    
    # 璁剧疆妯″紡涓篧ARP+ (鍙€?
    warp-cli set-mode warp
    
    log "WARP 瀹夎骞跺惎鍔ㄦ垚鍔?"
    warp-cli status
    
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

install_warp_wgcf() {
    log "姝ｅ湪瀹夎 wgcf (WireGuard WARP)..."
    
    # 瀹夎 WireGuard
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get install -y wireguard wireguard-tools
    else
        $PKG_MANAGER install -y wireguard-tools
    fi
    
    # 涓嬭浇 wgcf
    WGCF_VERSION=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION//v/}_linux_amd64"
    chmod +x /usr/local/bin/wgcf
    
    # 娉ㄥ唽
    cd /etc/wireguard
    wgcf register --accept-tos
    wgcf generate
    
    # 閰嶇疆 WireGuard
    cp wgcf-profile.conf /etc/wireguard/warp.conf
    
    # 鍚姩
    systemctl enable wg-quick@warp
    systemctl start wg-quick@warp
    
    log "wgcf WARP 瀹夎鎴愬姛!"
    
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

uninstall_warp() {
    log "姝ｅ湪鍗歌浇 WARP..."
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get remove -y cloudflare-warp
    else
        $PKG_MANAGER remove -y cloudflare-warp
    fi
    
    log "WARP 宸插嵏杞?
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== Xray 鏍稿績瀹夎 ====================

install_xray() {
    if command -v xray &>/dev/null; then
        log "Xray 宸插畨瑁咃紝鐗堟湰: $(xray version | head -n1)"
        return 0
    fi
    
    log "姝ｅ湪瀹夎 Xray 鏍稿績..."
    
    # 浣跨敤瀹樻柟鑴氭湰瀹夎
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    log "Xray 瀹夎瀹屾垚"
}

# ==================== Vless 瀹夎 ====================

install_vless() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Vless 涓€閿畨瑁?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 妫€鏌ユ垨鑾峰彇鍩熷悕
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}妫€娴嬪埌宸查厤缃殑DDNS鍩熷悕: $FULL_DOMAIN${NC}"
        read -rp "鏄惁浣跨敤姝ゅ煙鍚? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "璇疯緭鍏ユ偍鐨勫煙鍚? " DDNS_DOMAIN
        fi
    else
        read -rp "璇疯緭鍏ユ偍鐨勫煙鍚?(鎴栧厛閰嶇疆DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "鍩熷悕涓嶈兘涓虹┖"
    fi
    
    # 瀹夎Xray
    install_xray
    
    # 鐢熸垚閰嶇疆
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local PRIVATE_KEY=$(xray x25519 | grep "Private key:" | awk '{print $3}')
    local PUBLIC_KEY=$(xray x25519 -i "$PRIVATE_KEY" | grep "Public key:" | awk '{print $3}')
    local SHORT_ID=$(openssl rand -hex 4)
    
    log "姝ｅ湪鐢宠 SSL 璇佷功..."
    
    # 瀹夎acme.sh
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    
    # 鐢宠璇佷功
    ~/.acme.sh/acme.sh --issue -d "$DDNS_DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DDNS_DOMAIN" \
        --key-file /usr/local/etc/xray/private.key \
        --fullchain-file /usr/local/etc/xray/cert.crt
    
    # 鍒涘缓Vless閰嶇疆
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
    
    # 鍒涘缓TLS+WS澶囩敤閰嶇疆 (鏇村吋瀹?
    mkdir -p /usr/local/etc/xray
    
    # 閲嶅惎Xray
    systemctl restart xray
    
    # 淇濆瓨閰嶇疆淇℃伅
    cat > "$CONFIG_DIR/vless-info.txt" <<EOF
========== Vless 閰嶇疆淇℃伅 ==========
鍗忚: Vless + Reality
鏈嶅姟鍣ㄥ湴鍧€: $DDNS_DOMAIN
绔彛: $PORT
UUID: $UUID
娴佹帶: xtls-rprx-vision
浼犺緭鍗忚: tcp
瀹夊叏: reality
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: www.cloudflare.com
====================================
EOF
    
    # 鐢熸垚鍒嗕韩閾炬帴
    local VLESS_LINK="vless://${UUID}@${DDNS_DOMAIN}:${PORT}?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Vless-Reality-$(hostname)"
    
    echo "$VLESS_LINK" > "$CONFIG_DIR/vless-link.txt"
    
    # 鐢熸垚浜岀淮鐮?    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$VLESS_LINK"
        qrencode -o "$CONFIG_DIR/vless-qr.png" "$VLESS_LINK"
    fi
    
    # 娣诲姞璇佷功鑷姩缁
    (crontab -l 2>/dev/null | grep -v "acme.sh"; echo "0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh >/dev/null 2>&1 && systemctl restart xray") | crontab -
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Vless 瀹夎鎴愬姛!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vless-info.txt"
    echo ""
    echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-qr.png" ]]; then
        echo -e "${CYAN}浜岀淮鐮佸凡淇濆瓨鑷? $CONFIG_DIR/vless-qr.png${NC}"
    fi
    
    echo ""
    log "Vless 瀹夎瀹屾垚!"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== Hysteria2 瀹夎 ====================

install_hysteria2() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Hysteria2 涓€閿畨瑁?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 妫€鏌ュ煙鍚?    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}妫€娴嬪埌宸查厤缃殑DDNS鍩熷悕: $FULL_DOMAIN${NC}"
        read -rp "鏄惁浣跨敤姝ゅ煙鍚? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "璇疯緭鍏ユ偍鐨勫煙鍚? " DDNS_DOMAIN
        fi
    else
        read -rp "璇疯緭鍏ユ偍鐨勫煙鍚? " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "鍩熷悕涓嶈兘涓虹┖"
    fi
    
    log "姝ｅ湪瀹夎 Hysteria2..."
    
    # 瀹夎Hysteria2
    bash <(curl -fsSL https://get.hy2.sh/)
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local PASSWORD=$(openssl rand -base64 16)
    
    # 鐢熸垚鑷鍚嶈瘉涔?(Hysteria2鎺ㄨ崘)
    mkdir -p /etc/hysteria
    openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key
    openssl req -new -x509 -days 3650 -key /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt -subj "/CN=$DDNS_DOMAIN" \
        -addext "subjectAltName=DNS:$DDNS_DOMAIN"
    
    # 鍒涘缓閰嶇疆
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
    
    # 淇濆瓨閰嶇疆
    cat > "$CONFIG_DIR/hysteria2-info.txt" <<EOF
========== Hysteria2 閰嶇疆淇℃伅 ==========
鏈嶅姟鍣ㄥ湴鍧€: $DDNS_DOMAIN
绔彛: $PORT
瀵嗙爜: $PASSWORD
浼犺緭鍗忚: udp
TLS: 鑷鍚嶈瘉涔?SNI: $DDNS_DOMAIN
=======================================
EOF
    
    # 鐢熸垚鍒嗕韩閾炬帴
    local HY2_LINK="hysteria2://${PASSWORD}@${DDNS_DOMAIN}:${PORT}?sni=${DDNS_DOMAIN}&insecure=1#Hysteria2-$(hostname)"
    echo "$HY2_LINK" > "$CONFIG_DIR/hysteria2-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$HY2_LINK"
        qrencode -o "$CONFIG_DIR/hysteria2-qr.png" "$HY2_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Hysteria2 瀹夎鎴愬姛!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/hysteria2-info.txt"
    echo ""
    echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
    echo "$HY2_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/hysteria2-qr.png" ]]; then
        echo -e "${CYAN}浜岀淮鐮佸凡淇濆瓨鑷? $CONFIG_DIR/hysteria2-qr.png${NC}"
    fi
    
    echo ""
    log "Hysteria2 瀹夎瀹屾垚!"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== Shadowsocks 瀹夎 ====================

install_shadowsocks() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Shadowsocks 涓€閿畨瑁?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    log "姝ｅ湪瀹夎 Shadowsocks..."
    
    # 瀹夎 shadowsocks-libev
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get install -y shadowsocks-libev
    else
        $PKG_MANAGER install -y shadowsocks-libev
    fi
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local PASSWORD=$(openssl rand -base64 16)
    local METHOD="aes-256-gcm"
    
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
    
    # 淇濆瓨閰嶇疆
    cat > "$CONFIG_DIR/ss-info.txt" <<EOF
========== Shadowsocks 閰嶇疆淇℃伅 ==========
鏈嶅姟鍣ㄥ湴鍧€: $(curl -s -4 https://api.ipify.org)
绔彛: $PORT
瀵嗙爜: $PASSWORD
鍔犲瘑鏂瑰紡: $METHOD
=========================================
EOF
    
    # 鐢熸垚鍒嗕韩閾炬帴
    local SS_LINK="ss://$(echo -n "$METHOD:$PASSWORD" | base64 -w 0)@$(curl -s -4 https://api.ipify.org):$PORT#SS-$(hostname)"
    echo "$SS_LINK" > "$CONFIG_DIR/ss-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$SS_LINK"
        qrencode -o "$CONFIG_DIR/ss-qr.png" "$SS_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Shadowsocks 瀹夎鎴愬姛!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/ss-info.txt"
    echo ""
    echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
    echo "$SS_LINK"
    echo ""
    
    log "Shadowsocks 瀹夎瀹屾垚!"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== VMess 瀹夎 ====================

install_vmess() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         VMess 涓€閿畨瑁?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 妫€鏌ュ煙鍚?    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}妫€娴嬪埌宸查厤缃殑DDNS鍩熷悕: $FULL_DOMAIN${NC}"
        read -rp "鏄惁浣跨敤姝ゅ煙鍚? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "璇疯緭鍏ユ偍鐨勫煙鍚? " DDNS_DOMAIN
        fi
    else
        read -rp "璇疯緭鍏ユ偍鐨勫煙鍚?(鎴栧厛閰嶇疆DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "鍩熷悕涓嶈兘涓虹┖"
    fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "姝ｅ湪鐢宠 SSL 璇佷功..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DDNS_DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DDNS_DOMAIN" \
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
    
    # 浣跨敤鍗曠嫭鐨勯厤缃枃浠惰繍琛?    cp /usr/local/etc/xray/vmess.json /usr/local/etc/xray/config.json
    systemctl restart xray
    
    cat > "$CONFIG_DIR/vmess-info.txt" <<EOF
========== VMess 閰嶇疆淇℃伅 ==========
鏈嶅姟鍣ㄥ湴鍧€: $DDNS_DOMAIN
绔彛: $PORT
UUID: $UUID
棰濆ID: 0
浼犺緭鍗忚: ws
WebSocket璺緞: $WS_PATH
TLS: 寮€鍚?====================================
EOF
    
    # 鐢熸垚VMess閾炬帴
    local VMESS_JSON='{"v":"2","ps":"VMess-'$(hostname)'","add":"'$DDNS_DOMAIN'","port":"'$PORT'","id":"'$UUID'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$DDNS_DOMAIN'","path":"'$WS_PATH'","tls":"tls","sni":"'$DDNS_DOMAIN'"}'
    local VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    echo "$VMESS_LINK" > "$CONFIG_DIR/vmess-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$VMESS_LINK"
        qrencode -o "$CONFIG_DIR/vmess-qr.png" "$VMESS_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      VMess 瀹夎鎴愬姛!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vmess-info.txt"
    echo ""
    echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
    echo "$VMESS_LINK"
    echo ""
    
    log "VMess 瀹夎瀹屾垚!"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== Trojan 瀹夎 ====================

install_trojan() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Trojan 涓€閿畨瑁?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 妫€鏌ュ煙鍚?    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}妫€娴嬪埌宸查厤缃殑DDNS鍩熷悕: $FULL_DOMAIN${NC}"
        read -rp "鏄惁浣跨敤姝ゅ煙鍚? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "璇疯緭鍏ユ偍鐨勫煙鍚? " DDNS_DOMAIN
        fi
    else
        read -rp "璇疯緭鍏ユ偍鐨勫煙鍚?(鎴栧厛閰嶇疆DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "鍩熷悕涓嶈兘涓虹┖"
    fi
    
    log "姝ｅ湪瀹夎 Trojan..."
    
    # 瀹夎Trojan-go (鎺ㄨ崘锛屾敮鎸佹洿澶氱壒鎬?
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
    
    log "姝ｅ湪鐢宠 SSL 璇佷功..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DDNS_DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DDNS_DOMAIN" \
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
        "sni": "$DDNS_DOMAIN"
    },
    "websocket": {
        "enabled": true,
        "path": "$WS_PATH",
        "hostname": "$DDNS_DOMAIN"
    }
}
EOF
    
    # 鍒涘缓systemd鏈嶅姟
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
========== Trojan 閰嶇疆淇℃伅 ==========
鏈嶅姟鍣ㄥ湴鍧€: $DDNS_DOMAIN
绔彛: $PORT
瀵嗙爜: $PASSWORD
浼犺緭鍗忚: websocket
WebSocket璺緞: $WS_PATH
TLS: 寮€鍚?SNI: $DDNS_DOMAIN
=====================================
EOF
    
    # 鐢熸垚鍒嗕韩閾炬帴
    local TROJAN_LINK="trojan://${PASSWORD}@${DDNS_DOMAIN}:${PORT}?security=tls&sni=${DDNS_DOMAIN}&type=ws&host=${DDNS_DOMAIN}&path=${WS_PATH}#Trojan-$(hostname)"
    echo "$TROJAN_LINK" > "$CONFIG_DIR/trojan-link.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$TROJAN_LINK"
        qrencode -o "$CONFIG_DIR/trojan-qr.png" "$TROJAN_LINK"
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Trojan 瀹夎鎴愬姛!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/trojan-info.txt"
    echo ""
    echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
    echo "$TROJAN_LINK"
    echo ""
    
    log "Trojan 瀹夎瀹屾垚!"
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== 鏌ョ湅閰嶇疆 ====================

view_config() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         鏌ョ湅宸插畨瑁呮湇鍔￠厤缃?{NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-info.txt" ]]; then
        echo -e "${GREEN}銆怴less 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/vless-info.txt"
        echo ""
        echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
        cat "$CONFIG_DIR/vless-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-info.txt" ]]; then
        echo -e "${GREEN}銆怘ysteria2 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/hysteria2-info.txt"
        echo ""
        echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
        cat "$CONFIG_DIR/hysteria2-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-info.txt" ]]; then
        echo -e "${GREEN}銆怱hadowsocks 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/ss-info.txt"
        echo ""
        echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
        cat "$CONFIG_DIR/ss-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-info.txt" ]]; then
        echo -e "${GREEN}銆怴Mess 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/vmess-info.txt"
        echo ""
        echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
        cat "$CONFIG_DIR/vmess-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-info.txt" ]]; then
        echo -e "${GREEN}銆怲rojan 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/trojan-info.txt"
        echo ""
        echo -e "${CYAN}鍒嗕韩閾炬帴:${NC}"
        cat "$CONFIG_DIR/trojan-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        echo -e "${GREEN}銆怐DNS 閰嶇疆銆?{NC}"
        cat "$CONFIG_DIR/ddns.conf"
        echo ""
    fi
    
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== 鍗歌浇鏈嶅姟 ====================

uninstall_service() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         鍗歌浇鏈嶅姟${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "  1. 鍗歌浇 Vless"
    echo "  2. 鍗歌浇 Hysteria2"
    echo "  3. 鍗歌浇 Shadowsocks"
    echo "  4. 鍗歌浇 VMess"
    echo "  5. 鍗歌浇 Trojan"
    echo "  6. 鍗歌浇鎵€鏈夋湇鍔?
    echo "  7. 杩斿洖涓昏彍鍗?
    echo ""
    read -rp "璇烽€夋嫨 [1-7]: " uninstall_choice
    
    case $uninstall_choice in
        1)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/config.json
            rm -f "$CONFIG_DIR"/vless-*
            log "Vless 宸插嵏杞?
            ;;
        2)
            systemctl stop hysteria-server 2>/dev/null || true
            systemctl disable hysteria-server 2>/dev/null || true
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            rm -f "$CONFIG_DIR"/hysteria2-*
            log "Hysteria2 宸插嵏杞?
            ;;
        3)
            systemctl stop shadowsocks-libev 2>/dev/null || true
            systemctl disable shadowsocks-libev 2>/dev/null || true
            rm -f "$CONFIG_DIR"/ss-*
            log "Shadowsocks 宸插嵏杞?
            ;;
        4)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/vmess.json
            rm -f "$CONFIG_DIR"/vmess-*
            log "VMess 宸插嵏杞?
            ;;
        5)
            systemctl stop trojan-go 2>/dev/null || true
            systemctl disable trojan-go 2>/dev/null || true
            rm -rf /etc/trojan
            rm -f /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/trojan-*
            log "Trojan 宸插嵏杞?
            ;;
        6)
            systemctl stop xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            systemctl disable xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/hysteria /etc/trojan
            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/*-info.txt "$CONFIG_DIR"/*-link.txt "$CONFIG_DIR"/*-qr.png
            log "鎵€鏈夋湇鍔″凡鍗歌浇"
            ;;
        7) return ;;
    esac
    
    echo ""
    read -rp "鎸夊洖杞﹂敭缁х画..."
}

# ==================== 涓昏彍鍗?====================

show_menu() {
    clear
    echo -e "${CYAN}鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽${NC}"
    echo -e "${CYAN}鈺?{NC}           ${GREEN}VPS Toolbox - 澶氬姛鑳戒竴閿儴缃插伐鍏?{NC}                  ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺犫晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暎${NC}"
    echo -e "${CYAN}鈺?{NC}                                                              ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}  ${YELLOW}銆怐DNS & 缃戠粶銆?{NC}                                            ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   1. DDNS 鍩熷悕鐢宠涓庣鐞?(鑷姩缁)                          ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   2. WARP 涓€閿厤缃?                                          ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}                                                              ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}  ${YELLOW}銆愪唬鐞嗗崗璁€?{NC}                                               ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   3. 瀹夎 Vless + Reality (鎺ㄨ崘)                             ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   4. 瀹夎 Hysteria2 (鎺ㄨ崘)                                   ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   5. 瀹夎 Shadowsocks                                        ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   6. 瀹夎 VMess + WebSocket                                  ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   7. 瀹夎 Trojan + WebSocket                                 ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}                                                              ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}  ${YELLOW}銆愮鐞嗐€?{NC}                                                   ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   8. 鏌ョ湅鎵€鏈夐厤缃?                                           ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   9. 鍗歌浇鏈嶅姟                                                ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}   0. 閫€鍑鸿剼鏈?                                               ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺?{NC}                                                              ${CYAN}鈺?{NC}"
    echo -e "${CYAN}鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆${NC}"
    echo ""
}

main() {
    check_root
    check_system
    install_dependencies
    
    while true; do
        show_menu
        read -rp "璇烽€夋嫨鎿嶄綔 [0-9]: " choice
        
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
                echo -e "${GREEN}鎰熻阿浣跨敤 VPS Toolbox锛屽啀瑙?${NC}"
                exit 0
                ;;
            *)
                warn "鏃犳晥閫夋嫨锛岃閲嶆柊杈撳叆"
                sleep 1
                ;;
        esac
    done
}

# 杩愯涓诲嚱鏁?main "$@"
