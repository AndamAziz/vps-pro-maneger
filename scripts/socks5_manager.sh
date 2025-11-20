#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

DB_NAME="vps_manager"
DANTE_CONF="/etc/danted.conf"
DEFAULT_PORT="1080"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "127.0.0.1")

# Get network interface
get_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# Get all configured ports
get_current_ports() {
    grep "^internal.*port" $DANTE_CONF | awk -F'=' '{print $2}' | tr -d ' ' | tr '\n' ',' | sed 's/,$//'
}

# Backup config
backup_config() {
    cp $DANTE_CONF ${DANTE_CONF}.backup.$(date +%Y%m%d_%H%M%S)
}

# Add new port
add_socks5_port() {
    local new_port=$1
    
    [[ -z "$new_port" ]] && { 
        echo -e "${RED}Usage: add_socks5_port <port>${NC}"
        return 1
    }
    
    # Validate port number
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${RED}Error: Invalid port number. Use 1024-65535${NC}"
        return 1
    fi
    
    # Check if port already exists
    if grep -q "internal.*port = $new_port" $DANTE_CONF; then
        echo -e "${YELLOW}Port $new_port is already configured${NC}"
        return 0
    fi
    
    # Check if port is in use
    if ss -tulpn | grep -q ":$new_port "; then
        echo -e "${RED}Error: Port $new_port is already in use${NC}"
        ss -tulpn | grep ":$new_port"
        return 1
    fi
    
    echo -e "${CYAN}Adding port $new_port to SOCKS5...${NC}"
    
    # Backup config
    backup_config
    
    # Add new internal line after first internal
    sed -i "/^internal: 0.0.0.0 port = $DEFAULT_PORT/a internal: 0.0.0.0 port = $new_port" $DANTE_CONF
    
    # Test configuration
    if ! danted -V -f $DANTE_CONF &>/dev/null; then
        echo -e "${RED}Configuration error! Restoring backup...${NC}"
        cp ${DANTE_CONF}.backup.* $DANTE_CONF 2>/dev/null || true
        return 1
    fi
    
    # Restart service
    systemctl restart danted
    
    if systemctl is-active --quiet danted; then
        # Configure firewall if available
        command -v ufw &>/dev/null && ufw allow $new_port/tcp comment "SOCKS5 - Custom Port" 2>/dev/null || true
        
        echo -e "${GREEN}✓ Port $new_port added successfully!${NC}"
        echo ""
        echo -e "${CYAN}SOCKS5 is now listening on:${NC}"
        echo "  $(get_current_ports | tr ',' '\n  ')"
        echo ""
    else
        echo -e "${RED}✗ Failed to restart Dante. Restoring backup...${NC}"
        cp ${DANTE_CONF}.backup.* $DANTE_CONF 2>/dev/null || true
        systemctl restart danted
        return 1
    fi
}

# Remove port
remove_socks5_port() {
    local port=$1
    
    [[ -z "$port" ]] && {
        echo -e "${RED}Usage: remove_socks5_port <port>${NC}"
        return 1
    }
    
    # Don't allow removing default port
    if [[ "$port" == "$DEFAULT_PORT" ]]; then
        echo -e "${RED}Cannot remove default port $DEFAULT_PORT${NC}"
        return 1
    fi
    
    # Check if port exists
    if ! grep -q "internal.*port = $port" $DANTE_CONF; then
        echo -e "${YELLOW}Port $port not found in configuration${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Removing port $port from SOCKS5...${NC}"
    
    # Backup config
    backup_config
    
    # Remove the line
    sed -i "/^internal: 0.0.0.0 port = $port/d" $DANTE_CONF
    
    # Restart service
    systemctl restart danted
    
    if systemctl is-active --quiet danted; then
        # Remove from firewall if available
        command -v ufw &>/dev/null && ufw delete allow $port/tcp 2>/dev/null || true
        
        echo -e "${GREEN}✓ Port $port removed successfully!${NC}"
        echo ""
        echo -e "${CYAN}SOCKS5 is now listening on:${NC}"
        echo "  $(get_current_ports | tr ',' '\n  ')"
        echo ""
    else
        echo -e "${RED}✗ Failed to restart Dante. Restoring backup...${NC}"
        cp ${DANTE_CONF}.backup.* $DANTE_CONF 2>/dev/null || true
        systemctl restart danted
        return 1
    fi
}

# List all ports
list_socks5_ports() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              SOCKS5 Port Configuration                       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}Configured Ports (in config):${NC}"
    local port_num=1
    while IFS= read -r line; do
        local port=$(echo "$line" | awk -F'=' '{print $2}' | tr -d ' ')
        if [[ "$port" == "$DEFAULT_PORT" ]]; then
            echo -e "  ${GREEN}$port_num. Port $port ${MAGENTA}(Default)${NC}"
        else
            echo -e "  ${GREEN}$port_num. Port $port${NC}"
        fi
        ((port_num++))
    done < <(grep "^internal.*port" $DANTE_CONF)
    
    echo ""
    echo -e "${YELLOW}Active Listening Ports:${NC}"
    if ss -tulpn | grep danted | grep LISTEN &>/dev/null; then
        ss -tulpn | grep danted | grep LISTEN | awk '{print $5}' | sed 's/.*:/  ✓ Port /'
    else
        echo -e "  ${RED}No active ports found${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Connection Details:${NC}"
    echo "  Server: $SERVER_IP"
    echo "  Ports: $(get_current_ports)"
    echo "  Protocol: SOCKS5"
    echo "  Auth: Username/Password"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Remove all custom ports (keep only default)
remove_all_ports() {
    echo -e "${YELLOW}WARNING: This will remove all custom ports and keep only port $DEFAULT_PORT${NC}"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Cancelled${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Removing all custom ports...${NC}"
    
    # Backup config
    backup_config
    
    # Keep only default port and other config
    sed -i "/^internal: 0.0.0.0 port = /d" $DANTE_CONF
    sed -i "/^# Internal network interface/a internal: 0.0.0.0 port = $DEFAULT_PORT" $DANTE_CONF
    
    # Restart service
    systemctl restart danted
    
    if systemctl is-active --quiet danted; then
        echo -e "${GREEN}✓ All custom ports removed!${NC}"
        echo -e "${CYAN}SOCKS5 is now listening only on port $DEFAULT_PORT${NC}"
    else
        echo -e "${RED}✗ Failed to restart Dante. Restoring backup...${NC}"
        cp ${DANTE_CONF}.backup.* $DANTE_CONF 2>/dev/null || true
        systemctl restart danted
        return 1
    fi
}

# Initialize database
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

# Add user
add_socks5_user() {
    local username=$1
    local password=$2
    local days=$3
    local traffic_gb=${4:-0}
    
    [[ -z "$username" || -z "$password" || -z "$days" ]] && {
        echo -e "${RED}Usage: add_socks5_user <username> <password> <days> [traffic_gb]${NC}"
        return 1
    }
    
    # Add system user
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}User $username exists, updating password...${NC}"
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
    echo -e "${GREEN}Connection Details:${NC}"
    echo "  Server: $SERVER_IP"
    echo "  Ports: $(get_current_ports)"
    echo "  Protocol: SOCKS5"
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
    echo -e "${CYAN}Example Usage:${NC}"
    local first_port=$(get_current_ports | cut -d',' -f1)
    echo "  curl --socks5 $username:$password@$SERVER_IP:$first_port http://ipinfo.io/ip"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Delete user
delete_socks5_user() {
    local username=$1
    [[ -z "$username" ]] && { echo -e "${RED}Usage: delete_socks5_user <username>${NC}"; return 1; }
    
    userdel "$username" 2>/dev/null || true
    sudo mysql $DB_NAME -e "UPDATE socks5_users SET status='disabled' WHERE username='$username';"
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List users
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

# Show user info
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
    echo "  Server: $SERVER_IP"
    echo "  Ports: $(get_current_ports)"
    echo "  Protocol: SOCKS5"
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
}

# Test SOCKS5
test_socks5() {
    echo -e "${CYAN}Testing SOCKS5 server...${NC}"
    echo ""
    
    if systemctl is-active --quiet danted; then
        echo -e "${GREEN}✓${NC} Dante SOCKS5 server is running"
    else
        echo -e "${RED}✗${NC} Dante SOCKS5 server is not running"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}Listening Ports:${NC}"
    ss -tulpn | grep danted | grep LISTEN || echo "  No ports found"
    
    echo ""
    echo -e "${YELLOW}Active Connections:${NC}"
    ss -tn | grep -E ":($(get_current_ports | tr ',' '|'))" | wc -l
}

# Check expired
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

# Show menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        SOCKS5 Proxy Management - VPS Manager Pro            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${MAGENTA}━━━ USER MANAGEMENT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} Add SOCKS5 User"
    echo -e "${GREEN}2.${NC} Delete User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo ""
    
    echo -e "${MAGENTA}━━━ PORT MANAGEMENT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}6.${NC} Add New Port"
    echo -e "${GREEN}7.${NC} Remove Port"
    echo -e "${GREEN}8.${NC} List All Ports"
    echo -e "${GREEN}9.${NC} ${RED}Remove All Custom Ports${NC}"
    echo ""
    
    echo -e "${MAGENTA}━━━ SYSTEM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}10.${NC} Test SOCKS5 Server"
    echo -e "${GREEN}11.${NC} Restart SOCKS5"
    echo -e "${GREEN}12.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    
    echo -e "${YELLOW}Server:${NC} $SERVER_IP"
    echo -e "${YELLOW}Ports:${NC} $(get_current_ports)"
    echo -e "${YELLOW}Status:${NC} $(systemctl is-active danted 2>/dev/null || echo 'stopped')"
    echo ""
}

# Main
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
                read -p "Enter new port (1024-65535): " port
                add_socks5_port "$port"
                read -p "Press enter..."
                ;;
            7)
                list_socks5_ports
                read -p "Enter port to remove: " port
                remove_socks5_port "$port"
                read -p "Press enter..."
                ;;
            8)
                list_socks5_ports
                read -p "Press enter..."
                ;;
            9)
                remove_all_ports
                read -p "Press enter..."
                ;;
            10)
                test_socks5
                read -p "Press enter..."
                ;;
            11)
                systemctl restart danted
                echo "✓ Restarted"
                read -p "Press enter..."
                ;;
            12)
                init_socks5_database
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
