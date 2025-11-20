# Installation Guide

Complete installation guide for VPS Manager Pro.

## 📋 Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ or Debian 10+
- **RAM**: Minimum 1GB (2GB recommended)
- **Storage**: 10GB+ free space
- **Network**: Stable internet connection
- **Domain**: Valid domain pointing to your server (optional but recommended)

### Required Access
- Root or sudo privileges
- SSH access to server
- Firewall ports: 22, 80, 443, 3128

---

## 🚀 Quick Installation

### Method 1: One-Command Install (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
```

**That's it!** The script will:
- Update system packages
- Install all dependencies
- Configure services
- Set up database
- Install SSL certificate
- Configure firewall
- Start the bot

**Installation time**: 5-10 minutes

---

## 🐳 Docker Installation

### Prerequisites
- Docker installed
- Docker Compose installed

### Steps

1. **Clone repository**
```bash
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger
```

2. **Configure environment**
```bash
cp config.example.py config_local.py
# Edit config_local.py with your credentials
nano config_local.py
```

3. **Create .env file**
```bash
cat > .env << EOF
BOT_TOKEN=your_bot_token
ADMIN_IDS=your_admin_id
INSTAGRAM_USERNAME=your_username
INSTAGRAM_PASSWORD=your_password
EOF
```

4. **Build and run**
```bash
docker-compose up -d
```

5. **Check logs**
```bash
docker-compose logs -f
```

---

## 🔧 Manual Installation

### Step 1: System Update
```bash
apt update && apt upgrade -y
```

### Step 2: Install Dependencies
```bash
apt install -y python3 python3-pip python3-venv git curl wget
```

### Step 3: Clone Repository
```bash
git clone https://github.com/AndamAziz/vps-pro-maneger.git
cd vps-pro-maneger
```

### Step 4: Create Virtual Environment
```bash
python3 -m venv venv
source venv/bin/activate
```

### Step 5: Install Python Packages
```bash
pip install -r requirements.txt
```

### Step 6: Configure
```bash
cp config.example.py config.py
nano config.py  # Edit with your credentials
```

### Step 7: Run Bot
```bash
python3 bot.py
```

---

## ✅ Post-Installation

### Verify Installation
```bash
# Check bot status
vpsbot status

# View logs
vpsbot logs

# Test bot
# Send /start to @ALLINONEBIGBOSSbot on Telegram
```

### Configure Auto-Start
```bash
# Bot service is automatically configured
systemctl enable vpsmanager-bot
systemctl start vpsmanager-bot
```

---

## 🔄 Updates

### Update to Latest Version
```bash
cd /opt/vps-manager
git pull origin main
vpsbot restart
```

---

## 🐛 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

---

## 📞 Support

Need help? Contact us:
- GitHub Issues
- Email: support@kurdcloud.xyz
- Telegram: @ALLINONEBIGBOSSbot
