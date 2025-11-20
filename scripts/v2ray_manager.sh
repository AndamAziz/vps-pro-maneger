#!/bin/bash
################################################################################
# V2Ray VPN Management - Complete with Full Configs
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

# Generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Add user to config
add_user_to_config() {
    local uuid=$1
    local protocol=$2
    local email=$3
    
    command -v jq >/dev/null 2>&1 || apt-get install -y -qq jq
    
    case $protocol in
        vless)
            # Add to Port 443
            jq ".inbounds[0].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Add to Port 80
            jq ".inbounds[3].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            # Add to Port 443
            jq ".inbounds[1].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"alterId\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Add to Port 80
            jq ".inbounds[4].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"alterId\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            # Add to Port 443
            jq ".inbounds[2].settings.clients += [{\"password\": \"$uuid\", \"email\": \"$email\"}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Add to Port 80
            jq ".inbounds[5].settings.clients += [{\"password\": \"$uuid\", \"email\": \"$email\"}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
}
}

# Generate full configs with both Port 443 and 80
generate_full_configs() {
    local username=$1
    local uuid=$2
    local protocol=$3
    
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "87.106.64.47")
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  V2Ray User Configuration                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}UUID:${NC} $uuid"
    echo -e "${YELLOW}Protocol:${NC} $protocol"
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}IP:${NC} $server_ip"
    echo ""
    
    case $protocol in
        vless)
            echo -e "${GREEN}═══ Config 1: VLESS + TLS + WebSocket (Port 443) ═══${NC}"
            local vless_link="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless#${username}_VLESS_443"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$vless_link"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_link"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: VLESS + TCP (Port 80 Fallback) ═══${NC}"
            local vless_80="vless://${uuid}@${DOMAIN}:80?encryption=none&security=none&type=ws&path=%2Fvless80&host=${DOMAIN}#${username}_VLESS_80"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$vless_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_80"
            echo ""
            
            echo -e "${BLUE}Manual Configuration (Port 443):${NC}"
            echo "  Address: $DOMAIN"
            echo "  Port: 443"
            echo "  UUID: $uuid"
            echo "  Encryption: none"
            echo "  Network: WebSocket"
            echo "  Path: /vless"
            echo "  Host: $DOMAIN"
            echo "  TLS: enabled"
            echo "  SNI: $DOMAIN"
            echo "  ALPN: http/1.1"
            echo ""
            ;;
            
        vmess)
            echo -e "${GREEN}═══ Config 1: VMess + TLS + WebSocket (Port 443) ═══${NC}"
            
            # Create VMess JSON for Port 443
            local vmess_json_443=$(cat <<VMESS443
{
  "v": "2",
  "ps": "${username}_VMess_443",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${uuid}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "/vmess",
  "tls": "tls",
  "sni": "${DOMAIN}",
  "alpn": "http/1.1"
}
VMESS443
)
            local vmess_link_443="vmess://$(echo -n "$vmess_json_443" | base64 -w 0)"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$vmess_link_443"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vmess_link_443"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: VMess + TCP (Port 80) ═══${NC}"
            
            # Create VMess JSON for Port 80
            local vmess_json_80=$(cat <<VMESS80
{
  "v": "2",
  "ps": "${username}_VMess_80",
  "add": "${server_ip}",
  "port": "80",
  "id": "${uuid}",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "",
  "tls": "",
  "sni": ""
}
VMESS80
)
            local vmess_link_80="vmess://$(echo -n "$vmess_json_80" | base64 -w 0)"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$vmess_link_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vmess_link_80"
            echo ""
            
            echo -e "${BLUE}Manual Configuration (Port 443):${NC}"
            echo "  Address: $DOMAIN"
            echo "  Port: 443"
            echo "  UUID: $uuid"
            echo "  AlterID: 0"
            echo "  Network: WebSocket"
            echo "  Path: /vmess"
            echo "  Host: $DOMAIN"
            echo "  TLS: enabled"
            echo "  SNI: $DOMAIN"
            echo "  ALPN: http/1.1"
            echo ""
            ;;
            
        trojan)
            echo -e "${GREEN}═══ Config 1: Trojan + TLS (Port 443) ═══${NC}"
            local trojan_443="trojan://${uuid}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&type=ws&path=%2Fvless80&headerType=none#${username}_Trojan_443"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$trojan_443"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$trojan_443"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: Trojan + TCP (Port 80) ═══${NC}"
            local trojan_80="trojan://${uuid}@${server_ip}:80?security=none&type=ws&path=%2Fvless80#${username}_Trojan_80"
            echo ""
            echo -e "${CYAN}Link:${NC}"
            echo "$trojan_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$trojan_80"
            echo ""
            
            echo -e "${BLUE}Manual Configuration (Port 443):${NC}"
            echo "  Address: $DOMAIN"
            echo "  Port: 443"
            echo "  Password: $uuid"
            echo "  Network: TCP"
            echo "  TLS: enabled"
            echo "  SNI: $DOMAIN"
            echo ""
            ;;
    esac
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Note: Config 1 (Port 443) is recommended for better security${NC}"
    echo -e "${YELLOW}      Config 2 (Port 80) is fallback if 443 is blocked${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
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
    
    echo -e "${GREEN}✓${NC} V2Ray user created successfully!"
    
    # Show full configs
    generate_full_configs "$username" "$uuid" "$protocol"
}

# Delete V2Ray user
delete_v2ray_user() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: delete_v2ray_user <username>${NC}"
        return 1
    fi
    
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
    command -v jq >/dev/null 2>&1 || apt-get install -y -qq jq
    
    case $protocol in
        vless)
            jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            jq ".inbounds[1].settings.clients = [.inbounds[1].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            jq ".inbounds[2].settings.clients = [.inbounds[2].settings.clients[] | select(.password != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
    
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
    
    echo -e "${CYAN}V2Ray User Information:${NC}"
    echo ""
    
    sudo mysql $DB_NAME -t << EOF
SELECT * FROM v2ray_users WHERE username='$username';
EOF
    
    if [[ "$status" == "active" ]]; then
        generate_full_configs "$username" "$uuid" "$protocol"
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
    echo -e "${GREEN}4.${NC} Show User Info (Full Configs + QR)"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Restart V2Ray"
    echo -e "${GREEN}7.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active v2ray 2>/dev/null || echo 'Not running')"
    echo ""
}

# Main
main() {
    # Install qrencode
    command -v qrencode >/dev/null 2>&1 || apt-get install -y -qq qrencode
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " username
                read -p "Days valid: " days
                echo "Select protocol:"
                echo "  1. VLESS (Recommended)"
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
                systemctl restart v2ray
                echo -e "${GREEN}✓${NC} V2Ray restarted"
                read -p "Press enter to continue..."
                ;;
            7)
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
