#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
DOMAIN="v2ray.kurdcloud.xyz"
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"

init_v2ray_database() {
    sudo mysql $DB_NAME << 'EOF'
CREATE TABLE IF NOT EXISTS v2ray_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    protocol ENUM('vless', 'vmess', 'trojan') DEFAULT 'vless',
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    INDEX(uuid), INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} Database initialized"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

add_user_to_config() {
    local uuid=$1
    local protocol=$2
    local email=$3
    
    apt-get install -y -qq jq 2>/dev/null || true
    
    case $protocol in
        vless)
            jq ".inbounds[0].settings.clients += [{\"id\":\"$uuid\",\"email\":\"$email\"}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[3].settings.clients += [{\"id\":\"$uuid\",\"email\":\"$email\"}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            jq ".inbounds[1].settings.clients += [{\"id\":\"$uuid\",\"email\":\"$email\",\"alterId\":0}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[4].settings.clients += [{\"id\":\"$uuid\",\"email\":\"$email\",\"alterId\":0}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            jq ".inbounds[2].settings.clients += [{\"password\":\"$uuid\",\"email\":\"$email\"}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[5].settings.clients += [{\"password\":\"$uuid\",\"email\":\"$email\"}]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
}

generate_configs() {
    local username=$1
    local uuid=$2
    local protocol=$3
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              V2Ray Configs - $username (${protocol^^})              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}UUID:${NC} $uuid"
    echo ""
    
    case $protocol in
        vless)
            echo -e "${GREEN}▶ Config 1: VLESS + TLS (Port 443) - RECOMMENDED${NC}"
            local link443="vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&path=%2Fvless#${username}_443_TLS"
            echo "$link443"
            echo ""
            qrencode -t ANSIUTF8 "$link443" 2>/dev/null || echo "[QR code - install qrencode]"
            echo ""
            
            echo -e "${GREEN}▶ Config 2: VLESS (Port 8080) - NO TLS${NC}"
            local link8080="vless://${uuid}@${DOMAIN}:8080?encryption=none&security=none&type=ws&path=%2Fvless#${username}_8080"
            echo "$link8080"
            echo ""
            qrencode -t ANSIUTF8 "$link8080" 2>/dev/null || echo "[QR code - install qrencode]"
            ;;
            
        vmess)
            echo -e "${GREEN}▶ Config 1: VMess + TLS (Port 443) - RECOMMENDED${NC}"
            local json443='{"v":"2","ps":"'${username}'_443_TLS","add":"'${DOMAIN}'","port":"443","id":"'${uuid}'","aid":"0","net":"ws","path":"/vmess","host":"'${DOMAIN}'","tls":"tls"}'
            local link443="vmess://$(echo -n "$json443" | base64 -w 0)"
            echo "$link443"
            echo ""
            qrencode -t ANSIUTF8 "$link443" 2>/dev/null || echo "[QR code]"
            echo ""
            
            echo -e "${GREEN}▶ Config 2: VMess (Port 8081) - NO TLS${NC}"
            local json8081='{"v":"2","ps":"'${username}'_8081","add":"'${DOMAIN}'","port":"8081","id":"'${uuid}'","aid":"0","net":"ws","path":"/vmess","host":"'${DOMAIN}'","tls":""}'
            local link8081="vmess://$(echo -n "$json8081" | base64 -w 0)"
            echo "$link8081"
            echo ""
            qrencode -t ANSIUTF8 "$link8081" 2>/dev/null || echo "[QR code]"
            ;;
            
        trojan)
            echo -e "${GREEN}▶ Config 1: Trojan + TLS (Port 443) - RECOMMENDED${NC}"
            local link443="trojan://${uuid}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&type=tcp#${username}_443_TLS"
            echo "$link443"
            echo ""
            qrencode -t ANSIUTF8 "$link443" 2>/dev/null || echo "[QR code]"
            echo ""
            
            echo -e "${GREEN}▶ Config 2: Trojan (Port 8082) - NO TLS${NC}"
            local link8082="trojan://${uuid}@${DOMAIN}:8082?security=none&type=ws&path=%2Ftrojan#${username}_8082"
            echo "$link8082"
            echo ""
            qrencode -t ANSIUTF8 "$link8082" 2>/dev/null || echo "[QR code]"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}✓ Config 1 (Port 443): TLS encrypted - Use this!${NC}"
    echo -e "${YELLOW}✓ Config 2 (Port 8080+): Direct connection - Backup${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

add_v2ray_user() {
    local username=$1
    local days=$2
    local protocol=$3
    
    local uuid=$(generate_uuid)
    local expiry=$(date -d "+$days days" +%Y-%m-%d)
    
    add_user_to_config "$uuid" "$protocol" "${username}@${DOMAIN}"
    
    sudo mysql $DB_NAME << EOF
INSERT INTO v2ray_users (username, uuid, protocol, expiry_date)
VALUES ('$username', '$uuid', '$protocol', '$expiry');
EOF
    
    systemctl restart v2ray
    
    echo -e "${GREEN}✓${NC} User created!"
    generate_configs "$username" "$uuid" "$protocol"
}

delete_v2ray_user() {
    local username=$1
    local info=$(sudo mysql $DB_NAME -sN -e "SELECT uuid, protocol FROM v2ray_users WHERE username='$username' AND status='active';")
    
    [[ -z "$info" ]] && { echo -e "${RED}Not found${NC}"; return 1; }
    
    local uuid=$(echo "$info" | awk '{print $1}')
    local protocol=$(echo "$info" | awk '{print $2}')
    
    case $protocol in
        vless)
            jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[]|select(.id!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[3].settings.clients = [.inbounds[3].settings.clients[]|select(.id!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        vmess)
            jq ".inbounds[1].settings.clients = [.inbounds[1].settings.clients[]|select(.id!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[4].settings.clients = [.inbounds[4].settings.clients[]|select(.id!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
        trojan)
            jq ".inbounds[2].settings.clients = [.inbounds[2].settings.clients[]|select(.password!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            jq ".inbounds[5].settings.clients = [.inbounds[5].settings.clients[]|select(.password!=\"$uuid\")]" $V2RAY_CONFIG > ${V2RAY_CONFIG}.tmp && mv ${V2RAY_CONFIG}.tmp $V2RAY_CONFIG
            ;;
    esac
    
    sudo mysql $DB_NAME -e "UPDATE v2ray_users SET status='disabled' WHERE username='$username';"
    systemctl restart v2ray
    echo -e "${GREEN}✓${NC} Deleted"
}

list_users() {
    sudo mysql $DB_NAME -t -e "SELECT username, protocol, DATE_FORMAT(created_date,'%Y-%m-%d') as created, DATE_FORMAT(expiry_date,'%Y-%m-%d') as expires, status FROM v2ray_users ORDER BY created_date DESC;"
}

show_user_info() {
    local username=$1
    local info=$(sudo mysql $DB_NAME -sN -e "SELECT uuid, protocol, status FROM v2ray_users WHERE username='$username';")
    
    [[ -z "$info" ]] && { echo -e "${RED}Not found${NC}"; return 1; }
    
    local uuid=$(echo "$info" | awk '{print $1}')
    local protocol=$(echo "$info" | awk '{print $2}')
    local status=$(echo "$info" | awk '{print $3}')
    
    [[ "$status" == "active" ]] && generate_configs "$username" "$uuid" "$protocol" || echo -e "${RED}User is $status${NC}"
}

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║             V2Ray VPN - VPS Manager Pro                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add User    ${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}2.${NC} Delete User ${GREEN}5.${NC} Restart V2Ray"
    echo -e "${GREEN}3.${NC} List Users  ${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active v2ray 2>/dev/null || echo 'stopped')"
    echo ""
}

main() {
    while true; do
        show_menu
        read -p "Select: " choice
        case $choice in
            1)
                read -p "Username: " user
                read -p "Days: " days
                echo "Protocol: 1)VLESS 2)VMess 3)Trojan"
                read -p "[1]: " p
                case $p in 2) proto="vmess";; 3) proto="trojan";; *) proto="vless";; esac
                add_v2ray_user "$user" "$days" "$proto"
                read -p "Press enter..."
                ;;
            2) read -p "Username: " user; delete_v2ray_user "$user"; read -p "Press enter..." ;;
            3) list_users; read -p "Press enter..." ;;
            4) read -p "Username: " user; show_user_info "$user"; read -p "Press enter..." ;;
            5) systemctl restart v2ray; echo "✓ Restarted"; read -p "Press enter..." ;;
            0) exit 0 ;;
        esac
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
