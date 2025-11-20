#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
SQUID_CONF="/etc/squid/squid.conf"
CURRENT_PORTS=(3128 8080)  # Default ports

# Get current configured ports
get_current_ports() {
    grep "^http_port" $SQUID_CONF | awk '{print $2}' | tr '\n' ' '
}

# Add new port
add_proxy_port() {
    local new_port=$1
    
    [[ -z "$new_port" ]] && { echo -e "${RED}Usage: add_proxy_port <port>${NC}"; return 1; }
    
    # Check if port already exists
    if grep -q "^http_port $new_port" $SQUID_CONF; then
        echo -e "${YELLOW}Port $new_port already configured${NC}"
        return 0
    fi
    
    # Check if port is in use
    if ss -tulpn | grep -q ":$new_port "; then
        echo -e "${RED}Error: Port $new_port is already in use by another service${NC}"
        ss -tulpn | grep ":$new_port"
        return 1
    fi
    
    # Add port to squid config
    sed -i "/^http_port 3128/a http_port $new_port" $SQUID_CONF
    
    # Allow in firewall
    ufw allow $new_port/tcp comment "Squid Proxy - Custom Port"
    
    # Restart Squid
    systemctl restart squid
    
    if systemctl is-active --quiet squid; then
        echo -e "${GREEN}✓${NC} Port $new_port added successfully!"
        echo -e "${CYAN}Squid is now listening on:${NC}"
        get_current_ports
    else
        echo -e "${RED}✗${NC} Failed to restart Squid. Check configuration."
        systemctl status squid --no-pager -l | tail -10
        return 1
    fi
}

# Remove port
remove_proxy_port() {
    local port=$1
    
    [[ -z "$port" ]] && { echo -e "${RED}Usage: remove_proxy_port <port>${NC}"; return 1; }
    
    # Don't allow removing default port 3128
    if [[ "$port" == "3128" ]]; then
        echo -e "${RED}Cannot remove default port 3128${NC}"
        return 1
    fi
    
    # Check if port exists in config
    if ! grep -q "^http_port $port" $SQUID_CONF; then
        echo -e "${YELLOW}Port $port not found in configuration${NC}"
        return 0
    fi
    
    # Remove from config
    sed -i "/^http_port $port/d" $SQUID_CONF
    
    # Remove from firewall
    ufw delete allow $port/tcp 2>/dev/null || true
    
    # Restart Squid
    systemctl restart squid
    
    echo -e "${GREEN}✓${NC} Port $port removed successfully!"
    echo -e "${CYAN}Squid is now listening on:${NC}"
    get_current_ports
}

# List all ports
list_proxy_ports() {
    echo -e "${CYAN}Squid Proxy Ports:${NC}"
    echo ""
    echo -e "${YELLOW}Configured Ports:${NC}"
    grep "^http_port" $SQUID_CONF | awk '{print "  - Port " $2}'
    echo ""
    echo -e "${YELLOW}Listening Ports (Active):${NC}"
    ss -tulpn | grep squid | grep LISTEN | awk '{print "  - " $5}' | sed 's/.*:/Port /'
    echo ""
}

# Initialize database
init_proxy_database() {
    sudo mysql $DB_NAME << 'EOF'
CREATE TABLE IF NOT EXISTS proxy_users (
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
    echo -e "${GREEN}✓${NC} Proxy database initialized"
}

# Add user
add_proxy_user() {
    local username=$1
    local password=$2
    local days=$3
    local traffic_gb=${4:-0}
    
    [[ -z "$username" || -z "$password" || -z "$days" ]] && {
        echo -e "${RED}Usage: add_proxy_user <username> <password> <days> [traffic_gb]${NC}"
        return 1
    }
    
    # Add to htpasswd
    if [ ! -f /etc/squid/passwd ]; then
        touch /etc/squid/passwd
        chmod 640 /etc/squid/passwd
        chown root:proxy /etc/squid/passwd
    fi
    
    htpasswd -b /etc/squid/passwd "$username" "$password"
    
    local expiry=$(date -d "+$days days" +%Y-%m-%d)
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    sudo mysql $DB_NAME << EOF
INSERT INTO proxy_users (username, password, expiry_date, traffic_limit_gb)
VALUES ('$username', '$password', '$expiry', $traffic_gb)
ON DUPLICATE KEY UPDATE 
    password='$password',
    expiry_date='$expiry',
    traffic_limit_gb=$traffic_gb,
    status='active';
EOF
    
    echo -e "${GREEN}✓ Proxy user created:${NC}"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Squid Proxy Configuration                       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Username:${NC} $username"
    echo -e "  ${YELLOW}Password:${NC} $password"
    echo -e "  ${YELLOW}Expires:${NC} $expiry"
    echo -e "  ${YELLOW}Traffic Limit:${NC} ${traffic_gb}GB"
    echo ""
    echo -e "  ${GREEN}Proxy Configuration:${NC}"
    echo -e "  Host: $server_ip"
    echo -e "  Ports: $(get_current_ports | tr ' ' ', ')"
    echo -e "  Type: HTTP/HTTPS"
    echo ""
    echo -e "  ${CYAN}Browser Setup:${NC}"
    local ports_array=($(get_current_ports))
    echo -e "  HTTP Proxy: $server_ip:${ports_array[0]}"
    echo -e "  HTTPS Proxy: $server_ip:${ports_array[0]}"
    echo -e "  Username: $username"
    echo -e "  Password: $password"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Delete user
delete_proxy_user() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: delete_proxy_user <username>${NC}"; return 1; }
    
    htpasswd -D /etc/squid/passwd "$username" 2>/dev/null || true
    sudo mysql $DB_NAME -e "UPDATE proxy_users SET status='disabled' WHERE username='$username';"
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List users
list_proxy_users() {
    echo -e "${CYAN}Proxy Users:${NC}"
    echo ""
    sudo mysql $DB_NAME -t << 'EOF'
SELECT username, 
       DATE_FORMAT(created_date,'%Y-%m-%d') as created,
       DATE_FORMAT(expiry_date,'%Y-%m-%d') as expires,
       CONCAT(traffic_used_gb, '/', traffic_limit_gb, 'GB') as traffic,
       status
FROM proxy_users ORDER BY created_date DESC;
EOF
}

# Show user info
show_user_info() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: show_user_info <username>${NC}"; return 1; }
    
    local info=$(sudo mysql $DB_NAME -sN -e "SELECT password, DATE_FORMAT(expiry_date,'%Y-%m-%d'), traffic_limit_gb, status FROM proxy_users WHERE username='$username';")
    
    [[ -z "$info" ]] && { echo -e "${RED}User not found${NC}"; return 1; }
    
    local password=$(echo "$info" | awk '{print $1}')
    local expiry=$(echo "$info" | awk '{print $2}')
    local traffic=$(echo "$info" | awk '{print $3}')
    local status=$(echo "$info" | awk '{print $4}')
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${CYAN}Proxy User: $username${NC}"
    echo -e "${YELLOW}Status:${NC} $status"
    echo -e "${YELLOW}Password:${NC} $password"
    echo -e "${YELLOW}Expires:${NC} $expiry"
    echo -e "${YELLOW}Traffic:${NC} ${traffic}GB"
    echo ""
    echo -e "${GREEN}Connection Details:${NC}"
    echo "  Host: $server_ip"
    echo "  Ports: $(get_current_ports | tr ' ' ', ')"
    echo "  Type: HTTP/HTTPS"
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
}

# Test proxy
test_proxy() {
    echo -e "${CYAN}Testing Squid Proxy...${NC}"
    echo ""
    
    if systemctl is-active --quiet squid; then
        echo -e "${GREEN}✓${NC} Squid is running"
    else
        echo -e "${RED}✗${NC} Squid is not running"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}Active Ports:${NC}"
    ss -tulpn | grep squid | grep LISTEN || echo "No listening ports found"
    
    echo ""
    echo -e "${YELLOW}Active Connections:${NC}"
    ss -tn | grep -E ":($(get_current_ports | tr ' ' '|'))" | wc -l
}

# Check expired
check_expired() {
    echo -e "${CYAN}Checking for expired users...${NC}"
    
    local expired=$(sudo mysql $DB_NAME -sN << EOF
SELECT username FROM proxy_users WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    while IFS= read -r username; do
        delete_proxy_user "$username"
        echo -e "${YELLOW}✓${NC} Disabled: $username"
    done <<< "$expired"
}

# Show menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Squid Proxy Management - VPS Manager Pro            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add Proxy User"
    echo -e "${GREEN}2.${NC} Delete Proxy User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Test Proxy"
    echo ""
    echo -e "${YELLOW}━━━ PORT MANAGEMENT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}7.${NC} Add New Port"
    echo -e "${GREEN}8.${NC} Remove Port"
    echo -e "${GREEN}9.${NC} List All Ports"
    echo ""
    echo -e "${YELLOW}━━━ SYSTEM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}10.${NC} Restart Squid"
    echo -e "${GREEN}11.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Current Ports:${NC} $(get_current_ports | tr ' ' ', ')"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active squid 2>/dev/null || echo 'stopped')"
    echo ""
}

# Main
main() {
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " user
                read -p "Password: " pass
                read -p "Days valid: " days
                read -p "Traffic limit GB [0]: " traffic
                add_proxy_user "$user" "$pass" "$days" "${traffic:-0}"
                read -p "Press enter..."
                ;;
            2)
                read -p "Username: " user
                delete_proxy_user "$user"
                read -p "Press enter..."
                ;;
            3)
                list_proxy_users
                read -p "Press enter..."
                ;;
            4)
                read -p "Username: " user
                show_user_info "$user"
                read -p "Press enter..."
                ;;
            5)
                check_expired
                read -p "Press enter..."
                ;;
            6)
                test_proxy
                read -p "Press enter..."
                ;;
            7)
                read -p "Enter new port number (e.g., 9090): " port
                add_proxy_port "$port"
                read -p "Press enter..."
                ;;
            8)
                list_proxy_ports
                read -p "Enter port number to remove: " port
                remove_proxy_port "$port"
                read -p "Press enter..."
                ;;
            9)
                list_proxy_ports
                read -p "Press enter..."
                ;;
            10)
                systemctl restart squid
                echo "✓ Restarted"
                read -p "Press enter..."
                ;;
            11)
                init_proxy_database
                read -p "Press enter..."
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
