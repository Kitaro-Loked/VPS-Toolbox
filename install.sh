#!/bin/bash
# ============================================================
# VPS Toolbox - 一键部署脚本
# 功能: DDNS域名申请/Warp配置/Vless/Hysteria2/SS/VMess/Trojan
# 作者: VPS-Toolbox
# 版本: 1.0.0
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/vps-toolbox"
LOG_FILE="/var/log/vps-toolbox.log"
DDNS_DOMAIN=""
DDNS_TOKEN=""

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
    
    # 启动cron服务
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    log "基础依赖安装完成"
}

# ==================== DDNS 功能 ====================

# 申请DDNS域名
setup_ddns() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         DDNS 域名申请与管理${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}请选择 DDNS 服务商:${NC}"
    echo "  1. Cloudflare (推荐)"
    echo "  2. DuckDNS"
    echo "  3. No-IP"
    echo "  4. 返回主菜单"
    echo ""
    read -rp "请选择 [1-4]: " ddns_choice
    
    case $ddns_choice in
        1) setup_cloudflare_ddns ;;
        2) setup_duckdns ;;
        3) setup_noip ;;
        4) return ;;
        *) warn "无效选择"; sleep 2; setup_ddns ;;
    esac
}

# Cloudflare DDNS
setup_cloudflare_ddns() {
    echo ""
    info "Cloudflare DDNS 配置"
    echo "----------------------------------------"
    read -rp "请输入 Cloudflare API Token: " cf_token
    read -rp "请输入域名 (例如: example.com): " cf_domain
    read -rp "请输入子域名前缀 (例如: vps，留空使用根域名): " cf_subdomain
    
    if [[ -z "$cf_token" || -z "$cf_domain" ]]; then
        error "API Token 和域名不能为空"
    fi
    
    # 获取Zone ID
    log "正在获取 Zone ID..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$cf_domain" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
        error "无法获取 Zone ID，请检查 API Token 和域名"
    fi
    
    log "Zone ID: $ZONE_ID"
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me)
    if [[ -z "$PUBLIC_IP" ]]; then
        error "无法获取公网IP地址"
    fi
    
    # 设置完整域名
    if [[ -n "$cf_subdomain" ]]; then
        FULL_DOMAIN="${cf_subdomain}.${cf_domain}"
    else
        FULL_DOMAIN="$cf_domain"
    fi
    
    # 检查记录是否存在
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FULL_DOMAIN" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
        # 创建新记录
        log "创建 DNS 记录..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    else
        # 更新记录
        log "更新 DNS 记录..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FULL_DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null
    fi
    
    # 保存配置
    cat > "$CONFIG_DIR/ddns.conf" <<EOF
DDNS_PROVIDER=cloudflare
CF_TOKEN=$cf_token
CF_DOMAIN=$cf_domain
CF_SUBDOMAIN=$cf_subdomain
ZONE_ID=$ZONE_ID
FULL_DOMAIN=$FULL_DOMAIN
EOF
    
    # 创建DDNS更新脚本
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
    
    # 添加定时任务 (每5分钟检查一次)
    (crontab -l 2>/dev/null | grep -v "update-ddns"; echo "*/5 * * * * $CONFIG_DIR/update-ddns.sh >/dev/null 2>&1") | crontab -
    
    DDNS_DOMAIN="$FULL_DOMAIN"
    
    log "DDNS 配置完成!"
    log "域名: $FULL_DOMAIN"
    log "当前IP: $PUBLIC_IP"
    log "已添加自动更新定时任务 (每5分钟)"
    
    echo ""
    read -rp "按回车键继续..."
}

# DuckDNS
setup_duckdns() {
    echo ""
    info "DuckDNS 配置"
    echo "----------------------------------------"
    read -rp "请输入 DuckDNS Token: " duck_token
    read -rp "请输入子域名 (例如: myvps): " duck_domain
    
    if [[ -z "$duck_token" || -z "$duck_domain" ]]; then
        error "Token 和域名不能为空"
    fi
    
    FULL_DOMAIN="${duck_domain}.duckdns.org"
    PUBLIC_IP=$(curl -s -4 https://api.ipify.org)
    
    # 更新DuckDNS
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
    
    log "DuckDNS 配置完成! 域名: $FULL_DOMAIN"
    echo ""
    read -rp "按回车键继续..."
}

# No-IP
setup_noip() {
    echo ""
    info "No-IP 配置"
    echo "----------------------------------------"
    read -rp "请输入 No-IP 用户名: " noip_user
    read -rsp "请输入 No-IP 密码: " noip_pass
    echo ""
    read -rp "请输入主机名 (例如: myvps.ddns.net): " noip_host
    
    if [[ -z "$noip_user" || -z "$noip_pass" || -z "$noip_host" ]]; then
        error "所有字段都不能为空"
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
    
    log "No-IP 配置完成! 域名: $FULL_DOMAIN"
    echo ""
    read -rp "按回车键继续..."
}

# ==================== Warp 功能 ====================

setup_warp() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         WARP 一键配置${NC}"
    echo -e "${CYAN}========================================${NC}"
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
        # CentOS/RHEL/Fedora
        curl -s https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
        $PKG_MANAGER install -y cloudflare-warp
    fi
    
    # 注册并连接
    warp-cli registration new
    warp-cli connect
    
    # 设置模式为WARP+ (可选)
    warp-cli set-mode warp
    
    log "WARP 安装并启动成功!"
    warp-cli status
    
    echo ""
    read -rp "按回车键继续..."
}

install_warp_wgcf() {
    log "正在安装 wgcf (WireGuard WARP)..."
    
    # 安装 WireGuard
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get install -y wireguard wireguard-tools
    else
        $PKG_MANAGER install -y wireguard-tools
    fi
    
    # 下载 wgcf
    WGCF_VERSION=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION//v/}_linux_amd64"
    chmod +x /usr/local/bin/wgcf
    
    # 注册
    cd /etc/wireguard
    wgcf register --accept-tos
    wgcf generate
    
    # 配置 WireGuard
    cp wgcf-profile.conf /etc/wireguard/warp.conf
    
    # 启动
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
    
    # 使用官方脚本安装
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    log "Xray 安装完成"
}

# ==================== Vless 安装 ====================

install_vless() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Vless 一键安装${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 检查或获取域名
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}检测到已配置的DDNS域名: $FULL_DOMAIN${NC}"
        read -rp "是否使用此域名? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "请输入您的域名: " DDNS_DOMAIN
        fi
    else
        read -rp "请输入您的域名 (或先配置DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "域名不能为空"
    fi
    
    # 安装Xray
    install_xray
    
    # 生成配置
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local PRIVATE_KEY=$(xray x25519 | grep "Private key:" | awk '{print $3}')
    local PUBLIC_KEY=$(xray x25519 -i "$PRIVATE_KEY" | grep "Public key:" | awk '{print $3}')
    local SHORT_ID=$(openssl rand -hex 4)
    
    log "正在申请 SSL 证书..."
    
    # 安装acme.sh
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
    fi
    
    export PATH="$HOME/.acme.sh:$PATH"
    
    # 申请证书
    ~/.acme.sh/acme.sh --issue -d "$DDNS_DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DDNS_DOMAIN" \
        --key-file /usr/local/etc/xray/private.key \
        --fullchain-file /usr/local/etc/xray/cert.crt
    
    # 创建Vless配置
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
    
    # 创建TLS+WS备用配置 (更兼容)
    mkdir -p /usr/local/etc/xray
    
    # 重启Xray
    systemctl restart xray
    
    # 保存配置信息
    cat > "$CONFIG_DIR/vless-info.txt" <<EOF
========== Vless 配置信息 ==========
协议: Vless + Reality
服务器地址: $DDNS_DOMAIN
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
    
    # 生成分享链接
    local VLESS_LINK="vless://${UUID}@${DDNS_DOMAIN}:${PORT}?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Vless-Reality-$(hostname)"
    
    echo "$VLESS_LINK" > "$CONFIG_DIR/vless-link.txt"
    
    # 生成二维码
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$VLESS_LINK"
        qrencode -o "$CONFIG_DIR/vless-qr.png" "$VLESS_LINK"
    fi
    
    # 添加证书自动续签
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

# ==================== Hysteria2 安装 ====================

install_hysteria2() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Hysteria2 一键安装${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 检查域名
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}检测到已配置的DDNS域名: $FULL_DOMAIN${NC}"
        read -rp "是否使用此域名? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "请输入您的域名: " DDNS_DOMAIN
        fi
    else
        read -rp "请输入您的域名: " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "域名不能为空"
    fi
    
    log "正在安装 Hysteria2..."
    
    # 安装Hysteria2
    bash <(curl -fsSL https://get.hy2.sh/)
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local PASSWORD=$(openssl rand -base64 16)
    
    # 生成自签名证书 (Hysteria2推荐)
    mkdir -p /etc/hysteria
    openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key
    openssl req -new -x509 -days 3650 -key /etc/hysteria/server.key \
        -out /etc/hysteria/server.crt -subj "/CN=$DDNS_DOMAIN" \
        -addext "subjectAltName=DNS:$DDNS_DOMAIN"
    
    # 创建配置
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
    
    # 保存配置
    cat > "$CONFIG_DIR/hysteria2-info.txt" <<EOF
========== Hysteria2 配置信息 ==========
服务器地址: $DDNS_DOMAIN
端口: $PORT
密码: $PASSWORD
传输协议: udp
TLS: 自签名证书
SNI: $DDNS_DOMAIN
=======================================
EOF
    
    # 生成分享链接
    local HY2_LINK="hysteria2://${PASSWORD}@${DDNS_DOMAIN}:${PORT}?sni=${DDNS_DOMAIN}&insecure=1#Hysteria2-$(hostname)"
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

# ==================== Shadowsocks 安装 ====================

install_shadowsocks() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Shadowsocks 一键安装${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    log "正在安装 Shadowsocks..."
    
    # 安装 shadowsocks-libev
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
    
    # 保存配置
    cat > "$CONFIG_DIR/ss-info.txt" <<EOF
========== Shadowsocks 配置信息 ==========
服务器地址: $(curl -s -4 https://api.ipify.org)
端口: $PORT
密码: $PASSWORD
加密方式: $METHOD
=========================================
EOF
    
    # 生成分享链接
    local SS_LINK="ss://$(echo -n "$METHOD:$PASSWORD" | base64 -w 0)@$(curl -s -4 https://api.ipify.org):$PORT#SS-$(hostname)"
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

# ==================== VMess 安装 ====================

install_vmess() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         VMess 一键安装${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 检查域名
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}检测到已配置的DDNS域名: $FULL_DOMAIN${NC}"
        read -rp "是否使用此域名? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "请输入您的域名: " DDNS_DOMAIN
        fi
    else
        read -rp "请输入您的域名 (或先配置DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "域名不能为空"
    fi
    
    install_xray
    
    local PORT=$(shuf -i 10000-65000 -n 1)
    local UUID=$(xray uuid)
    local WS_PATH="/$(openssl rand -hex 8)"
    
    log "正在申请 SSL 证书..."
    
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
    
    # 使用单独的配置文件运行
    cp /usr/local/etc/xray/vmess.json /usr/local/etc/xray/config.json
    systemctl restart xray
    
    cat > "$CONFIG_DIR/vmess-info.txt" <<EOF
========== VMess 配置信息 ==========
服务器地址: $DDNS_DOMAIN
端口: $PORT
UUID: $UUID
额外ID: 0
传输协议: ws
WebSocket路径: $WS_PATH
TLS: 开启
====================================
EOF
    
    # 生成VMess链接
    local VMESS_JSON='{"v":"2","ps":"VMess-'$(hostname)'","add":"'$DDNS_DOMAIN'","port":"'$PORT'","id":"'$UUID'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$DDNS_DOMAIN'","path":"'$WS_PATH'","tls":"tls","sni":"'$DDNS_DOMAIN'"}'
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

# ==================== Trojan 安装 ====================

install_trojan() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         Trojan 一键安装${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 检查域名
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        source "$CONFIG_DIR/ddns.conf"
        echo -e "${GREEN}检测到已配置的DDNS域名: $FULL_DOMAIN${NC}"
        read -rp "是否使用此域名? [Y/n]: " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            DDNS_DOMAIN="$FULL_DOMAIN"
        else
            read -rp "请输入您的域名: " DDNS_DOMAIN
        fi
    else
        read -rp "请输入您的域名 (或先配置DDNS): " DDNS_DOMAIN
    fi
    
    if [[ -z "$DDNS_DOMAIN" ]]; then
        error "域名不能为空"
    fi
    
    log "正在安装 Trojan..."
    
    # 安装Trojan-go (推荐，支持更多特性)
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
    
    # 创建systemd服务
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
服务器地址: $DDNS_DOMAIN
端口: $PORT
密码: $PASSWORD
传输协议: websocket
WebSocket路径: $WS_PATH
TLS: 开启
SNI: $DDNS_DOMAIN
=====================================
EOF
    
    # 生成分享链接
    local TROJAN_LINK="trojan://${PASSWORD}@${DDNS_DOMAIN}:${PORT}?security=tls&sni=${DDNS_DOMAIN}&type=ws&host=${DDNS_DOMAIN}&path=${WS_PATH}#Trojan-$(hostname)"
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
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         查看已安装服务配置${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    if [[ -f "$CONFIG_DIR/vless-info.txt" ]]; then
        echo -e "${GREEN}【Vless 配置】${NC}"
        cat "$CONFIG_DIR/vless-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/vless-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-info.txt" ]]; then
        echo -e "${GREEN}【Hysteria2 配置】${NC}"
        cat "$CONFIG_DIR/hysteria2-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/hysteria2-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-info.txt" ]]; then
        echo -e "${GREEN}【Shadowsocks 配置】${NC}"
        cat "$CONFIG_DIR/ss-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/ss-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-info.txt" ]]; then
        echo -e "${GREEN}【VMess 配置】${NC}"
        cat "$CONFIG_DIR/vmess-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/vmess-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-info.txt" ]]; then
        echo -e "${GREEN}【Trojan 配置】${NC}"
        cat "$CONFIG_DIR/trojan-info.txt"
        echo ""
        echo -e "${CYAN}分享链接:${NC}"
        cat "$CONFIG_DIR/trojan-link.txt"
        echo ""
        echo "----------------------------------------"
    fi
    
    if [[ -f "$CONFIG_DIR/ddns.conf" ]]; then
        echo -e "${GREEN}【DDNS 配置】${NC}"
        cat "$CONFIG_DIR/ddns.conf"
        echo ""
    fi
    
    echo ""
    read -rp "按回车键继续..."
}

# ==================== 卸载服务 ====================

uninstall_service() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         卸载服务${NC}"
    echo -e "${CYAN}========================================${NC}"
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

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}           ${GREEN}VPS Toolbox - 多功能一键部署工具${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}【DDNS & 网络】${NC}                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   1. DDNS 域名申请与管理 (自动续签)                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   2. WARP 一键配置                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}【代理协议】${NC}                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   3. 安装 Vless + Reality (推荐)                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   4. 安装 Hysteria2 (推荐)                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   5. 安装 Shadowsocks                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   6. 安装 VMess + WebSocket                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   7. 安装 Trojan + WebSocket                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}【管理】${NC}                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   8. 查看所有配置                                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   9. 卸载服务                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   0. 退出脚本                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    check_root
    check_system
    install_dependencies
    
    while true; do
        show_menu
        read -rp "请选择操作 [0-9]: " choice
        
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

# 运行主函数
main "$@"
