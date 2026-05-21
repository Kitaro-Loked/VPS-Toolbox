# VPS Toolbox

一个功能强大的 Linux 服务器一键部署工具箱，支持 DDNS 域名自动申请与续签、WARP 配置，以及多种代理协议的无脑化安装。

> **致谢**: 本项目在设计和实现上借鉴了 [yeahwu/v2ray-wss](https://github.com/yeahwu/v2ray-wss) 的优秀思路，包括 Nginx 反代 WS + TLS、Reality SNI 伪装、Hysteria2 bing.com 伪装、Shadowsocks-rust 等技术方案。在此基础上进行了扩展和增强，增加了 DDNS 一键申请、WARP 配置、Trojan 支持、订阅链接生成、客户端配置导出等功能。

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
| 协议 | 特点 | 需要域名 | 推荐度 |
|------|------|---------|--------|
| **Vless + Reality** | 最新协议，SNI 可选，抗检测能力强 | ❌ | 5星 |
| **Hysteria2** | 基于 QUIC，bing.com 伪装，速度快 | ❌ | 5星 |
| **Shadowsocks-rust** | Rust 高性能版本，轻量简单 | ❌ | 4星 |
| **VMess + WS + TLS** | Nginx 反代 443 端口，伪装网站 | ✅ 推荐 | 4星 |
| **Trojan + WebSocket** | 伪装 HTTPS 流量 | ✅ | 4星 |
| **HTTPS 正向代理** | Caddy 实现，Surge/Clash 兼容 | ✅ | 3星 |

## 系统要求

- **操作系统**: Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora, AlmaLinux, Rocky Linux
- **架构**: AMD64 (x86_64)
- **权限**: Root 用户
- **网络**: 需要公网 IP (IPv4)

## 一键安装

### 中文版 (Chinese)

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh
bash install.sh
```

### 英文版 (English)

```bash
curl -fsSL -o install_en.sh https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install_en.sh
bash install_en.sh
```

或者使用 `wget`：

```bash
# 中文版
wget https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh
bash install.sh

# 英文版
wget https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install_en.sh
bash install_en.sh
```

## 使用指南

运行脚本后会显示交互式中文菜单，按提示选择即可：

```
[DDNS & 网络]
  1. DDNS 域名申请与管理 (自动续签)
  2. WARP 一键配置

[代理协议]
  3. 安装 Vless + Reality (无需域名，SNI可选)
  4. 安装 Hysteria2 (无需域名，bing.com伪装)
  5. 安装 Shadowsocks-rust (无需域名，高性能)
  6. 安装 VMess + WS + TLS (Nginx反代443端口)
  7. 安装 Trojan + WebSocket (需要域名)
  8. 安装 HTTPS 正向代理 (需要域名)

[管理]
  9. 查看所有配置
  10. 生成订阅链接
  11. 卸载服务
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

### v2.3.0
- **借鉴 yeahwu/v2ray-wss 技术方案**并扩展增强
- VMess+WS+TLS 改用 **Nginx 反代**（443端口，伪装网站）
- Vless Reality 增加 **SNI 选择菜单**（bing/amazon/apple/yahoo/自定义）
- Hysteria2 SNI 伪装改为 **bing.com**
- Shadowsocks 升级为 **shadowsocks-rust** 高性能版本
- 新增 **Caddy HTTPS 正向代理**（Surge/Clash 兼容）
- 新增 **端口占用检测**功能
- 所有协议支持 **客户端配置导出**（client.json）
- 所有协议支持 **IP 直连模式**（无需域名）
- 新增 **订阅链接生成**功能

### v2.2.0
- 所有协议支持 IP 直连模式（无需域名和证书）

### v2.1.x
- 修复输入验证、编码、换行符等问题
- 添加 DuckDNS 一键申请

### v1.0.0
- 初始版本发布
- 支持 Cloudflare/DuckDNS/No-IP DDNS
- 支持 WARP 官方客户端和 WireGuard 模式
- 支持 Vless + Reality / Hysteria2 / Shadowsocks / VMess + WebSocket / Trojan + WebSocket
- 自动 SSL 证书申请和续签
- 自动 DDNS IP 更新

## 许可证

本项目采用 MIT 许可证

## 免责声明

本工具仅供学习和研究使用，请遵守当地法律法规。使用本工具产生的任何后果由使用者自行承担。
