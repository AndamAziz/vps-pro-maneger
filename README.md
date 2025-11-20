# 🌐 VPS Manager Pro - Telegram Bot

**Complete VPS Management System with Media Downloader Bot**

[![GitHub](https://img.shields.io/badge/GitHub-VPS_Manager_Pro-blue)](https://github.com/AndamAziz/vps-pro-maneger)
[![Telegram](https://img.shields.io/badge/Telegram-@ALLINONEBIGBOSSbot-blue)](https://t.me/ALLINONEBIGBOSSbot)

---

## 🚀 One-Command Installation
```bash
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/install.sh | sudo bash
```

**Installation time:** 5-10 minutes

---

## ✨ Features

### 📥 Media Downloader Bot
- **TikTok** - Download videos without watermark
- **Instagram** - Photos, videos, reels, stories (with API login)
- **YouTube** - Videos up to 720p
- **Facebook** - Videos and posts

### 🔐 VPS Management
- SSH user management
- Squid Proxy server
- V2Ray VPN (VLESS/VMess)
- SSL certificates (Let's Encrypt)
- MySQL database
- Web admin panel

### 🤖 Telegram Bot
- Media downloads from 4 platforms
- User management (Admin only)
- Server statistics
- Auto-cleanup

---

## 📋 Requirements

- **OS:** Ubuntu 20.04+ or Debian 10+
- **RAM:** Minimum 1GB
- **Storage:** 10GB+ free
- **Domain:** Required for SSL
- **Root access:** Required

---

## 🎮 Bot Commands
```
/start - Welcome message
/help - Help menu
/status - Server status

Admin Commands (in code):
/adduser - Create VPS user
/listusers - List all users
/stats - Server statistics
```

### How to Download Media

Simply send any link:
```
https://www.tiktok.com/@username/video/123456789
https://www.instagram.com/p/ABC123/
https://www.youtube.com/watch?v=ABC123
https://www.facebook.com/watch/?v=123456789
```

Bot will automatically detect the platform and download!

---

## 🔧 Configuration

All configuration is automatic during installation:

- **Domain:** Set during install
- **Bot Token:** Configured automatically
- **Instagram Login:** Built-in credentials
- **Database:** Auto-created

### Default Credentials

**Telegram Bot:** `@ALLINONEBIGBOSSbot`

**Web Panel:**
- URL: `https://your-domain.com/admin`
- Username: `admin`
- Password: `KurdCloud@2025`

---

## 📱 After Installation

### Start the bot:
```bash
vpsbot start
```

### Check status:
```bash
vpsbot status
```

### View logs:
```bash
vpsbot logs
```

### Restart bot:
```bash
vpsbot restart
```

---

## 🗂️ Project Structure
```
telegram-bot/
├── bot.py                      # Main bot file
├── config.py                   # Configuration
├── requirements.txt            # Python packages
└── handlers/
    ├── media.py               # Media downloader
    └── users.py               # User management (future)
```

---

## 🔄 Manual Installation

If you prefer manual installation:
```bash
# 1. Download files
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger

# 2. Run installer
chmod +x install.sh
sudo ./install.sh

# 3. Start bot
vpsbot start
```

---

## 🐛 Troubleshooting

### Bot not responding?
```bash
# Check status
vpsbot status

# View logs
vpsbot logs

# Restart
vpsbot restart
```

### Instagram rate limit?

Instagram has rate limits. Solutions:
1. Wait 5-10 minutes
2. The bot uses API login to avoid most limits
3. Use TikTok/YouTube instead (no limits)

### Services not starting?
```bash
# Check all services
systemctl status nginx
systemctl status mysql
systemctl status v2ray
systemctl status vpsmanager-bot
```

---

## 🔐 Security

- Change default passwords after installation
- Use strong passwords for users
- Enable firewall (done automatically)
- Keep system updated
- Monitor logs regularly

---

## 📊 Tech Stack

- **Python 3.8+** - Bot framework
- **python-telegram-bot** - Telegram API
- **yt-dlp** - Video downloads
- **instagrapi** - Instagram API
- **MySQL/MariaDB** - Database
- **Nginx** - Web server
- **V2Ray** - VPN server
- **Squid** - Proxy server

---

## 🆘 Support

- **Issues:** [GitHub Issues](https://github.com/AndamAziz/vps-pro-maneger/issues)
- **Telegram:** [@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)
- **Email:** support@kurdcloud.xyz

---

## 📝 License

MIT License - Free to use for any purpose

---

## 🙏 Credits

**Developer:** KurdCloud Team
**Telegram Bot:** [@ALLINONEBIGBOSSbot](https://t.me/ALLINONEBIGBOSSbot)

**Powered by:**
- [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [instagrapi](https://github.com/adw0rd/instagrapi)
- [V2Ray](https://www.v2ray.com/)

---

## ⭐ Star This Repo!

If you find this useful, please star the repo! ⭐

---

**Made with ❤️ by KurdCloud Team**

**Version:** 1.0.0  
**Last Updated:** November 2025
