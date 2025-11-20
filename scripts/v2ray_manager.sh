#!/bin/bash
################################################################################
# V2Ray VPN Management - Complete Rewrite
# Supports: VLESS, VMess, Trojan with TLS + WebSocket
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

DB_NAME="vps_manager"
DOMAIN="v2ray.kurdcloud.xyz"
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

# Initialize database
init_v2ray_database() {
    sudo mysql $DB_NAME << 'EOF'
CREATE TABLE IF NOT EXISTS v2ray_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    protocol ENUM('vless', 'vmess', 'trojan') DEFAULT 'vless',
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
    
    # Install V2Ray
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    
    # Create directories
    mkdir -p /usr/local/etc/v2ray
    mkdir -p /var/log/v2ray
    
    echo -e "${GREEN}✓${NC} V2Ray installed"
}

# Setup SSL Certificate
setup_ssl() {
    echo -e "${CYAN}Setting up SSL for $DOMAIN...${NC}"
    
    # Stop services that use port 80
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    
    # Install certbot
    apt-get update -qq
    apt-get install -y -qq certbot
    
    # Get certificate
    certbot certonly --standalone \
        -d $DOMAIN \
        --non-interactive \
        --agree-tos \
        --email admin@$DOMAIN \
        --preferred-challenges http
    
    if [ -f "$CERT_DIR/fullchain.pem" ]; then
        echo -e "${GREEN}✓${NC} SSL certificate obtained"
        
        # Setup auto-renewal
        (crontab -l 2>/dev/null; echo "0 0 1 * * certbot renew --quiet --post-hook 'systemctl restart v2ray'") | crontab -
        
        return 0
    else
        echo -e "${RED}✗${NC} Failed to obtain SSL certificate"
        return 1
    fi
}

# Configure V2Ray with all protocols
configure_v2ray_full() {
    echo -e "${CYAN}Configuring V2Ray with VLESS, VMess, and Trojan...${NC}"
    
    # Check SSL
    if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
        echo -e "${YELLOW}SSL certificate not found. Setting up...${NC}"
        setup_ssl || return 1
    fi
    
    cat > $V2RAY_CONFIG << V2CONFIG
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
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 8001
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$DOMAIN",
          "alpn": ["http/1.1"],
          "certificates": [
            {
              "certificateFile": "$CERT_DIR/fullchain.pem",
              "keyFile": "$CERT_DIR/privkey.pem"
            }
          ]
        }
      },
      "tag": "vless_tls"
    },
    {
      "port": 443,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      },
      "tag": "vless_ws"
    },
    {
      "port": 8001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      },
      "tag": "vmess_ws"
    },
    {
      "port": 8002,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      },
      "tag": "trojan_tcp"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
V2CONFIG

    # Set permissions
    chown -R nobody:nogroup /var/log/v2ray
    chmod 644 $V2RAY_CONFIG
    
    # Test config
    /usr/local/bin/v2ray test -config=$V2RAY_CONFIG
    
    if [ $? -eq 0 ]; then
        # Enable and start
        systemctl enable v2ray
        systemctl restart v2ray
        
        echo -e "${GREEN}✓${NC} V2Ray configured with all protocols"
        return 0
    else
        echo -e "${RED}✗${NC} V2Ray configuration test failed"
        return 1
    fi
}

# Generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Add user to V2Ray config
add_user_to_config() {
    local uuid=$1
    local protocol=$2
    local email=$3
    
    # Install jq if not present
    command -v jq >/dev/null 2>&1 || apt-get install -y -qq jq
    
    case $protocol in
        vless)
            # Add to VLESS
            jq ".inbounds[0].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            
            jq ".inbounds[1].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            # Add to VMess
            jq ".inbounds[2].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"alterId\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            # Add to Trojan
            jq ".inbounds[3].settings.clients += [{\"password\": \"$uuid\", \"email\": \"$email\"}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
}

# Remove user from config
remove_user_from_config() {
    local uuid=$1
    local protocol=$2
    
    case $protocol in
        vless)
            jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            
            jq ".inbounds[1].settings.clients = [.inbounds[1].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            jq ".inbounds[2].settings.clients = [.inbounds[2].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            jq ".inbounds[3].settings.clients = [.inbounds[3].settings.clients[] | select(.password != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
}

# Generate links and QR codes
generate_links() {
    local username=$1
    local uuid=$2
    local protocol=$3
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}UUID:${NC} $uuid"
    echo -e "${YELLOW}Protocol:${NC} $protocol"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    case $protocol in
        vless)
            # VLESS TLS
            local vless_tls="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=tcp&headerType=none#${username}_vless_tls"
            
            # VLESS WS
            local vless_ws="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&path=%2Fvless#${username}_vless_ws"
            
            echo -e "${GREEN}VLESS TLS:${NC}"
            echo "$vless_tls"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_tls"
            echo ""
            
            echo -e "${GREEN}VLESS WebSocket:${NC}"
            echo "$vless_ws"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_ws"
            ;;
            
        vmess)
            # VMess config
            local vmess_json=$(cat <<VMESS
{
  "v": "2",
  "ps": "${username}_vmess",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${uuid}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "/vmess",
  "tls": "tls",
  "sni": "${DOMAIN}"
}
VMESS
)
            local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
            
            echo -e "${GREEN}VMess WebSocket:${NC}"
            echo "$vmess_link"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vmess_link"
            ;;
            
        trojan)
            local trojan_link="trojan://${uuid}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&type=tcp#${username}_trojan"
            
            echo -e "${GREEN}Trojan:${NC}"
            echo "$trojan_link"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$trojan_link"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Client Configuration:${NC}"
    echo "  Server: $DOMAIN"
    echo "  Port: 443"
    echo "  UUID/Password: $uuid"
    echo "  Protocol: $protocol"
    echo "  Security: TLS"
    echo "  SNI: $DOMAIN"
    echo ""
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
    
    # Check if V2Ray is configured
    if [ ! -f "$V2RAY_CONFIG" ]; then
        echo -e "${YELLOW}V2Ray not configured. Configuring now...${NC}"
        configure_v2ray_full || return 1
    fi
    
    # Generate UUID
    local uuid=$(generate_uuid)
    local email="${username}@${DOMAIN}"
    
    # Calculate expiry
    local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    
    # Add to config
    add_user_to_config "$uuid" "$protocol" "$email"
    
    # Add to database
    sudo mysql $DB_NAME << EOF
INSERT INTO v2ray_users (username, uuid, protocol, expiry_date, traffic_limit_gb)
VALUES ('$username', '$uuid', '$protocol', '$expiry_date', $traffic_gb);
EOF
    
    # Restart V2Ray
    systemctl restart v2ray
    
    echo -e "${GREEN}✓${NC} V2Ray user created"
    echo ""
    
    # Show links
    generate_links "$username" "$uuid" "$protocol"
}

# Delete V2Ray user
delete_v2ray_user() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: delete_v2ray_user <username>${NC}"
        return 1
    fi
    
    # Get user info
    local user_info=$(sudo mysql $DB_NAME -sN << EOF
SELECT uuid, protocol FROM v2ray_users WHERE username='$username' AND status='active';
EOF
)
    
    if [[ -z "$user_info" ]]; then
        echo -e "${RED}✗${NC} User not found or already disabled"
        return 1
    fi
    
    local uuid=$(echo "$user_info" | awk '{print $1}')
    local protocol=$(echo "$user_info" | awk '{print $2}')
    
    # Remove from config
    remove_user_from_config "$uuid" "$protocol"
    
    # Update database
    sudo mysql $DB_NAME << EOF
UPDATE v2ray_users SET status='disabled' WHERE username='$username';
EOF
    
    # Restart V2Ray
    systemctl restart v2ray
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List users
list_v2ray_users() {
    echo -e "${CYAN}V2Ray Users:${NC}"
    echo ""
    sudo mysql $DB_NAME -t << 'EOF'
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
    
    local user_info=$(sudo mysql $DB_NAME -sN << EOF
SELECT uuid, protocol, status FROM v2ray_users WHERE username='$username';
EOF
)
    
    if [[ -z "$user_info" ]]; then
        echo -e "${RED}✗${NC} User not found"
        return 1
    fi
    
    local uuid=$(echo "$user_info" | awk '{print $1}')
    local protocol=$(echo "$user_info" | awk '{print $2}')
    local status=$(echo "$user_info" | awk '{print $3}')
    
    echo -e "${CYAN}V2Ray User Information: $username${NC}"
    echo ""
    
    sudo mysql $DB_NAME -t << EOF
SELECT * FROM v2ray_users WHERE username='$username';
EOF
    
    if [[ "$status" == "active" ]]; then
        echo ""
        generate_links "$username" "$uuid" "$protocol"
    fi
}

# Check expired users
check_expired_users() {
    echo -e "${CYAN}Checking for expired users...${NC}"
    
    local expired=$(sudo mysql $DB_NAME -sN << EOF
SELECT username FROM v2ray_users 
WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    while IFS= read -r username; do
        delete_v2ray_user "$username"
        echo -e "${YELLOW}✓${NC} Disabled expired user: $username"
    done <<< "$expired"
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          V2Ray VPN Management - VPS Manager Pro             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add V2Ray User (VLESS/VMess/Trojan)"
    echo -e "${GREEN}2.${NC} Delete V2Ray User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info (with Links & QR)"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Setup SSL Certificate"
    echo -e "${GREEN}7.${NC} Configure V2Ray (Full Setup)"
    echo -e "${GREEN}8.${NC} Restart V2Ray"
    echo -e "${GREEN}9.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active v2ray 2>/dev/null || echo 'Not running')"
    echo ""
}

# Main
main() {
    # Install qrencode for QR codes
    command -v qrencode >/dev/null 2>&1 || apt-get install -y -qq qrencode
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " username
                read -p "Days valid: " days
                echo "Select protocol:"
                echo "  1. VLESS"
                echo "  2. VMess"
                echo "  3. Trojan"
                read -p "Protocol [1]: " proto_choice
                
                case $proto_choice in
                    2) protocol="vmess" ;;
                    3) protocol="trojan" ;;
                    *) protocol="vless" ;;
                esac
                
                read -p "Traffic limit (GB, 0=unlimited) [0]: " traffic
                traffic=${traffic:-0}
                
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
                configure_v2ray_full
                read -p "Press enter to continue..."
                ;;
            8)
                systemctl restart v2ray
                echo -e "${GREEN}✓${NC} V2Ray restarted"
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
