# -*- coding: utf-8 -*-
with open('install.sh', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Change version
content = content.replace('# 版本: 2.0.0', '# 版本: 2.1.2')

# Fix 2: get_domain() echo to stderr
old = 'echo -e "${GREEN}检测到已配置域名: $DDNS_DOMAIN${NC}"'
new = 'echo -e "${GREEN}检测到已配置域名: $DDNS_DOMAIN${NC}" >&2'
content = content.replace(old, new)

with open('install.sh', 'w', encoding='utf-8') as f:
    f.write(content)

print('Fix 1 & 2 applied')
