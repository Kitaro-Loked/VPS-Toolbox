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

- IPv6-only 环境自动安装 WARP 提供 IPv4 出口

- 一键启动/停止/查看状态



### 📡 代理协议支持



| 协议 | 特点 | 推荐度 |

|------|------|--------|

| **Vless + Reality** | 最新协议，抗检测能力强 | ⭐⭐⭐⭐⭐ |

| **Hysteria2** | 基于 QUIC，速度快，抗封锁 | ⭐⭐⭐⭐⭐ |

| **Shadowsocks** | 轻量简单，兼容性好 | ⭐⭐⭐⭐ |

| **VMess + WebSocket** | 成熟稳定，支持 CDN | ⭐⭐⭐⭐ |



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

- **网络**: 需要公网 IP (IPv4 或 IPv6，IPv6-only 环境会自动安装 WARP)



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

║           VPS Toolbox - 多功能一键部署工具 v1.0              ║

╠══════════════════════════════════════════════════════════════╣

║  【DDNS & 网络】                                             ║

║   1. DDNS 域名申请与管理 (自动续签)                          ║

║   2. WARP 一键配置                                           ║

║                                                              ║

║  【代理协议】                                                ║

║   3. 安装 Vless + Reality                                    ║

║   4. 安装 Hysteria2                                          ║

║   5. 安装 Shadowsocks-rust                                   ║

║   6. 安装 VMess + WS + TLS                                   ║

║   7. 安装 HTTPS 正向代理                                     ║

║                                                              ║

║  【系统优化】                                                ║

║   8. 网络优化 (BBR/系统参数)                                 ║

║   9. 一键重装系统 (DD)                                       ║

║                                                              ║

║  【工具】                                                    ║

║  10. 网络测速                                                ║

║  11. SSL 证书管理                                            ║

║  12. 端口占用一览                                            ║

║  13. Telegram Bot 配置                                       ║

║                                                              ║

║  【节点订阅】                                                ║

║  14. 节点订阅管理                                            ║

║  15. 推送订阅到 Telegram                                     ║

║  16. 启动 HTTP 订阅服务                                      ║

║                                                              ║

║  【高级】                                                    ║

║  17. 多节点负载均衡                                          ║

║  18. 安全配置审计                                            ║

║                                                              ║

║  【伪装网站】                                                ║

║  19. 部署伪装网站                                            ║

║                                                              ║

║  【管理】                                                    ║

║  20. 查看所有配置                                            ║

║  21. 生成订阅链接                                            ║

║  22. 流量统计                                                ║

║  23. 使用统计详情                                            ║

║  24. 卸载服务                                                ║

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



- 支持官方 Cloudflare WARP 客户端

- IPv6-only 环境自动安装

- 一键连接/断开



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



## 📝 版本

当前版本: **v1.0**

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

