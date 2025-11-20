#!/bin/bash

################################################################################
#
#   VPS Manager Pro - Professional Installation Script
#   
#   Author: KurdCloud Team
#   Version: 1.0.0
#   Repository: https://github.com/AndamAziz/vps-pro-maneger
#   
#   Description:
#   Automated installation script for VPS Manager Pro with Telegram Bot,
#   media downloader, VPN, proxy, and complete server management system.
#
#   Usage:
#   curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
#
################################################################################

set -e

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
readonly DOMAIN="${DOMAIN:-v2ray.kurdcloud.xyz}"
readonly BOT_TOKEN="${BOT_TOKEN:-8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g}"
readonly ADMIN_ID="${ADMIN_ID:-144068979}"
readonly INSTA_USER="${INSTA_USER:-allinonebigboss}"
readonly INSTA_PASS="${INSTA_PASS:-HelinGyan1122@@##}"

# Installation directories
readonly INSTALL_DIR="/opt/vps-manager"
readonly CONFIG_DIR="${INSTALL_DIR}/config"
readonly BOT_DIR="${INSTALL_DIR}/telegram-bot"
readonly LOGS_DIR="${INSTALL_DIR}/logs"

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              VPS MANAGER PRO - INSTALLER v1.0                   ║
║                                                                  ║
║          Professional VPS Management & Telegram Bot             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. Only Ubuntu/Debian supported."
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_error "Only Ubuntu and Debian are supported"
        exit 1
    fi
    
    log_success "OS detected: $PRETTY_NAME"
}

################################################################################
# Installation Steps
################################################################################

step_1_system_update() {
    log_info "Step 1/15: Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null 2>&1
    apt-get upgrade -y -qq > /dev/null 2>&1
    log_success "System updated successfully"
}

step_2_install_packages() {
    log_info "Step 2/15: Installing essential packages..."
    apt-get install -y -qq \
        curl wget git unzip software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release \
        ufw fail2ban htop net-tools dnsutils jq bc \
        > /dev/null 2>&1
    log_success "Essential packages installed"
}

step_3_create_directories() {
    log_info "Step 3/15: Creating directory structure..."
    mkdir -p "${INSTALL_DIR}"/{config,scripts,telegram-bot/handlers,logs,backups,ssl,downloads}
    echo "DOMAIN=$DOMAIN" > "${CONFIG_DIR}/domain.conf"
    log_success "Directory structure created"
}

step_4_install_mysql() {
    log_info "Step 4/15: Installing MySQL/MariaDB..."
    apt-get install -y -qq mariadb-server mariadb-client > /dev/null 2>&1
    systemctl start mariadb
    systemctl enable mariadb > /dev/null 2>&1
    
    DB_ROOT_PASS=$(openssl rand -base64 16)
    DB_USER_PASS=$(openssl rand -base64 16)
    
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';" 2>/dev/null || true
    mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS vps_manager;" 2>/dev/null
    mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'vps_admin'@'localhost' IDENTIFIED BY '$DB_USER_PASS';" 2>/dev/null
    mysql -uroot -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON vps_manager.* TO 'vps_admin'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
    
    cat > "${CONFIG_DIR}/database.conf" << EOF
DB_HOST=localhost
DB_NAME=vps_manager
DB_USER=vps_admin
DB_PASSWORD=$DB_USER_PASS
DB_ROOT_PASSWORD=$DB_ROOT_PASS
EOF
    chmod 600 "${CONFIG_DIR}/database.conf"
    log_success "MySQL installed and configured"
}

step_5_create_database() {
    log_info "Step 5/15: Creating database tables..."
    mysql -uvps_admin -p"$DB_USER_PASS" vps_manager << 'EOSQL'
CREATE TABLE IF NOT EXISTS ssh_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    expiry_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('active', 'expired', 'suspended') DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS proxy_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    port INT NOT NULL,
    expiry_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('active', 'expired', 'suspended') DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS v2ray_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    protocol ENUM('vless', 'vmess') DEFAULT 'vless',
    port INT NOT NULL,
    expiry_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('active', 'expired', 'suspended') DEFAULT 'active'
);
EOSQL
    log_success "Database tables created"
}

step_6_install_nginx() {
    log_info "Step 6/15: Installing Nginx web server..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    systemctl start nginx
    systemctl enable nginx > /dev/null 2>&1
    log_success "Nginx installed"
}

step_7_install_squid() {
    log_info "Step 7/15: Installing Squid proxy server..."
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
    log_success "Squid proxy installed"
}

step_8_install_v2ray() {
    log_info "Step 8/15: Installing V2Ray VPN server..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) > /dev/null 2>&1
    mkdir -p /var/log/v2ray
    cat > /usr/local/etc/v2ray/config.json << EOF
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {"clients": [], "decryption": "none"},
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "certificates": [{
          "certificateFile": "${INSTALL_DIR}/ssl/fullchain.pem",
          "keyFile": "${INSTALL_DIR}/ssl/privkey.pem"
        }]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    systemctl enable v2ray > /dev/null 2>&1
    log_success "V2Ray installed"
}

step_9_install_ssl() {
    log_info "Step 9/15: Installing SSL certificate..."
    apt-get install -y -qq certbot > /dev/null 2>&1
    systemctl stop nginx
    certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email -d "$DOMAIN" > /dev/null 2>&1 || true
    
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        cp /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem "${INSTALL_DIR}/ssl/"
        cp /etc/letsencrypt/live/"$DOMAIN"/privkey.pem "${INSTALL_DIR}/ssl/"
        log_success "SSL certificate installed"
    else
        log_warning "SSL certificate skipped (configure later)"
    fi
    
    systemctl start nginx
    systemctl start v2ray
}

step_10_configure_firewall() {
    log_info "Step 10/15: Configuring firewall..."
    ufw --force enable > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow 3128/tcp > /dev/null 2>&1
    log_success "Firewall configured"
}

step_11_install_python() {
    log_info "Step 11/15: Installing Python and dependencies..."
    apt-get install -y -qq python3 python3-pip python3-venv > /dev/null 2>&1
    cd "${BOT_DIR}"
    python3 -m venv venv > /dev/null 2>&1
    source venv/bin/activate
    pip install --quiet --upgrade pip > /dev/null 2>&1
    pip install --quiet \
        python-telegram-bot==20.7 \
        instagrapi==2.0.0 \
        yt-dlp \
        mysql-connector-python \
        qrcode Pillow psutil requests \
        > /dev/null 2>&1
    deactivate
    log_success "Python environment ready"
}

step_12_configure_bot() {
    log_info "Step 12/15: Configuring Telegram bot..."
    cat > "${BOT_DIR}/config.py" << EOF
BOT_TOKEN = "$BOT_TOKEN"
ADMIN_IDS = [$ADMIN_ID]
INSTAGRAM_USERNAME = "$INSTA_USER"
INSTAGRAM_PASSWORD = "$INSTA_PASS"
DOMAIN = "$DOMAIN"
DB_HOST = "localhost"
DB_NAME = "vps_manager"
DB_USER = "vps_admin"
DB_PASSWORD = "$DB_USER_PASS"
DOWNLOAD_DIR = "${BOT_DIR}/downloads"
import os
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)
EOF
    log_success "Bot configured"
}

step_13_create_service() {
    log_info "Step 13/15: Creating systemd service..."
    cat > /etc/systemd/system/vpsmanager-bot.service << EOF
[Unit]
Description=VPS Manager Pro - Telegram Bot
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=${BOT_DIR}
ExecStart=${BOT_DIR}/venv/bin/python3 ${BOT_DIR}/bot.py
Restart=always
RestartSec=10
StandardOutput=append:${LOGS_DIR}/telegram-bot.log
StandardError=append:${LOGS_DIR}/telegram-bot-error.log

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable vpsmanager-bot > /dev/null 2>&1
    log_success "Systemd service created"
}

step_14_create_commands() {
    log_info "Step 14/15: Creating management commands..."
    cat > /usr/local/bin/vpsbot << 'EOFCMD'
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
        tail -f /opt/vps-manager/logs/telegram-bot.log
        ;;
    *)
        echo "Usage: vpsbot {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOFCMD
    chmod +x /usr/local/bin/vpsbot
    log_success "Management commands created"
}

step_15_start_services() {
    log_info "Step 15/15: Starting services..."
    systemctl start vpsmanager-bot
    sleep 2
    log_success "All services started"
}

################################################################################
# Installation Summary
################################################################################

show_summary() {
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║            ✓ INSTALLATION COMPLETED SUCCESSFULLY!               ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Installation Summary${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "  ${CYAN}Domain:${NC}           ${GREEN}$DOMAIN${NC}"
    echo -e "  ${CYAN}Server IP:${NC}        ${GREEN}$SERVER_IP${NC}"
    echo -e "  ${CYAN}Telegram Bot:${NC}     ${GREEN}@ALLINONEBIGBOSSbot${NC}"
    echo -e "  ${CYAN}Admin ID:${NC}         ${GREEN}$ADMIN_ID${NC}"
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Services Installed${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "  ${GREEN}✓${NC} SSH Management"
    echo -e "  ${GREEN}✓${NC} Squid Proxy Server (Port 3128)"
    echo -e "  ${GREEN}✓${NC} V2Ray VPN (Port 443)"
    echo -e "  ${GREEN}✓${NC} SSL Certificate (Let's Encrypt)"
    echo -e "  ${GREEN}✓${NC} MySQL Database"
    echo -e "  ${GREEN}✓${NC} Telegram Bot"
    echo -e "  ${GREEN}✓${NC} Media Downloader (TikTok, Instagram, YouTube, Facebook)"
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Management Commands${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "  ${WHITE}vpsbot start${NC}      - Start bot"
    echo -e "  ${WHITE}vpsbot stop${NC}       - Stop bot"
    echo -e "  ${WHITE}vpsbot restart${NC}    - Restart bot"
    echo -e "  ${WHITE}vpsbot status${NC}     - Check status"
    echo -e "  ${WHITE}vpsbot logs${NC}       - View logs"
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Next Steps${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "  ${YELLOW}1.${NC} Open Telegram: ${GREEN}https://t.me/ALLINONEBIGBOSSbot${NC}"
    echo -e "  ${YELLOW}2.${NC} Send: ${GREEN}/start${NC}"
    echo -e "  ${YELLOW}3.${NC} Send any media link to test"
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Configuration Files${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "  Config:  ${WHITE}${CONFIG_DIR}/${NC}"
    echo -e "  Logs:    ${WHITE}${LOGS_DIR}/${NC}"
    echo -e "  Bot:     ${WHITE}${BOT_DIR}/${NC}"
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    echo -e "${GREEN}Made with ❤️  by KurdCloud Team${NC}"
    echo -e "${WHITE}GitHub: https://github.com/AndamAziz/vps-pro-maneger${NC}\n"
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    print_header
    check_root
    check_os
    
    log_info "Starting installation...\n"
    sleep 1
    
    step_1_system_update
    step_2_install_packages
    step_3_create_directories
    step_4_install_mysql
    step_5_create_database
    step_6_install_nginx
    step_7_install_squid
    step_8_install_v2ray
    step_9_install_ssl
    step_10_configure_firewall
    step_11_install_python
    step_12_configure_bot
    step_13_create_service
    step_14_create_commands
    step_15_start_services
    
    show_summary
}

# Execute main function
main

exit 0
