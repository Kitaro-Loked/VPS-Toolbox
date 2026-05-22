#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Add missing functions: check_system, install_dependencies, setup_ddns"""

with open('install.sh', 'rb') as f:
    content = f.read()

# ========== 1. Add check_system and install_dependencies after check_root() ==========

# Find position after check_root() function
marker = b'check_root() {'
start = content.find(marker)
# Find the closing brace of check_root - look for next function definition pattern
# After check_root, there's a blank line then a comment or function
idx = start
brace_count = 0
found_open = False
while idx < len(content):
    if content[idx] == ord('{'):
        brace_count += 1
        found_open = True
    elif content[idx] == ord('}'):
        brace_count -= 1
        if found_open and brace_count == 0:
            break
    idx += 1

# idx now points to the closing brace of check_root
# Find the newline after it
end_check_root = content.find(b'\n', idx) + 1

new_funcs = b'''# \xe6\xa3\x80\xe6\x9f\xa5\xe7\xb3\xbb\xe7\xbb\x9f\xe7\x8e\xaf\xe5\xa2\x83
check_system() {
    log "\xe6\xa3\x80\xe6\x9f\xa5\xe7\xb3\xbb\xe7\xbb\x9f\xe7\x8e\xaf\xe5\xa2\x83..."
    
    # \xe6\xa3\x80\xe6\x9f\xa5\xe6\x93\x8d\xe4\xbd\x9c\xe7\xb3\xbb\xe7\xbb\x9f
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    # \xe6\xa3\x80\xe6\x9f\xa5\xe6\x9e\xb6\xe6\x9e\x84
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        armv7l) ARCH=arm ;;
    esac
    
    log "\xe7\xb3\xbb\xe7\xbb\x9f: $OS $VER, \xe6\x9e\xb6\xe6\x9e\x84: $ARCH"
}

# \xe5\xae\x89\xe8\xa3\x85\xe5\x9f\xba\xe7\xa1\x80\xe4\xbe\x9d\xe8\xb5\x96
install_dependencies() {
    log "\xe5\xae\x89\xe8\xa3\x85\xe5\x9f\xba\xe7\xa1\x80\xe4\xbe\x9d\xe8\xb5\x96..."
    
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
    
    # \xe7\xa1\xae\xe4\xbf\x9d cron \xe6\x9c\x8d\xe5\x8a\xa1\xe8\xbf\x90\xe8\xa1\x8c
    if command -v systemctl &>/dev/null; then
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
        systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true
    fi
    
    log "\xe4\xbe\x9d\xe8\xb5\x96\xe5\xae\x89\xe8\xa3\x85\xe5\xae\x8c\xe6\x88\x90"
}

'''

content = content[:end_check_root] + new_funcs + content[end_check_root:]

# ========== 2. Add setup_ddns function before setup_warp ==========
# Find setup_warp() and insert setup_ddns before it
warp_marker = b'setup_warp() {'
warp_pos = content.find(warp_marker)

# Find the start of the line containing setup_warp
line_start = content.rfind(b'\n', 0, warp_pos) + 1

ddns_func = b'''# DDNS \xe5\x9f\x9f\xe5\x90\x8d\xe7\x94\xb3\xe8\xaf\xb7\xe4\xb8\x8e\xe7\xae\xa1\xe7\x90\x86
setup_ddns() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}              DDNS \xe5\x9f\x9f\xe5\x90\x8d\xe7\x94\xb3\xe8\xaf\xb7\xe4\xb8\x8e\xe7\xae\xa1\xe7\x90\x86${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}DDNS \xe5\x8a\x9f\xe8\x83\xbd\xe6\x9a\x82\xe6\x9c\xaa\xe5\xae\x9e\xe7\x8e\xb0\xef\xbc\x8c\xe8\xaf\xb7\xe4\xbd\xbf\xe7\x94\xa8\xe4\xbb\xa5\xe4\xb8\x8b\xe6\x96\xb9\xe5\xbc\x8f:${NC}"
    echo ""
    echo "  1. Cloudflare DNS API + acme.sh \xe8\x87\xaa\xe5\x8a\xa8\xe7\xbb\xad\xe7\xad\xbe"
    echo "  2. DuckDNS (\xe5\x85\x8d\xe8\xb4\xb9)"
    echo "  3. No-IP (\xe5\x85\x8d\xe8\xb4\xb9)"
    echo ""
    echo -e "${YELLOW}\xe6\x8e\xa8\xe8\x8d\x90\xe4\xbd\xbf\xe7\x94\xa8 Cloudflare + acme.sh \xe7\xbb\x84\xe5\x90\x88:${NC}"
    echo ""
    echo "  curl https://get.acme.sh | sh"
    echo "  ~/.acme.sh/acme.sh --register-account -m your@email.com"
    echo "  ~/.acme.sh/acme.sh --issue --dns dns_cf -d your.domain.com"
    echo ""
    read -rp "\xe6\x8c\x89\xe5\x9b\x9e\xe8\xbd\xa6\xe9\x94\xae\xe7\xbb\xa7\xe7\xbb\xad..."
}

'''

content = content[:line_start] + ddns_func + content[line_start:]

# Write back
with open('install.sh', 'wb') as f:
    f.write(content)

print('Added check_system(), install_dependencies(), setup_ddns()')
