#!/bin/bash
################################################################################
# V2Ray VPN Management - Dual Port (443 + 80)
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

# Add user to config (both Port 443 and 80)
add_user_to_config() {
    local uuid=$1
    local protocol=$2
    local email=$3
    
    command -v jq >/dev/null 2>&1 || apt-get install -y -qq jq
    
    case $protocol in
        vless)
            # Port 443
            jq ".inbounds[0].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Port 80
            jq ".inbounds[3].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"level\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            # Port 443
            jq ".inbounds[1].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"alterId\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Port 80
            jq ".inbounds[4].settings.clients += [{\"id\": \"$uuid\", \"email\": \"$email\", \"alterId\": 0}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            # Port 443
            jq ".inbounds[2].settings.clients += [{\"password\": \"$uuid\", \"email\": \"$email\"}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            # Port 80
            jq ".inbounds[5].settings.clients += [{\"password\": \"$uuid\", \"email\": \"$email\"}]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
}

# Generate full configs
generate_full_configs() {
    local username=$1
    local uuid=$2
    local protocol=$3
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  V2Ray User Configuration                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}UUID:${NC} $uuid"
    echo -e "${YELLOW}Protocol:${NC} $protocol"
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo ""
    
    case $protocol in
        vless)
            echo -e "${GREEN}═══ Config 1: VLESS + TLS (Port 443) ═══${NC}"
            local vless_443="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless#${username}_VLESS_443"
            echo ""
            echo "$vless_443"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_443"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: VLESS (Port 80) ═══${NC}"
            local vless_80="vless://${uuid}@${DOMAIN}:80?encryption=none&security=none&type=ws&host=${DOMAIN}&path=%2Fvless80#${username}_VLESS_80"
            echo ""
            echo "$vless_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vless_80"
            ;;
            
        vmess)
            echo -e "${GREEN}═══ Config 1: VMess + TLS (Port 443) ═══${NC}"
            local vmess_json_443=$(cat <<VMESS443
{"v":"2","ps":"${username}_VMess_443","add":"${DOMAIN}","port":"443","id":"${uuid}","aid":"0","net":"ws","type":"none","host":"${DOMAIN}","path":"/vmess","tls":"tls","sni":"${DOMAIN}","alpn":"http/1.1"}
VMESS443
)
            local vmess_443="vmess://$(echo -n "$vmess_json_443" | base64 -w 0)"
            echo ""
            echo "$vmess_443"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vmess_443"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: VMess (Port 80) ═══${NC}"
            local vmess_json_80=$(cat <<VMESS80
{"v":"2","ps":"${username}_VMess_80","add":"${DOMAIN}","port":"80","id":"${uuid}","aid":"0","net":"ws","type":"none","host":"${DOMAIN}","path":"/vmess80","tls":"","sni":""}
VMESS80
)
            local vmess_80="vmess://$(echo -n "$vmess_json_80" | base64 -w 0)"
            echo ""
            echo "$vmess_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$vmess_80"
            ;;
            
        trojan)
            echo -e "${GREEN}═══ Config 1: Trojan + TLS (Port 443) ═══${NC}"
            local trojan_443="trojan://${uuid}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&type=tcp#${username}_Trojan_443"
            echo ""
            echo "$trojan_443"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$trojan_443"
            echo ""
            
            echo -e "${GREEN}═══ Config 2: Trojan (Port 80) ═══${NC}"
            local trojan_80="trojan://${uuid}@${DOMAIN}:80?security=none&type=tcp#${username}_Trojan_80"
            echo ""
            echo "$trojan_80"
            echo ""
            command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "$trojan_80"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Config 1 (Port 443): TLS encrypted - Recommended${NC}"
    echo -e "${YELLOW}Config 2 (Port 80): No TLS - Fallback option${NC}"
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
    
    local uuid=$(generate_uuid)
    local email="${username}@${DOMAIN}"
    local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    
    add_user_to_config "$uuid" "$protocol" "$email"
    
    sudo mysql $DB_NAME << EOF
INSERT INTO v2ray_users (username, uuid, protocol, expiry_date, traffic_limit_gb)
VALUES ('$username', '$uuid', '$protocol', '$expiry_date', $traffic_gb);
EOF
    
    systemctl restart v2ray
    
    echo -e "${GREEN}✓${NC} V2Ray user created successfully!"
    
    generate_full_configs "$username" "$uuid" "$protocol"
}

# Delete user
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
        echo -e "${RED}✗${NC} User not found"
        return 1
    fi
    
    local uuid=$(echo "$user_info" | awk '{print $1}')
    local protocol=$(echo "$user_info" | awk '{print $2}')
    
    command -v jq >/dev/null 2>&1 || apt-get install -y -qq jq
    
    case $protocol in
        vless)
            jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[3].settings.clients = [.inbounds[3].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            jq ".inbounds[1].settings.clients = [.inbounds[1].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[4].settings.clients = [.inbounds[4].settings.clients[] | select(.id != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            jq ".inbounds[2].settings.clients = [.inbounds[2].settings.clients[] | select(.password != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[5].settings.clients = [.inbounds[5].settings.clients[] | select(.password != \"$uuid\")]" \
                $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp
            mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
    
    sudo mysql $DB_NAME << EOF
UPDATE v2ray_users SET status='disabled' WHERE username='$username';
EOF
    
    systemctl restart v2ray
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List users
list_v2ray_users() {
    echo -e "${CYAN}V2Ray Users:${NC}"
    echo ""
    sudo mysql $DB_NAME -t << 'EOF'
SELECT username, protocol, DATE_FORMAT(created_date, '%Y-%m-%d') as created,
       DATE_FORMAT(expiry_date, '%Y-%m-%d') as expires, status
FROM v2ray_users ORDER BY created_date DESC;
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
    
    if [[ "$status" == "active" ]]; then
        generate_full_configs "$username" "$uuid" "$protocol"
    else
        echo -e "${RED}User is $status${NC}"
    fi
}

# Check expired
check_expired_users() {
    echo -e "${CYAN}Checking for expired users...${NC}"
    
    local expired=$(sudo mysql $DB_NAME -sN << EOF
SELECT username FROM v2ray_users WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    while IFS= read -r username; do
        delete_v2ray_user "$username"
        echo -e "${YELLOW}✓${NC} Disabled: $username"
    done <<< "$expired"
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
    echo -e "${GREEN}4.${NC} Show User Info (Configs + QR)"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Restart V2Ray"
    echo -e "${GREEN}7.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active v2ray 2>/dev/null || echo 'stopped')"
    echo ""
}

# Main
main() {
    command -v qrencode >/dev/null 2>&1 || apt-get install -y -qq qrencode
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " username
                read -p "Days valid: " days
                echo "Protocol: 1)VLESS 2)VMess 3)Trojan"
                read -p "Select [1]: " proto_choice
                case $proto_choice in
                    2) protocol="vmess" ;;
                    3) protocol="trojan" ;;
                    *) protocol="vless" ;;
                esac
                read -p "Traffic limit GB [0]: " traffic
                add_v2ray_user "$username" "$days" "$protocol" "${traffic:-0}"
                read -p "Press enter..."
                ;;
            2)
                read -p "Username: " username
                delete_v2ray_user "$username"
                read -p "Press enter..."
                ;;
            3)
                list_v2ray_users
                read -p "Press enter..."
                ;;
            4)
                read -p "Username: " username
                show_user_info "$username"
                read -p "Press enter..."
                ;;
            5)
                check_expired_users
                read -p "Press enter..."
                ;;
            6)
                systemctl restart v2ray
                echo -e "${GREEN}✓${NC} Restarted"
                read -p "Press enter..."
                ;;
            7)
                init_v2ray_database
                read -p "Press enter..."
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Invalid"
                sleep 1
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
