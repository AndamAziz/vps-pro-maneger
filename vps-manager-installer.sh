#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config
DOMAIN="${DOMAIN:-v2ray.kurdcloud.xyz}"
BOT_TOKEN="${BOT_TOKEN:-8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g}"
ADMIN_ID="${ADMIN_ID:-144068979}"
INSTA_USER="${INSTA_USER:-allinonebigboss}"
INSTA_PASS="${INSTA_PASS:-HelinGyan1122@@##}"

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          VPS MANAGER PRO - INSTALLER v1.0                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}[1/15]${NC} Updating system..."
apt-get update -qq > /dev/null 2>&1
apt-get upgrade -y -qq > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[2/15]${NC} Installing packages..."
apt-get install -y -qq curl wget git unzip ufw htop net-tools jq bc > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[3/15]${NC} Creating directories..."
mkdir -p /opt/vps-manager/{config,scripts,telegram-bot/handlers,logs,backups,ssl,downloads}
echo "DOMAIN=$DOMAIN" > /opt/vps-manager/config/domain.conf
echo "Done"

echo -e "${GREEN}[4/15]${NC} Installing MySQL..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq mariadb-server > /dev/null 2>&1
systemctl start mariadb
systemctl enable mariadb > /dev/null 2>&1
DB_ROOT_PASS=$(openssl rand -base64 16)
DB_USER_PASS=$(openssl rand -base64 16)
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';" 2>/dev/null || true
mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS vps_manager;" 2>/dev/null
mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'vps_admin'@'localhost' IDENTIFIED BY '$DB_USER_PASS';" 2>/dev/null
mysql -uroot -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON vps_manager.* TO 'vps_admin'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
cat > /opt/vps-manager/config/database.conf << EOF
DB_HOST=localhost
DB_NAME=vps_manager
DB_USER=vps_admin
DB_PASSWORD=$DB_USER_PASS
DB_ROOT_PASSWORD=$DB_ROOT_PASS
EOF
chmod 600 /opt/vps-manager/config/database.conf
echo "Done"

echo -e "${GREEN}[5/15]${NC} Creating database tables..."
mysql -uvps_admin -p"$DB_USER_PASS" vps_manager << 'EOSQL'
CREATE TABLE IF NOT EXISTS ssh_users (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE, password VARCHAR(255), expiry_date DATE, status VARCHAR(20) DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS proxy_users (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE, password VARCHAR(255), port INT, expiry_date DATE, status VARCHAR(20) DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS v2ray_users (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE, uuid VARCHAR(36), protocol VARCHAR(10), port INT, expiry_date DATE, status VARCHAR(20) DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
EOSQL
echo "Done"

echo -e "${GREEN}[6/15]${NC} Installing Nginx..."
apt-get install -y -qq nginx > /dev/null 2>&1
systemctl start nginx
systemctl enable nginx > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[7/15]${NC} Installing Squid..."
apt-get install -y -qq squid apache2-utils > /dev/null 2>&1
cat > /etc/squid/squid.conf << 'EOF'
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 5
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
http_port 3128
EOF
touch /etc/squid/passwords
chmod 640 /etc/squid/passwords
systemctl restart squid
systemctl enable squid > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[8/15]${NC} Installing V2Ray..."
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) > /dev/null 2>&1
mkdir -p /var/log/v2ray
cat > /usr/local/etc/v2ray/config.json << EOF
{"inbounds":[{"port":443,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/opt/vps-manager/ssl/fullchain.pem","keyFile":"/opt/vps-manager/ssl/privkey.pem"}]}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
systemctl enable v2ray > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[9/15]${NC} Installing SSL..."
apt-get install -y -qq certbot > /dev/null 2>&1
systemctl stop nginx
certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN" > /dev/null 2>&1 || true
if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    cp /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem /opt/vps-manager/ssl/
    cp /etc/letsencrypt/live/"$DOMAIN"/privkey.pem /opt/vps-manager/ssl/
fi
systemctl start nginx
systemctl start v2ray
echo "Done"

echo -e "${GREEN}[10/15]${NC} Configuring firewall..."
ufw --force enable > /dev/null 2>&1
ufw allow 22,80,443,3128/tcp > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[11/15]${NC} Installing Python..."
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null 2>&1
cd /opt/vps-manager/telegram-bot
python3 -m venv venv > /dev/null 2>&1
source venv/bin/activate
pip install --quiet --upgrade pip > /dev/null 2>&1
pip install --quiet python-telegram-bot==20.7 instagrapi==2.0.0 yt-dlp mysql-connector-python qrcode Pillow psutil requests > /dev/null 2>&1
deactivate
echo "Done"

echo -e "${GREEN}[12/15]${NC} Downloading bot files..."
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/bot.py -o /opt/vps-manager/telegram-bot/bot.py
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/config.py -o /opt/vps-manager/telegram-bot/config.py
mkdir -p /opt/vps-manager/telegram-bot/handlers
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/handlers/media.py -o /opt/vps-manager/telegram-bot/handlers/media.py
curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/handlers/__init__.py -o /opt/vps-manager/telegram-bot/handlers/__init__.py
chmod +x /opt/vps-manager/telegram-bot/bot.py
sed -i "s/BOT_TOKEN = .*/BOT_TOKEN = \"$BOT_TOKEN\"/" /opt/vps-manager/telegram-bot/config.py
sed -i "s/ADMIN_IDS = .*/ADMIN_IDS = [$ADMIN_ID]/" /opt/vps-manager/telegram-bot/config.py
sed -i "s/DB_PASSWORD = .*/DB_PASSWORD = \"$DB_USER_PASS\"/" /opt/vps-manager/telegram-bot/config.py
echo "Done"

echo -e "${GREEN}[13/15]${NC} Creating service..."
cat > /etc/systemd/system/vpsmanager-bot.service << EOF
[Unit]
Description=VPS Manager Bot
After=network.target mysql.service
[Service]
Type=simple
User=root
WorkingDirectory=/opt/vps-manager/telegram-bot
ExecStart=/opt/vps-manager/telegram-bot/venv/bin/python3 /opt/vps-manager/telegram-bot/bot.py
Restart=always
RestartSec=10
StandardOutput=append:/opt/vps-manager/logs/telegram-bot.log
StandardError=append:/opt/vps-manager/logs/telegram-bot-error.log
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable vpsmanager-bot > /dev/null 2>&1
echo "Done"

echo -e "${GREEN}[14/15]${NC} Creating commands..."
cat > /usr/local/bin/vpsbot << 'EOFCMD'
#!/bin/bash
case "$1" in
    start) systemctl start vpsmanager-bot && echo "✓ Bot started" ;;
    stop) systemctl stop vpsmanager-bot && echo "✓ Bot stopped" ;;
    restart) systemctl restart vpsmanager-bot && echo "✓ Bot restarted" ;;
    status) systemctl status vpsmanager-bot ;;
    logs) tail -f /opt/vps-manager/logs/telegram-bot.log ;;
    *) echo "Usage: vpsbot {start|stop|restart|status|logs}" ;;
esac
EOFCMD
chmod +x /usr/local/bin/vpsbot
echo "Done"

echo -e "${GREEN}[15/15]${NC} Starting services..."
systemctl start vpsmanager-bot
sleep 2
echo "Done"

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ✓ INSTALLATION COMPLETED!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
echo -e "Telegram Bot: ${CYAN}@ALLINONEBIGBOSSbot${NC}"
echo -e "Domain: ${CYAN}$DOMAIN${NC}\n"
echo -e "Commands:"
echo -e "  ${YELLOW}vpsbot start${NC}   - Start bot"
echo -e "  ${YELLOW}vpsbot status${NC}  - Check status"
echo -e "  ${YELLOW}vpsbot logs${NC}    - View logs\n"
