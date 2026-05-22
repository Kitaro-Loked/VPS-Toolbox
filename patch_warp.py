#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Replace WARP functions with multi-option version - BINARY MODE to preserve LF"""

# Read original file in BINARY mode to preserve LF line endings
with open('install.sh', 'rb') as f:
    content = f.read()

# Find setup_warp function (search in bytes)
start_marker = b'setup_warp() {'
end_marker = b'# ==================== \xe5\x8d\x8f\xe8\xae\xae\xe5\xae\x89\xe8\xa3\x85'

start = content.find(start_marker)
end = content.find(end_marker)

if start == -1 or end == -1:
    print(f'ERROR: start={start}, end={end}')
    exit(1)

# New WARP functions with LF line endings (bytes)
new_warp = b'''setup_warp() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}                    WARP \xe7\xbd\x91\xe7\xbb\x9c\xe9\x85\x8d\xe7\xbd\xae${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}\xe8\xaf\xb7\xe9\x80\x89\xe6\x8b\xa9 WARP \xe5\xae\x89\xe8\xa3\x85\xe6\x96\xb9\xe5\xbc\x8f:${NC}"
    echo ""
    echo "  1. \xe5\xae\x98\xe6\x96\xb9 Cloudflare WARP (\xe6\x8e\xa8\xe8\x8d\x90\xef\xbc\x8c\xe5\x8a\x9f\xe8\x83\xbd\xe6\x9c\x80\xe5\x85\xa8)"
    echo "     - \xe6\x94\xaf\xe6\x8c\x81\xe5\x85\xa8\xe5\xb1\x80\xe4\xbb\xa3\xe7\x90\x86 / \xe5\x88\x86\xe6\xb5\x81\xe6\xa8\xa1\xe5\xbc\x8f"
    echo "     - \xe9\x9c\x80\xe8\xa6\x81 TUN \xe6\xa8\xa1\xe5\x9d\x97\xe6\x94\xaf\xe6\x8c\x81"
    echo "     - \xe4\xbd\x93\xe7\xa7\xaf\xe8\xbe\x83\xe5\xa4\xa7 (~200MB)"
    echo ""
    echo "  2. fscarmen WARP \xe8\x84\x9a\xe6\x9c\xac (\xe8\xbd\xbb\xe9\x87\x8f\xef\xbc\x8cLXC\xe5\x85\xbc\xe5\xae\xb9)"
    echo "     - \xe6\x94\xaf\xe6\x8c\x81 WireGuard / WireProxy \xe6\xa8\xa1\xe5\xbc\x8f"
    echo "     - \xe6\x94\xaf\xe6\x8c\x81 IPv4/IPv6 \xe5\x8f\x8c\xe6\xa0\x88"
    echo "     - \xe8\x87\xaa\xe5\x8a\xa8\xe9\x80\x82\xe9\x85\x8d\xe5\x86\x85\xe6\xa0\xb8\xe7\x89\x88\xe6\x9c\xac"
    echo "     - LXC / OpenVZ \xe5\xae\xb9\xe5\x99\xa8\xe5\x8f\xaf\xe7\x94\xa8"
    echo ""
    echo "  3. \xe8\xbf\x94\xe5\x9b\x9e\xe4\xb8\xbb\xe8\x8f\x9c\xe5\x8d\x95"
    echo ""
    read -rp "\xe8\xaf\xb7\xe9\x80\x89\xe6\x8b\xa9 [1-3]: " warp_choice
    
    case $warp_choice in
        1) setup_warp_official ;;
        2) setup_warp_fscarmen ;;
        3) return ;;
        *) warn "\xe6\x97\xa0\xe6\x95\x88\xe9\x80\x89\xe6\x8b\xa9" ;;
    esac
}

# \xe5\xae\x98\xe6\x96\xb9 Cloudflare WARP
setup_warp_official() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}              \xe5\xae\x98\xe6\x96\xb9 Cloudflare WARP \xe5\xae\x89\xe8\xa3\x85${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    log "\xe6\xad\xa3\xe5\x9c\xa8\xe5\xae\x89\xe8\xa3\x85\xe5\xae\x98\xe6\x96\xb9 Cloudflare WARP..."
    
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null || true
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
    apt-get update >/dev/null 2>&1 && apt-get install -y cloudflare-warp >/dev/null 2>&1 || true
    
    warp-cli registration new 2>/dev/null || true
    warp-cli connect 2>/dev/null || true
    
    log "\xe5\xae\x98\xe6\x96\xb9 WARP \xe5\xae\x89\xe8\xa3\x85\xe5\xae\x8c\xe6\x88\x90"
    echo ""
    echo -e "${YELLOW}\xe5\xb8\xb8\xe7\x94\xa8\xe5\x91\xbd\xe4\xbb\xa4:${NC}"
    echo "  warp-cli status     - \xe6\x9f\xa5\xe7\x9c\x8b\xe7\x8a\xb6\xe6\x80\x81"
    echo "  warp-cli connect    - \xe8\xbf\x9e\xe6\x8e\xa5"
    echo "  warp-cli disconnect - \xe6\x96\xad\xe5\xbc\x80"
    echo ""
    read -rp "\xe6\x8c\x89\xe5\x9b\x9e\xe8\xbd\xa6\xe9\x94\xae\xe7\xbb\xa7\xe7\xbb\xad..."
}

# fscarmen WARP \xe8\x84\x9a\xe6\x9c\xac (\xe8\xbd\xbb\xe9\x87\x8f\xef\xbc\x8cLXC\xe5\x85\xbc\xe5\xae\xb9)
setup_warp_fscarmen() {
    clear
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}            fscarmen WARP \xe8\x84\x9a\xe6\x9c\xac (\xe8\xbd\xbb\xe9\x87\x8f\xe7\x89\x88)${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}\xe5\x8d\xb3\xe5\xb0\x86\xe8\xbf\x90\xe8\xa1\x8c fscarmen \xe7\x9a\x84 WARP \xe8\x84\x9a\xe6\x9c\xac...${NC}"
    echo ""
    echo -e "${GREEN}\xe8\xaf\xa5\xe8\x84\x9a\xe6\x9c\xac\xe7\x89\xb9\xe7\x82\xb9:${NC}"
    echo "  - \xe6\x94\xaf\xe6\x8c\x81 LXC / OpenVZ \xe5\xae\xb9\xe5\x99\xa8"
    echo "  - \xe8\x87\xaa\xe5\x8a\xa8\xe6\xa3\x80\xe6\xb5\x8b\xe5\x86\x85\xe6\xa0\xb8\xe7\x89\x88\xe6\x9c\xac\xef\xbc\x8c\xe9\x80\x82\xe9\x85\x8d wireguard / wireguard-go"
    echo "  - \xe6\x94\xaf\xe6\x8c\x81 WARP+ / Teams \xe8\xb4\xa6\xe6\x88\xb7"
    echo "  - \xe6\x94\xaf\xe6\x8c\x81 Netflix \xe8\xa7\xa3\xe9\x94\x81\xe6\xa3\x80\xe6\xb5\x8b"
    echo ""
    echo -e "${YELLOW}\xe5\xae\x89\xe8\xa3\x85\xe5\x90\x8e\xe5\x8f\xaf\xe7\x94\xa8 warp \xe5\x91\xbd\xe4\xbb\xa4\xe7\xae\xa1\xe7\x90\x86:${NC}"
    echo "  warp n   - \xe8\x8e\xb7\xe5\x8f\x96 WARP IP"
    echo "  warp o   - \xe4\xb8\xb4\xe6\x97\xb6\xe5\x85\xb3\xe9\x97\xad WARP"
    echo "  warp u   - \xe5\x8d\xb8\xe8\xbd\xbd WARP"
    echo "  warp 4   - \xe6\xb7\xbb\xe5\x8a\xa0 IPv4 WARP"
    echo "  warp 6   - \xe6\xb7\xbb\xe5\x8a\xa0 IPv6 WARP"
    echo "  warp d   - \xe6\xb7\xbb\xe5\x8a\xa0\xe5\x8f\x8c\xe6\xa0\x88 WARP"
    echo "  warp c   - Socks5 \xe4\xbb\xa3\xe7\x90\x86\xe6\xa8\xa1\xe5\xbc\x8f"
    echo "  warp w   - WireProxy \xe6\xa8\xa1\xe5\xbc\x8f"
    echo ""
    read -rp "\xe7\xa1\xae\xe8\xae\xa4\xe5\xae\x89\xe8\xa3\x85? [Y/n]: " confirm
    
    if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
        log "\xe6\xad\xa3\xe5\x9c\xa8\xe4\xb8\x8b\xe8\xbd\xbd\xe5\xb9\xb6\xe8\xbf\x90\xe8\xa1\x8c fscarmen WARP \xe8\x84\x9a\xe6\x9c\xac..."
        echo ""
        bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh)
    fi
    
    echo ""
    read -rp "\xe6\x8c\x89\xe5\x9b\x9e\xe8\xbd\xa6\xe9\x94\xae\xe7\xbb\xa7\xe7\xbb\xad..."
}

'''

# Replace content
new_content = content[:start] + new_warp + content[end:]

# Write in BINARY mode to preserve LF
with open('install.sh', 'wb') as f:
    f.write(new_content)

print('Replaced setup_warp with multi-option version (binary mode)')
