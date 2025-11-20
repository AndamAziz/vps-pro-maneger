#!/bin/bash
################################################################################
#
#   VPS Manager Pro - Complete Automated Installer
#   Version: 3.0.0
#   Author: KurdCloud Team
#   
#   For: Fresh Ubuntu 20.04+ / Debian 10+ VPS
#   
#   One-command installation:
#   curl -sSL https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/vps-manager-installer.sh | sudo bash
#
################################################################################

set -e
export DEBIAN_FRONTEND=noninteractive

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
readonly INSTALL_DIR="/opt/vps-manager"
readonly BOT_DIR="$INSTALL_DIR/telegram-bot"
readonly LOG_DIR="$INSTALL_DIR/logs"
readonly DOWNLOADS_DIR="$BOT_DIR/downloads"
readonly CONFIG_DIR="$INSTALL_DIR/config"

DOMAIN="${DOMAIN:-v2ray.kurdcloud.xyz}"
BOT_TOKEN="${BOT_TOKEN:-8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g}"
ADMIN_ID="${ADMIN_ID:-144068979}"
INSTA_USER="${INSTA_USER:-allinonebigboss}"
INSTA_PASS="${INSTA_PASS:-HelinGyan1122@@##}"

################################################################################
# Helper Functions
################################################################################

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║          VPS MANAGER PRO - AUTOMATED INSTALLER v3.0         ║
║                                                              ║
║                    KurdCloud Team © 2025                    ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

################################################################################
# Pre-Installation Checks
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use: sudo bash)"
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system"
    fi
    
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    
    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        error "Only Ubuntu 20.04+ and Debian 10+ are supported"
    fi
    
    log "Detected: $PRETTY_NAME"
}

check_resources() {
    # Check RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 900 ]]; then
        warn "Low RAM detected: ${TOTAL_RAM}MB (Recommended: 1GB+)"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    
    # Check disk space
    DISK_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $DISK_SPACE -lt 5 ]]; then
        warn "Low disk space: ${DISK_SPACE}GB (Recommended: 10GB+)"
    fi
}

################################################################################
# Installation Steps
################################################################################

step01_update_system() {
    log "Step 1/20: Updating system packages..."
    
    # Fix any broken packages
    dpkg --configure -a 2>/dev/null || true
    apt-get --fix-broken install -y 2>/dev/null || true
    
    # Update package list
    apt-get update -qq
    
    # Upgrade packages
    apt-get upgrade -y -qq
    
    # Clean up
    apt-get autoremove -y -qq
    apt-get autoclean -qq
    
    success "System updated"
}

step02_install_essentials() {
    log "Step 2/20: Installing essential packages..."
    
    apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        git \
        gnupg \
        lsb-release \
        software-properties-common \
        nano \
        vim \
        htop \
        net-tools \
        unzip \
        zip \
        tar \
        gzip \
        screen \
        tmux \
        dnsutils \
        iputils-ping \
        traceroute
    
    success "Essential packages installed"
}

step03_install_build_tools() {
    log "Step 3/20: Installing build tools..."
    
    apt-get install -y -qq \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        autoconf \
        automake \
        libtool \
        pkg-config
    
    success "Build tools installed"
}

step04_install_python() {
    log "Step 4/20: Installing Python 3..."
    
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-dev \
        python3-venv \
        python3-setuptools \
        python3-wheel
    
    # Upgrade pip
    python3 -m pip install --upgrade pip setuptools wheel --quiet
    
    # Fix pip SSL warnings
    python3 -m pip install --upgrade certifi --quiet
    
    success "Python $(python3 --version | cut -d' ' -f2) installed"
}

step05_install_ffmpeg() {
    log "Step 5/20: Installing FFmpeg..."
    
    apt-get install -y -qq ffmpeg
    
    success "FFmpeg installed"
}

step06_install_mysql() {
    log "Step 6/20: Installing MySQL server..."
    
    # Install MySQL without prompts
    apt-get install -y -qq mysql-server mysql-client
    
    # Start MySQL
    systemctl start mysql
    systemctl enable mysql
    
    # Secure installation (automated)
    DB_ROOT_PASS=$(openssl rand -base64 16)
    DB_USER_PASS=$(openssl rand -base64 16)
    
    # Set root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';" 2>/dev/null || true
    
    # Create database and user
    mysql -u root -p"$DB_ROOT_PASS" << EOF 2>/dev/null
CREATE DATABASE IF NOT EXISTS vps_manager;
CREATE USER IF NOT EXISTS 'vps_admin'@'localhost' IDENTIFIED BY '$DB_USER_PASS';
GRANT ALL PRIVILEGES ON vps_manager.* TO 'vps_admin'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Save passwords
    mkdir -p $CONFIG_DIR
    cat > $CONFIG_DIR/mysql_credentials.txt << EOF
MySQL Root Password: $DB_ROOT_PASS
VPS Admin Password: $DB_USER_PASS
Database Name: vps_manager
Database User: vps_admin
EOF
    chmod 600 $CONFIG_DIR/mysql_credentials.txt
    
    success "MySQL installed (credentials saved)"
}

step07_install_nginx() {
    log "Step 7/20: Installing Nginx..."
    
    apt-get install -y -qq nginx
    
    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    success "Nginx installed"
}

step08_install_squid() {
    log "Step 8/20: Installing Squid proxy..."
    
    apt-get install -y -qq squid apache2-utils
    
    # Backup original config
    cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
    
    # Create new config
    cat > /etc/squid/squid.conf << 'EOF'
# Squid Proxy Configuration for VPS Manager Pro
http_port 3128

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm VPS Proxy Server
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# ACL definitions
acl SSL_ports port 443
acl Safe_ports port 80 443 3128
acl CONNECT method CONNECT

# Access rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow authenticated
http_access deny all

# Cache settings
cache deny all

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF
    
    # Create password file
    touch /etc/squid/passwd
    chmod 640 /etc/squid/passwd
    
    # Restart Squid
    systemctl restart squid
    systemctl enable squid
    
    success "Squid proxy installed"
}

step09_install_v2ray() {
    log "Step 9/20: Installing V2Ray..."
    
    # Download and install V2Ray
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) > /dev/null 2>&1 || {
        warn "V2Ray installation failed (optional service)"
        return 0
    }
    
    # Enable V2Ray
    systemctl enable v2ray 2>/dev/null || true
    
    success "V2Ray installed"
}

step10_configure_firewall() {
    log "Step 10/20: Configuring UFW firewall..."
    
    # Install UFW if not present
    apt-get install -y -qq ufw
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp comment 'SSH'
    
    # Allow HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Allow Squid Proxy
    ufw allow 3128/tcp comment 'Squid Proxy'
    
    # Enable firewall
    ufw --force enable
    
    success "Firewall configured"
}

step11_install_fail2ban() {
    log "Step 11/20: Installing Fail2Ban..."
    
    apt-get install -y -qq fail2ban
    
    # Configure Fail2Ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
EOF
    
    systemctl start fail2ban
    systemctl enable fail2ban
    
    success "Fail2Ban installed"
}

step12_install_ssl() {
    log "Step 12/20: Installing SSL certificate tools..."
    
    apt-get install -y -qq certbot python3-certbot-nginx
    
    # Try to get certificate (will fail if domain not configured)
    if [[ "$DOMAIN" != "v2ray.kurdcloud.xyz" ]]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
            --email "admin@$DOMAIN" --redirect --quiet 2>/dev/null && \
            success "SSL certificate obtained for $DOMAIN" || \
            warn "SSL certificate failed (check DNS configuration)"
    else
        warn "Using default domain - SSL skipped"
    fi
    
    success "SSL tools installed"
}

step13_create_directories() {
    log "Step 13/20: Creating directory structure..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BOT_DIR"
    mkdir -p "$BOT_DIR/handlers"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DOWNLOADS_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # Set permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$BOT_DIR"
    chmod 755 "$DOWNLOADS_DIR"
    chmod 700 "$CONFIG_DIR"
    
    success "Directory structure created"
}

step14_download_bot_files() {
    log "Step 14/20: Downloading bot files from GitHub..."
    
    GITHUB_RAW="https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main"
    
    # Download bot.py
    wget -q -O "$BOT_DIR/bot.py" "$GITHUB_RAW/bot.py" || \
        error "Failed to download bot.py"
    
    # Download config.py
    wget -q -O "$BOT_DIR/config.py" "$GITHUB_RAW/config.py" || \
        error "Failed to download config.py"
    
    # Download requirements.txt
    wget -q -O "$BOT_DIR/requirements.txt" "$GITHUB_RAW/requirements.txt" || \
        error "Failed to download requirements.txt"
    
    # Download handlers/__init__.py
    wget -q -O "$BOT_DIR/handlers/__init__.py" "$GITHUB_RAW/handlers/__init__.py" || \
        error "Failed to download handlers/__init__.py"
    
    # Download handlers/media.py
    wget -q -O "$BOT_DIR/handlers/media.py" "$GITHUB_RAW/handlers/media.py" || \
        error "Failed to download handlers/media.py"
    
    # Make bot.py executable
    chmod +x "$BOT_DIR/bot.py"
    
    success "Bot files downloaded"
}

step15_install_python_packages() {
    log "Step 15/20: Installing Python packages (this may take a few minutes)..."
    
    cd "$BOT_DIR"
    
    # Install from requirements.txt
    python3 -m pip install --quiet --no-cache-dir \
        python-telegram-bot==20.7 \
        instagrapi==2.0.0 \
        yt-dlp \
        mysql-connector-python==8.2.0 \
        qrcode==7.4.2 \
        Pillow==10.1.0 \
        psutil==5.9.6 \
        requests==2.31.0 || error "Failed to install Python packages"
    
    # Update yt-dlp to latest
    python3 -m pip install --upgrade yt-dlp --quiet
    
    success "Python packages installed"
}

step16_configure_bot() {
    log "Step 16/20: Configuring bot settings..."
    
    # Update config.py with actual values
    sed -i "s|BOT_TOKEN = .*|BOT_TOKEN = \"$BOT_TOKEN\"|g" "$BOT_DIR/config.py"
    sed -i "s|ADMIN_IDS = \[.*\]|ADMIN_IDS = [$ADMIN_ID]|g" "$BOT_DIR/config.py"
    sed -i "s|INSTAGRAM_USERNAME = .*|INSTAGRAM_USERNAME = \"$INSTA_USER\"|g" "$BOT_DIR/config.py"
    sed -i "s|INSTAGRAM_PASSWORD = .*|INSTAGRAM_PASSWORD = \"$INSTA_PASS\"|g" "$BOT_DIR/config.py"
    sed -i "s|DOMAIN = .*|DOMAIN = \"$DOMAIN\"|g" "$BOT_DIR/config.py"
    
    # Update paths in config
    sed -i "s|/opt/vps-manager/telegram-bot|$BOT_DIR|g" "$BOT_DIR/config.py"
    sed -i "s|/opt/vps-manager/logs|$LOG_DIR|g" "$BOT_DIR/config.py"
    
    success "Bot configured"
}

step17_create_systemd_service() {
    log "Step 17/20: Creating systemd service..."
    
    cat > /etc/systemd/system/vpsmanager-bot.service << EOF
[Unit]
Description=VPS Manager Pro Telegram Bot
After=network.target mysql.service nginx.service
Wants=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
Environment="PYTHONUNBUFFERED=1"
ExecStart=/usr/bin/python3 $BOT_DIR/bot.py
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/bot.log
StandardError=append:$LOG_DIR/bot-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    systemctl enable vpsmanager-bot
    
    success "Systemd service created"
}

step18_create_management_script() {
    log "Step 18/20: Creating management commands..."
    
    cat > /usr/local/bin/vpsbot << 'EOFSCRIPT'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

case "$1" in
    start)
        systemctl start vpsmanager-bot
        echo -e "${GREEN}✓${NC} Bot started"
        ;;
    stop)
        systemctl stop vpsmanager-bot
        echo -e "${YELLOW}✓${NC} Bot stopped"
        ;;
    restart)
        systemctl restart vpsmanager-bot
        echo -e "${GREEN}✓${NC} Bot restarted"
        ;;
    status)
        systemctl status vpsmanager-bot --no-pager
        ;;
    logs)
        tail -f /opt/vps-manager/logs/bot.log
        ;;
    errors)
        tail -f /opt/vps-manager/logs/bot-error.log
        ;;
    update)
        echo "Updating bot..."
        cd /opt/vps-manager/telegram-bot
        wget -q -O bot.py https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/bot.py
        wget -q -O handlers/media.py https://raw.githubusercontent.com/AndamAziz/vps-pro-maneger/main/handlers/media.py
        systemctl restart vpsmanager-bot
        echo -e "${GREEN}✓${NC} Bot updated and restarted"
        ;;
    *)
        echo "VPS Manager Pro - Bot Management"
        echo ""
        echo "Usage: vpsbot [command]"
        echo ""
        echo "Commands:"
        echo "  start    - Start the bot"
        echo "  stop     - Stop the bot"
        echo "  restart  - Restart the bot"
        echo "  status   - Show bot status"
        echo "  logs     - View live logs"
        echo "  errors   - View error logs"
        echo "  update   - Update bot to latest version"
        echo ""
        exit 1
        ;;
esac
EOFSCRIPT
    
    chmod +x /usr/local/bin/vpsbot
    
    success "Management commands created"
}

step19_start_services() {
    log "Step 19/20: Starting all services..."
    
    # Ensure all services are running
    systemctl restart mysql
    systemctl restart nginx
    systemctl restart squid
    systemctl restart fail2ban
    
    # Start bot
    systemctl start vpsmanager-bot
    sleep 5
    
    if systemctl is-active --quiet vpsmanager-bot; then
        success "All services started successfully"
    else
        warn "Bot service failed to start - check logs: vpsbot logs"
    fi
}

step20_cleanup() {
    log "Step 20/20: Cleaning up..."
    
    # Clean apt cache
    apt-get clean
    apt-get autoremove -y -qq
    
    # Remove unnecessary packages
    apt-get autoclean -qq
    
    success "Cleanup completed"
}

################################################################################
# Installation Summary
################################################################################

show_summary() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║          INSTALLATION COMPLETED SUCCESSFULLY! 🎉             ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    echo -e "${CYAN}📦 Installed Services:${NC}"
    echo "  ✓ MySQL Database Server"
    echo "  ✓ Nginx Web Server"
    echo "  ✓ Squid Proxy Server (Port 3128)"
    echo "  ✓ V2Ray VPN Server"
    echo "  ✓ UFW Firewall"
    echo "  ✓ Fail2Ban Security"
    echo "  ✓ SSL Certificate Tools"
    echo "  ✓ VPS Manager Telegram Bot"
    echo ""
    
    echo -e "${CYAN}🤖 Bot Information:${NC}"
    echo "  Bot Status: $(systemctl is-active vpsmanager-bot)"
    echo "  Telegram: @ALLINONEBIGBOSSbot"
    echo ""
    
    echo -e "${CYAN}📁 Important Directories:${NC}"
    echo "  Installation: $INSTALL_DIR"
    echo "  Bot: $BOT_DIR"
    echo "  Logs: $LOG_DIR"
    echo "  Downloads: $DOWNLOADS_DIR"
    echo "  Config: $CONFIG_DIR"
    echo ""
    
    echo -e "${CYAN}🔧 Management Commands:${NC}"
    echo "  vpsbot start     - Start the bot"
    echo "  vpsbot stop      - Stop the bot"
    echo "  vpsbot restart   - Restart the bot"
    echo "  vpsbot status    - Check bot status"
    echo "  vpsbot logs      - View live logs"
    echo "  vpsbot errors    - View error logs"
    echo "  vpsbot update    - Update to latest version"
    echo ""
    
    echo -e "${CYAN}🔐 Credentials:${NC}"
    echo "  MySQL saved in: $CONFIG_DIR/mysql_credentials.txt"
    echo ""
    
    echo -e "${CYAN}🌐 Network:${NC}"
    echo "  Domain: $DOMAIN"
    echo "  Proxy Port: 3128"
    echo ""
    
    echo -e "${CYAN}🔥 Firewall Ports:${NC}"
    echo "  SSH: 22"
    echo "  HTTP: 80"
    echo "  HTTPS: 443"
    echo "  Proxy: 3128"
    echo ""
    
    echo -e "${CYAN}📞 Support:${NC}"
    echo "  Telegram: @ALLINONEBIGBOSSbot"
    echo "  GitHub: github.com/AndamAziz/vps-pro-maneger"
    echo "  Email: support@kurdcloud.xyz"
    echo ""
    
    INSTALL_TIME=$((SECONDS / 60))
    echo -e "${GREEN}✓ Installation completed in $INSTALL_TIME minute(s)!${NC}"
    echo ""
    
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Check bot status: vpsbot status"
    echo "  2. View logs: vpsbot logs"
    echo "  3. Test bot on Telegram: /start"
    echo ""
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    # Start timer
    SECONDS=0
    
    # Show banner
    print_banner
    
    # Pre-installation checks
    log "Running pre-installation checks..."
    check_root
    check_os
    check_resources
    echo ""
    
    # Confirm installation
    echo -e "${YELLOW}This will install VPS Manager Pro and all dependencies.${NC}"
    echo -e "${YELLOW}Estimated time: 5-10 minutes${NC}"
    echo ""
    read -p "Continue with installation? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    echo ""
    log "Starting installation..."
    echo ""
    
    # Execute installation steps
    step01_update_system
    step02_install_essentials
    step03_install_build_tools
    step04_install_python
    step05_install_ffmpeg
    step06_install_mysql
    step07_install_nginx
    step08_install_squid
    step09_install_v2ray
    step10_configure_firewall
    step11_install_fail2ban
    step12_install_ssl
    step13_create_directories
    step14_download_bot_files
    step15_install_python_packages
    step16_configure_bot
    step17_create_systemd_service
    step18_create_management_script
    step19_start_services
    step20_cleanup
    
    # Show summary
    show_summary
}

# Run main installation
main "$@"
