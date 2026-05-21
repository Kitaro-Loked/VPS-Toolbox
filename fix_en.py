# -*- coding: utf-8 -*-
with open('install_en.sh', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Change version
content = content.replace('# Version: 2.0.0', '# Version: 2.1.2')

# Fix 2: get_domain() echo to stderr
old = 'echo -e "${GREEN}Detected configured domain: $DDNS_DOMAIN${NC}"'
new = 'echo -e "${GREEN}Detected configured domain: $DDNS_DOMAIN${NC}" >&2'
content = content.replace(old, new)

# 3. Add generate_subscription function after view_config function
sub_function = '''
# ==================== Subscription Link ====================

generate_subscription() {
    local SUB_CONTENT=""
    
    if [[ -f "$CONFIG_DIR/vless-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/vless-link.txt")\\n"
    fi
    
    if [[ -f "$CONFIG_DIR/hysteria2-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/hysteria2-link.txt")\\n"
    fi
    
    if [[ -f "$CONFIG_DIR/ss-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/ss-link.txt")\\n"
    fi
    
    if [[ -f "$CONFIG_DIR/vmess-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/vmess-link.txt")\\n"
    fi
    
    if [[ -f "$CONFIG_DIR/trojan-link.txt" ]]; then
        SUB_CONTENT="${SUB_CONTENT}$(cat "$CONFIG_DIR/trojan-link.txt")\\n"
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
    echo -e "${CYAN}                      Subscription Link${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    
    local SUB_B64=$(generate_subscription)
    
    if [[ -z "$SUB_B64" ]]; then
        echo -e "${YELLOW}No proxy services installed yet. Cannot generate subscription link.${NC}"
        echo ""
        read -rp "Press Enter to continue..."
        return
    fi
    
    echo "$SUB_B64" | base64 -d | base64 -w 0 > "$CONFIG_DIR/subscription.txt"
    
    local SERVER_IP=$(curl -s -4 https://api.ipify.org)
    
    echo -e "${GREEN}Subscription Link (Base64):${NC}"
    echo ""
    echo "$SUB_B64"
    echo ""
    echo -e "${CYAN}----------------------------------------${NC}"
    echo ""
    echo -e "${GREEN}Online Subscription URL:${NC}"
    echo ""
    echo "  http://${SERVER_IP}:8080/sub"
    echo ""
    echo -e "${YELLOW}Tip: Paste the Base64 content into clients that support subscription links${NC}"
    echo -e "${YELLOW}Or configure Nginx/Caddy to serve $CONFIG_DIR/subscription.txt as a static file${NC}"
    echo ""
    
    if command -v python3 &>/dev/null; then
        if ! ss -tlnp | grep -q ':8080'; then
            echo -e "${GREEN}Starting temporary subscription service (port 8080)...${NC}"
            mkdir -p /tmp/vps-sub
            echo "$SUB_B64" | base64 -d | base64 -w 0 > /tmp/vps-sub/sub
            nohup python3 -m http.server 8080 --directory /tmp/vps-sub >/dev/null 2>&1 &
            echo -e "${GREEN}Subscription service started. Access via http://${SERVER_IP}:8080/sub${NC}"
            echo ""
        fi
    fi
    
    read -rp "Press Enter to continue..."
}

'''

content = content.replace(
    '# ==================== Uninstall Service ====================',
    sub_function + '# ==================== Uninstall Service ===================='
)

# Update show_menu to add subscription option
old_menu = '''    echo -e "  ${YELLOW}[Management]${NC}"
    echo "    8. View All Configurations"
    echo "    9. Uninstall Service"
    echo "    0. Exit Script"'''

new_menu = '''    echo -e "  ${YELLOW}[Management]${NC}"
    echo "    8. View All Configurations"
    echo "    9. Generate Subscription Link"
    echo "    10. Uninstall Service"
    echo "    0. Exit Script"'''

content = content.replace(old_menu, new_menu)

# Update main() case statement
old_case = '''            8) view_config ;;
            9) uninstall_service ;;
            0)'''

new_case = '''            8) view_config ;;
            9) show_subscription ;;
            10) uninstall_service ;;
            0)'''

content = content.replace(old_case, new_case)

# Update prompt
content = content.replace('read -rp "Please select an option [0-9]: " choice', 'read -rp "Please select an option [0-10]: " choice')

with open('install_en.sh', 'w', encoding='utf-8') as f:
    f.write(content)

print('EN version fixed!')
