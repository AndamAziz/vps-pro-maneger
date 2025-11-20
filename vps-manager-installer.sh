#!/bin/bash
################################################################################
#
#   VPS Manager Pro - Complete Installation Script
#   Version: 2.0.0
#   For: Fresh Ubuntu/Debian VPS
#
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/vps-manager"
BOT_DIR="$INSTALL_DIR/telegram-bot"
DOMAIN="${DOMAIN:-v2ray.kurdcloud.xyz}"
BOT_TOKEN="${BOT_TOKEN:-8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g}"
ADMIN_ID="${ADMIN_ID:-144068979}"
INSTA_USER="${INSTA_USER:-allinonebigboss}"
INSTA_PASS="${INSTA_PASS:-HelinGyan1122@@##}"

################################################################################
# Functions
################################################################################

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          VPS MANAGER PRO - COMPLETE INSTALLER v2.0          ║"
    echo "║                  KurdCloud Team © 2025                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        error "Cannot detect OS"
    fi
    
    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        error "This script only supports Ubuntu/Debian"
    fi
    
    log "Detected: $PRETTY_NAME"
}

################################################################################
# Installation Steps
################################################################################

step1_update_system() {
    log "Step 1/15: Updating system..."
    apt update -qq
    apt upgrade -y -qq
    log "✓ System updated"
}

step2_install_essentials() {
    log "Step 2/15: Installing essential packages..."
    apt install -y -qq \
        curl \
        wget \
        git \
        nano \
        htop \
        net-tools \
        ufw \
        fail2ban \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common
    log "✓ Essentials installed"
}

step3_install_python() {
    log "Step 3/15: Installing Python and pip..."
    apt install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential
    
    # Upgrade pip
    python3 -m pip install --upgrade pip --quiet
    log "✓ Python $(python3 --version) installed"
}

step4_install_mysql() {
    log "Step 4/15: Installing MySQL..."
    export DEBIAN_FRONTEND=noninteractive
    apt install -y -qq mysql-server mysql-client
    
    # Start MySQL
    systemctl start mysql
    systemctl enable mysql
    
    # Create database and user
    DB_PASS=$(openssl rand -base64 12)
    mysql -e "CREATE DATABASE IF NOT EXISTS vps_manager;"
    mysql -e "CREATE USER IF NOT EXISTS 'vps_admin'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON vps_manager.* TO 'vps_admin'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo "$DB_PASS" > /root/.mysql_vps_password
    log "✓ MySQL installed (password saved in /root/.mysql_vps_password)"
}

step5_install_nginx() {
    log "Step 5/15: Installing Nginx..."
    apt install -y -qq nginx
    systemctl start nginx
    systemctl enable nginx
    log "✓ Nginx installed"
}

step6_install_squid() {
    log "Step 6/15: Installing Squid proxy..."
    apt install -y -qq squid
    
    # Configure Squid
    cat > /etc/squid/squid.conf << 'EOF'
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy Authentication
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
EOF
    
    # Create password file
    apt install -y -qq apache2-utils
    touch /etc/squid/passwd
    
    systemctl restart squid
    systemctl enable squid
    log "✓ Squid proxy installed"
}

step7_install_v2ray() {
    log "Step 7/15: Installing V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) > /dev/null 2>&1 || true
    systemctl enable v2ray || true
    log "✓ V2Ray installed"
}

step8_configure_firewall() {
    log "Step 8/15: Configuring firewall..."
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 3128/tcp
    ufw reload
    log "✓ Firewall configured"
}

step9_install_ssl() {
    log "Step 9/15: Installing SSL certificate..."
    apt install -y -qq certbot python3-certbot-nginx
    
    # Try to get certificate (will fail if domain not pointing)
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --quiet || log "⚠ SSL failed (check domain DNS)"
    log "✓ SSL setup attempted"
}

step10_clone_repository() {
    log "Step 10/15: Cloning repository..."
    mkdir -p $INSTALL_DIR
    mkdir -p $BOT_DIR
    mkdir -p $INSTALL_DIR/logs
    
    # Download files from GitHub
    cd $INSTALL_DIR
    
    # Download bot.py
    wget -q https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/bot.py -O $BOT_DIR/bot.py || error "Failed to download bot.py"
    
    # Download config.py
    wget -q https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/config.py -O $BOT_DIR/config.py || error "Failed to download config.py"
    
    # Download requirements
    wget -q https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/requirements.txt -O $BOT_DIR/requirements.txt || error "Failed to download requirements.txt"
    
    # Download handlers
    mkdir -p $BOT_DIR/handlers
    wget -q https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/handlers/__init__.py -O $BOT_DIR/handlers/__init__.py || error "Failed to download handlers/__init__.py"
    wget -q https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/handlers/media.py -O $BOT_DIR/handlers/media.py || error "Failed to download handlers/media.py"
    
    chmod +x $BOT_DIR/bot.py
    log "✓ Repository files downloaded"
}

step11_install_python_packages() {
    log "Step 11/15: Installing Python packages..."
    cd $BOT_DIR
    
    # Install packages
    pip3 install --quiet \
        python-telegram-bot==20.7 \
        instagrapi==2.0.0 \
        yt-dlp \
        mysql-connector-python==8.2.0 \
        qrcode==7.4.2 \
        Pillow==10.1.0 \
        psutil==5.9.6 \
        requests==2.31.0
    
    log "✓ Python packages installed"
}

step12_configure_bot() {
    log "Step 12/15: Configuring bot..."
    
    # Update config with actual values
    sed -i "s|BOT_TOKEN = .*|BOT_TOKEN = \"$BOT_TOKEN\"|g" $BOT_DIR/config.py
    sed -i "s|ADMIN_IDS = \[.*\]|ADMIN_IDS = [$ADMIN_ID]|g" $BOT_DIR/config.py
    sed -i "s|INSTAGRAM_USERNAME = .*|INSTAGRAM_USERNAME = \"$INSTA_USER\"|g" $BOT_DIR/config.py
    sed -i "s|INSTAGRAM_PASSWORD = .*|INSTAGRAM_PASSWORD = \"$INSTA_PASS\"|g" $BOT_DIR/config.py
    sed -i "s|DOMAIN = .*|DOMAIN = \"$DOMAIN\"|g" $BOT_DIR/config.py
    
    # Create downloads directory
    mkdir -p $BOT_DIR/downloads
    chmod 755 $BOT_DIR/downloads
    
    log "✓ Bot configured"
}

step13_create_systemd_service() {
    log "Step 13/15: Creating systemd service..."
    
    cat > /etc/systemd/system/vpsmanager-bot.service << EOF
[Unit]
Description=VPS Manager Pro Telegram Bot
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/bot.py
Restart=always
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/bot.log
StandardError=append:$INSTALL_DIR/logs/bot-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable vpsmanager-bot
    log "✓ Systemd service created"
}

step14_create_management_command() {
    log "Step 14/15: Creating management command..."
    
    cat > /usr/local/bin/vpsbot << 'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start vpsmanager-bot
        echo "✓ Bot started"
        ;;
    stop)
        systemctl stop vpsmanager-bot
        echo "✓ Bot stopped"
        ;;
    restart)
        systemctl restart vpsmanager-bot
        echo "✓ Bot restarted"
        ;;
    status)
        systemctl status vpsmanager-bot
        ;;
    logs)
        tail -f /opt/vps-manager/logs/bot.log
        ;;
    *)
        echo "Usage: vpsbot {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/vpsbot
    log "✓ Management command created"
}

step15_start_services() {
    log "Step 15/15: Starting services..."
    systemctl start vpsmanager-bot
    sleep 3
    
    if systemctl is-active --quiet vpsmanager-bot; then
        log "✓ Bot service started successfully"
    else
        error "Bot failed to start. Check logs: vpsbot logs"
    fi
}

################################################################################
# Summary
################################################################################

show_summary() {
    clear
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            INSTALLATION COMPLETED SUCCESSFULLY!              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${CYAN}📦 Installed Services:${NC}"
    echo "  ✓ MySQL Database"
    echo "  ✓ Nginx Web Server"
    echo "  ✓ Squid Proxy Server"
    echo "  ✓ V2Ray VPN Server"
    echo "  ✓ Telegram Bot"
    echo ""
    
    echo -e "${CYAN}🤖 Bot Information:${NC}"
    echo "  Token: $BOT_TOKEN"
    echo "  Admin ID: $ADMIN_ID"
    echo "  Status: $(systemctl is-active vpsmanager-bot)"
    echo ""
    
    echo -e "${CYAN}📁 Directories:${NC}"
    echo "  Install: $INSTALL_DIR"
    echo "  Bot: $BOT_DIR"
    echo "  Logs: $INSTALL_DIR/logs"
    echo ""
    
    echo -e "${CYAN}🔧 Management Commands:${NC}"
    echo "  vpsbot start    - Start bot"
    echo "  vpsbot stop     - Stop bot"
    echo "  vpsbot restart  - Restart bot"
    echo "  vpsbot status   - Check status"
    echo "  vpsbot logs     - View logs"
    echo ""
    
    echo -e "${CYAN}🔐 MySQL Password:${NC}"
    echo "  Saved in: /root/.mysql_vps_password"
    echo ""
    
    echo -e "${CYAN}🌐 Domain:${NC}"
    echo "  $DOMAIN"
    echo ""
    
    echo -e "${CYAN}📞 Support:${NC}"
    echo "  Telegram: @ALLINONEBIGBOSSbot"
    echo "  GitHub: github.com/AndamAziz/vps-pro-maneger"
    echo ""
    
    echo -e "${GREEN}Installation completed in $(($SECONDS / 60)) minutes!${NC}"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    print_banner
    check_root
    check_os
    
    log "Starting installation..."
    echo ""
    
    step1_update_system
    step2_install_essentials
    step3_install_python
    step4_install_mysql
    step5_install_nginx
    step6_install_squid
    step7_install_v2ray
    step8_configure_firewall
    step9_install_ssl
    step10_clone_repository
    step11_install_python_packages
    step12_configure_bot
    step13_create_systemd_service
    step14_create_management_command
    step15_start_services
    
    show_summary
}

# Run
main
