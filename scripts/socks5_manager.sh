#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
SOCKS5_PORT="1080"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "87.106.64.47")

init_socks5_database() {
    sudo mysql $DB_NAME << 'EOF'
CREATE TABLE IF NOT EXISTS socks5_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(100) NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    traffic_limit_gb INT DEFAULT 0,
    traffic_used_gb DECIMAL(10,2) DEFAULT 0,
    INDEX(username), INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} SOCKS5 database initialized"
}

add_socks5_user() {
    local username=$1
    local password=$2
    local days=$3
    local traffic_gb=${4:-0}
    
    [[ -z "$username" || -z "$password" || -z "$days" ]] && {
        echo -e "${RED}Usage: add_socks5_user <username> <password> <days> [traffic_gb]${NC}"
        return 1
    }
    
    # Add system user for SOCKS5
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}User $username already exists, updating password...${NC}"
        echo "$username:$password" | chpasswd
    else
        useradd -M -s /usr/sbin/nologin "$username"
        echo "$username:$password" | chpasswd
    fi
    
    local expiry=$(date -d "+$days days" +%Y-%m-%d)
    
    sudo mysql $DB_NAME << EOF
INSERT INTO socks5_users (username, password, expiry_date, traffic_limit_gb)
VALUES ('$username', '$password', '$expiry', $traffic_gb)
ON DUPLICATE KEY UPDATE 
    password='$password',
    expiry_date='$expiry',
    traffic_limit_gb=$traffic_gb,
    status='active';
EOF
    
    echo -e "${GREEN}✓ SOCKS5 user created${NC}"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              SOCKS5 Proxy Configuration                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}Password:${NC} $password"
    echo -e "${YELLOW}Expires:${NC} $expiry"
    echo -e "${YELLOW}Traffic Limit:${NC} ${traffic_gb}GB"
    echo ""
    echo -e "${GREEN}SOCKS5 Configuration:${NC}"
    echo "  Host: $SERVER_IP"
    echo "  Port: $SOCKS5_PORT"
    echo "  Type: SOCKS5"
    echo "  Auth: Username/Password"
    echo ""
    echo -e "${CYAN}Browser Setup (Firefox/Chrome):${NC}"
    echo "  SOCKS5 Proxy: $SERVER_IP:$SOCKS5_PORT"
    echo "  Username: $username"
    echo "  Password: $password"
    echo "  ✓ Use for DNS queries"
    echo ""
    echo -e "${CYAN}Mobile Apps (Shadowsocks/etc):${NC}"
    echo "  Server: $SERVER_IP"
    echo "  Port: $SOCKS5_PORT"
    echo "  Protocol: SOCKS5"
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

delete_socks5_user() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: delete_socks5_user <username>${NC}"; return 1; }
    
    # Remove system user
    userdel "$username" 2>/dev/null || true
    
    sudo mysql $DB_NAME -e "UPDATE socks5_users SET status='disabled' WHERE username='$username';"
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

list_socks5_users() {
    echo -e "${CYAN}SOCKS5 Users:${NC}"
    echo ""
    sudo mysql $DB_NAME -t << 'EOF'
SELECT username, 
       DATE_FORMAT(created_date,'%Y-%m-%d') as created,
       DATE_FORMAT(expiry_date,'%Y-%m-%d') as expires,
       CONCAT(traffic_used_gb, '/', traffic_limit_gb, 'GB') as traffic,
       status
FROM socks5_users ORDER BY created_date DESC;
EOF
}

show_socks5_user() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: show_socks5_user <username>${NC}"; return 1; }
    
    local info=$(sudo mysql $DB_NAME -sN -e "SELECT password, DATE_FORMAT(expiry_date,'%Y-%m-%d'), traffic_limit_gb, status FROM socks5_users WHERE username='$username';")
    
    [[ -z "$info" ]] && { echo -e "${RED}User not found${NC}"; return 1; }
    
    local password=$(echo "$info" | awk '{print $1}')
    local expiry=$(echo "$info" | awk '{print $2}')
    local traffic=$(echo "$info" | awk '{print $3}')
    local status=$(echo "$info" | awk '{print $4}')
    
    echo ""
    echo -e "${CYAN}SOCKS5 User: $username${NC}"
    echo -e "${YELLOW}Status:${NC} $status"
    echo -e "${YELLOW}Password:${NC} $password"
    echo -e "${YELLOW}Expires:${NC} $expiry"
    echo -e "${YELLOW}Traffic:${NC} ${traffic}GB"
    echo ""
    echo -e "${GREEN}Connection Details:${NC}"
    echo "  Host: $SERVER_IP"
    echo "  Port: $SOCKS5_PORT"
    echo "  Type: SOCKS5"
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
}

test_socks5() {
    echo -e "${CYAN}Testing SOCKS5 proxy...${NC}"
    echo ""
    
    # Check if dante is running
    if systemctl is-active --quiet danted; then
        echo -e "${GREEN}✓${NC} Dante SOCKS5 server is running"
    else
        echo -e "${RED}✗${NC} Dante SOCKS5 server is not running"
        return 1
    fi
    
    # Check port
    if ss -tulpn | grep -q ":$SOCKS5_PORT"; then
        echo -e "${GREEN}✓${NC} SOCKS5 listening on port $SOCKS5_PORT"
    else
        echo -e "${RED}✗${NC} SOCKS5 not listening on port $SOCKS5_PORT"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}Active connections:${NC}"
    ss -tn | grep ":$SOCKS5_PORT" | wc -l
}

check_expired() {
    echo -e "${CYAN}Checking for expired users...${NC}"
    
    local expired=$(sudo mysql $DB_NAME -sN << EOF
SELECT username FROM socks5_users WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    while IFS= read -r username; do
        delete_socks5_user "$username"
        echo -e "${YELLOW}✓${NC} Disabled: $username"
    done <<< "$expired"
}

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        SOCKS5 Proxy Management - VPS Manager Pro            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add SOCKS5 User"
    echo -e "${GREEN}2.${NC} Delete User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Test SOCKS5 Server"
    echo -e "${GREEN}7.${NC} Restart SOCKS5"
    echo -e "${GREEN}8.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Server:${NC} $SERVER_IP:$SOCKS5_PORT"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active danted 2>/dev/null || echo 'stopped')"
    echo ""
}

main() {
    while true; do
        show_menu
        read -p "Select: " choice
        case $choice in
            1)
                read -p "Username: " user
                read -p "Password: " pass
                read -p "Days valid: " days
                read -p "Traffic limit GB [0]: " traffic
                add_socks5_user "$user" "$pass" "$days" "${traffic:-0}"
                read -p "Press enter..."
                ;;
            2)
                read -p "Username: " user
                delete_socks5_user "$user"
                read -p "Press enter..."
                ;;
            3)
                list_socks5_users
                read -p "Press enter..."
                ;;
            4)
                read -p "Username: " user
                show_socks5_user "$user"
                read -p "Press enter..."
                ;;
            5)
                check_expired
                read -p "Press enter..."
                ;;
            6)
                test_socks5
                read -p "Press enter..."
                ;;
            7)
                systemctl restart danted
                echo "✓ Restarted"
                read -p "Press enter..."
                ;;
            8)
                init_socks5_database
                read -p "Press enter..."
                ;;
            0)
                exit 0
                ;;
        esac
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
