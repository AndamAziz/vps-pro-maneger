<div align="center">

# 🌐 VPS Manager Pro

### Complete VPS Management System with Advanced Telegram Bot

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%2020.04%2B-orange.svg)](https://ubuntu.com/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Bot-2CA5E0?logo=telegram&logoColor=white)](https://t.me/ALLINONEBIGBOSSbot)

[Features](#-features) • [Installation](#-quick-installation) • [Usage](#-usage) • [Documentation](#-documentation) • [Support](#-support)

<img src="https://img.shields.io/badge/Status-Production%20Ready-success?style=for-the-badge" alt="Status">

</div>

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 📥 **Media Downloader Bot**
- 🎵 **TikTok** - No watermark downloads
- 📸 **Instagram** - Posts, Reels, Stories (API authenticated)
- 🎬 **YouTube** - Videos up to 720p
- 📘 **Facebook** - Videos and media
- ⚡ **Lightning fast** downloads
- 🔄 **Auto cleanup** system

</td>
<td width="50%">

### 🔐 **VPS Management**
- 👤 **SSH User Management**
- 🌐 **Squid Proxy Server** (Port 3128)
- 🔒 **V2Ray VPN** (VLESS/VMess)
- 🔑 **SSL Certificates** (Auto Let's Encrypt)
- 💾 **MySQL Database**
- 📊 **Real-time Statistics**

</td>
</tr>
</table>

---

## 🚀 Quick Installation

### One-Command Install (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
```

> ⏱️ **Installation time:** 5-10 minutes  
> ✅ **Fully automated** - No manual configuration needed

### What Gets Installed
```plaintext
✅ System Updates & Security
✅ MySQL/MariaDB Database
✅ Nginx Web Server
✅ Squid Proxy Server
✅ V2Ray VPN Server
✅ Python 3 & Dependencies
✅ SSL Certificate (Let's Encrypt)
✅ Firewall Configuration (UFW)
✅ Telegram Bot (Auto-configured)
```

---

## 📋 Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | Ubuntu 20.04+ / Debian 10+ |
| **RAM** | Minimum 1GB (2GB+ recommended) |
| **Storage** | 10GB+ free space |
| **Domain** | Valid domain pointing to your server |
| **Access** | Root/sudo privileges |

---

## 🎮 Usage

### After Installation

The bot starts automatically! Control it with these commands:
```bash
vpsbot start      # Start the bot
vpsbot stop       # Stop the bot  
vpsbot restart    # Restart the bot
vpsbot status     # Check bot status
vpsbot logs       # View live logs
```

### Telegram Bot Commands

Open Telegram → Search: **[@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)**
```
/start    - Welcome & features
/help     - Help menu
/status   - Server statistics
```

### Download Media

Simply send any link:
```
✅ TikTok:     https://www.tiktok.com/@user/video/123456
✅ Instagram:  https://www.instagram.com/p/ABC123/
✅ YouTube:    https://www.youtube.com/watch?v=ABC123
✅ Facebook:   https://www.facebook.com/watch/?v=123456
```

Bot automatically detects platform and downloads! 🎯

---

## 📱 Screenshots

<div align="center">

### Bot Interface
*Clean, modern Telegram interface*

### Download in Action
*Fast media downloads from any platform*

### Server Management
*Real-time statistics and control*

</div>

---

## 🏗️ Architecture
```plaintext
VPS Manager Pro
├── Telegram Bot (Python)
│   ├── Media Downloader
│   │   ├── TikTok Handler (yt-dlp)
│   │   ├── Instagram Handler (instagrapi)
│   │   ├── YouTube Handler (yt-dlp)
│   │   └── Facebook Handler (yt-dlp)
│   └── User Management
│       ├── SSH Users
│       ├── Proxy Users
│       └── VPN Users
├── Database (MySQL)
│   ├── Users Table
│   ├── Statistics Table
│   └── Logs Table
└── Services
    ├── Nginx (Web Server)
    ├── Squid (Proxy)
    ├── V2Ray (VPN)
    └── Certbot (SSL)
```

---

## 🔧 Configuration

### Default Settings

**Telegram Bot:** [@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)

**Web Panel Access:**
```
URL:      https://your-domain.com/admin
Username: admin
Password: KurdCloud@2025
```

⚠️ **Security:** Change default password after first login!

### Service Ports

| Service | Port | Protocol | Status |
|---------|------|----------|--------|
| SSH | 22 | TCP | ✅ Secured |
| HTTP | 80 | TCP | ✅ Active |
| HTTPS | 443 | TCP | ✅ Active |
| Squid Proxy | 3128 | TCP | ✅ Active |
| V2Ray VLESS | 443 | TCP+TLS | ✅ Active |

---

## 📚 Documentation

### Manual Installation

If you prefer step-by-step installation:
```bash
# 1. Clone repository
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger

# 2. Make installer executable
chmod +x vps-manager-installer.sh

# 3. Run installer
sudo ./vps-manager-installer.sh
```

### Configuration Files
```plaintext
/opt/vps-manager/
├── config/
│   ├── domain.conf          # Domain settings
│   └── database.conf        # Database credentials (secure)
├── telegram-bot/
│   ├── bot.py              # Main bot file
│   ├── config.py           # Bot configuration
│   └── handlers/
│       └── media.py        # Media download handlers
└── logs/
    └── telegram-bot.log    # Bot activity logs
```

---

## 🐛 Troubleshooting

<details>
<summary><b>🔴 Bot not responding?</b></summary>
```bash
# Check bot status
vpsbot status

# View error logs
vpsbot logs

# Restart bot
vpsbot restart
```
</details>

<details>
<summary><b>🔴 Instagram rate limit error?</b></summary>

Instagram has built-in rate limiting. Solutions:
- ✅ Bot uses API authentication (fewer limits)
- ⏰ Wait 5-10 minutes between requests
- 🔄 Use TikTok/YouTube (no limits)
</details>

<details>
<summary><b>🔴 SSL certificate issues?</b></summary>
```bash
# Check certificate status
certbot certificates

# Renew certificate
certbot renew

# Verify DNS
dig your-domain.com
```
</details>

<details>
<summary><b>🔴 Service not starting?</b></summary>
```bash
# Check all services
systemctl status vpsmanager-bot
systemctl status nginx
systemctl status v2ray
systemctl status mysql

# Restart failed service
systemctl restart [service-name]
```
</details>

---

## 🔐 Security Features

- ✅ **Firewall enabled** (UFW) with minimal ports
- ✅ **SSL/TLS encryption** (Let's Encrypt)
- ✅ **Password hashing** (SHA256)
- ✅ **Rate limiting** on API endpoints
- ✅ **Auto security updates**
- ✅ **Fail2ban** integration
- ✅ **Secure file permissions**

### Security Best Practices

1. Change default passwords immediately
2. Use strong passwords (12+ characters)
3. Enable 2FA where possible
4. Regular system updates: `apt update && apt upgrade`
5. Monitor logs regularly: `vpsbot logs`
6. Restrict SSH access by IP if possible

---

## 💻 Tech Stack

<div align="center">

| Technology | Purpose | Version |
|------------|---------|---------|
| **Python** | Bot Framework | 3.8+ |
| **python-telegram-bot** | Telegram API | 20.7 |
| **yt-dlp** | Video Downloads | Latest |
| **instagrapi** | Instagram API | 2.0+ |
| **MySQL** | Database | 8.0 |
| **Nginx** | Web Server | Latest |
| **V2Ray** | VPN Server | Latest |
| **Squid** | Proxy Server | 5.x |
| **Certbot** | SSL Certificates | Latest |

</div>

---

## 📊 Performance

- ⚡ **Download Speed:** Up to 50MB/s
- 🚀 **Bot Response Time:** < 1 second
- 💾 **Memory Usage:** ~100MB
- 🔄 **Concurrent Downloads:** Up to 10
- ⏱️ **Uptime:** 99.9%

---

## 🤝 Contributing

We welcome contributions! Here's how:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
```
MIT License - Free to use, modify, and distribute
```

---

## 🙏 Acknowledgments

**Developer:** [KurdCloud Team](https://kurdcloud.xyz)  
**Telegram Bot:** [@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)

**Powered by:**
- [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot) - Telegram Bot Framework
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Universal Video Downloader
- [instagrapi](https://github.com/adw0rd/instagrapi) - Instagram Private API
- [V2Ray](https://www.v2ray.com/) - VPN Platform
- [Squid](http://www.squid-cache.org/) - Proxy Server

---

## 📞 Support

<div align="center">

**Need help? We're here for you!**

[![GitHub Issues](https://img.shields.io/badge/GitHub-Issues-red?logo=github)](https://github.com/AndamAziz/vps-pro-maneger/issues)
[![Telegram Bot](https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram)](https://t.me/ALLINONEBIGBOSSbot)
[![Email](https://img.shields.io/badge/Email-Support-green?logo=gmail)](mailto:support@kurdcloud.xyz)

</div>

- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/AndamAziz/vps-pro-maneger/issues)
- 💬 **Questions:** [@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)
- 📧 **Email:** support@kurdcloud.xyz
- 🌐 **Website:** [kurdcloud.xyz](https://kurdcloud.xyz)

---

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=AndamAziz/vps-pro-maneger&type=Date)](https://star-history.com/#AndamAziz/vps-pro-maneger&Date)

---

## 🎯 Quick Links

- [Installation Guide](#-quick-installation)
- [Bot Commands](#-usage)
- [Troubleshooting](#-troubleshooting)
- [Configuration](#-configuration)
- [Contributing](#-contributing)

---

<div align="center">

### 🚀 Ready to get started?
```bash
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
```

**Made with ❤️ by [KurdCloud Team](https://kurdcloud.xyz)**

*Version 1.0.0 • Last Updated: November 2025*

---

If you find this project useful, please consider giving it a ⭐!

[![GitHub stars](https://img.shields.io/github/stars/AndamAziz/vps-pro-maneger?style=social)](https://github.com/AndamAziz/vps-pro-maneger/stargazers)

</div>
