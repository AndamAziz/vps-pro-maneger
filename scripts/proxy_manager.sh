#!/bin/bash
################################################################################
# Squid Proxy User Management Script
# Manages proxy users with authentication
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
SQUID_CONF="/etc/squid/squid.conf"
SQUID_PASSWD="/etc/squid/passwd"

# Database initialization
init_proxy_database() {
    mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf << EOF
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS proxy_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    traffic_limit_gb INT DEFAULT 0,
    traffic_used_gb DECIMAL(10,2) DEFAULT 0,
    INDEX(username),
    INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} Proxy database initialized"
}

# Configure Squid
configure_squid() {
    echo -e "${CYAN}Configuring Squid Proxy...${NC}"
    
    # Backup original config
    cp $SQUID_CONF ${SQUID_CONF}.backup 2>/dev/null || true
    
    # Create new configuration
    cat > $SQUID_CONF << 'SQUIDCONF'
# Squid Proxy Configuration - VPS Manager Pro
# Port Configuration
http_port 3128

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm VPS Proxy Server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive on

# ACL Definitions
acl SSL_ports port 443
acl Safe_ports port 80          # HTTP
acl Safe_ports port 443         # HTTPS
acl Safe_ports port 1025-65535  # Unregistered ports
acl CONNECT method CONNECT
acl authenticated proxy_auth REQUIRED

# Access Rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow authenticated
http_access deny all

# Cache Configuration
cache deny all
cache_mem 256 MB
maximum_object_size 4096 KB

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
logfile_rotate 10

# Network Options
forwarded_for on
via on

# Performance
dns_nameservers 8.8.8.8 8.8.4.4
SQUIDCONF

    # Create password file if not exists
    touch $SQUID_PASSWD
    chmod 640 $SQUID_PASSWD
    chown proxy:proxy $SQUID_PASSWD
    
    # Test configuration
    squid -k parse && echo -e "${GREEN}✓${NC} Squid configuration valid" || {
        echo -e "${RED}✗${NC} Invalid Squid configuration"
        return 1
    }
    
    # Restart Squid
    systemctl restart squid
    systemctl enable squid
    
    echo -e "${GREEN}✓${NC} Squid configured and running on port 3128"
}

# Add proxy user
add_proxy_user() {
    local username=$1
    local password=$2
    local days=$3
    local traffic_gb=${4:-0}
    
    if [[ -z "$username" ]] || [[ -z "$password" ]] || [[ -z "$days" ]]; then
        echo -e "${RED}Usage: add_proxy_user <username> <password> <days> [traffic_gb]${NC}"
        return 1
    fi
    
    # Check if user exists
    if grep -q "^${username}:" $SQUID_PASSWD 2>/dev/null; then
        echo -e "${RED}✗${NC} User $username already exists"
        return 1
    fi
    
    # Add to Squid password file
    htpasswd -b $SQUID_PASSWD "$username" "$password"
    
    # Calculate expiry date
    local expiry_date=$(date -d "+$days days" +%Y-%m-%d)
    
    # Add to database
    mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME << EOF
INSERT INTO proxy_users (username, password, expiry_date, traffic_limit_gb)
VALUES ('$username', '$password', '$expiry_date', $traffic_gb);
EOF
    
    # Get server IP
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}✓${NC} Proxy user created:"
    echo ""
    echo "  Username: $username"
    echo "  Password: $password"
    echo "  Expires: $expiry_date"
    echo "  Traffic Limit: ${traffic_gb}GB"
    echo ""
    echo "  Proxy Configuration:"
    echo "  Host: $server_ip"
    echo "  Port: 3128"
    echo "  Type: HTTP/HTTPS"
    echo ""
    echo "  Browser Setup:"
    echo "  HTTP Proxy: $server_ip:3128"
    echo "  HTTPS Proxy: $server_ip:3128"
    echo "  Username: $username"
    echo "  Password: $password"
}

# Delete proxy user
delete_proxy_user() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: delete_proxy_user <username>${NC}"
        return 1
    fi
    
    # Remove from Squid password file
    htpasswd -D $SQUID_PASSWD "$username" 2>/dev/null || true
    
    # Update database
    mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME << EOF
UPDATE proxy_users SET status='disabled' WHERE username='$username';
EOF
    
    echo -e "${GREEN}✓${NC} Proxy user $username deleted"
}

# List proxy users
list_proxy_users() {
    echo -e "${CYAN}Proxy Users:${NC}"
    echo ""
    mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME -t << EOF
SELECT 
    username,
    DATE_FORMAT(created_date, '%Y-%m-%d') as created,
    DATE_FORMAT(expiry_date, '%Y-%m-%d') as expires,
    traffic_limit_gb as limit_gb,
    traffic_used_gb as used_gb,
    status
FROM proxy_users
ORDER BY created_date DESC;
EOF
}

# Check expired users
check_expired_users() {
    echo -e "${CYAN}Checking for expired proxy users...${NC}"
    
    # Get expired users
    local expired=$(mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME -sN << EOF
SELECT username FROM proxy_users 
WHERE expiry_date < CURDATE() AND status='active';
EOF
)
    
    if [[ -z "$expired" ]]; then
        echo -e "${GREEN}✓${NC} No expired users"
        return
    fi
    
    # Disable expired users
    while IFS= read -r username; do
        htpasswd -D $SQUID_PASSWD "$username" 2>/dev/null || true
        mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME << EOF
UPDATE proxy_users SET status='expired' WHERE username='$username';
EOF
        echo -e "${YELLOW}✓${NC} Disabled expired user: $username"
    done <<< "$expired"
    
    # Restart Squid to apply changes
    systemctl reload squid
}

# Show user info
show_user_info() {
    local username=$1
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Usage: show_user_info <username>${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Proxy User Information: $username${NC}"
    echo ""
    
    # From database
    mysql --defaults-extra-file=~/github-upload/scripts/.my.cnf -D $DB_NAME -t << EOF
SELECT * FROM proxy_users WHERE username='$username';
EOF
    
    # Check if active in Squid
    echo ""
    if grep -q "^${username}:" $SQUID_PASSWD 2>/dev/null; then
        echo -e "${GREEN}✓${NC} User is active in Squid"
    else
        echo -e "${RED}✗${NC} User not found in Squid"
    fi
}

# Test proxy
test_proxy() {
    local username=$1
    local password=$2
    
    if [[ -z "$username" ]] || [[ -z "$password" ]]; then
        echo -e "${RED}Usage: test_proxy <username> <password>${NC}"
        return 1
    fi
    
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "${CYAN}Testing proxy connection...${NC}"
    
    # Test HTTP connection
    if curl -x "http://${username}:${password}@${server_ip}:3128" \
         -s -o /dev/null -w "%{http_code}" \
         "http://www.google.com" | grep -q "200"; then
        echo -e "${GREEN}✓${NC} Proxy is working!"
    else
        echo -e "${RED}✗${NC} Proxy test failed"
    fi
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Squid Proxy Management - VPS Manager Pro             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Add Proxy User"
    echo -e "${GREEN}2.${NC} Delete Proxy User"
    echo -e "${GREEN}3.${NC} List All Users"
    echo -e "${GREEN}4.${NC} Show User Info"
    echo -e "${GREEN}5.${NC} Check Expired Users"
    echo -e "${GREEN}6.${NC} Test Proxy"
    echo -e "${GREEN}7.${NC} Configure Squid"
    echo -e "${GREEN}8.${NC} Initialize Database"
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
                read -p "Traffic limit (GB, 0=unlimited): " traffic
                add_proxy_user "$username" "$password" "$days" "$traffic"
                read -p "Press enter to continue..."
                ;;
            2)
                read -p "Username to delete: " username
                delete_proxy_user "$username"
                read -p "Press enter to continue..."
                ;;
            3)
                list_proxy_users
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
                read -p "Username: " username
                read -p "Password: " password
                test_proxy "$username" "$password"
                read -p "Press enter to continue..."
                ;;
            7)
                configure_squid
                read -p "Press enter to continue..."
                ;;
            8)
                init_proxy_database
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
