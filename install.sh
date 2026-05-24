#!/bin/bash

# ============================================================

# VPS Toolbox - 一键部署脚本

# 功能: DDNS/WARP/Vless/Hysteria2/SS/VMess/HTTPS代理

# 作者: Kitaro-Loked

# 仓库: https://github.com/Kitaro-Loked/VPS-Toolbox

# 版本: 3.6.0

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
# 检查系统环境
check_system() {
    log "检查系统环境..."
    
    # 检查操作系统
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release 2>/dev/null || true
        OS=${ID:-unknown}
        VER=${VERSION_ID:-unknown}
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release 2>/dev/null || true
        OS=${DISTRIB_ID:-unknown}
        VER=${DISTRIB_RELEASE:-unknown}
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    # 检查架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        armv7l) ARCH=arm ;;
    esac
    
    log "系统: $OS $VER, 架构: $ARCH"
}

# 安装基础依赖
install_dependencies() {
    log "安装基础依赖..."
    
    local deps="curl wget git unzip jq socat cron dnsutils net-tools iproute2"
    
    if command -v apt-get &>/dev/null; then
        apt-get update >/dev/null 2>&1
        apt-get install -y $deps >/dev/null 2>&1 || true
    elif command -v yum &>/dev/null; then
        yum install -y $deps >/dev/null 2>&1 || true
    elif command -v dnf &>/dev/null; then
        dnf install -y $deps >/dev/null 2>&1 || true
    elif command -v apk &>/dev/null; then
        apk add --no-cache $deps >/dev/null 2>&1 || true
    fi
    
    # 确保 cron 服务运行
    if command -v systemctl &>/dev/null; then
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
        systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true
    fi
    
    log "依赖安装完成"
}


# IPv6-only 环境检测与自动处理

IS_IPV6_ONLY=false

# 检测是否为 IPv6-only 环境
check_ipv6_only() {
    local has_v4=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127\.0\.0\.1' | head -n1)
    local has_v6=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[\da-fA-F:]+' | grep -v '^::1$' | grep -v '^fe80' | head -n1)
    if [[ -z "$has_v4" && -n "$has_v6" ]]; then
        return 0
    fi
    return 1
}

# 自动安装 WARP (非交互式，用于 IPv6-only 环境)
# ==================== DDNS 动态域名解析功能 ====================
# 支持: Cloudflare / DuckDNS / No-IP / 阿里云 / 腾讯云 DNSPod

DDNS_CONFIG_DIR="$CONFIG_DIR/ddns"
DDNS_CONFIG_FILE="$DDNS_CONFIG_DIR/config.json"
DDNS_LOG_FILE="$DDNS_CONFIG_DIR/ddns.log"
DDNS_PID_FILE="$DDNS_CONFIG_DIR/ddns.pid"
DDNS_LAST_IP_FILE="$DDNS_CONFIG_DIR/last_ip"

# 初始化 DDNS 目录
init_ddns() {
    mkdir -p "$DDNS_CONFIG_DIR"
    [[ ! -f "$DDNS_CONFIG_FILE" ]] && echo "[]" > "$DDNS_CONFIG_FILE"
}

# 获取当前公网 IP
get_current_ip() {
    local ip_type="${1:-ipv4}"
    local ip=""
    
    if [[ "$ip_type" == "ipv6" ]]; then
        ip=$(curl -s --max-time 10 -6 https://api.ip.sb/geoip 2>/dev/null | jq -r '.ip' 2>/dev/null)
        [[ -z "$ip" || "$ip" == "null" ]] && ip=$(curl -s --max-time 10 -6 https://ipapi.co/json/ 2>/dev/null | jq -r '.ip' 2>/dev/null)
        [[ -z "$ip" || "$ip" == "null" ]] && ip=$(curl -s --max-time 10 -6 https://api6.ipify.org 2>/dev/null)
    else
        ip=$(curl -s --max-time 10 https://api.ip.sb/geoip 2>/dev/null | jq -r '.ip' 2>/dev/null)
        [[ -z "$ip" || "$ip" == "null" ]] && ip=$(curl -s --max-time 10 https://ipapi.co/json/ 2>/dev/null | jq -r '.ip' 2>/dev/null)
        [[ -z "$ip" || "$ip" == "null" ]] && ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
    fi
    
    echo "$ip"
}

# 记录 DDNS 日志
ddns_log() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" >> "$DDNS_LOG_FILE"
    # 限制日志大小
    if [[ -f "$DDNS_LOG_FILE" ]] && [[ $(wc -l < "$DDNS_LOG_FILE") -gt 500 ]]; then
        tail -n 200 "$DDNS_LOG_FILE" > "$DDNS_LOG_FILE.tmp"
        mv "$DDNS_LOG_FILE.tmp" "$DDNS_LOG_FILE"
    fi
}

# ---------- Cloudflare DDNS ----------
# 使用 Cloudflare API Token 更新 DNS 记录
cf_ddns_update() {
    local token="$1"
    local zone_id="$2"
    local record_name="$3"
    local record_type="${4:-A}"
    local ip="$5"
    local proxied="${6:-false}"
    
    if [[ -z "$token" || -z "$zone_id" || -z "$record_name" || -z "$ip" ]]; then
        echo "参数缺失"
        return 1
    fi
    
    # 获取现有记录
    local list_result=$(curl -s --max-time 15 \
        -X GET \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$record_name&type=$record_type" 2>/dev/null)
    
    local record_id=$(echo "$list_result" | jq -r '.result[0].id' 2>/dev/null)
    local current_content=$(echo "$list_result" | jq -r '.result[0].content' 2>/dev/null)
    
    # 如果记录已存在且 IP 相同，跳过
    if [[ "$current_content" == "$ip" ]]; then
        echo "IP 未变化，跳过更新"
        return 0
    fi
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        # 更新现有记录
        local update_result=$(curl -s --max-time 15 \
            -X PUT \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"proxied\":$proxied}" \
            "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" 2>/dev/null)
        
        if echo "$update_result" | jq -e '.success' >/dev/null 2>&1; then
            echo "更新成功"
            return 0
        else
            local error_msg=$(echo "$update_result" | jq -r '.errors[0].message' 2>/dev/null)
            echo "更新失败: ${error_msg:-未知错误}"
            return 1
        fi
    else
        # 创建新记录
        local create_result=$(curl -s --max-time 15 \
            -X POST \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"proxied\":$proxied,\"ttl\":120}" \
            "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" 2>/dev/null)
        
        if echo "$create_result" | jq -e '.success' >/dev/null 2>&1; then
            echo "创建成功"
            return 0
        else
            local error_msg=$(echo "$create_result" | jq -r '.errors[0].message' 2>/dev/null)
            echo "创建失败: ${error_msg:-未知错误}"
            return 1
        fi
    fi
}

# 获取 Cloudflare Zone ID
cf_get_zone_id() {
    local token="$1"
    local domain="$2"
    
    local result=$(curl -s --max-time 15 \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones?name=$domain" 2>/dev/null)
    
    echo "$result" | jq -r '.result[0].id' 2>/dev/null
}

# ---------- DuckDNS DDNS ----------
duckdns_update() {
    local domain="$1"
    local token="$2"
    local ip="$3"
    local ip_type="${4:-ipv4}"
    
    if [[ -z "$domain" || -z "$token" ]]; then
        echo "参数缺失"
        return 1
    fi
    
    local url="https://www.duckdns.org/update?domains=$domain&token=$token"
    [[ -n "$ip" ]] && url="$url&ip=$ip"
    [[ "$ip_type" == "ipv6" ]] && url="$url&ipv6=$ip"
    
    local result=$(curl -s --max-time 15 "$url" 2>/dev/null)
    
    if [[ "$result" == "OK" ]]; then
        echo "更新成功"
        return 0
    else
        echo "更新失败"
        return 1
    fi
}

# ---------- No-IP DDNS ----------
noip_update() {
    local hostname="$1"
    local username="$2"
    local password="$3"
    local ip="$4"
    
    if [[ -z "$hostname" || -z "$username" || -z "$password" ]]; then
        echo "参数缺失"
        return 1
    fi
    
    local url="https://dynupdate.no-ip.com/nic/update?hostname=$hostname"
    [[ -n "$ip" ]] && url="$url&myip=$ip"
    
    local result=$(curl -s --max-time 15 \
        -u "$username:$password" \
        "$url" 2>/dev/null)
    
    if [[ "$result" == *"good"* || "$result" == *"nochg"* ]]; then
        echo "更新成功"
        return 0
    else
        echo "更新失败: $result"
        return 1
    fi
}

# ---------- 阿里云 DDNS ----------
ali_ddns_update() {
    local access_key="$1"
    local access_secret="$2"
    local domain="$3"
    local rr="$4"
    local ip="$5"
    local record_type="${6:-A}"
    
    if [[ -z "$access_key" || -z "$access_secret" || -z "$domain" || -z "$ip" ]]; then
        echo "参数缺失"
        return 1
    fi
    
    # 阿里云 DNS API 需要签名，这里使用简化版
    # 实际生产环境需要完整的签名算法
    echo "阿里云 DDNS 需要完整签名实现，建议使用 Cloudflare"
    return 1
}

# ---------- 腾讯云 DNSPod ----------
dnspod_update() {
    local id="$1"
    local token="$2"
    local domain="$3"
    local sub_domain="$4"
    local ip="$5"
    local record_type="${6:-A}"
    
    if [[ -z "$id" || -z "$token" || -z "$domain" || -z "$ip" ]]; then
        echo "参数缺失"
        return 1
    fi
    
    # DNSPod API
    local login_token="${id},${token}"
    
    # 获取记录列表
    local list_result=$(curl -s --max-time 15 \
        -X POST \
        -d "login_token=$login_token&format=json&domain=$domain&sub_domain=$sub_domain&record_type=$record_type" \
        "https://dnsapi.cn/Record.List" 2>/dev/null)
    
    local record_id=$(echo "$list_result" | jq -r '.records[0].id' 2>/dev/null)
    local current_ip=$(echo "$list_result" | jq -r '.records[0].value' 2>/dev/null)
    
    # IP 未变化则跳过
    if [[ "$current_ip" == "$ip" ]]; then
        echo "IP 未变化，跳过更新"
        return 0
    fi
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        # 修改记录
        local modify_result=$(curl -s --max-time 15 \
            -X POST \
            -d "login_token=$login_token&format=json&domain=$domain&record_id=$record_id&sub_domain=$sub_domain&record_type=$record_type&record_line=默认&value=$ip" \
            "https://dnsapi.cn/Record.Modify" 2>/dev/null)
        
        if echo "$modify_result" | jq -e '.status.code == "1"' >/dev/null 2>&1; then
            echo "更新成功"
            return 0
        else
            echo "更新失败"
            return 1
        fi
    else
        # 创建记录
        local create_result=$(curl -s --max-time 15 \
            -X POST \
            -d "login_token=$login_token&format=json&domain=$domain&sub_domain=$sub_domain&record_type=$record_type&record_line=默认&value=$ip" \
            "https://dnsapi.cn/Record.Create" 2>/dev/null)
        
        if echo "$create_result" | jq -e '.status.code == "1"' >/dev/null 2>&1; then
            echo "创建成功"
            return 0
        else
            echo "创建失败"
            return 1
        fi
    fi
}

# ---------- 配置管理 ----------

# 添加 DDNS 配置
add_ddns_config() {
    local provider="$1"
    local domain="$2"
    local record="$3"
    local record_type="$4"
    local ip_type="$5"
    local interval="$6"
    local credentials="$7"
    
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
    local new_entry="{\"provider\":\"$provider\",\"domain\":\"$domain\",\"record\":\"$record\",\"record_type\":\"$record_type\",\"ip_type\":\"$ip_type\",\"interval\":$interval,\"credentials\":$credentials,\"enabled\":true,\"last_update\":\"\",\"last_ip\":\"\"}"
    
    local new_config=$(echo "$config" | jq ". + [$new_entry]" 2>/dev/null)
    if [[ -n "$new_config" ]]; then
        echo "$new_config" > "$DDNS_CONFIG_FILE"
        return 0
    fi
    return 1
}

# 删除 DDNS 配置
delete_ddns_config() {
    local index="$1"
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
    local new_config=$(echo "$config" | jq "del(.[$index])" 2>/dev/null)
    if [[ -n "$new_config" ]]; then
        echo "$new_config" > "$DDNS_CONFIG_FILE"
        return 0
    fi
    return 1
}

# 切换 DDNS 启用状态
toggle_ddns_config() {
    local index="$1"
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
    local new_config=$(echo "$config" | jq "if .[$index] then .[$index].enabled = (.[$index].enabled | not) else . end" 2>/dev/null)
    if [[ -n "$new_config" ]]; then
        echo "$new_config" > "$DDNS_CONFIG_FILE"
        return 0
    fi
    return 1
}

# ---------- DDNS 执行器 ----------

# 执行单个 DDNS 更新
run_single_ddns() {
    local index="$1"
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null)
    local entry=$(echo "$config" | jq -r ".[$index]" 2>/dev/null)
    
    if [[ -z "$entry" || "$entry" == "null" ]]; then
        ddns_log "配置 #$index 不存在"
        return 1
    fi
    
    local enabled=$(echo "$entry" | jq -r '.enabled' 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        return 0
    fi
    
    local provider=$(echo "$entry" | jq -r '.provider' 2>/dev/null)
    local domain=$(echo "$entry" | jq -r '.domain' 2>/dev/null)
    local record=$(echo "$entry" | jq -r '.record' 2>/dev/null)
    local record_type=$(echo "$entry" | jq -r '.record_type' 2>/dev/null)
    local ip_type=$(echo "$entry" | jq -r '.ip_type' 2>/dev/null)
    
    # 获取当前 IP
    local current_ip=$(get_current_ip "$ip_type")
    if [[ -z "$current_ip" ]]; then
        ddns_log "[$provider][$record.$domain] 获取 IP 失败"
        return 1
    fi
    
    # 检查 IP 是否变化
    local last_ip=$(echo "$entry" | jq -r '.last_ip' 2>/dev/null)
    if [[ "$current_ip" == "$last_ip" && -n "$last_ip" ]]; then
        return 0
    fi
    
    # 执行更新
    local result=""
    case "$provider" in
        cloudflare)
            local token=$(echo "$entry" | jq -r '.credentials.token' 2>/dev/null)
            local zone_id=$(echo "$entry" | jq -r '.credentials.zone_id' 2>/dev/null)
            local proxied=$(echo "$entry" | jq -r '.credentials.proxied // false' 2>/dev/null)
            result=$(cf_ddns_update "$token" "$zone_id" "$record.$domain" "$record_type" "$current_ip" "$proxied")
            ;;
        duckdns)
            local token=$(echo "$entry" | jq -r '.credentials.token' 2>/dev/null)
            result=$(duckdns_update "$record" "$token" "$current_ip" "$ip_type")
            ;;
        noip)
            local username=$(echo "$entry" | jq -r '.credentials.username' 2>/dev/null)
            local password=$(echo "$entry" | jq -r '.credentials.password' 2>/dev/null)
            result=$(noip_update "$record.$domain" "$username" "$password" "$current_ip")
            ;;
        dnspod)
            local id=$(echo "$entry" | jq -r '.credentials.id' 2>/dev/null)
            local token=$(echo "$entry" | jq -r '.credentials.token' 2>/dev/null)
            result=$(dnspod_update "$id" "$token" "$domain" "$record" "$current_ip" "$record_type")
            ;;
        *)
            ddns_log "[$provider] 未知服务商"
            return 1
            ;;
    esac
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$result" == *"成功"* ]]; then
        ddns_log "[$provider][$record.$domain] IP 更新: $last_ip -> $current_ip"
        # 更新配置中的 last_ip 和 last_update
        local new_config=$(echo "$config" | jq ".[$index].last_ip = \"$current_ip\" | .[$index].last_update = \"$timestamp\"" 2>/dev/null)
        [[ -n "$new_config" ]] && echo "$new_config" > "$DDNS_CONFIG_FILE"
        return 0
    else
        ddns_log "[$provider][$record.$domain] 更新失败: $result"
        return 1
    fi
}

# 运行所有启用的 DDNS
run_all_ddns() {
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
    local count=$(echo "$config" | jq 'length' 2>/dev/null || echo 0)
    
    if [[ "$count" == "0" ]]; then
        return 0
    fi
    
    ddns_log "开始批量更新 ($count 个配置)"
    
    for ((i=0; i<count; i++)); do
        run_single_ddns "$i"
    done
    
    ddns_log "批量更新完成"
}

# ---------- 定时任务 ----------

# 安装 systemd 定时服务
install_ddns_systemd() {
    local interval="${1:-5}"
    
    cat > /etc/systemd/system/vps-toolbox-ddns.service <<EOF
[Unit]
Description=VPS Toolbox DDNS Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'source $CONFIG_DIR/install.sh 2>/dev/null || true; run_all_ddns'
EOF

    cat > /etc/systemd/system/vps-toolbox-ddns.timer <<EOF
[Unit]
Description=VPS Toolbox DDNS Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=${interval}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable vps-toolbox-ddns.timer 2>/dev/null || true
    systemctl start vps-toolbox-ddns.timer 2>/dev/null || true
    
    ddns_log "systemd 定时任务已安装 (间隔: ${interval}分钟)"
}

# 安装 cron 定时任务
install_ddns_cron() {
    local interval="${1:-5}"
    
    # 删除旧任务
    crontab -l 2>/dev/null | grep -v "vps-toolbox-ddns" > /tmp/cron_backup 2>/dev/null || true
    
    # 添加新任务
    echo "*/$interval * * * * /bin/bash -c 'export CONFIG_DIR=$CONFIG_DIR; source $CONFIG_DIR/ddns/ddns.sh 2>/dev/null; run_all_ddns' >/dev/null 2>&1" >> /tmp/cron_backup
    crontab /tmp/cron_backup 2>/dev/null || true
    rm -f /tmp/cron_backup
    
    ddns_log "cron 定时任务已安装 (间隔: ${interval}分钟)"
}

# 卸载定时任务
uninstall_ddns_timer() {
    systemctl stop vps-toolbox-ddns.timer 2>/dev/null || true
    systemctl disable vps-toolbox-ddns.timer 2>/dev/null || true
    rm -f /etc/systemd/system/vps-toolbox-ddns.timer
    rm -f /etc/systemd/system/vps-toolbox-ddns.service
    systemctl daemon-reload 2>/dev/null || true
    
    crontab -l 2>/dev/null | grep -v "vps-toolbox-ddns" | crontab - 2>/dev/null || true
    
    ddns_log "定时任务已卸载"
}

# ---------- 交互式菜单 ----------

# 添加 Cloudflare 配置向导
add_cloudflare_wizard() {
    echo ""
    echo -e "${YELLOW}Cloudflare DDNS 配置${NC}"
    echo ""
    echo "需要以下信息:"
    echo "  1. API Token (从 Cloudflare 控制台获取)"
    echo "  2. Zone ID (域名对应的 Zone ID)"
    echo "  3. 域名 (如: example.com)"
    echo "  4. 记录名 (如: www 或 @)"
    echo "  5. 记录类型 (A 或 AAAA)"
    echo ""
    
    read -rp "API Token: " cf_token
    read -rp "Zone ID (留空自动获取): " cf_zone_id
    read -rp "域名 (如 example.com): " cf_domain
    read -rp "记录名 (如 www 或 @): " cf_record
    read -rp "记录类型 [A/AAAA] (默认 A): " cf_record_type
    read -rp "IP 类型 [ipv4/ipv6] (默认 ipv4): " cf_ip_type
    read -rp "更新间隔(分钟) [1-60] (默认 5): " cf_interval
    read -rp "是否开启 Cloudflare 代理 [true/false] (默认 false): " cf_proxied
    
    [[ -z "$cf_record_type" ]] && cf_record_type="A"
    [[ -z "$cf_ip_type" ]] && cf_ip_type="ipv4"
    [[ -z "$cf_interval" ]] && cf_interval=5
    [[ -z "$cf_proxied" ]] && cf_proxied="false"
    
    if [[ -z "$cf_token" || -z "$cf_domain" || -z "$cf_record" ]]; then
        echo -e "${RED}Token、域名和记录名不能为空${NC}"
        return 1
    fi
    
    # 自动获取 Zone ID
    if [[ -z "$cf_zone_id" ]]; then
        echo -e "${YELLOW}正在获取 Zone ID...${NC}"
        cf_zone_id=$(cf_get_zone_id "$cf_token" "$cf_domain")
        if [[ -z "$cf_zone_id" || "$cf_zone_id" == "null" ]]; then
            echo -e "${RED}获取 Zone ID 失败，请手动输入${NC}"
            return 1
        fi
        echo -e "${GREEN}Zone ID: $cf_zone_id${NC}"
    fi
    
    # 测试连接
    echo -e "${YELLOW}测试 API 连接...${NC}"
    local test_result=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $cf_token" \
        "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
    
    if ! echo "$test_result" | jq -e '.success' >/dev/null 2>&1; then
        echo -e "${RED}API Token 验证失败${NC}"
        return 1
    fi
    echo -e "${GREEN}API Token 验证通过${NC}"
    
    # 保存配置
    local credentials="{\"token\":\"$cf_token\",\"zone_id\":\"$cf_zone_id\",\"proxied\":$cf_proxied}"
    if add_ddns_config "cloudflare" "$cf_domain" "$cf_record" "$cf_record_type" "$cf_ip_type" "$cf_interval" "$credentials"; then
        echo -e "${GREEN}配置已保存${NC}"
        
        # 立即执行一次更新
        echo -e "${YELLOW}正在执行首次更新...${NC}"
        local config=$(cat "$DDNS_CONFIG_FILE")
        local index=$(echo "$config" | jq 'length - 1')
        run_single_ddns "$index"
        return 0
    else
        echo -e "${RED}配置保存失败${NC}"
        return 1
    fi
}

# 添加 DuckDNS 配置向导
add_duckdns_wizard() {
    echo ""
    echo -e "${YELLOW}DuckDNS 配置${NC}"
    echo ""
    echo "DuckDNS 是免费的动态域名服务"
    echo "官网: https://www.duckdns.org"
    echo ""
    
    read -rp "Token (从 duckdns.org 获取): " duck_token
    read -rp "子域名 (如: myhome -> myhome.duckdns.org): " duck_domain
    read -rp "IP 类型 [ipv4/ipv6] (默认 ipv4): " duck_ip_type
    read -rp "更新间隔(分钟) [1-60] (默认 5): " duck_interval
    
    [[ -z "$duck_ip_type" ]] && duck_ip_type="ipv4"
    [[ -z "$duck_interval" ]] && duck_interval=5
    
    if [[ -z "$duck_token" || -z "$duck_domain" ]]; then
        echo -e "${RED}Token 和子域名不能为空${NC}"
        return 1
    fi
    
    local credentials="{\"token\":\"$duck_token\"}"
    if add_ddns_config "duckdns" "$duck_domain.duckdns.org" "$duck_domain" "A" "$duck_ip_type" "$duck_interval" "$credentials"; then
        echo -e "${GREEN}配置已保存${NC}"
        
        echo -e "${YELLOW}正在执行首次更新...${NC}"
        local config=$(cat "$DDNS_CONFIG_FILE")
        local index=$(echo "$config" | jq 'length - 1')
        run_single_ddns "$index"
        return 0
    else
        echo -e "${RED}配置保存失败${NC}"
        return 1
    fi
}

# 添加 No-IP 配置向导
add_noip_wizard() {
    echo ""
    echo -e "${YELLOW}No-IP 配置${NC}"
    echo ""
    
    read -rp "用户名: " noip_user
    read -rp "密码: " noip_pass
    read -rp "主机名 (如: myhost.no-ip.biz): " noip_host
    read -rp "IP 类型 [ipv4/ipv6] (默认 ipv4): " noip_ip_type
    read -rp "更新间隔(分钟) [1-60] (默认 5): " noip_interval
    
    [[ -z "$noip_ip_type" ]] && noip_ip_type="ipv4"
    [[ -z "$noip_interval" ]] && noip_interval=5
    
    if [[ -z "$noip_user" || -z "$noip_pass" || -z "$noip_host" ]]; then
        echo -e "${RED}所有字段都不能为空${NC}"
        return 1
    fi
    
    local credentials="{\"username\":\"$noip_user\",\"password\":\"$noip_pass\"}"
    local domain=$(echo "$noip_host" | sed 's/^[^.]*\.//')
    local record=$(echo "$noip_host" | sed 's/\..*$//')
    
    if add_ddns_config "noip" "$domain" "$record" "A" "$noip_ip_type" "$noip_interval" "$credentials"; then
        echo -e "${GREEN}配置已保存${NC}"
        
        echo -e "${YELLOW}正在执行首次更新...${NC}"
        local config=$(cat "$DDNS_CONFIG_FILE")
        local index=$(echo "$config" | jq 'length - 1')
        run_single_ddns "$index"
        return 0
    else
        echo -e "${RED}配置保存失败${NC}"
        return 1
    fi
}

# 添加 DNSPod 配置向导
add_dnspod_wizard() {
    echo ""
    echo -e "${YELLOW}腾讯云 DNSPod 配置${NC}"
    echo ""
    
    read -rp "API ID: " dp_id
    read -rp "API Token: " dp_token
    read -rp "域名 (如: example.com): " dp_domain
    read -rp "子域名 (如: www 或 @): " dp_record
    read -rp "记录类型 [A/AAAA] (默认 A): " dp_record_type
    read -rp "IP 类型 [ipv4/ipv6] (默认 ipv4): " dp_ip_type
    read -rp "更新间隔(分钟) [1-60] (默认 5): " dp_interval
    
    [[ -z "$dp_record_type" ]] && dp_record_type="A"
    [[ -z "$dp_ip_type" ]] && dp_ip_type="ipv4"
    [[ -z "$dp_interval" ]] && dp_interval=5
    
    if [[ -z "$dp_id" || -z "$dp_token" || -z "$dp_domain" || -z "$dp_record" ]]; then
        echo -e "${RED}所有字段都不能为空${NC}"
        return 1
    fi
    
    local credentials="{\"id\":\"$dp_id\",\"token\":\"$dp_token\"}"
    if add_ddns_config "dnspod" "$dp_domain" "$dp_record" "$dp_record_type" "$dp_ip_type" "$dp_interval" "$credentials"; then
        echo -e "${GREEN}配置已保存${NC}"
        
        echo -e "${YELLOW}正在执行首次更新...${NC}"
        local config=$(cat "$DDNS_CONFIG_FILE")
        local index=$(echo "$config" | jq 'length - 1')
        run_single_ddns "$index"
        return 0
    else
        echo -e "${RED}配置保存失败${NC}"
        return 1
    fi
}

# 显示 DDNS 配置列表
show_ddns_list() {
    local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
    local count=$(echo "$config" | jq 'length' 2>/dev/null || echo 0)
    
    if [[ "$count" == "0" ]]; then
        echo -e "${YELLOW}暂无 DDNS 配置${NC}"
        return
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    DDNS 配置列表${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    echo "$config" | jq -r '.[] | "  [\(.enabled | if . then \"✓\" else \"✗\" end)] \(.provider) | \(.record).\(.domain) | \(.record_type) | IP:\(.ip_type) | 间隔:\(.interval)min | 上次:\(.last_update // \"从未\") | IP:\(.last_ip // \"-\")"' 2>/dev/null | nl -v 0
}

# 查看 DDNS 日志
show_ddns_logs() {
    if [[ ! -f "$DDNS_LOG_FILE" ]]; then
        echo -e "${YELLOW}暂无日志${NC}"
        return
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    DDNS 更新日志 (最近 50 条)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    tail -n 50 "$DDNS_LOG_FILE"
}

# DDNS 主菜单
setup_ddns() {
    init_ddns
    
    while true; do
        clear
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}              DDNS 动态域名解析管理${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        
        # 显示当前配置
        local config=$(cat "$DDNS_CONFIG_FILE" 2>/dev/null || echo "[]")
        local count=$(echo "$config" | jq 'length' 2>/dev/null || echo 0)
        
        if [[ "$count" -gt 0 ]]; then
            echo -e "${YELLOW}当前配置 (${count}个):${NC}"
            echo "$config" | jq -r '.[] | "  [\(.enabled | if . then \"✓\" else \"✗\" end)] \(.provider) | \(.record).\(.domain) | 上次:\(.last_update // \"从未\")"' 2>/dev/null
            echo ""
        fi
        
        echo -e "${YELLOW}操作选项:${NC}"
        echo "  1. 添加 Cloudflare DDNS"
        echo "  2. 添加 DuckDNS (免费)"
        echo "  3. 添加 No-IP"
        echo "  4. 添加 腾讯云 DNSPod"
        echo ""
        echo "  5. 查看配置列表"
        echo "  6. 启用/禁用配置"
        echo "  7. 删除配置"
        echo "  8. 立即执行更新"
        echo "  9. 查看更新日志"
        echo ""
        echo "  10. 安装定时任务 (systemd/cron)"
        echo "  11. 卸载定时任务"
        echo "  12. 查看当前公网 IP"
        echo ""
        echo "  0. 返回主菜单"
        echo ""
        
        read -rp "请选择 [0-12]: " ddns_choice
        
        case $ddns_choice in
            1)
                add_cloudflare_wizard
                echo ""
                read -rp "按回车键继续..."
                ;;
            2)
                add_duckdns_wizard
                echo ""
                read -rp "按回车键继续..."
                ;;
            3)
                add_noip_wizard
                echo ""
                read -rp "按回车键继续..."
                ;;
            4)
                add_dnspod_wizard
                echo ""
                read -rp "按回车键继续..."
                ;;
            5)
                show_ddns_list
                echo ""
                read -rp "按回车键继续..."
                ;;
            6)
                show_ddns_list
                echo ""
                read -rp "请输入要切换的配置编号: " toggle_idx
                if [[ "$toggle_idx" =~ ^[0-9]+$ ]]; then
                    if toggle_ddns_config "$toggle_idx"; then
                        echo -e "${GREEN}状态已切换${NC}"
                    else
                        echo -e "${RED}切换失败${NC}"
                    fi
                fi
                echo ""
                read -rp "按回车键继续..."
                ;;
            7)
                show_ddns_list
                echo ""
                read -rp "请输入要删除的配置编号: " del_idx
                if [[ "$del_idx" =~ ^[0-9]+$ ]]; then
                    if delete_ddns_config "$del_idx"; then
                        echo -e "${GREEN}配置已删除${NC}"
                    else
                        echo -e "${RED}删除失败${NC}"
                    fi
                fi
                echo ""
                read -rp "按回车键继续..."
                ;;
            8)
                echo -e "${YELLOW}正在执行更新...${NC}"
                run_all_ddns
                echo -e "${GREEN}更新完成${NC}"
                echo ""
                read -rp "按回车键继续..."
                ;;
            9)
                show_ddns_logs
                echo ""
                read -rp "按回车键继续..."
                ;;
            10)
                echo ""
                echo -e "${YELLOW}安装定时任务${NC}"
                read -rp "更新间隔(分钟) [默认5]: " timer_interval
                [[ -z "$timer_interval" ]] && timer_interval=5
                
                if command -v systemctl &>/dev/null; then
                    install_ddns_systemd "$timer_interval"
                    echo -e "${GREEN}systemd 定时任务已安装${NC}"
                else
                    install_ddns_cron "$timer_interval"
                    echo -e "${GREEN}cron 定时任务已安装${NC}"
                fi
                echo ""
                read -rp "按回车键继续..."
                ;;
            11)
                uninstall_ddns_timer
                echo -e "${GREEN}定时任务已卸载${NC}"
                echo ""
                read -rp "按回车键继续..."
                ;;
            12)
                echo ""
                echo -e "${YELLOW}正在获取公网 IP...${NC}"
                local v4_ip=$(get_current_ip "ipv4")
                local v6_ip=$(get_current_ip "ipv6")
                echo -e "  IPv4: ${GREEN}${v4_ip:-获取失败}${NC}"
                echo -e "  IPv6: ${GREEN}${v6_ip:-获取失败}${NC}"
                echo ""
                read -rp "按回车键继续..."
                ;;
            0)
                return
                ;;
            *)
                warn "无效选择"
                sleep 1
                ;;
        esac
    done
}

setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    WARP 网络配置${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}请选择 WARP 安装方式:${NC}"
    echo ""
    echo "  1. 官方 Cloudflare WARP (推荐，功能最全)"
    echo "     - 支持全局代理 / 分流模式"
    echo "     - 需要 TUN 模块支持"
    echo "     - 体积较大 (~200MB)"
    echo ""
    echo "  2. fscarmen WARP 脚本 (轻量，LXC兼容)"
    echo "     - 支持 WireGuard / WireProxy 模式"
    echo "     - 支持 IPv4/IPv6 双栈"
    echo "     - 自动适配内核版本"
    echo "     - LXC / OpenVZ 容器可用"
    echo ""
    echo "  3. 返回主菜单"
    echo ""
    read -rp "请选择 [1-3]: " warp_choice
    
    case $warp_choice in
        1) setup_warp_official ;;
        2) setup_warp_fscarmen ;;
        3) return ;;
        *) warn "无效选择" ;;
    esac
}

# 官方 Cloudflare WARP
setup_warp_official() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}              官方 Cloudflare WARP 安装${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "正在安装官方 Cloudflare WARP..."
    
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null || true
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
    apt-get update >/dev/null 2>&1 && apt-get install -y cloudflare-warp >/dev/null 2>&1 || true
    
    warp-cli registration new 2>/dev/null || true
    warp-cli connect 2>/dev/null || true
    
    log "官方 WARP 安装完成"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  warp-cli status     - 查看状态"
    echo "  warp-cli connect    - 连接"
    echo "  warp-cli disconnect - 断开"
    echo ""
    read -rp "按回车键继续..."
}

# fscarmen WARP 脚本 (轻量，LXC兼容)
setup_warp_fscarmen() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}            fscarmen WARP 脚本 (轻量版)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}即将运行 fscarmen 的 WARP 脚本...${NC}"
    echo ""
    echo -e "${GREEN}该脚本特点:${NC}"
    echo "  - 支持 LXC / OpenVZ 容器"
    echo "  - 自动检测内核版本，适配 wireguard / wireguard-go"
    echo "  - 支持 WARP+ / Teams 账户"
    echo "  - 支持 Netflix 解锁检测"
    echo ""
    echo -e "${YELLOW}安装后可用 warp 命令管理:${NC}"
    echo "  warp n   - 获取 WARP IP"
    echo "  warp o   - 临时关闭 WARP"
    echo "  warp u   - 卸载 WARP"
    echo "  warp 4   - 添加 IPv4 WARP"
    echo "  warp 6   - 添加 IPv6 WARP"
    echo "  warp d   - 添加双栈 WARP"
    echo "  warp c   - Socks5 代理模式"
    echo "  warp w   - WireProxy 模式"
    echo ""
    read -rp "确认安装? [Y/n]: " confirm
    
    if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
        log "正在下载并运行 fscarmen WARP 脚本..."
        echo ""
        bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh)
    fi
    
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

    cd /tmp 2>/dev/null || true

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh 2>/dev/null ||     curl -sL https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh -o reality.sh

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

    cd /tmp 2>/dev/null || true

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/hy2.sh 2>/dev/null ||     curl -sL https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/hy2.sh -o hy2.sh

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

    cd /tmp 2>/dev/null || true

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ss-rust.sh 2>/dev/null ||     curl -sL https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ss-rust.sh -o ss-rust.sh

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

    cd /tmp 2>/dev/null || true

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh 2>/dev/null ||     curl -sL https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh -o tcp-wss.sh

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

    cd /tmp 2>/dev/null || true

    wget -q https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/https.sh 2>/dev/null ||     curl -sL https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/https.sh -o https.sh

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

    

    if [[ -f "$DDNS_CONFIG_FILE" ]]; then
        local ddns_count=$(cat "$DDNS_CONFIG_FILE" | jq 'length' 2>/dev/null || echo 0)
        if [[ "$ddns_count" -gt 0 ]]; then
            echo -e "${GREEN}[DDNS 动态域名配置 (${ddns_count}个)]${NC}"
            cat "$DDNS_CONFIG_FILE" | jq -r '.[] | "  [\(.enabled | if . then "启用" else "禁用" end)] \(.provider) | \(.record).\(.domain) | 类型:\(.record_type) | 上次更新:\(.last_update // "从未") | 当前IP:\(.last_ip // "-")"' 2>/dev/null
            echo ""
        fi
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

    echo "  7. Rocky Linux 9"

    echo "  8. AlmaLinux 9"

    echo "  9. Windows Server 2022 (实验性)"

    echo ""

    echo "  10. 自定义镜像 URL"

    echo "  11. 返回主菜单"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

    read -rp "请选择 [1-11]: " dd_choice

    

    local install_args=""

    local distro=""

    local is_dd=0

    local image_url=""

    

    case $dd_choice in

        1) install_args="-debian 12"; distro="Debian 12" ;;

        2) install_args="-debian 11"; distro="Debian 11" ;;

        3) install_args="-ubuntu 24.04"; distro="Ubuntu 24.04" ;;

        4) install_args="-ubuntu 22.04"; distro="Ubuntu 22.04" ;;

        5) install_args="-centos 9"; distro="CentOS Stream 9" ;;

        6) install_args="-alpine 3.19"; distro="Alpine Linux" ;;

        7) install_args="-rockylinux 9"; distro="Rocky Linux 9" ;;

        8) install_args="-almalinux 9"; distro="AlmaLinux 9" ;;

        9)

            echo ""

            read -rp "请输入Windows镜像URL (直接回车使用默认镜像): " win_url

            if [[ -n "$win_url" ]]; then

                install_args="-windows 2022 --image \"$win_url\""

            else

                install_args="-windows 2022"

            fi

            distro="Windows Server 2022"

            ;;

        10)

            echo ""

            read -rp "请输入自定义镜像 URL: " custom_url

            if [[ -z "$custom_url" ]]; then

                warn "未输入镜像地址"

                return

            fi

            image_url="$custom_url"

            install_args="-dd \"$image_url\""

            distro="自定义系统"

            is_dd=1

            ;;

        11)

            return

            ;;

        *)

            warn "无效选择"

            return

            ;;

    esac

    

    if [[ -z "$install_args" ]]; then

        return

    fi

    

    echo ""

    echo -e "${RED}============================================================${NC}"

    echo -e "${RED}                     最终确认${NC}"

    echo -e "${RED}============================================================${NC}"

    echo ""

    echo -e "目标系统: ${YELLOW}${distro}${NC}"

    if [[ "$is_dd" -eq 1 ]]; then

        echo -e "镜像地址: ${YELLOW}${image_url}${NC}"

    fi

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

    

    # 下载并执行 InstallNET 脚本

    echo -e "${YELLOW}正在下载系统重装脚本...${NC}"

    cd /tmp 2>/dev/null || true

    

    local script_url="https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh"

    

    # 先下载脚本到本地，避免管道中失败无法检测

    if wget --no-check-certificate -qO /tmp/InstallNET.sh "$script_url"; then

        chmod +x /tmp/InstallNET.sh

        echo -e "${YELLOW}开始重装系统，请稍候...${NC}"

        echo -e "${YELLOW}默认密码: ${GREEN}LeitboGi0ro${NC}"

        echo ""

        eval "bash /tmp/InstallNET.sh $install_args"

    else

        error "下载重装脚本失败，请检查网络连接"

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
                # 检测包管理器
                local PKG_MANAGER=""
                if command -v apt &>/dev/null; then
                    PKG_MANAGER="apt"
                elif command -v yum &>/dev/null; then
                    PKG_MANAGER="yum"
                elif command -v dnf &>/dev/null; then
                    PKG_MANAGER="dnf"
                fi
                
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

                cd /tmp 2>/dev/null || true

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

        source "$bot_config" 2>/dev/null || true 2>/dev/null || true

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

                source "$bot_config" 2>/dev/null || true 2>/dev/null || true

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

    

    source "$bot_config" 2>/dev/null || true

    

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

    source "$bot_config" 2>/dev/null || true

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

    

    source "$bot_config" 2>/dev/null || true

    

    # 创建 Bot 处理脚本

    cat > /usr/local/bin/vps-toolbox-bot.sh <<'BOTSCRIPT'

#!/bin/bash

# VPS Toolbox Telegram Bot

source /etc/vps-toolbox/tgbot.conf 2>/dev/null || true

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

    

    source "$bot_config" 2>/dev/null || true

    

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

source "$BOT_CONFIG" 2>/dev/null || true

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
_get_machine_id() {
    if [[ -f /etc/machine-id ]]; then
        head -c 12 /etc/machine-id
    elif [[ -f /sys/class/net/eth0/address ]]; then
        cat /sys/class/net/eth0/address | tr -d ':' | head -c 12
    else
        hostname | md5sum | head -c 12
    fi
}

init_stats() {
    mkdir -p "$STATS_DIR"
    local machine_id=$(_get_machine_id)
    if [[ ! -f "$STATS_FILE" ]]; then
        echo "machine_id:${machine_id}" > "$STATS_FILE"
        echo "total:0" >> "$STATS_FILE"
        echo "today:0" >> "$STATS_FILE"
        echo "last_date:$(date +%Y%m%d)" >> "$STATS_FILE"
        echo "daily_record:" >> "$STATS_FILE"
    else
        # Check if machine changed
        local saved_id=$(grep "^machine_id:" "$STATS_FILE" | cut -d: -f2)
        if [[ -n "$saved_id" && "$saved_id" != "$machine_id" ]]; then
            # New machine, reset stats
            echo "machine_id:${machine_id}" > "$STATS_FILE"
            echo "total:0" >> "$STATS_FILE"
            echo "today:0" >> "$STATS_FILE"
            echo "last_date:$(date +%Y%m%d)" >> "$STATS_FILE"
            echo "daily_record:" >> "$STATS_FILE"
        fi
    fi
}

# 记录一次使用
record_usage() {
    init_stats
    
    local machine_id=$(_get_machine_id)
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
    
    # 写回文件 (保留 machine_id)
    cat > "$STATS_FILE" <<EOF
machine_id:${machine_id}
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
                    source "$bot_config" 2>/dev/null || true 2>/dev/null || true
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
                source "$bot_config" 2>/dev/null || true 2>/dev/null || true
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
    local now_ts=$(date +%s)
    
    # 检查 acme.sh 证书
    for cert in /root/.acme.sh/*/*.cer /home/*/.acme.sh/*/*.cer; do
        [[ ! -f "$cert" ]] && continue
        certs_found=true
        
        local end_date=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expire_ts=$(date -d "$end_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$end_date" +%s 2>/dev/null || echo "0")
        if [[ "$expire_ts" == "0" ]]; then
            continue
        fi
        local days_left=$(( (expire_ts - now_ts) / 86400 ))
        
        local domain=$(basename "$cert" .cer)
        if [[ $days_left -lt 7 ]]; then
            echo "CRITICAL|证书 $domain 将在 ${days_left} 天后过期|立即续签"
            warn_count=$((warn_count + 1))
        elif [[ $days_left -lt 30 ]]; then
            echo "WARN|证书 $domain 将在 ${days_left} 天后过期|建议续签"
            warn_count=$((warn_count + 1))
        fi
    done
    
    # 检查 letsencrypt
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        [[ ! -f "$cert" ]] && continue
        certs_found=true
        
        local end_date=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expire_ts=$(date -d "$end_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$end_date" +%s 2>/dev/null || echo "0")
        if [[ "$expire_ts" == "0" ]]; then
            continue
        fi
        local days_left=$(( (expire_ts - now_ts) / 86400 ))
        
        local domain=$(basename $(dirname "$cert"))
        if [[ $days_left -lt 7 ]]; then
            echo "CRITICAL|证书 $domain 将在 ${days_left} 天后过期|立即续签"
            warn_count=$((warn_count + 1))
        elif [[ $days_left -lt 30 ]]; then
            echo "WARN|证书 $domain 将在 ${days_left} 天后过期|建议续签"
            warn_count=$((warn_count + 1))
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
    local exposed_ports=0
    if command -v ss &>/dev/null; then
        exposed_ports=$(ss -tln 2>/dev/null | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -u | wc -l)
    elif command -v netstat &>/dev/null; then
        exposed_ports=$(netstat -tln 2>/dev/null | awk 'NR>2 {print $4}' | sed 's/.*://' | sort -u | wc -l)
    else
        echo "INFO|无法检测端口 (缺少 ss/netstat)|跳过"
        return 0
    fi
    
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
    local audit_log="/etc/vps-toolbox/audit.log"
    local audit_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p /etc/vps-toolbox
    echo "=== 安全审计报告 ${audit_time} ===" > "$audit_log"
    
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
        local check_name=${check_func/check_/}
        echo -n "  检查 ${check_name} ... "
        
        local result
        result=$($check_func 2>/dev/null) || result="ERROR|检查执行失败|请手动检查"
        
        # Handle multi-line results (take first line)
        local first_line=$(echo "$result" | head -n1)
        local level=$(echo "$first_line" | cut -d'|' -f1)
        local detail=$(echo "$first_line" | cut -d'|' -f2)
        local advice=$(echo "$first_line" | cut -d'|' -f3)
        
        # If parsing failed, treat as error
        if [[ -z "$level" || -z "$detail" ]]; then
            level="ERROR"
            detail="检查执行异常"
            advice="请检查系统环境"
        fi
        
        case "$level" in
            OK)
                echo -e "${GREEN}[✓]${NC} $detail"
                ok_count=$((ok_count + 1))
                echo "[OK] ${check_name}: $detail" >> "$audit_log"
                ;;
            WARN)
                echo -e "${YELLOW}[!]${NC} $detail"
                echo -e "      ${YELLOW}→ $advice${NC}"
                warn_count=$((warn_count + 1))
                echo "[WARN] ${check_name}: $detail → $advice" >> "$audit_log"
                ;;
            CRITICAL)
                echo -e "${RED}[✗]${NC} $detail"
                echo -e "      ${RED}→ $advice${NC}"
                critical_count=$((critical_count + 1))
                echo "[CRITICAL] ${check_name}: $detail → $advice" >> "$audit_log"
                ;;
            INFO|ERROR)
                echo -e "${CYAN}[i]${NC} $detail"
                info_count=$((info_count + 1))
                echo "[INFO] ${check_name}: $detail" >> "$audit_log"
                ;;
        esac
    done
    
    echo "" >> "$audit_log"
    echo "结果: ${ok_count} 通过 | ${warn_count} 警告 | ${critical_count} 严重 | ${info_count} 信息" >> "$audit_log"
    
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
                if [[ -f "/etc/vps-toolbox/audit.log" ]]; then
                    cat "/etc/vps-toolbox/audit.log"
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
    
    # 恢复 set -e（安全兜底）
    set -e
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

# ==================== IP 综合体检功能 (Pro版) ====================
# 对标 MediaUnlockTest / RegionRestrictionCheck 级别
# 50+ 检测项，包含：基础信息、流媒体解锁(25+)、IP风控、网络质量、游戏平台

IP_CHECK_DIR="/etc/vps-toolbox/ip-check"
IP_CHECK_HISTORY="$IP_CHECK_DIR/history.json"
IP_CHECK_CACHE="$IP_CHECK_DIR/cache"

# 颜色定义（局部）
CHK_GREEN="\033[1;32m"
CHK_RED="\033[1;31m"
CHK_YELLOW="\033[1;33m"
CHK_CYAN="\033[1;36m"
CHK_PURPLE="\033[1;35m"
CHK_NC="\033[0m"

# 状态图标
ICON_OK="${CHK_GREEN}✓${CHK_NC}"
ICON_FAIL="${CHK_RED}✗${CHK_NC}"
ICON_WARN="${CHK_YELLOW}△${CHK_NC}"
ICON_INFO="${CHK_CYAN}○${CHK_NC}"

# 初始化体检目录
init_ip_check() {
    mkdir -p "$IP_CHECK_DIR"
    mkdir -p "$IP_CHECK_CACHE"
    [[ ! -f "$IP_CHECK_HISTORY" ]] && echo "[]" > "$IP_CHECK_HISTORY"
}

# ============ 基础信息模块 ============

# 获取公网 IP 和基础信息
get_public_ip_info() {
    local ip=""
    local info=""
    
    # 尝试多个 API 获取 IP
    ip=$(curl -s --max-time 8 https://api.ip.sb/geoip 2>/dev/null | grep -oP '"ip":"\K[^"]+' | head -1)
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 8 https://ipapi.co/json/ 2>/dev/null | grep -oP '"ip":"\K[^"]+' | head -1)
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 8 http://ip-api.com/json/?fields=query 2>/dev/null | grep -oP '"query":"\K[^"]+' | head -1)
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null)
    
    echo "$ip"
}

# 获取详细 IP 信息 (使用 ip-api.com，免费，45次/分钟)
get_ip_details() {
    local ip="$1"
    local data=""
    
    if [[ -n "$ip" ]]; then
        data=$(curl -s --max-time 10 "http://ip-api.com/json/${ip}?fields=status,message,country,countryCode,region,regionName,city,zip,lat,lon,timezone,isp,org,as,asname,proxy,hosting,query" 2>/dev/null)
    fi
    
    # 备用：ipapi.co
    if [[ -z "$data" || "$data" == *'"status":"fail"'* ]]; then
        local backup=$(curl -s --max-time 10 "https://ipapi.co/json/" 2>/dev/null)
        if [[ -n "$backup" ]]; then
            data="$backup"
        fi
    fi
    
    echo "$data"
}

# 获取 ASN 信息
get_asn_info() {
    local ip="$1"
    local asn_data=""
    
    # 使用 ipinfo.io (lite 版免费)
    if [[ -n "$ip" ]]; then
        asn_data=$(curl -s --max-time 8 "https://api.ipinfo.io/lite/$ip" 2>/dev/null)
    fi
    
    echo "$asn_data"
}

# 反向 DNS 查询
check_reverse_dns() {
    local ip="$1"
    local hostname=""
    
    if [[ -n "$ip" ]]; then
        hostname=$(host "$ip" 2>/dev/null | grep -oP 'domain name pointer \K[^.]+.*' | head -1)
        [[ -z "$hostname" ]] && hostname=$(dig +short -x "$ip" 2>/dev/null | head -1 | sed 's/\.$//')
    fi
    
    echo "$hostname"
}

# 判断是否为数据中心 IP
is_datacenter_ip() {
    local asn="$1"
    local org="$2"
    local hostname="$3"
    
    local dc_asns="AS16509|AS14618|AS15169|AS19527|AS8075|AS8068|AS14061|AS63949|AS20473|AS16276|AS24940|AS45102|AS45090|AS37963|AS132203|AS136907|AS13335|AS31898|AS36351|AS51167|AS12876|AS214996|AS9009|AS60068|AS53667"
    local dc_keywords="amazon|aws|google|cloud|azure|digitalocean|linode|vultr|ovh|hetzner|aliyun|alibaba|tencent|huawei|cloudflare|oracle|ibm|softlayer|choopa|contabo|scaleway|rackspace|godaddy|hostinger|m247|cdn77|frantech|server|hosting|datacenter|vps|dedicated"
    
    if [[ -n "$asn" && "$asn" =~ $dc_asns ]]; then
        echo "true"
        return
    fi
    
    local combined="${org,,} ${hostname,,}"
    if echo "$combined" | grep -qiE "$dc_keywords"; then
        echo "true"
        return
    fi
    
    echo "false"
}

# ============ 流媒体解锁模块 (基于 RegionRestrictionCheck) ============
# 使用正确的检测逻辑，不是简单的 HTTP 状态码判断

# 统一的 User-Agent
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
UA_MOBILE="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

# ---------- Netflix 检测 ----------
# 原理：访问非自制剧(70143836=复仇者联盟)，200=原生解锁，404=仅自制剧，其他=不可用
check_netflix_pro() {
    local tmpfile=$(mktemp)
    local result=$(curl -s --max-time 15 \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Accept: text/html,application/xhtml+xml" \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.netflix.com/title/70143836" 2>/dev/null)
    
    echo "$result" > "$tmpfile"
    
    # 检查是否包含 "Sorry, Netflix is not available in your country yet"
    if grep -qi "not available in your country" "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        echo "不可用"
        return
    fi
    
    # 检查是否包含 "Netflix Site Error" 或访问被阻止
    if grep -qi "site error\|access denied\|blocked" "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        echo "不可用"
        return
    fi
    
    # 检查页面内容是否包含视频信息（非自制剧能访问到详情页）
    if grep -qi "title.*avengers\|video-title\|playback" "$tmpfile" 2>/dev/null; then
        # 尝试获取地区
        local region=$(curl -s --max-time 10 \
            -H "Accept-Language: en-US" \
            -H "User-Agent: $UA_BROWSER" \
            --url "https://www.netflix.com" 2>/dev/null | \
            grep -oP '"country":"\K[A-Z]{2}' | head -1)
        rm -f "$tmpfile"
        if [[ -n "$region" ]]; then
            echo "原生解锁 ($region)"
        else
            echo "原生解锁"
        fi
        return
    fi
    
    # 如果能访问但找不到视频信息，可能是自制剧-only
    local http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.netflix.com/title/70143836" 2>/dev/null)
    
    rm -f "$tmpfile"
    
    if [[ "$http_code" == "200" ]]; then
        # 能访问但可能只有自制剧
        echo "仅自制剧"
    elif [[ "$http_code" == "404" || "$http_code" == "403" ]]; then
        echo "仅自制剧"
    else
        echo "不可用"
    fi
}

# ---------- Disney+ 检测 ----------
# 原理：访问 Disney+，检查是否重定向到登录页或地区选择页
check_disney_pro() {
    local result=$(curl -s --max-time 12 -L \
        -H "Accept-Language: en-US" \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.disneyplus.com" 2>/dev/null)
    
    # 检查是否包含地区限制信息
    if echo "$result" | grep -qi "not available\|unavailable\|region\|country"; then
        # 进一步检查是否是正常的地区页面
        if echo "$result" | grep -qi "disney\|login\|signup"; then
            local region=$(echo "$result" | grep -oP '"country":"\K[A-Z]{2}' | head -1)
            if [[ -n "$region" ]]; then
                echo "解锁 ($region)"
            else
                echo "解锁"
            fi
        else
            echo "不可用"
        fi
    elif echo "$result" | grep -qi "disney"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- YouTube Premium 检测 ----------
# 原理：访问 YouTube Premium 页面，检查是否显示价格和地区
check_youtube_pro() {
    local result=$(curl -s --max-time 12 \
        -H "Accept-Language: en-US" \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.youtube.com/premium" 2>/dev/null)
    
    # 检查是否包含 Premium 相关信息
    if echo "$result" | grep -qi "premium\|YouTube Premium"; then
        # 尝试获取地区代码
        local region=$(echo "$result" | grep -oP 'countryCode":"\K[A-Z]{2}' | head -1)
        if [[ -z "$region" ]]; then
            region=$(echo "$result" | grep -oP '"gl":"\K[A-Z]{2}' | head -1)
        fi
        if [[ -n "$region" ]]; then
            echo "Premium ($region)"
        else
            echo "Premium"
        fi
    else
        echo "不可用"
    fi
}

# ---------- YouTube CDN 区域 ----------
check_youtube_cdn() {
    local result=$(curl -s --max-time 8 -o /dev/null -w "%{redirect_url}" \
        -H "User-Agent: $UA_BROWSER" \
        --url "http://www.youtube.com/red" 2>/dev/null)
    local region=$(echo "$result" | grep -oP 'gl=\K[A-Z]{2}' | head -1)
    if [[ -n "$region" ]]; then
        echo "$region"
    else
        echo "未知"
    fi
}

# ---------- HBO Max 检测 ----------
check_hbo_max() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.max.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "max\|hbo\|stream"; then
        if echo "$result" | grep -qi "not available\|unavailable"; then
            echo "不可用"
        else
            echo "解锁"
        fi
    else
        echo "不可用"
    fi
}

# ---------- Hulu 检测 ----------
check_hulu() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.hulu.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "hulu\|watch"; then
        if echo "$result" | grep -qi "not available\|unavailable\|region"; then
            echo "不可用"
        else
            echo "解锁"
        fi
    else
        echo "不可用"
    fi
}

# ---------- Amazon Prime Video 检测 ----------
check_prime_video() {
    local result=$(curl -s --max-time 12 -L \
        -H "Accept-Language: en-US" \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.primevideo.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "primevideo\|prime video"; then
        local region=$(echo "$result" | grep -oP '"currentTerritory":"\K[A-Z]{2}' | head -1)
        if [[ -n "$region" ]]; then
            echo "解锁 ($region)"
        else
            echo "解锁"
        fi
    else
        echo "不可用"
    fi
}

# ---------- Paramount+ 检测 ----------
check_paramount() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.paramountplus.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "paramount\|stream"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- Apple TV+ 检测 ----------
check_apple_tv() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://tv.apple.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "apple tv\|tv.apple"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- Discovery+ 检测 ----------
check_discovery() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.discoveryplus.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "discovery\|stream"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- Spotify 检测 ----------
check_spotify() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.spotify.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "spotify"; then
        local region=$(echo "$result" | grep -oP 'country":"\K[A-Z]{2}' | head -1)
        if [[ -n "$region" ]]; then
            echo "解锁 ($region)"
        else
            echo "解锁"
        fi
    else
        echo "不可用"
    fi
}

# ---------- BBC iPlayer 检测 ----------
check_bbc() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.bbc.co.uk/iplayer" 2>/dev/null)
    
    if echo "$result" | grep -qi "bbc\|iplayer"; then
        if echo "$result" | grep -qi "not available\|outside the uk"; then
            echo "不可用"
        else
            echo "解锁"
        fi
    else
        echo "不可用"
    fi
}

# ---------- Abema TV 检测 ----------
check_abema() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://abema.tv" 2>/dev/null)
    
    if echo "$result" | grep -qi "abema"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- DMM 检测 ----------
check_dmm() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.dmm.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "dmm"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- TVB 检测 ----------
check_tvb() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.mytvsuper.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "mytvsuper\|tvb"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- Viu 检测 ----------
check_viu() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.viu.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "viu"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- ChatGPT 检测 ----------
# 原理：访问 ChatGPT 登录页，检查是否返回 200 且不是封锁页面
check_chatgpt_pro() {
    local result=$(curl -s --max-time 12 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://chat.openai.com" 2>/dev/null)
    
    # 检查是否被封锁
    if echo "$result" | grep -qi "not available\|access denied\|blocked\|unsupported country"; then
        echo "不可用"
        return
    fi
    
    # 检查是否正常页面
    if echo "$result" | grep -qi "chatgpt\|openai\|login\|signin"; then
        echo "可用"
    else
        echo "不可用"
    fi
}

# ---------- Claude 检测 ----------
check_claude() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://claude.ai" 2>/dev/null)
    
    if echo "$result" | grep -qi "not available\|unavailable\|region"; then
        echo "不可用"
    elif echo "$result" | grep -qi "claude\|anthropic"; then
        echo "可用"
    else
        echo "不可用"
    fi
}

# ---------- Google Gemini 检测 ----------
check_gemini() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://gemini.google.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "not available\|unavailable"; then
        echo "不可用"
    elif echo "$result" | grep -qi "gemini\|google"; then
        echo "可用"
    else
        echo "不可用"
    fi
}

# ---------- TikTok 检测 ----------
check_tiktok_pro() {
    local result=$(curl -s --max-time 12 -L \
        -H "User-Agent: $UA_MOBILE" \
        --url "https://www.tiktok.com" 2>/dev/null)
    
    # 检查地区信息
    local region=$(echo "$result" | grep -oP '"region":"\K[A-Z]{2}' | head -1)
    if [[ -z "$region" ]]; then
        region=$(echo "$result" | grep -oP 'region=\K[A-Z]{2}' | head -1)
    fi
    
    if [[ -n "$region" ]]; then
        echo "解锁 ($region)"
    elif echo "$result" | grep -qi "tiktok\|foryou"; then
        echo "解锁"
    else
        echo "不可用"
    fi
}

# ---------- Instagram 检测 ----------
check_instagram() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://www.instagram.com" 2>/dev/null)
    
    if echo "$result" | grep -qi "instagram\|login"; then
        echo "可用"
    else
        echo "不可用"
    fi
}

# ---------- Wikipedia 检测 ----------
check_wikipedia() {
    local result=$(curl -s --max-time 10 -L \
        -H "User-Agent: $UA_BROWSER" \
        --url "https://zh.wikipedia.org" 2>/dev/null)
    
    if echo "$result" | grep -qi "wikipedia\|维基百科"; then
        echo "可用"
    else
        echo "不可用"
    fi
}

# ============ IP 风控模块 ============

# 使用 ip-api 检测代理/托管标记
check_ip_api_proxy() {
    local ip="$1"
    local data=""
    
    if [[ -n "$ip" ]]; then
        data=$(curl -s --max-time 8 "http://ip-api.com/json/${ip}?fields=proxy,hosting,query" 2>/dev/null)
    fi
    
    echo "$data"
}

# 检测 IP 风险评分 (综合多个免费源)
check_ip_risk() {
    local ip="$1"
    local risk_score=0
    local risk_reasons=""
    local is_proxy="false"
    local is_hosting="false"
    local is_vpn="false"
    local is_tor="false"
    
    # 1. ip-api.com 检测
    local ipapi_data=$(check_ip_api_proxy "$ip")
    if [[ -n "$ipapi_data" ]]; then
        if echo "$ipapi_data" | grep -q '"proxy":true'; then
            is_proxy="true"
            risk_score=$((risk_score + 30))
            risk_reasons="$risk_reasons 代理/VPN/Tor"
        fi
        if echo "$ipapi_data" | grep -q '"hosting":true'; then
            is_hosting="true"
            risk_score=$((risk_score + 20))
            risk_reasons="$risk_reasons 托管/数据中心"
        fi
    fi
    
    # 2. 通过反向 DNS 判断
    local hostname=$(check_reverse_dns "$ip")
    if [[ -n "$hostname" ]]; then
        if echo "$hostname" | grep -qiE "amazon|aws|google|cloud|azure|digitalocean|linode|vultr|ovh|hetzner|aliyun|tencent|server|hosting|vps|datacenter"; then
            if [[ "$is_hosting" == "false" ]]; then
                is_hosting="true"
                risk_score=$((risk_score + 15))
                risk_reasons="$risk_reasons 数据中心(反向DNS)"
            fi
        fi
    fi
    
    # 3. 简单黑名单检测 (通过 httpbin 测试)
    local cf_test=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
        --url "https://httpbin.org/get" 2>/dev/null)
    if [[ "$cf_test" == "403" ]]; then
        risk_score=$((risk_score + 25))
        risk_reasons="$risk_reasons Cloudflare挑战"
    fi
    
    # 限制分数
    if [[ $risk_score -gt 100 ]]; then risk_score=100; fi
    
    # 输出结果
    echo "{\"score\":$risk_score,\"proxy\":$is_proxy,\"hosting\":$is_hosting,\"vpn\":$is_vpn,\"tor\":$is_tor,\"reasons\":\"$risk_reasons\",\"hostname\":\"$hostname\"}"
}

# 真人度评分计算
calculate_human_score() {
    local risk_data="$1"
    local dc_result="$2"
    local score=100
    local factors=""
    
    local risk_score=$(echo "$risk_data" | grep -oP '"score":\K[0-9]+' | head -1)
    local is_proxy=$(echo "$risk_data" | grep -oP '"proxy":\K[a-z]+' | head -1)
    local is_hosting=$(echo "$risk_data" | grep -oP '"hosting":\K[a-z]+' | head -1)
    
    # 代理/VPN 扣分
    if [[ "$is_proxy" == "true" ]]; then
        score=$((score - 35))
        factors="$factors 代理/VPN(-35)"
    fi
    
    # 托管/数据中心扣分
    if [[ "$is_hosting" == "true" || "$dc_result" == "true" ]]; then
        score=$((score - 25))
        factors="$factors 数据中心(-25)"
    fi
    
    # 风险评分扣分
    if [[ "$risk_score" -gt 50 ]]; then
        score=$((score - 20))
        factors="$factors 高风险(-20)"
    elif [[ "$risk_score" -gt 20 ]]; then
        score=$((score - 10))
        factors="$factors 中风险(-10)"
    fi
    
    # 确保范围
    if [[ $score -lt 0 ]]; then score=0; fi
    if [[ $score -gt 100 ]]; then score=100; fi
    
    echo "$score"
}

# ============ 网络质量模块 ============

# 检测到指定目标的延迟和丢包
check_ping() {
    local target="$1"
    local name="$2"
    local count="${3:-4}"
    
    local result=$(ping -c "$count" -W 2 "$target" 2>/dev/null)
    local avg=$(echo "$result" | tail -1 | grep -oP '\d+\.\d+' | head -1)
    local loss=$(echo "$result" | grep -oP '\d+(?=\% packet loss)' | head -1)
    
    if [[ -n "$avg" ]]; then
        echo "${name}:${avg}ms:${loss:-0}%"
    else
        echo "${name}:超时:100%"
    fi
}

# 三网质量检测
check_network_quality_pro() {
    local results=""
    
    # 电信
    results="$results$(check_ping "219.141.136.12" "电信北京") "
    results="$results$(check_ping "202.96.209.133" "电信上海") "
    
    # 联通
    results="$results$(check_ping "61.135.169.121" "联通北京") "
    results="$results$(check_ping "221.179.38.100" "联通广州") "
    
    # 移动
    results="$results$(check_ping "223.5.5.5" "移动阿里DNS") "
    results="$results$(check_ping "114.114.114.114" "电信114DNS") "
    
    # 国际
    results="$results$(check_ping "8.8.8.8" "Google DNS") "
    results="$results$(check_ping "1.1.1.1" "Cloudflare DNS") "
    
    echo "$results"
}

# 带宽估算 (通过下载测试)
check_bandwidth() {
    local speed=""
    
    # 使用 cachefly 测速
    local start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    curl -s --max-time 10 -o /dev/null \
        --url "http://cachefly.cachefly.net/10mb.test" 2>/dev/null
    local end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    
    # 简化：返回是否通畅
    if [[ $? -eq 0 ]]; then
        echo "通畅"
    else
        echo "受限"
    fi
}

# DNS 解析测试
check_dns() {
    local domains=("google.com" "github.com" "youtube.com" "netflix.com")
    local ok_count=0
    
    for domain in "${domains[@]}"; do
        local result=$(dig +short "$domain" 2>/dev/null | head -1)
        if [[ -n "$result" ]]; then
            ok_count=$((ok_count + 1))
        fi
    done
    
    echo "$ok_count/${#domains}"
}

# IPv6 连通性测试
check_ipv6_connectivity() {
    local result=$(curl -s --max-time 8 -6 -o /dev/null -w "%{http_code}" \
        --url "https://ipv6.google.com" 2>/dev/null)
    
    if [[ "$result" == "200" || "$result" == "302" ]]; then
        echo "通畅"
    else
        echo "不可用"
    fi
}

# ============ 游戏平台模块 ============

check_game_platform() {
    local name="$1"
    local url="$2"
    local pattern="${3:-}"
    
    local result=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
        --url "$url" 2>/dev/null)
    
    if [[ "$result" == "200" || "$result" == "302" ]]; then
        if [[ -n "$pattern" ]]; then
            local body=$(curl -s --max-time 8 --url "$url" 2>/dev/null)
            if echo "$body" | grep -qiE "$pattern"; then
                echo "可用"
            else
                echo "不可用"
            fi
        else
            echo "可用"
        fi
    else
        echo "不可用"
    fi
}

# Steam 商店检测
check_steam_store() {
    check_game_platform "Steam" "https://store.steampowered.com" "steam"
}

# Epic Games 检测
check_epic() {
    check_game_platform "Epic" "https://store.epicgames.com" "epic"
}

# PlayStation 检测
check_playstation() {
    check_game_platform "PlayStation" "https://store.playstation.com" "playstation"
}

# Xbox 检测
check_xbox() {
    check_game_platform "Xbox" "https://www.xbox.com" "xbox"
}

# Nintendo 检测
check_nintendo() {
    check_game_platform "Nintendo" "https://www.nintendo.com" "nintendo"
}

# GeForce NOW 检测
check_geforce_now() {
    check_game_platform "GeForce NOW" "https://www.nvidia.com/en-us/geforce-now" "geforce"
}

# EA App 检测
check_ea() {
    check_game_platform "EA" "https://www.ea.com" "ea"
}

# Ubisoft 检测
check_ubisoft() {
    check_game_platform "Ubisoft" "https://www.ubisoft.com" "ubisoft"
}

# ============ 评分与报告系统 ============

# 流媒体解锁计数
count_media_unlocks() {
    local count=0
    for result in "$@"; do
        if [[ "$result" == *"解锁"* || "$result" == *"可用"* || "$result" == *"Premium"* ]]; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

# 计算综合评分 (Pro版)
calculate_score_pro() {
    local media_unlocks="$1"
    local total_media="$2"
    local human_score="$3"
    local network_quality="$4"
    
    local score=50  # 基础分
    
    # 流媒体解锁加分 (最多 +30)
    local media_pct=$(( media_unlocks * 100 / total_media ))
    local media_bonus=$(( media_pct * 30 / 100 ))
    score=$((score + media_bonus))
    
    # 真人度评分加分 (最多 +20)
    local human_bonus=$(( human_score * 20 / 100 ))
    score=$((score + human_bonus))
    
    # 网络质量加分 (最多 +10)
    if [[ "$network_quality" == "通畅" ]]; then
        score=$((score + 10))
    fi
    
    # 限制范围
    if [[ $score -gt 100 ]]; then score=100; fi
    if [[ $score -lt 0 ]]; then score=0; fi
    
    echo "$score"
}

# 获取评级 (Pro版)
get_grade_pro() {
    local score=$1
    if [[ $score -ge 95 ]]; then echo "S"
    elif [[ $score -ge 85 ]]; then echo "A+"
    elif [[ $score -ge 75 ]]; then echo "A"
    elif [[ $score -ge 65 ]]; then echo "B"
    elif [[ $score -ge 55 ]]; then echo "C"
    elif [[ $score -ge 40 ]]; then echo "D"
    else echo "F"
    fi
}

# 获取评级颜色
get_grade_color_pro() {
    local grade=$1
    case "$grade" in
        "S") echo "${CHK_PURPLE}" ;;
        "A+"|"A") echo "${CHK_GREEN}" ;;
        "B") echo "${CHK_CYAN}" ;;
        "C") echo "${CHK_YELLOW}" ;;
        "D"|"F") echo "${CHK_RED}" ;;
        *) echo "${CHK_NC}" ;;
    esac
}

# 获取用途推荐
get_recommendation() {
    local grade="$1"
    local media_count="$2"
    local human_score="$3"
    
    if [[ "$grade" == "S" || "$grade" == "A+" ]]; then
        echo "全能型：代理服务器、流媒体解锁、AI服务、建站、游戏加速"
    elif [[ "$grade" == "A" ]]; then
        echo "优质型：代理服务器、大部分流媒体、AI服务、建站"
    elif [[ "$grade" == "B" ]]; then
        echo "良好型：代理服务器、部分流媒体、基础建站"
    elif [[ "$grade" == "C" ]]; then
        echo "一般型：基础代理、建站（流媒体受限）"
    else
        echo "受限型：仅基础代理，不适合流媒体和AI服务"
    fi
}

# 保存检测历史 (Pro版)
save_check_history_pro() {
    local record="$1"
    local history_file="$IP_CHECK_HISTORY"
    
    local history=$(cat "$history_file" 2>/dev/null || echo "[]")
    
    local new_history=$(echo "$history" | python3 -c "
import sys, json
history = json.load(sys.stdin)
history.insert(0, json.loads('$record'))
if len(history) > 10:
    history = history[:10]
print(json.dumps(history, ensure_ascii=False))
" 2>/dev/null || echo "[$record]")
    
    echo "$new_history" > "$history_file"
}

# 显示历史记录 (Pro版)
show_check_history_pro() {
    local history_file="$IP_CHECK_HISTORY"
    if [[ ! -f "$history_file" ]]; then
        echo -e "${CHK_YELLOW}暂无检测历史${CHK_NC}"
        return
    fi
    
    local history=$(cat "$history_file")
    local count=$(echo "$history" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    
    if [[ "$count" == "0" ]]; then
        echo -e "${CHK_YELLOW}暂无检测历史${CHK_NC}"
        return
    fi
    
    echo ""
    echo -e "${CHK_CYAN}╔══════════════════════════════════════════════════════════════╗${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}              📋 检测历史记录 (${count}条)                      ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    
    echo "$history" | python3 -c "
import sys, json
history = json.load(sys.stdin)
for i, record in enumerate(history[:5], 1):
    time = record.get('time', '未知')
    score = record.get('score', 0)
    grade = record.get('grade', '?')
    ip = record.get('ip', '未知')
    media = record.get('media_unlocks', 0)
    print(f'  {i}. {time}')
    print(f'     IP: {ip} | 评分: {score} | 评级: {grade} | 流媒体: {media}')
    print()
" 2>/dev/null
    
    echo -e "${CHK_CYAN}╚══════════════════════════════════════════════════════════════╝${CHK_NC}"
}

# 导出 JSON 报告
export_json_report() {
    local report="$1"
    local output_file="$IP_CHECK_DIR/report_$(date +%Y%m%d_%H%M%S).json"
    echo "$report" > "$output_file"
    echo "$output_file"
}

# ============ 主函数 ============

# IP 综合体检主函数 (Pro版)
ip_health_check() {
    # 临时关闭 set -e，避免检测过程中的错误导致整个脚本退出
    set +e
    
    init_ip_check
    
    clear
    echo ""
    echo -e "${CHK_CYAN}╔══════════════════════════════════════════════════════════════╗${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}              🌐 IP 综合体检 (Pro版)                          ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}         50+ 检测项 · 流媒体 · 风控 · 网络 · 游戏            ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}╚══════════════════════════════════════════════════════════════╝${CHK_NC}"
    echo ""
    
    # ========== 基础信息 ==========
    echo -e "${CHK_YELLOW}[1/5] 正在获取 IP 基础信息...${CHK_NC}"
    local public_ip=$(get_public_ip_info)
    local ip_details=""
    local country="未知"
    local country_code="--"
    local region="未知"
    local city="未知"
    local isp="未知"
    local org="未知"
    local asn="未知"
    local asn_name="未知"
    local timezone="未知"
    local lat=""
    local lon=""
    
    if [[ -n "$public_ip" ]]; then
        ip_details=$(get_ip_details "$public_ip")
        country=$(echo "$ip_details" | grep -oP '"country":"\K[^"]+' | head -1)
        country_code=$(echo "$ip_details" | grep -oP '"countryCode":"\K[^"]+' | head -1)
        region=$(echo "$ip_details" | grep -oP '"regionName":"\K[^"]+' | head -1)
        city=$(echo "$ip_details" | grep -oP '"city":"\K[^"]+' | head -1)
        isp=$(echo "$ip_details" | grep -oP '"isp":"\K[^"]+' | head -1)
        org=$(echo "$ip_details" | grep -oP '"org":"\K[^"]+' | head -1)
        asn=$(echo "$ip_details" | grep -oP '"as":"\K[^"]+' | head -1)
        asn_name=$(echo "$ip_details" | grep -oP '"asname":"\K[^"]+' | head -1)
        timezone=$(echo "$ip_details" | grep -oP '"timezone":"\K[^"]+' | head -1)
    fi
    
    # 备用获取
    [[ -z "$public_ip" ]] && public_ip="获取失败"
    [[ -z "$country" ]] && country="未知"
    [[ -z "$country_code" ]] && country_code="--"
    [[ -z "$region" ]] && region="未知"
    [[ -z "$city" ]] && city="未知"
    [[ -z "$isp" ]] && isp="未知"
    
    # ASN 信息
    local asn_info=$(get_asn_info "$public_ip")
    if [[ -z "$asn" && -n "$asn_info" ]]; then
        asn=$(echo "$asn_info" | grep -oP '"asn":"\K[^"]+' | head -1)
        asn_name=$(echo "$asn_info" | grep -oP '"as_name":"\K[^"]+' | head -1)
    fi
    [[ -z "$asn" ]] && asn="未知"
    [[ -z "$asn_name" ]] && asn_name=""
    
    # 反向 DNS
    local hostname=$(check_reverse_dns "$public_ip")
    
    # 数据中心判断
    local is_dc=$(is_datacenter_ip "$asn" "$org" "$hostname")
    
    # ========== IP 风控 ==========
    echo -e "${CHK_YELLOW}[2/5] 正在检测 IP 风控信息...${CHK_NC}"
    local risk_data=$(check_ip_risk "$public_ip")
    local risk_score=$(echo "$risk_data" | grep -oP '"score":\K[0-9]+' | head -1)
    local risk_reasons=$(echo "$risk_data" | grep -oP '"reasons":"\K[^"]+' | head -1)
    local is_proxy=$(echo "$risk_data" | grep -oP '"proxy":\K[a-z]+' | head -1)
    local is_hosting=$(echo "$risk_data" | grep -oP '"hosting":\K[a-z]+' | head -1)
    [[ -z "$risk_score" ]] && risk_score=0
    
    local human_score=$(calculate_human_score "$risk_data" "$is_dc")
    
    # ========== 流媒体解锁 ==========
    echo -e "${CHK_YELLOW}[3/5] 正在检测流媒体解锁 (25+ 平台)...${CHK_NC}"
    
    local nf=$(check_netflix_pro)
    local ds=$(check_disney_pro)
    local yt=$(check_youtube_pro)
    local ytc=$(check_youtube_cdn)
    local hb=$(check_hbo_max)
    local hu=$(check_hulu)
    local pv=$(check_prime_video)
    local pm=$(check_paramount)
    local atv=$(check_apple_tv)
    local dis=$(check_discovery)
    local sp=$(check_spotify)
    local bb=$(check_bbc)
    local ab=$(check_abema)
    local dm=$(check_dmm)
    local tv=$(check_tvb)
    local vi=$(check_viu)
    local cg=$(check_chatgpt_pro)
    local cl=$(check_claude)
    local gm=$(check_gemini)
    local tt=$(check_tiktok_pro)
    local ig=$(check_instagram)
    local wp=$(check_wikipedia)
    
    local media_results=("$nf" "$ds" "$yt" "$hb" "$hu" "$pv" "$pm" "$atv" "$dis" "$sp" "$bb" "$ab" "$dm" "$tv" "$vi" "$cg" "$cl" "$gm" "$tt" "$ig" "$wp")
    local media_count=$(count_media_unlocks "${media_results[@]}")
    local total_media=${#media_results[@]}
    
    # ========== 网络质量 ==========
    echo -e "${CHK_YELLOW}[4/5] 正在检测网络质量...${CHK_NC}"
    local network_data=$(check_network_quality_pro)
    local bandwidth=$(check_bandwidth)
    local dns_ok=$(check_dns)
    local ipv6_status=$(check_ipv6_connectivity)
    
    # ========== 游戏平台 ==========
    echo -e "${CHK_YELLOW}[5/5] 正在检测游戏平台...${CHK_NC}"
    local st=$(check_steam_store)
    local ep=$(check_epic)
    local ps=$(check_playstation)
    local xb=$(check_xbox)
    local ni=$(check_nintendo)
    local gf=$(check_geforce_now)
    local ea=$(check_ea)
    local ub=$(check_ubisoft)
    
    local game_results=("$st" "$ep" "$ps" "$xb" "$ni" "$gf" "$ea" "$ub")
    local game_count=$(count_media_unlocks "${game_results[@]}")
    
    # ========== 计算评分 ==========
    local score=$(calculate_score_pro "$media_count" "$total_media" "$human_score" "$bandwidth")
    local grade=$(get_grade_pro "$score")
    local grade_color=$(get_grade_color_pro "$grade")
    local recommendation=$(get_recommendation "$grade" "$media_count" "$human_score")
    local check_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 保存历史
    local record="{\"time\":\"$check_time\",\"ip\":\"$public_ip\",\"score\":$score,\"grade\":\"$grade\",\"media_unlocks\":$media_count,\"human_score\":$human_score,\"country\":\"$country\"}"
    save_check_history_pro "$record"
    
    # ========== 显示报告 ==========
    clear
    echo ""
    echo -e "${CHK_CYAN}╔══════════════════════════════════════════════════════════════╗${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}              🌐 IP 综合体检报告 (Pro版)                      ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}  检测时间: ${CHK_YELLOW}$check_time${CHK_NC}                                    ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}  综合评分: ${grade_color}${score}/100${CHK_NC}  [${grade_color}${grade}级${CHK_NC}]                              ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    
    # 基础信息
    echo -e "${CHK_CYAN}║${CHK_NC} 📍 ${CHK_YELLOW}基础信息${CHK_NC}                                                  ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    IP:       ${CHK_GREEN}$public_ip${CHK_NC}                                  ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    归属:     ${CHK_GREEN}$country ($country_code)${CHK_NC} / ${CHK_GREEN}$region${CHK_NC} / ${CHK_GREEN}$city${CHK_NC}       ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    ISP:      ${CHK_GREEN}$isp${CHK_NC}                                   ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    ASN:      ${CHK_GREEN}${asn:0:40}${CHK_NC}                    ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    时区:     ${CHK_GREEN}$timezone${CHK_NC}                                    ${CHK_CYAN}║${CHK_NC}"
    if [[ -n "$hostname" ]]; then
        echo -e "${CHK_CYAN}║${CHK_NC}    反向DNS:  ${CHK_GREEN}${hostname:0:45}${CHK_NC}              ${CHK_CYAN}║${CHK_NC}"
    fi
    
    # IP 风控
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC} 🛡️  ${CHK_YELLOW}IP 风控检测${CHK_NC}                                               ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    真人度评分: ${CHK_GREEN}${human_score}/100${CHK_NC}                                   ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    风险评分:   ${CHK_GREEN}${risk_score}/100${CHK_NC}                                   ${CHK_CYAN}║${CHK_NC}"
    
    local proxy_icon="$ICON_OK"
    [[ "$is_proxy" == "true" ]] && proxy_icon="$ICON_FAIL"
    local host_icon="$ICON_OK"
    [[ "$is_hosting" == "true" ]] && host_icon="$ICON_FAIL"
    local dc_icon="$ICON_OK"
    [[ "$is_dc" == "true" ]] && dc_icon="$ICON_FAIL"
    
    echo -e "${CHK_CYAN}║${CHK_NC}    代理/VPN:   $proxy_icon  托管/数据中心: $host_icon  数据中心: $dc_icon    ${CHK_CYAN}║${CHK_NC}"
    if [[ -n "$risk_reasons" ]]; then
        echo -e "${CHK_CYAN}║${CHK_NC}    风险因素: ${CHK_YELLOW}${risk_reasons:0:50}${CHK_NC}              ${CHK_CYAN}║${CHK_NC}"
    fi
    
    # 流媒体
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC} 🎬 ${CHK_YELLOW}流媒体解锁 (${media_count}/${total_media})${CHK_NC}                                  ${CHK_CYAN}║${CHK_NC}"
    
    # 第一行: Netflix Disney+ YouTube HBO Hulu
    local nf_icon="$ICON_OK"; [[ "$nf" == *"不可用"* ]] && nf_icon="$ICON_FAIL"; [[ "$nf" == *"自制剧"* ]] && nf_icon="$ICON_WARN"
    local ds_icon="$ICON_OK"; [[ "$ds" == *"不可用"* ]] && ds_icon="$ICON_FAIL"
    local yt_icon="$ICON_OK"; [[ "$yt" == *"不可用"* ]] && yt_icon="$ICON_FAIL"
    local hb_icon="$ICON_OK"; [[ "$hb" == *"不可用"* ]] && hb_icon="$ICON_FAIL"
    local hu_icon="$ICON_OK"; [[ "$hu" == *"不可用"* ]] && hu_icon="$ICON_FAIL"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${nf_icon}Netflix${CHK_NC} ${nf}  ${ds_icon}Disney+${CHK_NC} ${ds}                    ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${yt_icon}YouTube${CHK_NC} ${yt}  ${hb_icon}HBO Max${CHK_NC} ${hb}  ${hu_icon}Hulu${CHK_NC} ${hu}        ${CHK_CYAN}║${CHK_NC}"
    
    # 第二行: Prime Paramount AppleTV Discovery Spotify
    local pv_icon="$ICON_OK"; [[ "$pv" == *"不可用"* ]] && pv_icon="$ICON_FAIL"
    local pm_icon="$ICON_OK"; [[ "$pm" == *"不可用"* ]] && pm_icon="$ICON_FAIL"
    local atv_icon="$ICON_OK"; [[ "$atv" == *"不可用"* ]] && atv_icon="$ICON_FAIL"
    local dis_icon="$ICON_OK"; [[ "$dis" == *"不可用"* ]] && dis_icon="$ICON_FAIL"
    local sp_icon="$ICON_OK"; [[ "$sp" == *"不可用"* ]] && sp_icon="$ICON_FAIL"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${pv_icon}Prime${CHK_NC} ${pv}  ${pm_icon}Paramount+${CHK_NC} ${pm}             ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${atv_icon}Apple TV+${CHK_NC} ${atv}  ${dis_icon}Discovery+${CHK_NC} ${dis}  ${sp_icon}Spotify${CHK_NC} ${sp}  ${CHK_CYAN}║${CHK_NC}"
    
    # 第三行: BBC Abema DMM TVB Viu
    local bb_icon="$ICON_OK"; [[ "$bb" == *"不可用"* ]] && bb_icon="$ICON_FAIL"
    local ab_icon="$ICON_OK"; [[ "$ab" == *"不可用"* ]] && ab_icon="$ICON_FAIL"
    local dm_icon="$ICON_OK"; [[ "$dm" == *"不可用"* ]] && dm_icon="$ICON_FAIL"
    local tv_icon="$ICON_OK"; [[ "$tv" == *"不可用"* ]] && tv_icon="$ICON_FAIL"
    local vi_icon="$ICON_OK"; [[ "$vi" == *"不可用"* ]] && vi_icon="$ICON_FAIL"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${bb_icon}BBC${CHK_NC} ${bb}  ${ab_icon}Abema${CHK_NC} ${ab}  ${dm_icon}DMM${CHK_NC} ${dm}  ${tv_icon}TVB${CHK_NC} ${tv}  ${vi_icon}Viu${CHK_NC} ${vi}  ${CHK_CYAN}║${CHK_NC}"
    
    # 第四行: ChatGPT Claude Gemini TikTok
    local cg_icon="$ICON_OK"; [[ "$cg" == *"不可用"* ]] && cg_icon="$ICON_FAIL"
    local cl_icon="$ICON_OK"; [[ "$cl" == *"不可用"* ]] && cl_icon="$ICON_FAIL"
    local gm_icon="$ICON_OK"; [[ "$gm" == *"不可用"* ]] && gm_icon="$ICON_FAIL"
    local tt_icon="$ICON_OK"; [[ "$tt" == *"不可用"* ]] && tt_icon="$ICON_FAIL"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${cg_icon}ChatGPT${CHK_NC} ${cg}  ${cl_icon}Claude${CHK_NC} ${cl}  ${gm_icon}Gemini${CHK_NC} ${gm}  ${tt_icon}TikTok${CHK_NC} ${tt}  ${CHK_CYAN}║${CHK_NC}"
    
    # 第五行: Instagram Wikipedia
    local ig_icon="$ICON_OK"; [[ "$ig" == *"不可用"* ]] && ig_icon="$ICON_FAIL"
    local wp_icon="$ICON_OK"; [[ "$wp" == *"不可用"* ]] && wp_icon="$ICON_FAIL"
    echo -e "${CHK_CYAN}║${CHK_NC}  ${ig_icon}Instagram${CHK_NC} ${ig}  ${wp_icon}Wikipedia${CHK_NC} ${wp}                          ${CHK_CYAN}║${CHK_NC}"
    
    # 网络质量
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC} 🌐 ${CHK_YELLOW}网络质量${CHK_NC}                                                  ${CHK_CYAN}║${CHK_NC}"
    
    # 解析并显示网络质量
    IFS=' ' read -ra net_arr <<< "$network_data"
    for entry in "${net_arr[@]}"; do
        if [[ -n "$entry" ]]; then
            local net_name=$(echo "$entry" | cut -d: -f1)
            local net_delay=$(echo "$entry" | cut -d: -f2)
            local net_loss=$(echo "$entry" | cut -d: -f3)
            
            local delay_color="${CHK_GREEN}"
            if [[ "$net_delay" == "超时" ]]; then
                delay_color="${CHK_RED}"
            elif echo "$net_delay" | grep -qE '^[0-9]+'; then
                local delay_num=$(echo "$net_delay" | grep -oE '^[0-9]+')
                if [[ "$delay_num" -gt 300 ]]; then
                    delay_color="${CHK_RED}"
                elif [[ "$delay_num" -gt 150 ]]; then
                    delay_color="${CHK_YELLOW}"
                fi
            fi
            
            printf "${CHK_CYAN}║${CHK_NC}    %-12s ${delay_color}%8s${CHK_NC}  丢包: %5s                          ${CHK_CYAN}║${CHK_NC}\n" "$net_name" "$net_delay" "$net_loss"
        fi
    done
    
    echo -e "${CHK_CYAN}║${CHK_NC}    带宽: ${CHK_GREEN}$bandwidth${CHK_NC}  |  DNS: ${CHK_GREEN}$dns_ok${CHK_NC}  |  IPv6: ${CHK_GREEN}$ipv6_status${CHK_NC}                    ${CHK_CYAN}║${CHK_NC}"
    
    # 游戏平台
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC} 🎮 ${CHK_YELLOW}游戏平台 (${game_count}/8)${CHK_NC}                                     ${CHK_CYAN}║${CHK_NC}"
    
    local st_icon="$ICON_OK"; [[ "$st" == *"不可用"* ]] && st_icon="$ICON_FAIL"
    local ep_icon="$ICON_OK"; [[ "$ep" == *"不可用"* ]] && ep_icon="$ICON_FAIL"
    local ps_icon="$ICON_OK"; [[ "$ps" == *"不可用"* ]] && ps_icon="$ICON_FAIL"
    local xb_icon="$ICON_OK"; [[ "$xb" == *"不可用"* ]] && xb_icon="$ICON_FAIL"
    local ni_icon="$ICON_OK"; [[ "$ni" == *"不可用"* ]] && ni_icon="$ICON_FAIL"
    local gf_icon="$ICON_OK"; [[ "$gf" == *"不可用"* ]] && gf_icon="$ICON_FAIL"
    local ea_icon="$ICON_OK"; [[ "$ea" == *"不可用"* ]] && ea_icon="$ICON_FAIL"
    local ub_icon="$ICON_OK"; [[ "$ub" == *"不可用"* ]] && ub_icon="$ICON_FAIL"
    
    echo -e "${CHK_CYAN}║${CHK_NC}  ${st_icon}Steam${CHK_NC}  ${ep_icon}Epic${CHK_NC}  ${ps_icon}PSN${CHK_NC}  ${xb_icon}Xbox${CHK_NC}  ${ni_icon}Nintendo${CHK_NC}  ${gf_icon}GeForce${CHK_NC}  ${ea_icon}EA${CHK_NC}  ${ub_icon}Ubisoft${CHK_NC}  ${CHK_CYAN}║${CHK_NC}"
    
    # 综合评级
    echo -e "${CHK_CYAN}╠══════════════════════════════════════════════════════════════╣${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC} 📊 ${CHK_YELLOW}综合评级${CHK_NC}: ${grade_color}${grade}级${CHK_NC}                                           ${CHK_CYAN}║${CHK_NC}"
    echo -e "${CHK_CYAN}║${CHK_NC}    推荐用途: ${CHK_GREEN}${recommendation:0:50}${CHK_NC}                    ${CHK_CYAN}║${CHK_NC}"
    
    echo -e "${CHK_CYAN}╚══════════════════════════════════════════════════════════════╝${CHK_NC}"
    echo ""
    
    # 操作选项
    echo -e "${CHK_YELLOW}操作选项:${CHK_NC}"
    echo "  1. 查看检测历史"
    echo "  2. 重新检测"
    echo "  3. 导出 JSON 报告"
    echo "  4. 导出 Base64 报告"
    echo "  5. 返回主菜单"
    echo ""
    
    read -rp "请选择 [1-5]: " check_choice
    
    case $check_choice in
        1)
            show_check_history_pro
            echo ""
            read -rp "按回车键继续..."
            set -e
            ip_health_check
            ;;
        2)
            set -e
            ip_health_check
            ;;
        3)
            local json_report="{\"time\":\"$check_time\",\"ip\":\"$public_ip\",\"country\":\"$country\",\"country_code\":\"$country_code\",\"region\":\"$region\",\"city\":\"$city\",\"isp\":\"$isp\",\"asn\":\"$asn\",\"score\":$score,\"grade\":\"$grade\",\"human_score\":$human_score,\"risk_score\":$risk_score,\"media_unlocks\":$media_count,\"total_media\":$total_media,\"game_unlocks\":$game_count,\"network\":\"$bandwidth\",\"dns\":\"$dns_ok\",\"ipv6\":\"$ipv6_status\",\"recommendation\":\"$recommendation\"}"
            local report_file=$(export_json_report "$json_report")
            echo ""
            echo -e "${CHK_GREEN}JSON 报告已导出: $report_file${CHK_NC}"
            echo ""
            read -rp "按回车键继续..."
            ip_health_check
            ;;
        4)
            local b64_report="IP:$public_ip|Country:$country|Score:$score|Grade:$grade|Media:$media_count/$total_media|Human:$human_score"
            local b64=$(echo "$b64_report" | base64 -w 0 2>/dev/null)
            echo ""
            echo -e "${CHK_GREEN}Base64 报告:${CHK_NC}"
            echo "$b64"
            echo ""
            read -rp "按回车键继续..."
            set -e
            ip_health_check
            ;;
        5)
            set -e
            return
            ;;
        *)
            warn "无效选择"
            ;;
    esac
}

# ==================== Swap 管理功能 ====================

manage_swap() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Swap 管理${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    local swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    local mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    
    if [[ "$swap_total" == "0" || -z "$swap_total" ]]; then
        echo -e "  ${YELLOW}Swap: 未启用${NC}"
    else
        local usage_pct=0
        if [[ "$swap_total" -gt 0 ]]; then
            usage_pct=$(( swap_used * 100 / swap_total ))
        fi
        echo -e "  ${GREEN}Swap 总量:${NC} ${swap_total} MB"
        echo -e "  ${GREEN}已使用:${NC} ${swap_used} MB (${usage_pct}%)"
    fi
    echo -e "  ${GREEN}内存总量:${NC} ${mem_total} MB"
    echo ""
    
    if [[ -f /swapfile ]]; then
        local swapfile_size=$(du -sh /swapfile 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}Swap 文件:${NC} /swapfile (${swapfile_size})"
    elif swapon --show=NAME,SIZE 2>/dev/null | grep -q "^/"; then
        echo -e "  ${GREEN}Swap 设备:${NC}"
        swapon --show=NAME,SIZE,USED 2>/dev/null | grep "^/" | while read -r line; do
            echo "    $line"
        done
    fi
    
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}操作选项:${NC}"
    echo "  1. 一键创建 Swap (自动推荐大小)"
    echo "  2. 自定义大小创建 Swap"
    echo "  3. 删除 Swap"
    echo "  4. 调整 Swappiness 值"
    echo "  5. 返回主菜单"
    echo ""
    read -rp "请选择 [1-5]: " swap_choice
    
    case $swap_choice in
        1)
            local recommend_size=0
            if [[ "$mem_total" -le 512 ]]; then
                recommend_size=1024
            elif [[ "$mem_total" -le 1024 ]]; then
                recommend_size=2048
            elif [[ "$mem_total" -le 2048 ]]; then
                recommend_size=4096
            elif [[ "$mem_total" -le 4096 ]]; then
                recommend_size=4096
            else
                recommend_size=2048
            fi
            echo ""
            echo -e "${YELLOW}内存: ${mem_total}MB, 推荐 Swap: ${recommend_size}MB${NC}"
            read -rp "确认创建 ${recommend_size}MB Swap? [Y/n]: " confirm
            if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
                create_swap "$recommend_size"
            fi
            ;;
        2)
            echo ""
            read -rp "请输入 Swap 大小 (MB): " custom_size
            if [[ -z "$custom_size" ]] || ! [[ "$custom_size" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}请输入有效的数字${NC}"
                read -rp "按回车键继续..."
                return
            fi
            read -rp "确认创建 ${custom_size}MB Swap? [Y/n]: " confirm
            if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
                create_swap "$custom_size"
            fi
            ;;
        3) remove_swap ;;
        4) adjust_swappiness ;;
        5) return ;;
        *) warn "无效选择" ;;
    esac
    
    echo ""
    read -rp "按回车键继续..."
}

create_swap() {
    local size_mb="$1"
    if swapon --show 2>/dev/null | grep -q "^/"; then
        echo -e "${YELLOW}检测到已有 Swap，先删除再创建...${NC}"
        remove_swap
    fi
    echo -e "${YELLOW}正在创建 ${size_mb}MB Swap 文件...${NC}"
    dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress 2>/dev/null || \
    dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" 2>/dev/null
    if [[ ! -f /swapfile ]]; then
        echo -e "${RED}Swap 文件创建失败${NC}"
        return 1
    fi
    chmod 600 /swapfile
    mkswap /swapfile 2>/dev/null
    swapon /swapfile 2>/dev/null
    if ! grep -q "^/swapfile" /etc/fstab 2>/dev/null; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    echo -e "${GREEN}Swap 创建完成!${NC}"
    echo ""
    free -m | grep -E "^Mem:|^Swap:"
}

remove_swap() {
    echo -e "${YELLOW}正在删除 Swap...${NC}"
    swapoff -a 2>/dev/null || true
    if [[ -f /swapfile ]]; then
        rm -f /swapfile
    fi
    sed -i '/^\/swapfile/d' /etc/fstab 2>/dev/null || true
    echo -e "${GREEN}Swap 已删除${NC}"
}

adjust_swappiness() {
    local current=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "30")
    echo ""
    echo -e "${YELLOW}当前 Swappiness: ${current}${NC}"
    echo ""
    echo "说明:"
    echo "  0-10: 尽量减少 Swap 使用 (推荐用于 SSD/高性能服务器)"
    echo "  30-60: 平衡模式 (默认推荐)"
    echo "  60-100: 积极使用 Swap (内存紧张时使用)"
    echo ""
    read -rp "请输入新的 Swappiness 值 (0-100): " new_val
    if [[ -z "$new_val" ]] || ! [[ "$new_val" =~ ^[0-9]+$ ]] || [[ "$new_val" -gt 100 ]]; then
        echo -e "${RED}请输入 0-100 之间的数字${NC}"
        return
    fi
    sysctl vm.swappiness="$new_val" 2>/dev/null
    if grep -q "^vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s/^vm.swappiness.*/vm.swappiness=${new_val}/" /etc/sysctl.conf 2>/dev/null || true
    else
        echo "vm.swappiness=${new_val}" >> /etc/sysctl.conf
    fi
    echo -e "${GREEN}Swappiness 已设置为 ${new_val}${NC}"
}

# ==================== 日志管理功能 ====================

manage_logs() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    日志管理${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}日志磁盘占用:${NC}"
    echo ""
    if command -v journalctl &>/dev/null; then
        local journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+[KMGT]?' | head -1)
        echo -e "  Systemd Journal: ${journal_size:-未知}"
    fi
    if [[ -d /var/log ]]; then
        local log_dir_size=$(du -sh /var/log 2>/dev/null | cut -f1)
        echo -e "  /var/log 目录: ${log_dir_size:-未知}"
    fi
    echo ""
    echo -e "${YELLOW}各服务日志大小:${NC}"
    local log_files=(
        "/var/log/xray/access.log"
        "/var/log/xray/error.log"
        "/var/log/hysteria/server.log"
        "/var/log/nginx/access.log"
        "/var/log/nginx/error.log"
        "/var/log/caddy/access.log"
        "/var/log/vps-toolbox.log"
    )
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            local size=$(du -sh "$log_file" 2>/dev/null | cut -f1)
            echo -e "  ${log_file}: ${GREEN}${size}${NC}"
        fi
    done
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}操作选项:${NC}"
    echo "  1. 清理 Systemd Journal 日志"
    echo "  2. 清理 /var/log 旧日志"
    echo "  3. 清理代理服务日志"
    echo "  4. 查看实时日志"
    echo "  5. 配置日志自动清理 (cron)"
    echo "  6. 一键清理所有日志"
    echo "  7. 返回主菜单"
    echo ""
    read -rp "请选择 [1-7]: " log_choice
    case $log_choice in
        1) clean_journal_logs ;;
        2) clean_var_logs ;;
        3) clean_proxy_logs ;;
        4) view_realtime_logs ;;
        5) setup_log_rotation ;;
        6) clean_all_logs ;;
        7) return ;;
        *) warn "无效选择" ;;
    esac
    echo ""
    read -rp "按回车键继续..."
}

clean_journal_logs() {
    if ! command -v journalctl &>/dev/null; then
        echo -e "${YELLOW}未安装 systemd-journald${NC}"
        return
    fi
    echo ""
    echo -e "${YELLOW}当前 Journal 占用:${NC}"
    journalctl --disk-usage 2>/dev/null
    echo ""
    echo "  1. 保留最近 1 天"
    echo "  2. 保留最近 7 天"
    echo "  3. 保留最近 30 天"
    echo "  4. 保留最近 100MB"
    echo "  5. 清空所有日志"
    echo "  6. 返回"
    echo ""
    read -rp "请选择 [1-6]: " journal_choice
    case $journal_choice in
        1) journalctl --vacuum-time=1d 2>/dev/null ;;
        2) journalctl --vacuum-time=7d 2>/dev/null ;;
        3) journalctl --vacuum-time=30d 2>/dev/null ;;
        4) journalctl --vacuum-size=100M 2>/dev/null ;;
        5) journalctl --rotate 2>/dev/null && journalctl --vacuum-time=1s 2>/dev/null ;;
        6) return ;;
        *) warn "无效选择" ;;
    esac
    echo ""
    echo -e "${GREEN}Journal 清理完成${NC}"
    journalctl --disk-usage 2>/dev/null
}

clean_var_logs() {
    echo -e "${YELLOW}正在清理 /var/log 旧日志...${NC}"
    find /var/log -name "*.log.*" -type f -mtime +7 -delete 2>/dev/null || true
    find /var/log -name "*.gz" -type f -mtime +30 -delete 2>/dev/null || true
    for log_file in /var/log/*.log; do
        if [[ -f "$log_file" ]]; then
            : > "$log_file" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}/var/log 清理完成${NC}"
}

clean_proxy_logs() {
    echo -e "${YELLOW}正在清理代理服务日志...${NC}"
    if [[ -d /var/log/xray ]]; then
        : > /var/log/xray/access.log 2>/dev/null || true
        : > /var/log/xray/error.log 2>/dev/null || true
        echo -e "  ${GREEN}Xray 日志已清空${NC}"
    fi
    if [[ -d /var/log/hysteria ]]; then
        : > /var/log/hysteria/server.log 2>/dev/null || true
        echo -e "  ${GREEN}Hysteria 日志已清空${NC}"
    fi
    if [[ -d /var/log/nginx ]]; then
        : > /var/log/nginx/access.log 2>/dev/null || true
        : > /var/log/nginx/error.log 2>/dev/null || true
        echo -e "  ${GREEN}Nginx 日志已清空${NC}"
    fi
    if [[ -d /var/log/caddy ]]; then
        find /var/log/caddy -name "*.log" -type f -exec sh -c ': > "$1"' _ {} \; 2>/dev/null || true
        echo -e "  ${GREEN}Caddy 日志已清空${NC}"
    fi
    : > /var/log/vps-toolbox.log 2>/dev/null || true
    echo -e "  ${GREEN}VPS Toolbox 日志已清空${NC}"
    echo ""
    echo -e "${GREEN}代理服务日志清理完成${NC}"
}

view_realtime_logs() {
    echo ""
    echo -e "${YELLOW}选择要查看的日志:${NC}"
    echo "  1. Xray 访问日志"
    echo "  2. Xray 错误日志"
    echo "  3. Hysteria 日志"
    echo "  4. Nginx 访问日志"
    echo "  5. Nginx 错误日志"
    echo "  6. Systemd Journal (全部)"
    echo "  7. VPS Toolbox 日志"
    echo "  8. 返回"
    echo ""
    read -rp "请选择 [1-8]: " rt_choice
    local log_file=""
    local use_journal=false
    case $rt_choice in
        1) log_file="/var/log/xray/access.log" ;;
        2) log_file="/var/log/xray/error.log" ;;
        3) log_file="/var/log/hysteria/server.log" ;;
        4) log_file="/var/log/nginx/access.log" ;;
        5) log_file="/var/log/nginx/error.log" ;;
        6) use_journal=true ;;
        7) log_file="/var/log/vps-toolbox.log" ;;
        8) return ;;
        *) warn "无效选择"; return ;;
    esac
    echo ""
    echo -e "${YELLOW}按 Ctrl+C 退出实时查看${NC}"
    echo ""
    if [[ "$use_journal" == true ]]; then
        journalctl -f 2>/dev/null || echo -e "${RED}journalctl 不可用${NC}"
    elif [[ -f "$log_file" ]]; then
        tail -f "$log_file" 2>/dev/null
    else
        echo -e "${YELLOW}日志文件不存在: ${log_file}${NC}"
    fi
}

setup_log_rotation() {
    echo -e "${YELLOW}配置日志自动清理...${NC}"
    echo ""
    echo "  1. 每天清理一次"
    echo "  2. 每周清理一次"
    echo "  3. 每月清理一次"
    echo "  4. 关闭自动清理"
    echo "  5. 返回"
    echo ""
    read -rp "请选择 [1-5]: " rot_choice
    local cron_expr=""
    case $rot_choice in
        1) cron_expr="0 3 * * *" ;;
        2) cron_expr="0 3 * * 0" ;;
        3) cron_expr="0 3 1 * *" ;;
        4)
            crontab -l 2>/dev/null | grep -v "vps-toolbox-log-clean" | crontab - 2>/dev/null || true
            echo -e "${GREEN}自动清理已关闭${NC}"
            return
            ;;
        5) return ;;
        *) warn "无效选择"; return ;;
    esac
    cat > /usr/local/bin/vps-toolbox-log-clean.sh <<'CLEANSCRIPT'
#!/bin/bash
if command -v journalctl &>/dev/null; then
    journalctl --vacuum-time=7d --quiet 2>/dev/null
fi
for log_file in /var/log/xray/access.log /var/log/xray/error.log /var/log/hysteria/server.log; do
    if [[ -f "$log_file" ]] && [[ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0) -gt 104857600 ]]; then
        : > "$log_file"
    fi
done
find /var/log -name "*.log.*" -type f -mtime +7 -delete 2>/dev/null || true
CLEANSCRIPT
    chmod +x /usr/local/bin/vps-toolbox-log-clean.sh
    (crontab -l 2>/dev/null | grep -v "vps-toolbox-log-clean"; echo "$cron_expr /usr/local/bin/vps-toolbox-log-clean.sh >/dev/null 2>&1") | crontab -
    echo -e "${GREEN}日志自动清理已设置!${NC}"
    echo -e "${YELLOW}清理频率: $cron_expr${NC}"
    echo -e "${YELLOW}清理脚本: /usr/local/bin/vps-toolbox-log-clean.sh${NC}"
}

clean_all_logs() {
    echo ""
    echo -e "${RED}警告: 此操作将清空所有日志!${NC}"
    read -rp "确认清理? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        clean_journal_logs
        clean_var_logs
        clean_proxy_logs
        echo ""
        echo -e "${GREEN}所有日志清理完成!${NC}"
    else
        echo -e "${YELLOW}已取消${NC}"
    fi
}

show_banner() {

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo -e "${GREEN}           VPS Toolbox - 多功能一键部署工具 v3.5.0${NC}"

    echo -e "${CYAN}============================================================${NC}"

    if [[ "$IS_IPV6_ONLY" == "true" ]]; then
        echo -e "  ${YELLOW}网络模式${NC}: ${CYAN}IPv6-only (WARP)${NC}"
    fi

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

    echo -e "  ${YELLOW}[系统维护]${NC}"

    echo "    20. Swap 管理"

    echo "    21. 日志管理"

    echo ""

    echo -e "  ${YELLOW}[管理]${NC}"

    echo "    22. 查看所有配置"

    echo "    23. 生成订阅链接"

    echo "    24. 流量统计"

    echo "    25. 使用统计详情"

    echo "    26. IP 综合体检"

    echo "    27. 卸载服务"

    echo ""

    echo -e "  ${YELLOW}[容器]${NC}"

    echo "    28. Docker 应用商店"

    echo ""

    echo -e "  ${YELLOW}[备份]${NC}"

    echo "    29. 配置备份与还原"

    echo "    0. 退出脚本"

    echo ""

    echo -e "${CYAN}============================================================${NC}"

    echo ""

}

# ==================== Docker 应用商店 ====================

check_docker_installed() {
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        return 0
    fi
    return 1
}

install_docker_engine() {
    if check_docker_installed; then
        echo -e "${GREEN}Docker 已安装${NC}"
        docker --version
        echo ""
        read -rp "是否配置/更换国内镜像源? [y/N]: " cfg_mirror
        if [[ "$cfg_mirror" == "y" || "$cfg_mirror" == "Y" ]]; then
            _setup_docker_mirror
        fi
        return 0
    fi
    echo -e "${YELLOW}正在安装 Docker...${NC}"
    if curl -fsSL https://get.docker.com | bash; then
        systemctl enable docker --now 2>/dev/null || service docker start 2>/dev/null || true
        echo -e "${GREEN}Docker 安装完成${NC}"
        docker --version
        echo ""
        read -rp "是否配置国内镜像源加速? [y/N]: " cfg_mirror
        if [[ "$cfg_mirror" == "y" || "$cfg_mirror" == "Y" ]]; then
            _setup_docker_mirror
        fi
    else
        error "Docker 安装失败"
    fi
}

_setup_docker_mirror() {
    echo ""
    echo -e "${YELLOW}可用镜像源:${NC}"
    echo "  1. 阿里云 (需要登录获取专属地址)"
    echo "  2. 中科大 (docker.mirrors.ustc.edu.cn)"
    echo "  3. Docker Proxy (dockerproxy.net)"
    echo "  4. 网易云 (hub-mirror.c.163.com)"
    echo "  5. 腾讯云 (mirror.ccs.tencentyun.com)"
    echo "  6. DaoCloud (m.daocloud.io)"
    echo "  7. 自定义"
    echo "  8. 返回"
    echo ""
    read -rp "请选择 [1-8]: " mirror_choice
    
    local mirror_url=""
    case $mirror_choice in
        1) mirror_url="https://docker.mirrors.aliyun.com" ;;
        2) mirror_url="https://docker.mirrors.ustc.edu.cn" ;;
        3) mirror_url="https://dockerproxy.net" ;;
        4) mirror_url="https://hub-mirror.c.163.com" ;;
        5) mirror_url="https://mirror.ccs.tencentyun.com" ;;
        6) mirror_url="https://m.daocloud.io" ;;
        7)
            read -rp "请输入镜像源地址: " custom_mirror
            mirror_url="$custom_mirror"
            ;;
        8) return ;;
        *) warn "无效选择"; return ;;
    esac
    
    if [[ -n "$mirror_url" ]]; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["${mirror_url}"]
}
EOF
        systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
        echo -e "${GREEN}镜像源已配置: ${mirror_url}${NC}"
        echo -e "${YELLOW}正在测试拉取...${NC}"
        if docker pull hello-world >/dev/null 2>&1; then
            echo -e "${GREEN}镜像源测试成功!${NC}"
            docker rmi hello-world >/dev/null 2>&1 || true
        else
            echo -e "${YELLOW}镜像源测试可能受限，请确认网络环境${NC}"
        fi
    fi
}

_docker_check_port() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tln 2>/dev/null | grep -qE ":${port}\b" && return 1
    elif command -v netstat &>/dev/null; then
        netstat -tln 2>/dev/null | grep -qE ":${port}\b" && return 1
    fi
    # Fallback: try to bind to the port
    if command -v python3 &>/dev/null; then
        python3 -c "import socket; s=socket.socket(); s.bind(('',${port})); s.close()" 2>/dev/null || return 1
    elif command -v python &>/dev/null; then
        python -c "import socket; s=socket.socket(); s.bind(('',${port})); s.close()" 2>/dev/null || return 1
    fi
    return 0
}

_docker_get_free_port() {
    local start="$1"
    local p="$start"
    while [[ "$p" -lt 65535 ]]; do
        if _docker_check_port "$p"; then
            echo "$p"
            return 0
        fi
        p=$((p + 1))
    done
    echo ""
}

deploy_portainer() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=9000
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 9001)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 9000 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Portainer...${NC}"
    docker volume create portainer_data 2>/dev/null || true
    docker run -d \
        --name portainer \
        --restart always \
        -p "${port}:9000" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest 2>/dev/null || \
    docker run -d \
        --name portainer \
        --restart always \
        -p "${port}:9000" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:linux-amd64
    echo -e "${GREEN}Portainer 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "首次访问需要设置管理员密码"
}

deploy_nginx_proxy_manager() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local http_port=80
    local https_port=443
    local admin_port=81
    local use_alt=0
    if ! _docker_check_port 80 || ! _docker_check_port 443 || ! _docker_check_port 81; then
        echo -e "${YELLOW}检测到 80/443/81 端口被占用${NC}"
        http_port=$(_docker_get_free_port 8080)
        https_port=$(_docker_get_free_port 8443)
        admin_port=$(_docker_get_free_port 8181)
        use_alt=1
        echo -e "${YELLOW}将使用替代端口: HTTP=${http_port}, HTTPS=${https_port}, Admin=${admin_port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Nginx Proxy Manager...${NC}"
    mkdir -p /opt/npm/{data,letsencrypt} 2>/dev/null
    docker run -d \
        --name nginx-proxy-manager \
        --restart always \
        -p "${http_port}:80" \
        -p "${https_port}:443" \
        -p "${admin_port}:81" \
        -v /opt/npm/data:/data \
        -v /opt/npm/letsencrypt:/etc/letsencrypt \
        jc21/nginx-proxy-manager:latest
    echo -e "${GREEN}Nginx Proxy Manager 部署完成!${NC}"
    if [[ "$use_alt" -eq 1 ]]; then
        echo -e "管理面板: ${CYAN}http://$(get_server_ip):${admin_port}${NC}"
    else
        echo -e "管理面板: ${CYAN}http://$(get_server_ip):81${NC}"
    fi
    echo -e "默认账号: ${YELLOW}admin@example.com${NC}"
    echo -e "默认密码: ${YELLOW}changeme${NC}"
}

deploy_uptime_kuma() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=3001
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 3002)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 3001 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Uptime Kuma...${NC}"
    mkdir -p /opt/uptime-kuma 2>/dev/null
    docker run -d \
        --name uptime-kuma \
        --restart always \
        -p "${port}:3001" \
        -v /opt/uptime-kuma:/app/data \
        louislam/uptime-kuma:latest
    echo -e "${GREEN}Uptime Kuma 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "首次访问需要创建管理员账号"
}

deploy_watchtower() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    echo -e "${YELLOW}正在部署 Watchtower (容器自动更新)...${NC}"
    docker run -d \
        --name watchtower \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower:latest \
        --cleanup --schedule "0 0 4 * * *"
    echo -e "${GREEN}Watchtower 部署完成!${NC}"
    echo -e "每天 04:00 自动检查并更新所有容器"
}

deploy_adguard_home() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=3000
    local dns_port=53
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 3002)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 3000 被占用，管理面板将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 AdGuard Home...${NC}"
    mkdir -p /opt/adguardhome/{work,conf} 2>/dev/null
    docker run -d \
        --name adguardhome \
        --restart always \
        -p "${port}:3000" \
        -p "53:53/tcp" \
        -p "53:53/udp" \
        -p "853:853/tcp" \
        -v /opt/adguardhome/work:/opt/adguardhome/work \
        -v /opt/adguardhome/conf:/opt/adguardhome/conf \
        adguard/adguardhome:latest
    echo -e "${GREEN}AdGuard Home 部署完成!${NC}"
    echo -e "管理面板: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "DNS 端口: ${CYAN}53${NC}"
}

deploy_nextcloud() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=8080
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 8081)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 8080 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Nextcloud...${NC}"
    mkdir -p /opt/nextcloud 2>/dev/null
    docker run -d \
        --name nextcloud \
        --restart always \
        -p "${port}:80" \
        -v /opt/nextcloud:/var/www/html \
        nextcloud:latest
    echo -e "${GREEN}Nextcloud 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "首次访问需要创建管理员账号"
}

deploy_alist() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=5244
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 5245)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 5244 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Alist...${NC}"
    mkdir -p /opt/alist 2>/dev/null
    docker run -d \
        --name alist \
        --restart always \
        -p "${port}:5244" \
        -v /opt/alist:/opt/alist/data \
        xhofe/alist:latest
    echo -e "${GREEN}Alist 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "默认账号: ${YELLOW}admin${NC}"
    echo -e "默认密码: ${YELLOW}从容器日志获取${NC}"
    echo -e "获取密码命令: ${CYAN}docker logs alist | grep password${NC}"
}

deploy_vaultwarden() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=3010
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 3011)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 3010 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Vaultwarden (密码管理器)...${NC}"
    mkdir -p /opt/vaultwarden 2>/dev/null
    docker run -d \
        --name vaultwarden \
        --restart always \
        -p "${port}:80" \
        -v /opt/vaultwarden:/data \
        vaultwarden/server:latest
    echo -e "${GREEN}Vaultwarden 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "首次访问需要创建管理员账号"
}

deploy_qbittorrent() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=8085
    local bt_port=6881
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 8086)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 8085 被占用，Web 将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 qBittorrent...${NC}"
    mkdir -p /opt/qbittorrent/{config,downloads} 2>/dev/null
    docker run -d \
        --name qbittorrent \
        --restart always \
        -p "${port}:8080" \
        -p "${bt_port}:${bt_port}" \
        -p "${bt_port}:${bt_port}/udp" \
        -v /opt/qbittorrent/config:/config \
        -v /opt/qbittorrent/downloads:/downloads \
        -e PUID=1000 -e PGID=1000 \
        linuxserver/qbittorrent:latest
    echo -e "${GREEN}qBittorrent 部署完成!${NC}"
    echo -e "Web 地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "默认账号: ${YELLOW}admin${NC}"
    echo -e "默认密码: ${YELLOW}从容器日志获取${NC}"
    echo -e "获取密码: ${CYAN}docker logs qbittorrent | grep password${NC}"
}

deploy_jellyfin() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=8096
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 8097)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 8096 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Jellyfin (媒体服务器)...${NC}"
    mkdir -p /opt/jellyfin/{config,cache,media} 2>/dev/null
    docker run -d \
        --name jellyfin \
        --restart always \
        -p "${port}:8096" \
        -v /opt/jellyfin/config:/config \
        -v /opt/jellyfin/cache:/cache \
        -v /opt/jellyfin/media:/media \
        jellyfin/jellyfin:latest
    echo -e "${GREEN}Jellyfin 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "首次访问需要初始化设置"
}

deploy_redis() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=6379
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 6380)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 6379 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Redis...${NC}"
    mkdir -p /opt/redis 2>/dev/null
    docker run -d \
        --name redis \
        --restart always \
        -p "${port}:6379" \
        -v /opt/redis:/data \
        redis:latest redis-server --appendonly yes
    echo -e "${GREEN}Redis 部署完成!${NC}"
    echo -e "连接地址: ${CYAN}$(get_server_ip):${port}${NC}"
    echo -e "默认无密码，生产环境请配置认证"
}

deploy_mysql() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=3306
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 3307)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 3306 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 MySQL...${NC}"
    mkdir -p /opt/mysql 2>/dev/null
    docker run -d \
        --name mysql \
        --restart always \
        -p "${port}:3306" \
        -v /opt/mysql:/var/lib/mysql \
        -e MYSQL_ROOT_PASSWORD=root123456 \
        mysql:8.0
    echo -e "${GREEN}MySQL 部署完成!${NC}"
    echo -e "连接地址: ${CYAN}$(get_server_ip):${port}${NC}"
    echo -e "root 密码: ${YELLOW}root123456${NC}"
}

deploy_memos() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=5230
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 5231)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 5230 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Memos (轻量笔记)...${NC}"
    mkdir -p /opt/memos 2>/dev/null
    docker run -d \
        --name memos \
        --restart always \
        -p "${port}:5230" \
        -v /opt/memos:/var/opt/memos \
        neosmemo/memos:latest
    echo -e "${GREEN}Memos 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
}

deploy_aria2() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=6880
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 6881)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 6880 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Aria2 + AriaNg...${NC}"
    mkdir -p /opt/aria2/{config,downloads} 2>/dev/null
    docker run -d \
        --name aria2 \
        --restart always \
        -p "${port}:80" \
        -p "6800:6800" \
        -v /opt/aria2/config:/aria2/conf \
        -v /opt/aria2/downloads:/aria2/downloads \
        -e PUID=1000 -e PGID=1000 \
        p3terx/ariang:latest
    echo -e "${GREEN}Aria2 + AriaNg 部署完成!${NC}"
    echo -e "Web 地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "RPC 端口: ${CYAN}6800${NC}"
    echo -e "默认 RPC Secret: ${YELLOW}从容器日志获取${NC}"
}

deploy_searxng() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=8089
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 8090)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 8089 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 SearXNG (私有搜索引擎)...${NC}"
    mkdir -p /opt/searxng 2>/dev/null
    docker run -d \
        --name searxng \
        --restart always \
        -p "${port}:8080" \
        -v /opt/searxng:/etc/searxng \
        -e BASE_URL="http://$(get_server_ip):${port}/" \
        searxng/searxng:latest
    echo -e "${GREEN}SearXNG 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
}

deploy_code_server() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=8443
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 8444)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 8443 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Code Server (VS Code 网页版)...${NC}"
    mkdir -p /opt/code-server 2>/dev/null
    docker run -d \
        --name code-server \
        --restart always \
        -p "${port}:8443" \
        -v /opt/code-server:/home/coder \
        -e PASSWORD=vps123456 \
        codercom/code-server:latest
    echo -e "${GREEN}Code Server 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "密码: ${YELLOW}vps123456${NC}"
}

deploy_1panel() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=10086
    local ssh_port=10087
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 10088)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 10086 被占用，面板将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 1Panel (Linux 运维面板)...${NC}"
    echo -e "${YELLOW}这将需要几分钟...${NC}"
    mkdir -p /opt/1panel 2>/dev/null
    docker run -d \
        --name 1panel \
        --restart always \
        -p "${port}:10086" \
        -p "${ssh_port}:10087" \
        -v /opt/1panel:/opt/1panel \
        -v /var/run/docker.sock:/var/run/docker.sock \
        moelin/1panel:latest
    echo -e "${GREEN}1Panel 部署完成!${NC}"
    echo -e "面板地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "默认账号: ${YELLOW}1panel${NC}"
    echo -e "默认密码: ${YELLOW}1panel_password${NC}"
}

deploy_sun_panel() {
    if ! check_docker_installed; then
        echo -e "${YELLOW}Docker 未安装，先执行安装...${NC}"
        install_docker_engine
    fi
    local port=3005
    if ! _docker_check_port "$port"; then
        port=$(_docker_get_free_port 3006)
        if [[ -z "$port" ]]; then
            error "无法找到可用端口"
        fi
        echo -e "${YELLOW}端口 3005 被占用，将使用端口 ${port}${NC}"
    fi
    echo -e "${YELLOW}正在部署 Sun-Panel (NAS 导航面板)...${NC}"
    mkdir -p /opt/sun-panel/{database,uploads,conf} 2>/dev/null
    docker run -d \
        --name sun-panel \
        --restart always \
        -p "${port}:3002" \
        -v /opt/sun-panel/database:/app/database \
        -v /opt/sun-panel/uploads:/app/uploads \
        -v /opt/sun-panel/conf:/app/conf \
        hslr/sun-panel:latest
    echo -e "${GREEN}Sun-Panel 部署完成!${NC}"
    echo -e "访问地址: ${CYAN}http://$(get_server_ip):${port}${NC}"
    echo -e "默认账号: ${YELLOW}admin@sun.cc${NC}"
    echo -e "默认密码: ${YELLOW}12345678${NC}"
}

docker_container_mgmt() {
    if ! check_docker_installed; then
        warn "Docker 未安装"
        return
    fi
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Docker 容器管理${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo "  1. 查看运行中的容器"
    echo "  2. 查看所有容器"
    echo "  3. 启动容器"
    echo "  4. 停止容器"
    echo "  5. 重启容器"
    echo "  6. 删除容器"
    echo "  7. 查看容器日志"
    echo "  8. 清理未使用的镜像/卷/网络"
    echo "  9. 返回"
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    read -rp "请选择 [1-9]: " cm_choice
    case $cm_choice in
        1)
            echo ""
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
        2)
            echo ""
            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
        3)
            read -rp "请输入容器名称: " cname
            [[ -n "$cname" ]] && docker start "$cname"
            ;;
        4)
            read -rp "请输入容器名称: " cname
            [[ -n "$cname" ]] && docker stop "$cname"
            ;;
        5)
            read -rp "请输入容器名称: " cname
            [[ -n "$cname" ]] && docker restart "$cname"
            ;;
        6)
            read -rp "请输入容器名称: " cname
            if [[ -n "$cname" ]]; then
                read -rp "确认删除? 输入 y: " cfm
                [[ "$cfm" == "y" ]] && docker rm -f "$cname"
            fi
            ;;
        7)
            read -rp "请输入容器名称: " cname
            [[ -n "$cname" ]] && docker logs --tail 50 "$cname"
            ;;
        8)
            echo -e "${YELLOW}正在清理...${NC}"
            docker system prune -f
            docker volume prune -f
            echo -e "${GREEN}清理完成${NC}"
            ;;
        9) return ;;
        *) warn "无效选择" ;;
    esac
    echo ""
    read -rp "按回车键继续..."
}

docker_manager() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    Docker 应用商店${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    if check_docker_installed; then
        echo -e "${GREEN}Docker 状态: 已安装${NC}"
        docker --version 2>/dev/null
    else
        echo -e "${YELLOW}Docker 状态: 未安装${NC}"
    fi
    echo ""
    echo -e "${YELLOW}环境:${NC}"
    echo "    1. 安装/更新 Docker 环境"
    echo ""
    echo -e "${YELLOW}常用应用:${NC}"
    echo "    2. Portainer (Docker 可视化管理)"
    echo "    3. Nginx Proxy Manager (反向代理+SSL)"
    echo "    4. Uptime Kuma (服务监控)"
    echo "    5. Watchtower (容器自动更新)"
    echo "    6. AdGuard Home (DNS 去广告)"
    echo "    7. Nextcloud (私有网盘)"
    echo "    8. Alist (多网盘聚合)"
    echo ""
    echo -e "${YELLOW}媒体与下载:${NC}"
    echo "    11. qBittorrent (BT下载)"
    echo "    12. Jellyfin (媒体服务器)"
    echo "    13. Aria2 + AriaNg (离线下载)"
    echo ""
    echo -e "${YELLOW}工具:${NC}"
    echo "    14. Vaultwarden (密码管理器)"
    echo "    15. Memos (轻量笔记)"
    echo "    16. SearXNG (私有搜索引擎)"
    echo "    17. Code Server (VS Code网页版)"
    echo ""
    echo -e "${YELLOW}运维面板:${NC}"
    echo "    18. 1Panel (Linux运维面板)"
    echo "    19. Sun-Panel (NAS导航面板)"
    echo ""
    echo -e "${YELLOW}数据库:${NC}"
    echo "    20. Redis"
    echo "    21. MySQL"
    echo ""
    echo -e "${YELLOW}管理:${NC}"
    echo "    9. 容器管理"
    echo "    10. 返回主菜单"
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    read -rp "请选择 [1-21]: " dk_choice
    case $dk_choice in
        1) install_docker_engine ;;
        2) deploy_portainer ;;
        3) deploy_nginx_proxy_manager ;;
        4) deploy_uptime_kuma ;;
        5) deploy_watchtower ;;
        6) deploy_adguard_home ;;
        7) deploy_nextcloud ;;
        8) deploy_alist ;;
        9) docker_container_mgmt ;;
        10) return ;;
        11) deploy_qbittorrent ;;
        12) deploy_jellyfin ;;
        13) deploy_aria2 ;;
        14) deploy_vaultwarden ;;
        15) deploy_memos ;;
        16) deploy_searxng ;;
        17) deploy_code_server ;;
        18) deploy_1panel ;;
        19) deploy_sun_panel ;;
        20) deploy_redis ;;
        21) deploy_mysql ;;
        *) warn "无效选择" ;;
    esac
    echo ""
    read -rp "按回车键继续..."
}

# ==================== 配置备份与还原 ====================

BACKUP_DIR="/etc/vps-toolbox/backups"

_init_backup_dir() {
    [[ -d "$BACKUP_DIR" ]] || mkdir -p "$BACKUP_DIR"
}

create_backup() {
    _init_backup_dir
    echo ""
    echo -e "${YELLOW}正在扫描需要备份的配置...${NC}"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local tmp_list="/tmp/vps-toolbox-backup-${ts}.list"
    : > "$tmp_list"
    local items=()
    [[ -d "/etc/vps-toolbox" ]] && items+=("/etc/vps-toolbox")
    [[ -d "/etc/nginx/conf.d" ]] && items+=("/etc/nginx/conf.d")
    [[ -f "/etc/nginx/nginx.conf" ]] && items+=("/etc/nginx/nginx.conf")
    [[ -d "/etc/caddy" ]] && items+=("/etc/caddy")
    [[ -d "/var/www/vps-toolbox-site" ]] && items+=("/var/www/vps-toolbox-site")
    [[ -d "/etc/systemd/system" ]] && {
        find /etc/systemd/system -maxdepth 1 -name "vps-toolbox-*" >> "$tmp_list" 2>/dev/null
    }
    [[ -d "/etc/letsencrypt" ]] && items+=("/etc/letsencrypt")
    [[ -d "/root/.local/share/caddy" ]] && items+=("/root/.local/share/caddy")
    [[ -f "/etc/crontab" ]] && items+=("/etc/crontab")
    [[ -d "/etc/cron.d" ]] && {
        find /etc/cron.d -maxdepth 1 -name "*vps*" >> "$tmp_list" 2>/dev/null
    }
    for item in "${items[@]}"; do
        echo "$item" >> "$tmp_list"
    done
    local file_count
    file_count=$(wc -l < "$tmp_list" | tr -d ' ')
    if [[ "$file_count" -eq 0 ]]; then
        echo -e "${YELLOW}没有找到可备份的配置${NC}"
        rm -f "$tmp_list"
        return
    fi
    echo -e "发现 ${GREEN}${file_count}${NC} 项配置"
    echo ""
    read -rp "是否设置加密密码? (直接回车不加密): " bk_pwd
    local backup_file="${BACKUP_DIR}/vps-toolbox-backup-${ts}.tar.gz"
    echo -e "${YELLOW}正在打包备份...${NC}"
    if tar czf "$backup_file" -T "$tmp_list" 2>/dev/null; then
        rm -f "$tmp_list"
        if [[ -n "$bk_pwd" ]]; then
            local enc_file="${backup_file}.enc"
            if openssl enc -aes-256-cbc -salt -in "$backup_file" -out "$enc_file" -k "$bk_pwd" 2>/dev/null; then
                rm -f "$backup_file"
                backup_file="$enc_file"
                echo -e "${GREEN}加密备份完成!${NC}"
            else
                echo -e "${YELLOW}加密失败，保留未加密备份${NC}"
            fi
        else
            echo -e "${GREEN}备份完成!${NC}"
        fi
        local size
        size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        echo -e "备份文件: ${CYAN}${backup_file}${NC}"
        echo -e "文件大小: ${CYAN}${size}${NC}"
        ls -t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null | tail -n +11 | xargs -r rm -f
    else
        rm -f "$tmp_list"
        error "备份打包失败"
    fi
}

restore_backup() {
    _init_backup_dir
    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有找到备份文件${NC}"
        return
    fi
    echo ""
    echo -e "${YELLOW}可用的备份文件:${NC}"
    local i=1
    for bk in "${backups[@]}"; do
        local sz
        sz=$(du -h "$bk" 2>/dev/null | cut -f1)
        local name
        name=$(basename "$bk")
        echo "  ${i}. ${name} (${sz})"
        ((i++))
    done
    echo ""
    read -rp "请选择要还原的备份编号 (0取消): " bk_idx
    if [[ -z "$bk_idx" ]] || [[ "$bk_idx" == "0" ]]; then
        return
    fi
    if ! [[ "$bk_idx" =~ ^[0-9]+$ ]] || [[ "$bk_idx" -lt 1 ]] || [[ "$bk_idx" -gt ${#backups[@]} ]]; then
        warn "无效选择"
        return
    fi
    local selected
    selected="${backups[$((bk_idx-1))]}"
    local is_enc=0
    if [[ "$selected" == *.enc ]]; then
        is_enc=1
        read -rsp "请输入解密密码: " dec_pwd
        echo ""
        local dec_file="${selected%.enc}.tmp"
        if ! openssl enc -aes-256-cbc -d -in "$selected" -out "$dec_file" -k "$dec_pwd" 2>/dev/null; then
            rm -f "$dec_file"
            error "解密失败，密码错误"
        fi
        selected="$dec_file"
    fi
    echo ""
    echo -e "${RED}警告: 还原将覆盖现有配置!${NC}"
    read -rp "确认还原? 输入 [确认还原] 继续: " cfm
    if [[ "$cfm" != "确认还原" ]]; then
        [[ "$is_enc" -eq 1 ]] && rm -f "$selected"
        echo -e "${YELLOW}已取消${NC}"
        return
    fi
    echo -e "${YELLOW}正在还原...${NC}"
    systemctl stop vps-toolbox-bot 2>/dev/null || true
    systemctl stop vps-toolbox-sub-http 2>/dev/null || true
    systemctl stop vps-toolbox-ddns 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    systemctl stop caddy 2>/dev/null || true
    if tar xzf "$selected" -C / 2>/dev/null; then
        echo -e "${GREEN}还原完成!${NC}"
        echo -e "${YELLOW}正在重启相关服务...${NC}"
        systemctl daemon-reload 2>/dev/null || true
        systemctl restart nginx 2>/dev/null || true
        systemctl restart caddy 2>/dev/null || true
        systemctl restart vps-toolbox-bot 2>/dev/null || true
        systemctl restart vps-toolbox-sub-http 2>/dev/null || true
        systemctl restart vps-toolbox-ddns 2>/dev/null || true
        echo -e "${GREEN}服务已重启${NC}"
    else
        error "还原失败"
    fi
    [[ "$is_enc" -eq 1 ]] && rm -f "$selected"
}

list_backups() {
    _init_backup_dir
    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有备份文件${NC}"
        return
    fi
    echo ""
    echo -e "${CYAN}备份列表:${NC}"
    local i=1
    for bk in "${backups[@]}"; do
        local sz
        sz=$(du -h "$bk" 2>/dev/null | cut -f1)
        local name
        name=$(basename "$bk")
        local enc_mark=""
        [[ "$name" == *.enc ]] && enc_mark=" [已加密]"
        echo "  ${i}. ${name} (${sz})${enc_mark}"
        ((i++))
    done
}

delete_backup() {
    _init_backup_dir
    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有备份文件${NC}"
        return
    fi
    list_backups
    echo ""
    read -rp "请输入要删除的备份编号 (0取消, all删除全部): " bk_idx
    if [[ -z "$bk_idx" ]] || [[ "$bk_idx" == "0" ]]; then
        return
    fi
    if [[ "$bk_idx" == "all" ]]; then
        read -rp "确认删除所有备份? 输入 y: " cfm
        if [[ "$cfm" == "y" ]]; then
            rm -f "${BACKUP_DIR}"/*.tar.gz*
            echo -e "${GREEN}所有备份已删除${NC}"
        fi
        return
    fi
    if ! [[ "$bk_idx" =~ ^[0-9]+$ ]] || [[ "$bk_idx" -lt 1 ]] || [[ "$bk_idx" -gt ${#backups[@]} ]]; then
        warn "无效选择"
        return
    fi
    local selected
    selected="${backups[$((bk_idx-1))]}"
    rm -f "$selected"
    echo -e "${GREEN}已删除: $(basename "$selected")${NC}"
}

backup_manager() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN}                    配置备份与还原${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        echo "  1. 创建备份"
        echo "  2. 还原备份"
        echo "  3. 查看备份列表"
        echo "  4. 删除备份"
        echo "  5. 返回主菜单"
        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo ""
        read -rp "请选择 [1-5]: " bu_choice
        case $bu_choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) list_backups ;;
            4) delete_backup ;;
            5) return ;;
            *) warn "无效选择" ;;
        esac
        echo ""
        read -rp "按回车键继续..."
    done
}

main() {

    check_root

    check_system

    # IPv6-only 环境检测
    if check_ipv6_only; then
        IS_IPV6_ONLY=true
        log "检测到 IPv6-only 环境"
    else
        IS_IPV6_ONLY=false
    fi

    record_usage

    install_dependencies

    

    while true; do

        show_menu

        read -rp "请选择操作 [0-29]: " choice

        

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

            20) manage_swap ;;

            21) manage_logs ;;

            22) view_config ;;

            23) show_subscription ;;

            24) show_traffic_stats ;;

            25) view_stats_menu ;;

            26) ip_health_check ;;

            27) uninstall_service ;;

            28) docker_manager ;;

            29) backup_manager ;;

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

