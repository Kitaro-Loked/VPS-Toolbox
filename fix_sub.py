# -*- coding: utf-8 -*-
with open('install.sh', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add generate_subscription function after view_config function
sub_function = '''
# ==================== 订阅链接 ====================

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

'''

# Insert after view_config function (before uninstall_service)
content = content.replace(
    '# ==================== 卸载服务 ====================',
    sub_function + '# ==================== 卸载服务 ===================='
)

# 2. Update show_menu to add subscription option
old_menu = '''    echo -e "  ${YELLOW}[管理]${NC}"
    echo "    8. 查看所有配置"
    echo "    9. 卸载服务"
    echo "    0. 退出脚本"'''

new_menu = '''    echo -e "  ${YELLOW}[管理]${NC}"
    echo "    8. 查看所有配置"
    echo "    9. 生成订阅链接"
    echo "    10. 卸载服务"
    echo "    0. 退出脚本"'''

content = content.replace(old_menu, new_menu)

# 3. Update main() case statement
old_case = '''            8) view_config ;;
            9) uninstall_service ;;
            0)'''

new_case = '''            8) view_config ;;
            9) show_subscription ;;
            10) uninstall_service ;;
            0)'''

content = content.replace(old_case, new_case)

# 4. Update prompt
content = content.replace('read -rp "请选择操作 [0-9]: " choice', 'read -rp "请选择操作 [0-10]: " choice')

with open('install.sh', 'w', encoding='utf-8') as f:
    f.write(content)

print('Subscription features added!')
