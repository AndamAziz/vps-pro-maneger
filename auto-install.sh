#!/bin/bash
set -e
DOMAIN="v2ray.kurdcloud.xyz"
BOT_TOKEN="8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g"
ADMIN_ID="144068979"
INSTA_USER="allinonebigboss"
INSTA_PASS="HelinGyan1122@@##"
clear
echo "VPS MANAGER PRO - INSTALLING..."
echo "[1/15] Updating system..."
apt-get update -qq > /dev/null 2>&1 && echo "Done"
echo "[2/15] Installing packages..."
apt-get install -y -qq curl wget git unzip ufw htop net-tools jq bc mariadb-server nginx squid apache2-utils python3 python3-pip python3-venv certbot > /dev/null 2>&1 && echo "Done"
echo "[3/15] Creating directories..."
mkdir -p /opt/vps-manager/{config,scripts,telegram-bot/handlers,logs,backups,ssl,downloads} && echo "DOMAIN=$DOMAIN" > /opt/vps-manager/config/domain.conf && echo "Done"
echo "[4/15] Configuring MySQL..."
systemctl start mariadb && systemctl enable mariadb > /dev/null 2>&1
DB_PASS=$(openssl rand -base64 16)
mysql -e "CREATE DATABASE IF NOT EXISTS vps_manager;" 2>/dev/null && echo "Done"
echo "[5/15] Installing V2Ray..."
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) > /dev/null 2>&1 && echo "Done"
echo "[6/15] Configuring firewall..."
ufw --force enable > /dev/null 2>&1 && ufw allow 22,80,443,3128/tcp > /dev/null 2>&1 && echo "Done"
echo "[7/15] Installing Python packages..."
cd /opt/vps-manager/telegram-bot && python3 -m venv venv && source venv/bin/activate && pip install --quiet python-telegram-bot==20.7 instaloader yt-dlp mysql-connector-python qrcode Pillow psutil requests && echo "Done"
echo "[8/15] Configuring bot..."
cat > /opt/vps-manager/telegram-bot/config.py << EOF
BOT_TOKEN="$BOT_TOKEN"
ADMIN_IDS=[$ADMIN_ID]
INSTAGRAM_USERNAME="$INSTA_USER"
INSTAGRAM_PASSWORD="$INSTA_PASS"
EOF
echo "Done"
systemctl start nginx squid v2ray
clear
echo "INSTALLATION COMPLETED!"
echo "Telegram: @ALLINONEBIGBOSSbot"
echo "Commands: vpsbot start|stop|status"
