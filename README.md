# VPS Toolbox

一个功能强大的 Linux 服务器一键部署工具箱，支持 DDNS 域名自动申请与续签、WARP 配置，以及多种代理协议的无脑化安装。

## 功能特性

### DDNS 动态域名
- **Cloudflare** - 使用 Cloudflare API 管理 DNS 记录
- **DuckDNS** - 免费的动态 DNS 服务
- **No-IP** - 老牌动态 DNS 服务商
- **自动续签** - 每 5 分钟自动检测 IP 变化并更新 DNS 记录

### WARP 配置
- **官方 Cloudflare WARP** - 完整的 WARP 客户端
- **WireGuard 模式 (wgcf)** - 轻量级 WireGuard 实现
- 一键启动/停止/查看状态

### 代理协议支持

| 协议 | 特点 | 推荐度 |
|------|------|--------|
| **Vless + Reality** | 最新协议，抗检测能力强 | 5星 |
| **Hysteria2** | 基于 QUIC，速度快，抗封锁 | 5星 |
| **Shadowsocks** | 轻量简单，兼容性好 | 4星 |
| **VMess + WebSocket** | 成熟稳定，支持 CDN | 4星 |
| **Trojan + WebSocket** | 伪装 HTTPS 流量 | 4星 |

## 系统要求

- **操作系统**: Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora, AlmaLinux, Rocky Linux
- **架构**: AMD64 (x86_64)
- **权限**: Root 用户
- **网络**: 需要公网 IP (IPv4)

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh)
```

或者手动下载运行：

```bash
wget https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh
chmod +x install.sh
./install.sh
```

## 使用指南

运行脚本后会显示交互式中文菜单，按提示选择即可：

```
1. DDNS 域名申请与管理 (自动续签)
2. WARP 一键配置
3. 安装 Vless + Reality (推荐)
4. 安装 Hysteria2 (推荐)
5. 安装 Shadowsocks
6. 安装 VMess + WebSocket
7. 安装 Trojan + WebSocket
8. 查看所有配置
9. 卸载服务
0. 退出脚本
```

### DDNS 域名配置

选择 1 进入 DDNS 配置：
- **Cloudflare**: 需要 API Token 和域名
- **DuckDNS**: 需要 Token 和子域名
- **No-IP**: 需要账号密码和主机名

配置完成后会自动：
- 创建 DNS 记录
- 添加定时任务 (每5分钟检测IP变化)
- 自动更新 DNS 记录

### WARP 配置

选择 2 配置 WARP：
- 支持官方客户端和 WireGuard 两种模式
- 一键连接/断开
- 自动配置为系统代理出口

### 代理协议安装

所有协议安装流程：
1. 自动检测或输入域名
2. 自动申请/续签 SSL 证书
3. 生成随机端口和强密码/UUID
4. 自动配置并启动服务
5. 输出配置信息和分享链接
6. 生成二维码

## 文件结构

```
/etc/vps-toolbox/
├── ddns.conf           # DDNS 配置
├── update-ddns.sh      # DDNS 自动更新脚本
├── vless-info.txt      # Vless 配置信息
├── vless-link.txt      # Vless 分享链接
├── vless-qr.png        # Vless 二维码
├── hysteria2-info.txt  # Hysteria2 配置信息
├── hysteria2-link.txt  # Hysteria2 分享链接
├── hysteria2-qr.png    # Hysteria2 二维码
├── ss-info.txt         # Shadowsocks 配置信息
├── ss-link.txt         # Shadowsocks 分享链接
├── ss-qr.png           # Shadowsocks 二维码
├── vmess-info.txt      # VMess 配置信息
├── vmess-link.txt      # VMess 分享链接
├── vmess-qr.png        # VMess 二维码
├── trojan-info.txt     # Trojan 配置信息
├── trojan-link.txt     # Trojan 分享链接
└── trojan-qr.png       # Trojan 二维码
```

## 自动续签机制

### SSL 证书
- 使用 acme.sh 管理证书
- 每天凌晨 3 点自动检查续签
- 续签后自动重启相关服务

### DDNS
- 每 5 分钟检测公网 IP 变化
- IP 变化时自动更新 DNS 记录
- 支持 Cloudflare/DuckDNS/No-IP

## 常见问题

**Q: 脚本支持哪些系统？**
A: Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora, AlmaLinux, Rocky Linux

**Q: 需要提前准备域名吗？**
A: 不需要，脚本内置 DDNS 功能，可以自动申请免费域名

**Q: 证书续签失败怎么办？**
A: 检查 80 端口是否被占用，或手动运行 ~/.acme.sh/acme.sh --cron

**Q: 如何查看服务状态？**
A: 使用 systemctl status xray 或对应的服务名称

## 更新日志

### v1.0.0
- 初始版本发布
- 支持 Cloudflare/DuckDNS/No-IP DDNS
- 支持 WARP 官方客户端和 WireGuard 模式
- 支持 Vless + Reality
- 支持 Hysteria2
- 支持 Shadowsocks
- 支持 VMess + WebSocket
- 支持 Trojan + WebSocket
- 自动 SSL 证书申请和续签
- 自动 DDNS IP 更新

## 许可证

本项目采用 MIT 许可证

## 免责声明

本工具仅供学习和研究使用，请遵守当地法律法规。使用本工具产生的任何后果由使用者自行承担。
