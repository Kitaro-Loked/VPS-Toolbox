# VPS Toolbox 🚀



一个功能强大的 Linux 服务器一键部署工具箱，支持 DDNS 域名自动申请与续签、WARP 配置，以及多种代理协议的无脑化安装。

> **🍴 本项目是 [yeahwu/v2ray-wss](https://github.com/yeahwu/v2ray-wss) 的分支/扩展版本**
>
> 核心协议安装脚本（Vless Reality / Hysteria2 / Shadowsocks-rust / VMess+WS+TLS / HTTPS正向代理）
> 全部来自 [yeahwu/v2ray-wss](https://github.com/yeahwu/v2ray-wss)，原封不动直接调用。
>
> VPS Toolbox 在此基础上增加了以下管理功能：
> - DDNS 域名一键申请（DuckDNS / Cloudflare / No-IP）
> - WARP 一键配置
> - 统一菜单系统（中文/英文）
> - 订阅链接生成
> - 服务卸载管理



[![GitHub stars](https://img.shields.io/github/stars/Kitaro-Loked/VPS-Toolbox?style=flat-square)](https://github.com/Kitaro-Loked/VPS-Toolbox)

[![License](https://img.shields.io/github/license/Kitaro-Loked/VPS-Toolbox?style=flat-square)](LICENSE)



---



## ✨ 功能特性



### 🌐 DDNS 动态域名

- **Cloudflare** - 使用 Cloudflare API 管理 DNS 记录

- **DuckDNS** - 免费的动态 DNS 服务

- **No-IP** - 老牌动态 DNS 服务商

- ⏰ **自动续签** - 每 5 分钟自动检测 IP 变化并更新 DNS 记录



### 🔒 WARP 配置

- **官方 Cloudflare WARP** - 完整的 WARP 客户端

- **WireGuard 模式 (wgcf)** - 轻量级 WireGuard 实现

- 一键启动/停止/查看状态



### 📡 代理协议支持



| 协议 | 特点 | 推荐度 |

|------|------|--------|

| **Vless + Reality** | 最新协议，抗检测能力强 | ⭐⭐⭐⭐⭐ |

| **Hysteria2** | 基于 QUIC，速度快，抗封锁 | ⭐⭐⭐⭐⭐ |

| **Shadowsocks** | 轻量简单，兼容性好 | ⭐⭐⭐⭐ |

| **VMess + WebSocket** | 成熟稳定，支持 CDN | ⭐⭐⭐⭐ |

| **Trojan + WebSocket** | 伪装 HTTPS 流量 | ⭐⭐⭐⭐ |



---



## 🏗️ 项目架构

```
┌─────────────────────────────────────────────────────┐
│                    VPS Toolbox                       │
│              (菜单外壳 + 管理功能)                    │
├─────────────────────────────────────────────────────┤
│  DDNS管理  │  WARP配置  │  订阅生成  │  服务卸载     │
├─────────────────────────────────────────────────────┤
│              调用 yeahwu/v2ray-wss 脚本              │
│   reality.sh │ hy2.sh │ ss-rust.sh │ tcp-wss.sh    │
└─────────────────────────────────────────────────────┘
```

**核心理念**: 不重复造轮子，协议安装全部委托给 yeahwu 的原版脚本，VPS Toolbox 专注于提供便捷的管理外壳。

---



## 📋 系统要求



- **操作系统**: Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora, AlmaLinux, Rocky Linux

- **架构**: AMD64 (x86_64)

- **权限**: Root 用户

- **网络**: 需要公网 IP (IPv4)



---



## 🚀 一键安装



```bash

bash <(curl -fsSL https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh)

```



或者手动下载运行：



```bash

# 下载脚本

wget https://raw.githubusercontent.com/Kitaro-Loked/VPS-Toolbox/master/install.sh



# 赋予执行权限

chmod +x install.sh



# 运行

./install.sh

```



---



## 📖 使用指南



### 主菜单



运行脚本后会显示交互式菜单：



```

╔══════════════════════════════════════════════════════════════╗

║           VPS Toolbox - 多功能一键部署工具                   ║

╠══════════════════════════════════════════════════════════════╣

║                                                              ║

║  【DDNS & 网络】                                             ║

║   1. DDNS 域名申请与管理 (自动续签)                          ║

║   2. WARP 一键配置                                           ║

║                                                              ║

║  【代理协议】                                                ║

║   3. 安装 Vless + Reality (推荐)                             ║

║   4. 安装 Hysteria2 (推荐)                                   ║

║   5. 安装 Shadowsocks                                        ║

║   6. 安装 VMess + WebSocket                                  ║

║   7. 安装 Trojan + WebSocket                                 ║

║                                                              ║

║  【管理】                                                    ║

║   8. 查看所有配置                                            ║

║   9. 卸载服务                                                ║

║   0. 退出脚本                                                ║

╚══════════════════════════════════════════════════════════════╝

```



### 1️⃣ DDNS 域名配置



选择 `1` 进入 DDNS 配置：



- **Cloudflare**: 需要 API Token 和域名

- **DuckDNS**: 需要 Token 和子域名

- **No-IP**: 需要账号密码和主机名



配置完成后会自动：

- ✅ 创建 DNS 记录

- ✅ 添加定时任务 (每 5 分钟检测 IP 变化)

- ✅ 自动更新 DNS 记录



### 2️⃣ WARP 配置



选择 `2` 配置 WARP：



- 支持官方客户端和 WireGuard 两种模式

- 一键连接/断开

- 自动配置为系统代理出口



### 3️⃣-7️⃣ 安装代理协议



所有协议安装流程：



1. 自动检测或输入域名

2. 自动申请/续签 SSL 证书

3. 生成随机端口和强密码/UUID

4. 自动配置并启动服务

5. 输出配置信息和分享链接

6. 生成二维码



### 8️⃣ 查看配置



随时查看所有已安装服务的：

- 服务器地址和端口

- 密码/UUID

- 分享链接

- 二维码



### 9️⃣ 卸载服务



支持单独或全部卸载服务，清理配置文件。



---



## 📁 文件结构



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



---



## 🔧 配置示例



### Vless + Reality



```

协议: Vless + Reality

服务器地址: your-domain.com

端口: 443

UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

流控: xtls-rprx-vision

传输协议: tcp

安全: reality

Public Key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Short ID: a1b2c3d4

SNI: www.cloudflare.com

```



### Hysteria2



```

服务器地址: your-domain.com

端口: 443

密码: your-strong-password

传输协议: udp

TLS: 自签名证书

SNI: your-domain.com

```



---



## 🛡️ 安全特性



- ✅ 自动 SSL 证书申请和续签

- ✅ 随机端口生成 (10000-65000)

- ✅ 强密码/UUID 自动生成

- ✅ Reality 协议抗检测

- ✅ 证书自动续期定时任务



---



## 🔄 自动续签机制



### SSL 证书

- 使用 `acme.sh` 管理证书

- 每天凌晨 3 点自动检查续签

- 续签后自动重启相关服务



### DDNS

- 每 5 分钟检测公网 IP 变化

- IP 变化时自动更新 DNS 记录

- 支持 Cloudflare/DuckDNS/No-IP



---



## ❓ 常见问题



### Q: 脚本支持哪些系统？

A: Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora, AlmaLinux, Rocky Linux



### Q: 需要提前准备域名吗？

A: 不需要，脚本内置 DDNS 功能，可以自动申请免费域名



### Q: 如何更新脚本？

A: 重新运行一键安装命令即可自动获取最新版本



### Q: 证书续签失败怎么办？

A: 检查 80 端口是否被占用，或手动运行 `~/.acme.sh/acme.sh --cron`



### Q: 如何查看服务状态？

A: 使用 `systemctl status xray` 或对应的服务名称



---



## 📝 更新日志



### v1.0.0 (2024-XX-XX)

- 🎉 初始版本发布

- ✨ 支持 Cloudflare/DuckDNS/No-IP DDNS

- ✨ 支持 WARP 官方客户端和 WireGuard 模式

- ✨ 支持 Vless + Reality

- ✨ 支持 Hysteria2

- ✨ 支持 Shadowsocks

- ✨ 支持 VMess + WebSocket

- ✨ 支持 Trojan + WebSocket

- ✨ 自动 SSL 证书申请和续签

- ✨ 自动 DDNS IP 更新



---



## 🤝 贡献



欢迎提交 Issue 和 Pull Request！



1. Fork 本仓库

2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)

3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)

4. 推送到分支 (`git push origin feature/AmazingFeature`)

5. 打开 Pull Request



---



## 📜 许可证



本项目采用 [MIT](LICENSE) 许可证



---



## ⚠️ 免责声明



本工具仅供学习和研究使用，请遵守当地法律法规。使用本工具产生的任何后果由使用者自行承担。



---



## 🌟 Star History



如果这个项目对你有帮助，请给个 Star ⭐



[![Star History Chart](https://api.star-history.com/svg?repos=Kitaro-Loked/VPS-Toolbox&type=Date)](https://star-history.com/#Kitaro-Loked/VPS-Toolbox&Date)



---



<p align="center">

  <b>Made with ❤️ for the community</b>

</p>



---

## 💡 未来可能添加的功能

> 以下功能正在评估或规划中，欢迎提 Issue 建议：

### 高优先级
- [ ] **多用户管理** - 为同一协议添加多个 UUID/密码
- [ ] **流量统计** - 基于 v2ray/xray API 的实时流量监控
- [ ] **自动更新** - 检测 yeahwu 脚本更新并提示
- [ ] **端口管理** - 统一查看/修改所有协议端口
- [ ] **防火墙管理** - 一键开放/关闭端口 (iptables/nftables/ufw)

### 中优先级
- [ ] **证书管理** - 查看/续签/更换 SSL 证书
- [ ] **日志查看** - 实时查看各协议日志
- [ ] **备份恢复** - 导出/导入所有配置
- [ ] **BBR/网络优化** - 一键开启 BBR、锐速等加速
- [ ] **Docker 部署** - 提供 Docker Compose 版本

### 低优先级 / 脑洞
- [ ] **Telegram Bot** - 通过 Bot 远程管理节点
- [ ] **Web 面板** - 浏览器图形化管理界面
- [ ] **多服务器管理** - 批量管理多台 VPS
- [ ] **节点测速** - 集成 speedtest / iperf3
- [ ] **自动切换** - 节点故障自动切换备用
