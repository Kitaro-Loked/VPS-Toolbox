#!/bin/bash
# ============================================================
# VPS Toolbox - ????scrision
# Function: DDNS/WARP/Vless/Hysteria2/SS/VMess/Trojan
# Author: Kitaro-Loked
# Repo: https://github.com/Kitaro-Loked/VPS-Toolbox
# Version: 2.0.0
# ============================================================

set -e

# Colorble?
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# GlobalVars
CONFIG_DIR="/etc/vps-toolbox"
LOG_FILE="/var/log/vps-toolbox.log"
DDNS_DOMAIN=""
DDNS_PROVIDER=""
DDNS_PASS=""

# Log??
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ??: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ??: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# deteckroot??
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "requestuse root ????scrision"
    fi
}

# detecksystemtype
check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "no-brainerwaydetect?Ausystemtype"
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
            error "notsupport??Ausystem: $OS"
            ;;
    esac
    
    log "detecttosystem: $OS $VER"
}

# installeddependencies
install_dependencies() {
    log "ininginstalledbasicdependencies..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip >/dev/null 2>&1
    else
        $PKG_MANAGER install -y curl wget git socat jq cronie openssl qrencode net-tools unzip >/dev/null 2>&1
    fi
    
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    mkdir -p "$CONFIG_DIR"
    
    log "basicdependenciesinstalledcomerate"
}

# ==================== DDNS Function ====================

setup_ddns() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                   DDNS Domainapplyrequestandmanage${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}requestselect DDNS servicepro:${NC}"
    echo ""
    echo -e "  ${GREEN}1. Auto-Apply DuckDNS (easiest)${NC}"
    echo "     No website signup, apply via command line"
    echo ""
    echo "  2. Use Public IP (no domain)"
    echo "     Show server IP, good for Shadowsocks etc."
    echo ""
    echo "  3. Cloudflare (have domain)"
    echo "  4. No-IP (have account)"
    echo "  5. ?back??ple"
    echo ""
    read -rp "requestselect [1-5]: " ddns_choice
    
    case $ddns_choice in
        1) setup_duckdns_auto ;;
        2) show_public_ip ;;
        3) setup_cloudflare_ddns ;;
        4) setup_noip ;;
        5) return ;;
        *) warn "no-brainer?select"; sleep 2; setup_ddns ;;
    esac
}

# showPublic IP
show_public_ip() {
    echo ""
    info "getPublic IPInfo..."
    echo "----------------------------------------"
    
    local IPV4=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 https://ifconfig.me 2>/dev/null)
    local IPV6=$(curl -s -6 https://api6.ipify.org 2>/dev/null || echo "?detectto")
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}           service???Info${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}IPv4 ??:${NC} $IPV4"
    echo -e "${CYAN}IPv6 ??:${NC} $IPV6"
    echo ""
    echo -e "${YELLOW}useinstruction:${NC}"
    echo "  - Shadowsocks candirectuse IP ??"
    echo "  - Hysteria2 canuse IP + ??cert"
    echo "  - Vless/VMess/Trojan needDomain+cert"
    echo ""
    echo -e "${YELLOW}needDomain，requestselect:${NC}"
    echo "  1. DuckDNS (mostsimple)"
    echo "  2. Cloudflare (moststable)"
    echo "  3. ?back"
    echo ""
    read -rp "requestselect [1-3]: " ip_choice
    
    case $ip_choice in
        1) setup_duckdns ;;
        2) setup_cloudflare_ddns ;;
        3) return ;;
        *) warn "no-brainer?select"; sleep 2; show_public_ip ;;
    esac
}

# Cloudflare DDNS
setup_cloudflare_ddns() {
    echo ""
    info "Cloudflare DDNS config"
    echo "----------------------------------------"
    read -rp "requestout? Cloudflare API Token: " cf_token
    read -rp "requestout?Domain (e.g.: example.com): " cf_domain
    read -rp "requestout?subDomain?? (e.g.: vps，leaveemptyuse?Domain): " cf_subdomain
    
    if [[ -z "$cf_token" || -z "$cf_domain" ]]; then
        error "API Token ?Domainnottion?empty"
    fi
    
    log "iningget Zone ID..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error "no-brainerwayget Zone ID，requestdeteck API Token ?Domain"
    fi
    
    log "Zone ID: $ZONE_ID"
    
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "no-brainerwaygetPublic IP??"
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
        log "create DNS ??..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    else
        log "update DNS ??..."
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
    
    log "DDNS configcomerate!"
    log "Domain: $FULL_DOMAIN"
    log "??IP: $PUBLIC_IP"
    log "Auto-update cron job added (every 5minutes)"
    
    echo ""
    read -rp "?back????..."
}

# DuckDNS - ????applyrequest（no-brainerneed????）
setup_duckdns_auto() {
    echo ""
    info "Auto-applying DuckDNS domain..."
    echo "----------------------------------------"
    
    # getPublic IP
    local PUBLIC_IP=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 https://ifconfig.me 2>/dev/null)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "no-brainerwaygetPublic IP"
    fi
    
    # generaterandomsubDomain（8?random????）
    local RANDOM_SUB=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
    local DUCK_DOMAIN="${RANDOM_SUB}"
    local DDNS_DOMAIN="${RANDOM_SUB}.duckdns.org"
    
    echo ""
    echo -e "${CYAN}Generated random subdomain:${NC} $RANDOM_SUB"
    echo -e "${CYAN}Full domain:${NC} $DDNS_DOMAIN"
    echo -e "${CYAN}Public IP:${NC} $PUBLIC_IP"
    echo ""
    
    # DuckDNS ??no-brainer token create（use "none" Au? token cancreatetemporaryDomain）
    # ?up??so??use DuckDNS ?sim?????
    # ??? DuckDNS support email get token
    
    echo -e "${YELLOW}DuckDNS Auto-Apply Guide:${NC}"
    echo "  DuckDNS needs Token to update domain。"
    echo "  Please select how to get Token:"
    echo ""
    echo "  1. I already have DuckDNS Token (enter directly)"
    echo "  2. Open DuckDNS signup page (get Token)"
    echo "  3. Use temporary solution (IP direct, no domain)"
    echo ""
    read -rp "requestselect [1-3]: " duck_choice
    
    case $duck_choice in
        1)
            read -rp "requestout? DuckDNS Token: " duck_token
            if [[ -z "$duck_token" ]]; then
                error "Token nottion?empty"
            fi
            
            # ??updateDomain
            local RESULT=$(curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$duck_token&ip=$PUBLIC_IP")
            
            if [[ "$RESULT" == "OK" ]]; then
                log "DuckDNS domain application successful!"
            else
                warn "Domain update returned: $RESULT"
                warn "If domain does not exist, DuckDNS will auto-create"
            fi
            
            # saveconfig
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
            
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}      DuckDNS configured!${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${CYAN}Domain:${NC} $DDNS_DOMAIN"
            echo -e "${CYAN}Token:${NC} $duck_token"
            echo -e "${CYAN}IP:${NC} $PUBLIC_IP"
            echo ""
            log "Auto-update cron job added (every 5minutes)"
            ;;
        2)
            echo ""
            echo -e "${CYAN}Follow these steps to get DuckDNS Token:${NC}"
            echo "  1. open https://www.duckdns.org"
            echo "  2. Login with Google/GitHub/Reddit/Twitter"
            echo "  3. Create a subdomain (e.g. myvps)"
            echo "  4. Copy the Token shown on page"
            echo "  5. Come back here and select '1. ?al?? Token'"
            echo ""
            
            # ??commandopen???（?can）
            if command -v xdg-open &>/dev/null; then
                xdg-open "https://www.duckdns.org" 2>/dev/null || true
            fi
            
            read -rp "?back???back DuckDNS ?ple..."
            setup_duckdns_auto
            return
            ;;
        3)
            echo ""
            info "usePublic IPdirectaccess..."
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}           service???Info${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${CYAN}IPv4 ??:${NC} $PUBLIC_IP"
            echo ""
            echo -e "${YELLOW}Tip:${NC} Shadowsocks or Hysteria2 can use this IP directly"
            echo ""
            ;;
        *)
            warn "no-brainer?select"
            sleep 2
            setup_duckdns_auto
            return
            ;;
    esac
    
    echo ""
    read -rp "?back????..."
}

# DuckDNS - ??config（al?Token）
setup_duckdns() {
    echo ""
    info "DuckDNS config"
    echo "----------------------------------------"
    read -rp "requestout? DuckDNS Token: " duck_token
    read -rp "requestout?subDomain (e.g.: myvps): " duck_domain
    
    if [[ -z "$duck_token" || -z "$duck_domain" ]]; then
        error "Token ?Domainnottion?empty"
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
    
    log "DuckDNS configured! Domain: $DDNS_DOMAIN"
    echo ""
    read -rp "?back????..."
}

# No-IP
setup_noip() {
    echo ""
    info "No-IP config"
    echo "----------------------------------------"
    read -rp "requestout? No-IP ?: " noip_user
    read -rsp "requestout? No-IP ??: " noip_pass
    echo ""
    read -rp "requestout??dom (e.g.: myvps.ddns.net): " noip_host
    
    if [[ -z "$noip_user" || -z "$noip_pass" || -z "$noip_host" ]]; then
        error "?????nottion?empty"
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
    
    log "No-IP configcomerate! Domain: $DDNS_DOMAIN"
    echo ""
    read -rp "?back????..."
}

# get?out?Domain
get_domain() {
    local PROTOCOL_NAME=$1
    local NEED_DOMAIN=${2:-"yes"}
    
    # ???notneedDomain，direct?backIP
    if [[ "$NEED_DOMAIN" == "no" ]]; then
        local SERVER_IP=$(curl -s -4 https://api.ipify.org)
        echo "$SERVER_IP"
        return 0
    fi
    
    # deteck??al?DDNSconfig
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        if [[ -n "$DDNS_DOMAIN" ]]; then
            echo -e "${GREEN}detecttoalconfigDomain: $DDNS_DOMAIN${NC}"
            read -rp "use?Domain? [Y/n]: " use_existing
            if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            fi
        fi
    fi
    
    # viderselect
    echo ""
    echo -e "${YELLOW}requestselectDomain??:${NC}"
    echo "  1. Auto-Apply DuckDNS (easiest)"
    echo "  2. use???Domain"
    echo "  3. ?back???"
    echo ""
    read -rp "requestselect [1-3]: " domain_choice
    
    case $domain_choice in
        1)
            setup_scritch
            if [[ -n "$DDNS_DOMAIN" ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            else
                error "Domainapplyrequestfail"
            fi
            ;;
        2)
            read -rp "requestout???Domain: " custom_domain
            if [[ -n "$custom_domain" ]]; then
                echo "$custom_domain"
                return 0
            else
                error "Domainnottion?empty"
            fi
            ;;
        3)
            return 1
            ;;
        *)
            error "no-brainer?select"
            ;;
    esac
}

# ==================== WARP Function ====================

setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      WARP ??config${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if command -v warp-cli &>/dev/null; then
        info "WARP alinstalled"
        echo ""
        echo "  1. ?? WARP"
        echo "  2. stopped WARP"
        echo "  3. eck???"
        echo "  4. ?? WARP"
        echo "  5. ?back??ple"
        echo ""
        read -rp "requestselect [1-5]: " warp_choice
        
        case $warp_choice in
            1) warp-cli connect; log "WARP al??" ;;
            2) warp-cli disconnect; log "WARP alstopped" ;;
            3) warp-cli status ;;
            4) uninstall_warp ;;
            5) return ;;
        esac
        return
    fi
    
    echo -e "${YELLOW}requestselectinstalledso?:${NC}"
    echo "  1. ?so Cloudflare WARP (Recommended)"
    echo "  2. WireGuard ?? (wgcf)"
    echo "  3. ?back??ple"
    echo ""
    read -rp "requestselect [1-3]: " warp_install_choice
    
    case $warp_install_choice in
        1) install_warp_official ;;
        2) install_warp_wgcf ;;
        3) return ;;
        *) warn "no-brainer?select"; sleep 2; setup_warp ;;
    esac
}

install_warp_official() {
    log "ininginstalled Cloudflare WARP..."
    
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
    
    log "WARP installed???erateFunc!"
    warp-cli status
    
    echo ""
    read -rp "?back????..."
}

install_warp_wgcf() {
    log "ininginstalled wgcf (WireGuard WARP)..."
    
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
    
    log "wgcf WARP installederateFunc!"
    
    echo ""
    read -rp "?back????..."
}

uninstall_warp() {
    log "ining?? WARP..."
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get remove -y cloudflare-warp
    else
        $PKG_MANAGER remove -y cloudflare-warp
    fi
    
    log "WARP al??"
    echo ""
    read -rp "?back????..."
}

# ==================== Xray ??installed ====================

install_xray() {
    if command -v xray &>/dev/null; then
        log "Xray alinstalled，Version: $(xray version | head -n1)"
        return 0
    fi
    
    log "ininginstalled Xray ??..."
    
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    log "Xray installedcomerate"
}

# ==================== Vless installed (needDomain) ====================

install_vless() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Vless + Reality installed${NC}"
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
    
    log "iningapplyrequest SSL cert..."
    
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
========== Vless configInfo ==========
??: Vless + Reality
service???: $DOMAIN
??: $PORT
UUID: $UUID
??: xtls-rprx-vision
?out??: tcp
instGlo: reality
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
    echo -e "${GREEN}      Vless installederateFunc!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vless-info.txt"
    echo ""
    echo -e "${CYAN}min??rect:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-qr.png" ]]; then
        echo -e "${CYAN}???alsave?: $CONFIG_DIR/vless-qr.png${NC}"
    fi
    
    echo ""
    log "Vless installedcomerate!"
    echo ""
    read -rp "?back????..."
}

# ==================== Hysteria2 installed (needDomain) ====================

install_hysteria2() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      Hysteria2 installed${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Hysteria2")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "ininginstalled Hysteria2..."
    
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
========== Hysteria2 configInfo ==========
service???: $DOMAIN
??: $PORT
??: $PASSWORD
?out??: udp
TLS: ??cert
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
    echo -e "${GREEN}      Hysteria2 installederateFunc!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/hysteria2-info.txt"
    echo ""
    echo -e "${CYAN}min??rect:${NC}"
    echo "$HY2_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/hysteria2-qr.png" ]]; then
        echo -e "${CYAN}???alsave?: $CONFIG_DIR/hysteria2-qr.png${NC}"
    fi
    
    echo ""
    log "Hysteria2 installedcomerate!"
    echo ""
    read -rp "?back????..."
}

# ==================== Shadowsocks installed (notneedDomain) ====================

install_shadowsocks() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Shadowsocks installed${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "ininginstalled Shadowsocks..."
    
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
========== Shadowsocks configInfo ==========
service???: $SERVER_IP
??: $PORT
??: $PASSWORD
d?so?: $METHOD
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
    echo -e "${GREEN}      Shadowsocks installederateFunc!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/ss-info.txt"
    echo ""
    echo -e "${CYAN}min??rect:${NC}"
    echo "$SS_LINK"
    echo ""
    
    log "Shadowsocks installedcomerate!"
    echo ""
    read -rp "?back????..."
}

# ==================== VMess installed (needDomain) ====================

install_vmess() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    VMess + WebSocket installed${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "VMess")
    if [[ $? -ne 0 ]]; then return; fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "iningapplyrequest SSL cert..."
    
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
========== VMess configInfo ==========
service???: $DOMAIN
??: $PORT
UUID: $UUID
??ID: 0
?out??: ws
WebSocket??: $WS_PATH
TLS: ?
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
    echo -e "${GREEN}      VMess installederateFunc!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vmess-info.txt"
    echo ""
    echo -e "${CYAN}min??rect:${NC}"
    echo "$VMESS_LINK"
    echo ""
    
    log "VMess installedcomerate!"
    echo ""
    read -rp "?back????..."
}

# ==================== Trojan installed (needDomain) ====================

install_trojan() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Trojan + WebSocket installed${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Trojan")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "ininginstalled Trojan..."
    
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
    
    log "iningapplyrequest SSL cert..."
    
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
========== Trojan configInfo ==========
service???: $DOMAIN
??: $PORT
??: $PASSWORD
?out??: websocket
WebSocket??: $WS_PATH
TLS: ?
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
    echo -e "${GREEN}      Trojan installederateFunc!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/trojan-info.txt"
    echo ""
    echo -e "${CYAN}min??rect:${NC}"
    echo "$TROJAN_LINK"
    echo ""
    
    log "Trojan installedcomerate!"
    echo ""
    read -rp "?back????..."
}

# ==================== eck?config ====================

view_config() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    eck?alinstalledserviceconfig${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-info.txt" ]]; then
        echo -e "${GREEN}[Vless config]${NC}"
        cat "$CONFIG_DIR/vless-info.txt"
        echo ""
        echo -e "${CYAN}min??rect:${NC}"
        cat "$CONFIG_DIR/vless-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-info.txt" ]]; then
        echo -e "${GREEN}[Hysteria2 config]${NC}"
        cat "$CONFIG_DIR/hysteria2-info.txt"
        echo ""
        echo -e "${CYAN}min??rect:${NC}"
        cat "$CONFIG_DIR/hysteria2-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-info.txt" ]]; then
        echo -e "${GREEN}[Shadowsocks config]${NC}"
        cat "$CONFIG_DIR/ss-info.txt"
        echo ""
        echo -e "${CYAN}min??rect:${NC}"
        cat "$CONFIG_DIR/ss-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-info.txt" ]]; then
        echo -e "${GREEN}[VMess config]${NC}"
        cat "$CONFIG_DIR/vmess-info.txt"
        echo ""
        echo -e "${CYAN}min??rect:${NC}"
        cat "$CONFIG_DIR/vmess-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-info.txt" ]]; then
        echo -e "${GREEN}[Trojan config]${NC}"
        cat "$CONFIG_DIR/trojan-info.txt"
        echo ""
        echo -e "${CYAN}min??rect:${NC}"
        cat "$CONFIG_DIR/trojan-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        echo -e "${GREEN}[DDNS config]${NC}"
        cat "$CONFIG_DIR/ddns.conf"
        echo ""
    fi
    
    echo ""
    read -rp "?back????..."
}

# ==================== ??service ====================

uninstall_service() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                        ??service${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo "  1. ?? Vless"
    echo "  2. ?? Hysteria2"
    echo "  3. ?? Shadowsocks"
    echo "  4. ?? VMess"
    echo "  5. ?? Trojan"
    echo "  6. ????service"
    echo "  7. ?back??ple"
    echo ""
    read -rp "requestselect [1-7]: " uninstall_choice
    
    case $uninstall_choice in
        1)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/config.json
            rm -f "$CONFIG_DIR"/vless-*
            log "Vless al??"
            ;;
        2)
            systemctl stop hysteria-server 2>/dev/null || true
            systemctl disable hysteria-server 2>/dev/null || true
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            rm -f "$CONFIG_DIR"/hysteria2-*
            log "Hysteria2 al??"
            ;;
        3)
            systemctl stop shadowsocks-libev 2>/dev/null || true
            systemctl disable shadowsocks-libev 2>/dev/null || true
            rm -f "$CONFIG_DIR"/ss-*
            log "Shadowsocks al??"
            ;;
        4)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/vmess.json
            rm -f "$CONFIG_DIR"/vmess-*
            log "VMess al??"
            ;;
        5)
            systemctl stop trojan-go 2>/dev/null || true
            systemctl disable trojan-go 2>/dev/null || true
            rm -rf /etc/trojan
            rm -f /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/trojan-*
            log "Trojan al??"
            ;;
        6)
            systemctl stop xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            systemctl disable xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/hysteria /etc/trojan
            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/*-info.txt "$CONFIG_DIR"/*-link.txt "$CONFIG_DIR"/*-qr.png
            log "??serviceal??"
            ;;
        7) return ;;
    esac
    
    echo ""
    read -rp "?back????..."
}

# ==================== ??ple ====================

show_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${GREEN}           VPS Toolbox - ?Function?????? v2.0.0${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "  ${YELLOW}Author${NC}: Kitaro-Loked"
    echo -e "  ${YELLOW}Repo${NC}: https://github.com/Kitaro-Loked/VPS-Toolbox"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

show_menu() {
    clear
    show_banner
    echo -e "  ${YELLOW}[DDNS & ??]${NC}"
    echo "    1. DDNS Domainapplyrequestandmanage (????)"
    echo "    2. WARP ??config"
    echo ""
    echo -e "  ${YELLOW}[???]${NC}"
    echo "    3. installed Vless + Reality (needDomain)"
    echo "    4. installed Hysteria2 (needDomain)"
    echo "    5. installed Shadowsocks (no-brainerneedDomain)"
    echo "    6. installed VMess + WebSocket (needDomain)"
    echo "    7. installed Trojan + WebSocket (needDomain)"
    echo ""
    echo -e "  ${YELLOW}[manage]${NC}"
    echo "    8. eck???config"
    echo "    9. ??service"
    echo "    0. ?putscrision"
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
        read -rp "requestselect?Au [0-9]: " choice
        
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
                echo -e "${GREEN}??use VPS Toolbox，??!${NC}"
                exit 0
                ;;
            *)
                warn "no-brainer?select，request?dateout?"
                sleep 1
                ;;
        esac
    done
}

main "$@"
