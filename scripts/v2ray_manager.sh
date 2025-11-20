#!/bin/bash
################################################################################
# V2Ray VPN User Management Script
# Manages V2Ray users with VLESS/VMess protocols
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

DB_NAME="vps_manager"
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
DOMAIN="v2ray.kurdcloud.xyz"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

# Database initialization
init_v2ray_database() {
    mysql -u root << EOF
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS v2ray_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    protocol ENUM('vless', 'vmess') DEFAULT 'vless',
    port INT DEFAULT 443,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    traffic_limit_gb INT DEFAULT 0,
    traffic_used_gb DECIMAL(10,2) DEFAULT 0,
    last_connection DATETIME,
    INDEX(uuid),
    INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} V2Ray database initialized"
}

# Install V2Ray
install_v2ray() {
    echo -e "${CYAN}Installing V2Ray...${NC}"
    
    # Download and install
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    
    # Create config directory
    mkdir -p /usr/local/etc/v2ray
    
    echo -e "${GREEN}✓${NC} V2Ray installed"
}

# Configure V2Ray base
configure_v2ray_base() {
    echo -e "${CYAN}Configuring V2Ray base...${NC}"
    
    cat > $V2RAY_CONFIG << 'V2RAYCONF'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "wsSettings": {
          "path": "/v2ray"
        },
        "tlsSettings": {
          "serverName": "v2ray.kurdcloud.xyz",
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/v2ray.kurdcloud.xyz/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/v2ray.kurdcloud.xyz/privkey.pem"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
V2RAYCONF

    # Create log directory
    mkdir -p /var/log/v2ray
    
    # Set permissions
    chown -R nobody:nogroup /var/log/v2ray
    
    echo -e "${GREEN}✓${NC} V2Ray base configuration created"
}

# Generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Add V2Ray user
add_v2ray_user() {
    local username=$1
    local days=$2
    local protocol=${3:-vless}
    local traffic_gb=${4:-0}
    
    if [[ -z "$username" ]] || [[ -z "$days" ]]; then
        echo -e "${RED}Usage: add_v2ray_user <username> <days> [protocol] [traffic_gb]${NC}"
        return 1
    fi
    
    # Generate UUID
    local uuid=$(generate_uuid)
    
    # Calculate expiry
    local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    
    # Read current config
    local config=$(cat $V2RAY_CONFIG)
    
    # Add user to clients array
    local new_client=$(cat << CLIENTJSON
{
  "id": "$uuid",
  "email": "$username@$DOMAIN"
}
CLIENTJSON
)
    
    # Use jq to add client (install if not present)
    if ! command -v jq &> /dev/null; then
        apt-get install -y -qq jq
    fi
    
    # Add client
    jq ".inbounds[0].settings.clients += [$new_client]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
    mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
    
    # Add to database
    mysql -u root -D $DB_NAME << EOF
INSERT INTO v2ray_users (username, uuid, protocol, expiry_date, traffic_limit_gb)
VALUES ('$username', '$uuid', '$protocol', '$expiry_date', $traffic_gb);
EOF
    
    # Restart V2Ray
    systemctl restart v2ray
    
    # Generate connection info
    generate_connection_info "$username" "$uuid" "$protocol"
}

# Generate connection info
generate_connection_info() {
    local username=$1
    local uuid=$2
    local protocol=$3
    
    local server_ip=$(curl -s ifconfig.me)
    
    echo -e "${GREEN}✓${NC} V2Ray user created:"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}UUID:${NC} $uuid"
    echo -e "${YELLOW}Protocol:${NC} $protocol"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ "$protocol" == "vless" ]]; then
        local vless_link="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&path=%2Fv2ray#${username}"
        echo -e "${YELLOW}VLESS Link:${NC}"
        echo "$vless_link"
        echo ""
        
        # Generate QR code if qrencode is available
        if command -v qrencode &> /dev/null; then
            qrencode -t ANSIUTF8 "$vless_link"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Client Configuration:${NC}"
    echo "  Address: $DOMAIN"
    echo "  Port: 443"
    echo "  UUID: $uuid"
    echo "  Protocol: $protocol"
    echo "  Network: WebSocket"
    echo "  Path: /v2ray"
    echo "  Security: TLS"
    echo "  SNI: $DOMAIN"
    echo ""
}

# Delete V2Ray user
delete_v2ray_user() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: delete_v2ray_user <username>${NC}"
        return 1
    fi
    
    # Get UUID from database
    local uuid=$(mysql -u root -D $DB_NAME -sN << EOF
SELECT uuid FROM v2ray_users WHERE username='$username';
EOF
)
    
    if [[ -z "$uuid" ]]; then
        echo -e "${RED}✗${NC} User not found"
        return 1
    fi
    
    # Remove from V2Ray config
    jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" \
        $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
    mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
    
    # Update database
    mysql -u root -D $DB_NAME << EOF
UPDATE v2ray_users SET status='disabled' WHERE username='$username';
EOF
    
    # Restart V2Ray
    systemctl restart v2ray
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List V2Ray users
list_v2ray_users() {
    echo -e "${CYAN}V2Ray Users:${NC}"
    echo ""
    mysql -u root -D $DB_NAME -t << EOF
SELECT 
    username,
    protocol,
    DATE_FORMAT(created_date, '%Y-%m-%d') as created,
    DATE_FORMAT(expiry_date, '%Y-%m-%d') as expires,
    traffic_limit_gb as limit_gb,
    ROUND(traffic_used_gb, 2) as used_gb,
    status
FROM v2ray_users
ORDER BY created_date DESC;
EOF
}

# Show user info
show_user_info() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: show_user_info <username>${NC}"
        return 1
    fi
    
    # Get user data
    local user_data=$(mysql -u root -D $DB_NAME << EOF
SELECT uuid, protocol FROM v2ray_users WHERE username='$username';
EOF
)
    
    if [[ -z "$user_data" ]]; then
        echo -e "${RED}✗${NC} User not found"
        return 1
    fi
    
    local uuid=$(echo "$user_data" | tail -1 | awk '{print $1}')
    local protocol=$(echo "$user_data" | tail -1 | awk '{print $2}')
    
    echo -e "${CYAN}V2Ray User Information: $username${NC}"
    echo ""
    
    # From database
    mysql -u root -D $DB_NAME -t << EOF
SELECT * FROM v2ray_users WHERE username='$username';
EOF
    
    echo ""
    generate_connection_info "$username" "$uuid" "$protocol"
}

# Check expired users
check_expired_users() {
    echo -e "${CYAN}Checking for expired V2Ray users...${NC}"
    
    # Get expired users
    local expired=$(mysql -u root -D $DB_NAME -sN << EOF
SELECT username FROM v2ray_users 
WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    # Disable expired users
    while IFS= read -r username; do
        delete_v2ray_user "$username"
        echo -e "${YELLOW}✓${NC} Disabled expired user: $username"
    done <<< "$expired"
}

# Setup SSL certificate
setup_ssl() {
    echo -e "${CYAN}Setting up SSL certificate for $DOMAIN...${NC}"
    
    # Stop services that might use port 80
    systemctl stop nginx 2>/dev/null || true
    
    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq certbot
    fi
    
    # Get certificate
    certbot certonly --standalone \
        -d $DOMAIN \
        --non-interactive \
        --agree-tos \
        --email admin@$DOMAIN \
        --preferred-challenges http
    
    if [[ -f "$CERT_DIR/fullchain.pem" ]]; then
        echo -e "${GREEN}✓${NC} SSL certificate obtained"
        
        # Setup auto-renewal
        (crontab -l 2>/dev/null; echo "0 0 1 * * certbot renew --quiet && systemctl restart v2ray") | crontab -
        
        # Start nginx again
        systemctl start nginx 2>/dev/null || true
    else
        echo -e "${RED}✗${NC} Failed to obtain SSL certificate"
        return 1
    fi
}

# Test V2Ray
test_v2ray() {
    echo -e "${CYAN}Testing V2Ray configuration...${NC}"
    
    # Test config
    /usr/local/bin/v2ray test -config=$V2RAY_CONFIG
    
    # Check service status
    if systemctl is-active --quiet v2ray; then
        echo -e "${GREEN}✓${NC} V2Ray is running"
    else
        echo -e "${RED}✗${NC} V2Ray is not running"
    fi
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          V2Ray VPN Management - VPS Manager Pro             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add V2Ray User"
    echo -e "${GREEN}2.${NC} Delete V2Ray User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info (with QR)"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Setup SSL Certificate"
    echo -e "${GREEN}7.${NC} Test V2Ray"
    echo -e "${GREEN}8.${NC} Configure V2Ray Base"
    echo -e "${GREEN}9.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active v2ray 2>/dev/null || echo 'Not running')"
    echo ""
}

# Main
main() {
    # Check if V2Ray is installed
    if ! command -v v2ray &> /dev/null; then
        echo -e "${YELLOW}V2Ray not installed. Install now? (y/n)${NC}"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_v2ray
            configure_v2ray_base
        fi
    fi
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " username
                read -p "Days valid: " days
                read -p "Protocol (vless/vmess) [vless]: " protocol
                protocol=${protocol:-vless}
                read -p "Traffic limit (GB, 0=unlimited): " traffic
                add_v2ray_user "$username" "$days" "$protocol" "$traffic"
                read -p "Press enter to continue..."
                ;;
            2)
                read -p "Username to delete: " username
                delete_v2ray_user "$username"
                read -p "Press enter to continue..."
                ;;
            3)
                list_v2ray_users
                read -p "Press enter to continue..."
                ;;
            4)
                read -p "Username: " username
                show_user_info "$username"
                read -p "Press enter to continue..."
                ;;
            5)
                check_expired_users
                read -p "Press enter to continue..."
                ;;
            6)
                setup_ssl
                read -p "Press enter to continue..."
                ;;
            7)
                test_v2ray
                read -p "Press enter to continue..."
                ;;
            8)
                configure_v2ray_base
                read -p "Press enter to continue..."
                ;;
            9)
                init_v2ray_database
                read -p "Press enter to continue..."
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

# If called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
