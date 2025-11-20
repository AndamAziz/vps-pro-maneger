#!/bin/bash
################################################################################
# SSH User Management Script
# Manages SSH users with expiration dates
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_USER="vps_admin"
DB_NAME="vps_manager"
DB_PASS=$(cat /root/.config/mysql_password 2>/dev/null || echo "")

# Database functions
init_ssh_database() {
    sudo mysql << EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS ssh_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    connection_limit INT DEFAULT 2,
    last_login DATETIME,
    INDEX(username),
    INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} SSH database initialized"
}

# Add SSH user
add_ssh_user() {
    local username=$1
    local password=$2
    local days=$3
    
    if [[ -z "$username" ]] || [[ -z "$password" ]] || [[ -z "$days" ]]; then
        echo -e "${RED}Usage: add_ssh_user <username> <password> <days>${NC}"
        return 1
    fi
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo -e "${RED}✗${NC} User $username already exists"
        return 1
    fi
    
    # Create user
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    
    # Set expiry date
    local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    chage -E $(date -d "+$days days" +%Y-%m-%d) "$username"
    
    # Add to database
    sudo mysql -D $DB_NAME << EOF
INSERT INTO ssh_users (username, password, expiry_date)
VALUES ('$username', '$password', '$expiry_date');
EOF
    
    echo -e "${GREEN}✓${NC} SSH user created:"
    echo "  Username: $username"
    echo "  Password: $password"
    echo "  Expires: $expiry_date"
    echo ""
    echo "  SSH Command: ssh $username@$(hostname -I | awk '{print $1}')"
}

# Delete SSH user
delete_ssh_user() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: delete_ssh_user <username>${NC}"
        return 1
    fi
    
    # Kill user processes
    pkill -u "$username" 2>/dev/null || true
    
    # Delete user
    userdel -r "$username" 2>/dev/null || true
    
    # Update database
    sudo mysql -D $DB_NAME << EOF
UPDATE ssh_users SET status='disabled' WHERE username='$username';
EOF
    
    echo -e "${GREEN}✓${NC} User $username deleted"
}

# List SSH users
list_ssh_users() {
    echo -e "${CYAN}SSH Users:${NC}"
    echo ""
    sudo mysql -D $DB_NAME -t << EOF
SELECT 
    username,
    DATE_FORMAT(created_date, '%Y-%m-%d') as created,
    DATE_FORMAT(expiry_date, '%Y-%m-%d') as expires,
    status,
    connection_limit as max_conn
FROM ssh_users
ORDER BY created_date DESC;
EOF
}

# Check expired users
check_expired_users() {
    echo -e "${CYAN}Checking for expired users...${NC}"
    
    # Get expired users
    local expired=$(sudo mysql -D $DB_NAME -sN << EOF
SELECT username FROM ssh_users 
WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    # Disable expired users
    while IFS= read -r username; do
        usermod -L "$username" 2>/dev/null || true
        sudo mysql -D $DB_NAME << EOF
UPDATE ssh_users SET status='expired' WHERE username='$username';
EOF
        echo -e "${YELLOW}✓${NC} Disabled expired user: $username"
    done <<< "$expired"
}

# Show user info
show_user_info() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: show_user_info <username>${NC}"
        return 1
    fi
    
    echo -e "${CYAN}User Information: $username${NC}"
    echo ""
    
    # From database
    sudo mysql -D $DB_NAME -t << EOF
SELECT * FROM ssh_users WHERE username='$username';
EOF
    
    # Current connections
    echo ""
    echo -e "${CYAN}Current Connections:${NC}"
    who | grep "$username" || echo "  No active connections"
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           SSH User Management - VPS Manager Pro             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add SSH User"
    echo -e "${GREEN}2.${NC} Delete SSH User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
}

# Main
main() {
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Username: " username
                read -p "Password: " password
                read -p "Days valid: " days
                add_ssh_user "$username" "$password" "$days"
                read -p "Press enter to continue..."
                ;;
            2)
                read -p "Username to delete: " username
                delete_ssh_user "$username"
                read -p "Press enter to continue..."
                ;;
            3)
                list_ssh_users
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
                init_ssh_database
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
