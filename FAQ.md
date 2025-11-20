# Frequently Asked Questions

## General Questions

### What is VPS Manager Pro?
VPS Manager Pro is a complete server management system with an integrated Telegram bot for media downloading from TikTok, Instagram, YouTube, and Facebook.

### Is it free?
Yes! VPS Manager Pro is open source under MIT License.

### What platforms are supported?
- TikTok (no watermark)
- Instagram (posts, reels, stories, albums)
- YouTube (up to 720p)
- Facebook (videos)

---

## Installation Questions

### What are the requirements?
- Ubuntu 20.04+ or Debian 10+
- 1GB RAM minimum (2GB recommended)
- 10GB free disk space
- Root access

### How long does installation take?
5-10 minutes with the automated installer.

### Can I install on shared hosting?
No, you need a VPS or dedicated server with root access.

---

## Usage Questions

### How do I download media?
Simply send a link to the bot on Telegram:
```
https://www.tiktok.com/@user/video/123
https://www.instagram.com/p/ABC123/
https://www.youtube.com/watch?v=ABC123
https://www.facebook.com/watch/?v=123
```

### Are there any limits?
- File size: 50MB for videos, 10MB for photos
- Download timeout: 5 minutes
- Instagram may have rate limits

### Can I download private content?
No, only public content is supported.

---

## Technical Questions

### How do I update?
```bash
cd /opt/vps-manager
git pull origin main
vpsbot restart
```

### How do I backup?
```bash
bash /opt/vps-manager/scripts/backup.sh
```

### Where are logs stored?
```
/opt/vps-manager/logs/telegram-bot.log
```

### How do I change bot token?
1. Edit `/opt/vps-manager/telegram-bot/config.py`
2. Update BOT_TOKEN
3. Restart: `vpsbot restart`

---

## Security Questions

### Is my data safe?
- All credentials are stored locally
- No data is sent to third parties
- Session files are encrypted
- SSL/TLS enabled by default

### How do I change passwords?
Edit configuration files and restart services.

### Can I use 2FA?
Telegram bot supports Telegram's built-in 2FA.

---

For more help, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
