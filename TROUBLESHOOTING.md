# Troubleshooting Guide

Common issues and solutions for VPS Manager Pro.

## 🤖 Bot Issues

### Bot Not Starting

**Symptoms**: Bot service fails to start

**Solutions**:
```bash
# Check logs
vpsbot logs

# Check status
systemctl status vpsmanager-bot

# Restart bot
vpsbot restart

# Check Python errors
python3 /opt/vps-manager/telegram-bot/bot.py
```

### Bot Not Responding

**Check**:
1. Bot token is correct
2. Bot is running: `vpsbot status`
3. Network connectivity
4. Telegram API is accessible

**Fix**:
```bash
# Verify token
cat /opt/vps-manager/telegram-bot/config.py | grep BOT_TOKEN

# Test connection
curl https://api.telegram.org/botYOUR_TOKEN/getMe

# Restart
vpsbot restart
```

---

## 📥 Download Issues

### Instagram Rate Limit

**Error**: "Rate limit reached"

**Solutions**:
- Wait 5-10 minutes
- Check if account is not banned
- Use different account
- Try again later

### TikTok Downloads Fail

**Solutions**:
```bash
# Update yt-dlp
pip install --upgrade yt-dlp

# Check if URL is valid
# Try different TikTok URL format
```

---

## 🗄️ Database Issues

### Cannot Connect to Database
```bash
# Check MySQL status
systemctl status mysql

# Start MySQL
systemctl start mysql

# Check credentials
cat /opt/vps-manager/config/database.conf
```

---

## 🌐 Network Issues

### SSL Certificate Errors
```bash
# Renew certificate
certbot renew

# Check certificate
certbot certificates

# Manual renewal
certbot certonly --standalone -d your-domain.com
```

### Firewall Blocking
```bash
# Check firewall
ufw status

# Allow required ports
ufw allow 22,80,443,3128/tcp

# Restart firewall
ufw reload
```

---

## 📞 Get Help

Still having issues? Contact:
- GitHub Issues
- Email: support@kurdcloud.xyz
- Telegram: @ALLINONEBIGBOSSbot
