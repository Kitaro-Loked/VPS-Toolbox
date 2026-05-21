#!/bin/bash
# ============================================================
# VPS Toolbox - 一键部署脚本
# 功能: DDNS/WARP/Vless/Hysteria2/SS/VMess/Trojan
# 作者: Kitaro-Loked
# 仓库: https://github.com/Kitaro-Loked/VPS-Toolbox
# 版本: 2.1.2
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
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
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
        apt-get install -y curl wget git socat jq cron openssl qrencode net-tools unzip >/dev/null 2>&1
    else
        $PKG_MANAGER install -y curl wget git socat jq cronie openssl qrencode net-tools unzip >/dev/null 2>&1
    fi
    
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    mkdir -p "$CONFIG_DIR"
    
    log "基础依赖安装完成"
}

# ==================== DDNS 功能 ====================

setup_ddns() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                   DDNS 域名申请与管理${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}请选择 DDNS 服务商:${NC}"
    echo ""
    echo -e "  ${GREEN}1. 一键申请 DuckDNS (最无脑)${NC}"
    echo "     无需注册网站，直接命令行申请"
    echo ""
    echo "  2. 使用公网IP (无需域名)"
    echo "     直接显示服务器IP，适合Shadowsocks等"
    echo ""
    echo "  3. Cloudflare (已有域名)"
    echo "  4. No-IP (已有账号)"
    echo "  5. 返回主菜单"
    echo ""
    read -rp "请选择 [1-5]: " ddns_choice
    
    case $ddns_choice in
        1) setup_duckdns_auto ;;
        2) show_public_ip ;;
        3) setup_cloudflare_ddns ;;
        4) setup_noip ;;
        5) return ;;
        *) warn "无效选择"; sleep 2; setup_ddns ;;
    esac
}

# 显示公网IP
show_public_ip() {
    echo ""
    info "获取公网IP信息..."
    echo "----------------------------------------"
    
    local IPV4=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 https://ifconfig.me 2>/dev/null)
    local IPV6=$(curl -s -6 https://api6.ipify.org 2>/dev/null || echo "未检测到")
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}           服务器网络信息${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}IPv4 地址:${NC} $IPV4"
    echo -e "${CYAN}IPv6 地址:${NC} $IPV6"
    echo ""
    echo -e "${YELLOW}使用说明:${NC}"
    echo "  - Shadowsocks 可直接使用 IP 地址"
    echo "  - Hysteria2 可使用 IP + 自签名证书"
    echo "  - Vless/VMess/Trojan 需要域名+证书"
    echo ""
    echo -e "${YELLOW}如需域名，请选择:${NC}"
    echo "  1. DuckDNS (最简单)"
    echo "  2. Cloudflare (最稳定)"
    echo "  3. 返回"
    echo ""
    read -rp "请选择 [1-3]: " ip_choice
    
    case $ip_choice in
        1) setup_duckdns ;;
        2) setup_cloudflare_ddns ;;
        3) return ;;
        *) warn "无效选择"; sleep 2; show_public_ip ;;
    esac
}

# Cloudflare DDNS
setup_cloudflare_ddns() {
    echo ""
    info "Cloudflare DDNS 配置"
    echo "----------------------------------------"
    cf_token=""
    while [[ -z "$cf_token" ]]; do
        read -rp "请输入 Cloudflare API Token: " cf_token
        cf_token=$(echo "$cf_token" | xargs)
        if [[ -z "$cf_token" ]]; then
            warn "API Token 不能为空，请重新输入"
        fi
    done
    
    cf_domain=""
    while [[ -z "$cf_domain" ]]; do
        read -rp "请输入域名 (例如: example.com): " cf_domain
        cf_domain=$(echo "$cf_domain" | xargs)
        if [[ -z "$cf_domain" ]]; then
            warn "域名不能为空，请重新输入"
        fi
    done
    
    read -rp "请输入子域名前缀 (例如: vps，留空使用根域名): " cf_subdomain
    
    log "正在获取 Zone ID..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error "无法获取 Zone ID，请检查 API Token 和域名"
    fi
    
    log "Zone ID: $ZONE_ID"
    
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "无法获取公网IP地址"
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
        log "创建 DNS 记录..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    else
        log "更新 DNS 记录..."
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
    
    log "DDNS 配置完成!"
    log "域名: $FULL_DOMAIN"
    log "当前IP: $PUBLIC_IP"
    log "已添加自动更新定时任务 (每5分钟)"
    
    echo ""
    read -rp "按回车键继续..."
}

# DuckDNS - 一键自动申请（无需注册网站）
setup_duckdns_auto() {
    echo ""
    info "正在一键申请 DuckDNS 域名..."
    echo "----------------------------------------"
    
    # 获取公网IP
    local PUBLIC_IP=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 https://ifconfig.me 2>/dev/null)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "无法获取公网IP"
    fi
    
    # 生成随机子域名（8位随机字母数字）
    local RANDOM_SUB=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
    local DUCK_DOMAIN="${RANDOM_SUB}"
    local DDNS_DOMAIN="${RANDOM_SUB}.duckdns.org"
    
    echo ""
    echo -e "${CYAN}生成的随机子域名:${NC} $RANDOM_SUB"
    echo -e "${CYAN}完整域名:${NC} $DDNS_DOMAIN"
    echo -e "${CYAN}公网IP:${NC} $PUBLIC_IP"
    echo ""
    
    # DuckDNS 允许无 token 创建（使用 "none" 作为 token 可以创建临时域名）
    # 但更好的方式是使用 DuckDNS 的简化注册流程
    # 实际上 DuckDNS 支持用 email 获取 token
    
    echo -e "${YELLOW}DuckDNS 一键申请说明:${NC}"
    echo "  DuckDNS 需要 Token 才能更新域名。"
    echo "  请选择获取方式:"
    echo ""
    echo "  1. 我已经有 DuckDNS Token (直接输入)"
    echo "  2. 帮我打开 DuckDNS 注册页面 (获取 Token)"
    echo "  3. 使用临时方案 (IP直接访问，无需域名)"
    echo ""
    read -rp "请选择 [1-3]: " duck_choice
    
    case $duck_choice in
        1)
            # Loop until we get a non-empty token
            duck_token=""
            while [[ -z "$duck_token" ]]; do
                read -rp "请输入 DuckDNS Token: " duck_token
                # Trim whitespace
                duck_token=$(echo "$duck_token" | xargs)
                if [[ -z "$duck_token" ]]; then
                    warn "Token 不能为空，请重新输入"
                fi
            done
            
            # 尝试更新域名
            local RESULT=$(curl -s "https://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$duck_token&ip=$PUBLIC_IP")
            
            if [[ "$RESULT" == "OK" ]]; then
                log "DuckDNS 域名申请成功!"
            else
                warn "域名更新返回: $RESULT"
                warn "如果域名不存在，DuckDNS 会自动创建"
            fi
            
            # 保存配置
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
            echo -e "${GREEN}      DuckDNS 配置完成!${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${CYAN}域名:${NC} $DDNS_DOMAIN"
            echo -e "${CYAN}Token:${NC} $duck_token"
            echo -e "${CYAN}IP:${NC} $PUBLIC_IP"
            echo ""
            log "已添加自动更新定时任务 (每5分钟)"
            ;;
        2)
            echo ""
            echo -e "${CYAN}请按以下步骤获取 DuckDNS Token:${NC}"
            echo "  1. 打开 https://www.duckdns.org"
            echo "  2. 用 Google/GitHub/Reddit/Twitter 账号登录"
            echo "  3. 创建一个子域名 (例如: myvps)"
            echo "  4. 复制页面显示的 Token"
            echo "  5. 回到这里选择 '1. 我已经有 Token'"
            echo ""
            
            # 尝试用命令打开浏览器（如果可用）
            if command -v xdg-open &>/dev/null; then
                xdg-open "https://www.duckdns.org" 2>/dev/null || true
            fi
            
            read -rp "按回车键返回 DuckDNS 菜单..."
            setup_duckdns_auto
            return
            ;;
        3)
            echo ""
            info "使用公网IP直接访问..."
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}           服务器网络信息${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${CYAN}IPv4 地址:${NC} $PUBLIC_IP"
            echo ""
            echo -e "${YELLOW}提示:${NC} 安装 Shadowsocks 或 Hysteria2 时可以直接使用此IP"
            echo ""
            ;;
        *)
            warn "无效选择"
            sleep 2
            setup_duckdns_auto
            return
            ;;
    esac
    
    echo ""
    read -rp "按回车键继续..."
}

# DuckDNS - 手动配置（已有Token）
setup_duckdns() {
    echo ""
    info "DuckDNS 配置"
    echo "----------------------------------------"
    duck_token=""
    while [[ -z "$duck_token" ]]; do
        read -rp "请输入 DuckDNS Token: " duck_token
        duck_token=$(echo "$duck_token" | xargs)
        if [[ -z "$duck_token" ]]; then
            warn "Token 不能为空，请重新输入"
        fi
    done
    
    duck_domain=""
    while [[ -z "$duck_domain" ]]; do
        read -rp "请输入子域名 (例如: myvps): " duck_domain
        duck_domain=$(echo "$duck_domain" | xargs)
        if [[ -z "$duck_domain" ]]; then
            warn "子域名不能为空，请重新输入"
        fi
    done
    
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
    
    log "DuckDNS 配置完成! 域名: $DDNS_DOMAIN"
    echo ""
    read -rp "按回车键继续..."
}

# No-IP
setup_noip() {
    echo ""
    info "No-IP 配置"
    echo "----------------------------------------"
    noip_user=""
    while [[ -z "$noip_user" ]]; do
        read -rp "请输入 No-IP 用户名: " noip_user
        noip_user=$(echo "$noip_user" | xargs)
        if [[ -z "$noip_user" ]]; then
            warn "用户名不能为空，请重新输入"
        fi
    done
    
    noip_pass=""
    while [[ -z "$noip_pass" ]]; do
        read -rsp "请输入 No-IP 密码: " noip_pass
        echo ""
        noip_pass=$(echo "$noip_pass" | xargs)
        if [[ -z "$noip_pass" ]]; then
            warn "密码不能为空，请重新输入"
        fi
    done
    
    noip_host=""
    while [[ -z "$noip_host" ]]; do
        read -rp "请输入主机名 (例如: myvps.ddns.net): " noip_host
        noip_host=$(echo "$noip_host" | xargs)
        if [[ -z "$noip_host" ]]; then
            warn "主机名不能为空，请重新输入"
        fi
    done
    
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
    
    log "No-IP 配置完成! 域名: $DDNS_DOMAIN"
    echo ""
    read -rp "按回车键继续..."
}

# 获取或输入域名
get_domain() {
    local PROTOCOL_NAME=$1
    local NEED_DOMAIN=${2:-"yes"}
    
    # 如果协议不需要域名，直接返回IP
    if [[ "$NEED_DOMAIN" == "no" ]]; then
        local SERVER_IP=$(curl -s -4 https://api.ipify.org)
        echo "$SERVER_IP"
        return 0
    fi
    
    # 检查是否已有DDNS配置
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        if [[ -n "$DDNS_DOMAIN" ]]; then
            echo -e "${GREEN}检测到已配置域名: $DDNS_DOMAIN${NC}" >&2
            read -rp "使用此域名? [Y/n]: " use_existing
            if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            fi
        fi
    fi
    
    # 提供选择
    echo ""
    echo -e "${YELLOW}请选择域名来源:${NC}"
    echo "  1. 一键申请 DuckDNS (最无脑)"
    echo "  2. 使用自己的域名"
    echo "  3. 返回上一级"
    echo ""
    read -rp "请选择 [1-3]: " domain_choice
    
    case $domain_choice in
        1)
            setup_duckdns_auto
            if [[ -n "$DDNS_DOMAIN" ]]; then
                echo "$DDNS_DOMAIN"
                return 0
            else
                error "域名申请失败"
            fi
            ;;
        2)
            custom_domain=""
            while [[ -z "$custom_domain" ]]; do
                read -rp "请输入您的域名: " custom_domain
                custom_domain=$(echo "$custom_domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -z "$custom_domain" ]]; then
                    warn "域名不能为空，请重新输入"
                fi
            done
            echo "$custom_domain"
            return 0
            ;;
        3)
            return 1
            ;;
        *)
            error "无效选择"
            ;;
    esac
}

# ==================== WARP 功能 ====================

setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      WARP 一键配置${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if command -v warp-cli &>/dev/null; then
        info "WARP 已安装"
        echo ""
        echo "  1. 启动 WARP"
        echo "  2. 停止 WARP"
        echo "  3. 查看状态"
        echo "  4. 卸载 WARP"
        echo "  5. 返回主菜单"
        echo ""
        read -rp "请选择 [1-5]: " warp_choice
        
        case $warp_choice in
            1) warp-cli connect; log "WARP 已启动" ;;
            2) warp-cli disconnect; log "WARP 已停止" ;;
            3) warp-cli status ;;
            4) uninstall_warp ;;
            5) return ;;
        esac
        return
    fi
    
    echo -e "${YELLOW}请选择安装方式:${NC}"
    echo "  1. 官方 Cloudflare WARP (推荐)"
    echo "  2. WireGuard 模式 (wgcf)"
    echo "  3. 返回主菜单"
    echo ""
    read -rp "请选择 [1-3]: " warp_install_choice
    
    case $warp_install_choice in
        1) install_warp_official ;;
        2) install_warp_wgcf ;;
        3) return ;;
        *) warn "无效选择"; sleep 2; setup_warp ;;
    esac
}

install_warp_official() {
    log "正在安装 Cloudflare WARP..."
    
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
    
    log "WARP 安装并启动成功!"
    warp-cli status
    
    echo ""
    read -rp "按回车键继续..."
}

install_warp_wgcf() {
    log "正在安装 wgcf (WireGuard WARP)..."
    
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
    
    log "wgcf WARP 安装成功!"
    
    echo ""
    read -rp "按回车键继续..."
}

uninstall_warp() {
    log "正在卸载 WARP..."
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get remove -y cloudflare-warp
    else
        $PKG_MANAGER remove -y cloudflare-warp
    fi
    
    log "WARP 已卸载"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== Xray 核心安装 ====================

install_xray() {
    if command -v xray &>/dev/null; then
        log "Xray 已安装，版本: $(xray version | head -n1)"
        return 0
    fi
    
    log "正在安装 Xray 核心..."
    
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    log "Xray 安装完成"
}

# ==================== Vless 安装 (需要域名) ====================

install_vless() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Vless + Reality 安装${NC}"
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
    
    log "正在申请 SSL 证书..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --server letsencrypt
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
========== Vless 配置信息 ==========
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
    echo -e "${GREEN}      Vless 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vless-info.txt"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-qr.png" ]]; then
        echo -e "${CYAN}二维码已保存至: $CONFIG_DIR/vless-qr.png${NC}"
    fi
    
    echo ""
    log "Vless 安装完成!"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== Hysteria2 安装 (需要域名) ====================

install_hysteria2() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                      Hysteria2 安装${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Hysteria2")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "正在安装 Hysteria2..."
    
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
========== Hysteria2 配置信息 ==========
服务器地址: $DOMAIN
端口: $PORT
密码: $PASSWORD
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
    echo -e "${GREEN}      Hysteria2 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/hysteria2-info.txt"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo "$HY2_LINK"
    echo ""
    
    if [[ -f "$CONFIG_DIR/hysteria2-qr.png" ]]; then
        echo -e "${CYAN}二维码已保存至: $CONFIG_DIR/hysteria2-qr.png${NC}"
    fi
    
    echo ""
    log "Hysteria2 安装完成!"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== Shadowsocks 安装 (不需要域名) ====================

install_shadowsocks() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Shadowsocks 安装${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "正在安装 Shadowsocks..."
    
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
========== Shadowsocks 配置信息 ==========
服务器地址: $SERVER_IP
端口: $PORT
密码: $PASSWORD
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
    echo -e "${GREEN}      Shadowsocks 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/ss-info.txt"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo "$SS_LINK"
    echo ""
    
    log "Shadowsocks 安装完成!"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== VMess 安装 (需要域名) ====================

install_vmess() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    VMess + WebSocket 安装${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "VMess")
    if [[ $? -ne 0 ]]; then return; fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "正在申请 SSL 证书..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --server letsencrypt
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
========== VMess 配置信息 ==========
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
    echo -e "${GREEN}      VMess 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/vmess-info.txt"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo "$VMESS_LINK"
    echo ""
    
    log "VMess 安装完成!"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== Trojan 安装 (需要域名) ====================

install_trojan() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Trojan + WebSocket 安装${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local DOMAIN=$(get_domain "Trojan")
    if [[ $? -ne 0 ]]; then return; fi
    
    log "正在安装 Trojan..."
    
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
    
    log "正在申请 SSL 证书..."
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --server letsencrypt
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
========== Trojan 配置信息 ==========
服务器地址: $DOMAIN
端口: $PORT
密码: $PASSWORD
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
    echo -e "${GREEN}      Trojan 安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$CONFIG_DIR/trojan-info.txt"
    echo ""
    echo -e "${CYAN}分享链接:${NC}"
    echo "$TROJAN_LINK"
    echo ""
    
    log "Trojan 安装完成!"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== 查看配置 ====================

view_config() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    查看已安装服务配置${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-info.txt" ]]; then
        echo -e "${GREEN}[Vless 配置]${NC}"
        cat "$CONFIG_DIR/vless-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/vless-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-info.txt" ]]; then
        echo -e "${GREEN}[Hysteria2 配置]${NC}"
        cat "$CONFIG_DIR/hysteria2-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/hysteria2-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-info.txt" ]]; then
        echo -e "${GREEN}[Shadowsocks 配置]${NC}"
        cat "$CONFIG_DIR/ss-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/ss-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-info.txt" ]]; then
        echo -e "${GREEN}[VMess 配置]${NC}"
        cat "$CONFIG_DIR/vmess-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/vmess-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-info.txt" ]]; then
        echo -e "${GREEN}[Trojan 配置]${NC}"
        cat "$CONFIG_DIR/trojan-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/trojan-link.txt"
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


# ==================== 订阅链接 ====================

generate_subscription() {
    local SUB_CONTENT=""
    
    if [[ -f "$CONFIG_DIR/vless-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/vless-link.txt")\n"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/hysteria2-link.txt")\n"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/ss-link.txt")\n"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/vmess-link.txt")\n"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/trojan-link.txt")\n"
    fi
    
    if [[ -z "$SUB_CONTENT" ]]; then
        echo ""
        return 1
    fi
    
    # Remove trailing newline and base64 encode
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
        echo -e "${YELLOW}尚未安装任何代理服务，无法生成订阅链接${NC}"
        echo ""
        read -rp "按回车键继续..."
        return
    fi
    
    # Save subscription file
    echo "$SUB_B64" | base64 -d | base64 -w 0 > "$CONFIG_DIR/subscription.txt"
    
    local SERVER_IP=$(curl -s -4 https://api.ipify.org)
    
    echo -e "${GREEN}订阅链接 (Base64):${NC}"
    echo ""
    echo "$SUB_B64"
    echo ""
    echo -e "${CYAN}----------------------------------------${NC}"
    echo ""
    echo -e "${GREEN}在线订阅地址:${NC}"
    echo ""
    echo "  http://${SERVER_IP}:8080/sub"
    echo ""
    echo -e "${YELLOW}提示: 在支持订阅的客户端中粘贴 Base64 内容${NC}"
    echo -e "${YELLOW}或配置 Nginx/Caddy 将 $CONFIG_DIR/subscription.txt 作为静态文件提供${NC}"
    echo ""
    
    # Try to start a simple HTTP server for subscription
    if command -v python3 &>/dev/null; then
        if ! ss -tlnp | grep -q ':8080'; then
            echo -e "${GREEN}正在启动临时订阅服务 (端口 8080)...${NC}"
            mkdir -p /tmp/vps-sub
            echo "$SUB_B64" | base64 -d | base64 -w 0 > /tmp/vps-sub/sub
            nohup python3 -m http.server 8080 --directory /tmp/vps-sub >/dev/null 2>&1 &
            echo -e "${GREEN}订阅服务已启动，可通过 http://${SERVER_IP}:8080/sub 访问${NC}"
            echo ""
        fi
    fi
    
    read -rp "按回车键继续..."
}

# ==================== 卸载服务 ====================

uninstall_service() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                        卸载服务${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo "  1. 卸载 Vless"
    echo "  2. 卸载 Hysteria2"
    echo "  3. 卸载 Shadowsocks"
    echo "  4. 卸载 VMess"
    echo "  5. 卸载 Trojan"
    echo "  6. 卸载所有服务"
    echo "  7. 返回主菜单"
    echo ""
    read -rp "请选择 [1-7]: " uninstall_choice
    
    case $uninstall_choice in
        1)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/config.json
            rm -f "$CONFIG_DIR"/vless-*
            log "Vless 已卸载"
            ;;
        2)
            systemctl stop hysteria-server 2>/dev/null || true
            systemctl disable hysteria-server 2>/dev/null || true
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            rm -f "$CONFIG_DIR"/hysteria2-*
            log "Hysteria2 已卸载"
            ;;
        3)
            systemctl stop shadowsocks-libev 2>/dev/null || true
            systemctl disable shadowsocks-libev 2>/dev/null || true
            rm -f "$CONFIG_DIR"/ss-*
            log "Shadowsocks 已卸载"
            ;;
        4)
            systemctl stop xray 2>/dev/null || true
            systemctl disable xray 2>/dev/null || true
            rm -f /usr/local/etc/xray/vmess.json
            rm -f "$CONFIG_DIR"/vmess-*
            log "VMess 已卸载"
            ;;
        5)
            systemctl stop trojan-go 2>/dev/null || true
            systemctl disable trojan-go 2>/dev/null || true
            rm -rf /etc/trojan
            rm -f /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/trojan-*
            log "Trojan 已卸载"
            ;;
        6)
            systemctl stop xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            systemctl disable xray hysteria-server shadowsocks-libev trojan-go 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/hysteria /etc/trojan
            rm -f /usr/local/bin/xray /usr/local/bin/hysteria /usr/local/bin/trojan-go
            rm -f "$CONFIG_DIR"/*-info.txt "$CONFIG_DIR"/*-link.txt "$CONFIG_DIR"/*-qr.png
            log "所有服务已卸载"
            ;;
        7) return ;;
    esac
    
    echo ""
    read -rp "按回车键继续..."
}

# ==================== 主菜单 ====================

show_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${GREEN}           VPS Toolbox - 多功能一键部署工具 v2.0.0${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "  ${YELLOW}作者${NC}: Kitaro-Loked"
    echo -e "  ${YELLOW}仓库${NC}: https://github.com/Kitaro-Loked/VPS-Toolbox"
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
    echo -e "  ${YELLOW}[代理协议]${NC}"
    echo "    3. 安装 Vless + Reality (需要域名)"
    echo "    4. 安装 Hysteria2 (需要域名)"
    echo "    5. 安装 Shadowsocks (无需域名)"
    echo "    6. 安装 VMess + WebSocket (需要域名)"
    echo "    7. 安装 Trojan + WebSocket (需要域名)"
    echo ""
    echo -e "  ${YELLOW}[管理]${NC}"
    echo "    8. 查看所有配置"
    echo "    9. 生成订阅链接"
    echo "    10. 卸载服务"
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
        read -rp "请选择操作 [0-10]: " choice
        
        case $choice in
            1) setup_ddns ;;
            2) setup_warp ;;
            3) install_vless ;;
            4) install_hysteria2 ;;
            5) install_shadowsocks ;;
            6) install_vmess ;;
            7) install_trojan ;;
            8) view_config ;;
            9) show_subscription ;;
            10) uninstall_service ;;
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
