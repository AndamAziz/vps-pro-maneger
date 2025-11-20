#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "87.106.64.47")
DOMAIN="v2ray.kurdcloud.xyz"
DOWNLOAD_DIR="/var/www/html/ovpn"

init_openvpn_database() {
    sudo mysql $DB_NAME << 'EOF'
CREATE TABLE IF NOT EXISTS openvpn_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    udp_config VARCHAR(255),
    tcp_config VARCHAR(255),
    INDEX(username), INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} OpenVPN database initialized"
}

create_client() {
    local username=$1
    local days=$2
    
    [[ -z "$username" || -z "$days" ]] && { echo -e "${RED}Usage: create_client <username> <days>${NC}"; return 1; }
    
    echo -e "${CYAN}Creating OpenVPN user: $username${NC}"
    echo ""
    
    cd $EASYRSA_DIR
    
    # Build client certificate with auto-yes
    echo "yes" | ./easyrsa build-client-full "$username" nopass 2>&1 | grep -E "(Notice|Certificate created)"
    
    local expiry=$(date -d "+$days days" +%Y-%m-%d)
    
    mkdir -p $DOWNLOAD_DIR
    
    # Generate UDP config
    local udp_file="$DOWNLOAD_DIR/${username}-udp.ovpn"
    cat > "$udp_file" << UDPCONFIG
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3
<ca>
$(cat $EASYRSA_DIR/pki/ca.crt)
</ca>
<cert>
$(openssl x509 -in $EASYRSA_DIR/pki/issued/$username.crt)
</cert>
<key>
$(cat $EASYRSA_DIR/pki/private/$username.key)
</key>
<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
UDPCONFIG

    # Generate TCP config
    local tcp_file="$DOWNLOAD_DIR/${username}-tcp.ovpn"
    cat > "$tcp_file" << TCPCONFIG
client
dev tun
proto tcp
remote $SERVER_IP 1443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3
<ca>
$(cat $EASYRSA_DIR/pki/ca.crt)
</ca>
<cert>
$(openssl x509 -in $EASYRSA_DIR/pki/issued/$username.crt)
</cert>
<key>
$(cat $EASYRSA_DIR/pki/private/$username.key)
</key>
<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
TCPCONFIG

    chmod 644 "$udp_file" "$tcp_file"
    
    local udp_link="http://$DOMAIN/ovpn/${username}-udp.ovpn"
    local tcp_link="http://$DOMAIN/ovpn/${username}-tcp.ovpn"
    
    sudo mysql $DB_NAME << EOF
INSERT INTO openvpn_users (username, expiry_date, udp_config, tcp_config)
VALUES ('$username', '$expiry', '$udp_link', '$tcp_link');
EOF
    
    echo ""
    echo -e "${GREEN}✓ OpenVPN user created!${NC}"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              OpenVPN Configuration Links                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}Expires:${NC} $expiry"
    echo ""
    echo -e "${GREEN}▶ UDP Config (Port 1194) - RECOMMENDED${NC}"
    echo "$udp_link"
    echo ""
    echo -e "${GREEN}▶ TCP Config (Port 1443) - Fallback${NC}"
    echo "$tcp_link"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Download and import to OpenVPN client${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

delete_client() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: delete_client <username>${NC}"; return 1; }
    
    cd $EASYRSA_DIR
    echo "yes" | ./easyrsa revoke "$username" 2>&1 | grep -E "(Notice|revoked)"
    ./easyrsa gen-crl 2>&1 | grep -E "Notice"
    
    rm -f "$DOWNLOAD_DIR/${username}-udp.ovpn"
    rm -f "$DOWNLOAD_DIR/${username}-tcp.ovpn"
    
    sudo mysql $DB_NAME -e "UPDATE openvpn_users SET status='disabled' WHERE username='$username';"
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

list_clients() {
    echo -e "${CYAN}OpenVPN Users:${NC}"
    echo ""
    sudo mysql $DB_NAME -t << 'EOF'
SELECT username, DATE_FORMAT(created_date,'%Y-%m-%d') as created, 
       DATE_FORMAT(expiry_date,'%Y-%m-%d') as expires, status
FROM openvpn_users ORDER BY created_date DESC;
EOF
}

show_client_info() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: show_client_info <username>${NC}"; return 1; }
    
    local info=$(sudo mysql $DB_NAME -sN -e "SELECT udp_config, tcp_config, DATE_FORMAT(expiry_date,'%Y-%m-%d'), status FROM openvpn_users WHERE username='$username';")
    
    [[ -z "$info" ]] && { echo -e "${RED}User not found${NC}"; return 1; }
    
    local udp=$(echo "$info" | awk '{print $1}')
    local tcp=$(echo "$info" | awk '{print $2}')
    local expiry=$(echo "$info" | awk '{print $3}')
    local status=$(echo "$info" | awk '{print $4}')
    
    echo ""
    echo -e "${CYAN}OpenVPN User: $username${NC}"
    echo -e "${YELLOW}Status:${NC} $status"
    echo -e "${YELLOW}Expires:${NC} $expiry"
    echo ""
    echo -e "${GREEN}UDP Config:${NC}"
    echo "$udp"
    echo ""
    echo -e "${GREEN}TCP Config:${NC}"
    echo "$tcp"
    echo ""
}

show_connections() {
    echo -e "${CYAN}Active OpenVPN Connections:${NC}"
    echo ""
    echo -e "${YELLOW}UDP (Port 1194):${NC}"
    [[ -f /var/log/openvpn/openvpn-status-udp.log ]] && cat /var/log/openvpn/openvpn-status-udp.log | grep "^CLIENT_LIST" || echo "No connections"
    echo ""
    echo -e "${YELLOW}TCP (Port 1443):${NC}"
    [[ -f /var/log/openvpn/openvpn-status-tcp.log ]] && cat /var/log/openvpn/openvpn-status-tcp.log | grep "^CLIENT_LIST" || echo "No connections"
}

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           OpenVPN Management - VPS Manager Pro              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add OpenVPN User"
    echo -e "${GREEN}2.${NC} Delete User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info (Download Links)"
    echo -e "${GREEN}5.${NC} Show Active Connections"
    echo -e "${GREEN}6.${NC} Restart OpenVPN"
    echo -e "${GREEN}7.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Ports:${NC} UDP 1194, TCP 1443"
    echo -e "${YELLOW}Status:${NC} UDP=$(systemctl is-active openvpn-server@server-udp) TCP=$(systemctl is-active openvpn-server@server-tcp)"
    echo ""
}

main() {
    while true; do
        show_menu
        read -p "Select: " choice
        case $choice in
            1)
                read -p "Username: " user
                read -p "Days valid: " days
                create_client "$user" "$days"
                read -p "Press enter..."
                ;;
            2)
                read -p "Username: " user
                delete_client "$user"
                read -p "Press enter..."
                ;;
            3)
                list_clients
                read -p "Press enter..."
                ;;
            4)
                read -p "Username: " user
                show_client_info "$user"
                read -p "Press enter..."
                ;;
            5)
                show_connections
                read -p "Press enter..."
                ;;
            6)
                systemctl restart openvpn-server@server-udp
                systemctl restart openvpn-server@server-tcp
                echo "✓ Restarted"
                read -p "Press enter..."
                ;;
            7)
                init_openvpn_database
                read -p "Press enter..."
                ;;
            0)
                exit 0
                ;;
        esac
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
