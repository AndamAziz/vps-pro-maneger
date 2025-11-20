#!/bin/bash
################################################################################
# SSL Certificate Management Script
# Auto Let's Encrypt SSL certificates
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="vps_manager"
DOMAIN="v2ray.kurdcloud.xyz"
EMAIL="admin@kurdcloud.xyz"

# Database initialization
init_ssl_database() {
    sudo mysql << EOF
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS ssl_certificates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    domain VARCHAR(255) UNIQUE NOT NULL,
    issued_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATETIME NOT NULL,
    status ENUM('active', 'expired', 'renewing') DEFAULT 'active',
    auto_renew BOOLEAN DEFAULT TRUE,
    last_check DATETIME,
    INDEX(domain),
    INDEX(status)
);
EOF
    echo -e "${GREEN}✓${NC} SSL database initialized"
}

# Install certbot
install_certbot() {
    echo -e "${CYAN}Installing certbot...${NC}"
    
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx
    
    echo -e "${GREEN}✓${NC} Certbot installed"
}

# Obtain SSL certificate
obtain_certificate() {
    local domain=$1
    local email=${2:-$EMAIL}
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}Usage: obtain_certificate <domain> [email]${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Obtaining SSL certificate for $domain...${NC}"
    
    # Stop nginx temporarily
    systemctl stop nginx 2>/dev/null || true
    
    # Obtain certificate
    certbot certonly --standalone \
        -d "$domain" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --preferred-challenges http
    
    if [[ $? -eq 0 ]]; then
        # Start nginx
        systemctl start nginx
        
        # Get expiry date
        local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" | cut -d= -f2)
        local expiry_date=$(date -d "$expiry" +"%Y-%m-%d %H:%M:%S")
        
        # Add to database
        sudo mysql -D $DB_NAME << EOF
INSERT INTO ssl_certificates (domain, expiry_date)
VALUES ('$domain', '$expiry_date')
ON DUPLICATE KEY UPDATE expiry_date='$expiry_date', status='active';
EOF
        
        echo -e "${GREEN}✓${NC} Certificate obtained for $domain"
        echo -e "   Expires: $expiry_date"
        
        # Setup auto-renewal cron
        setup_auto_renewal
        
        return 0
    else
        systemctl start nginx
        echo -e "${RED}✗${NC} Failed to obtain certificate"
        return 1
    fi
}

# Renew certificate
renew_certificate() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        echo -e "${CYAN}Renewing all certificates...${NC}"
        certbot renew --quiet
    else
        echo -e "${CYAN}Renewing certificate for $domain...${NC}"
        certbot renew --cert-name "$domain" --quiet
    fi
    
    if [[ $? -eq 0 ]]; then
        # Update database
        sudo mysql -D $DB_NAME << EOF
UPDATE ssl_certificates 
SET last_check=NOW(), status='active' 
WHERE domain='$domain' OR '$domain' = '';
EOF
        
        # Reload services
        systemctl reload nginx 2>/dev/null || true
        systemctl reload v2ray 2>/dev/null || true
        
        echo -e "${GREEN}✓${NC} Certificates renewed"
    else
        echo -e "${RED}✗${NC} Renewal failed"
    fi
}

# Setup auto-renewal
setup_auto_renewal() {
    echo -e "${CYAN}Setting up auto-renewal...${NC}"
    
    # Remove old cron jobs
    crontab -l 2>/dev/null | grep -v "certbot renew" | crontab -
    
    # Add new cron job (daily at 2 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx; systemctl reload v2ray' >> /var/log/letsencrypt/renew.log 2>&1") | crontab -
    
    echo -e "${GREEN}✓${NC} Auto-renewal configured (daily at 2 AM)"
}

# Check certificates
check_certificates() {
    echo -e "${CYAN}SSL Certificates Status:${NC}"
    echo ""
    
    # List from database
    sudo mysql -D $DB_NAME -t << EOF
SELECT 
    domain,
    DATE_FORMAT(issued_date, '%Y-%m-%d') as issued,
    DATE_FORMAT(expiry_date, '%Y-%m-%d %H:%i') as expires,
    DATEDIFF(expiry_date, NOW()) as days_left,
    status,
    auto_renew
FROM ssl_certificates
ORDER BY expiry_date;
EOF
    
    # Check expiring soon (< 30 days)
    local expiring=$(sudo mysql -D $DB_NAME -sN << EOF
SELECT COUNT(*) FROM ssl_certificates 
WHERE DATEDIFF(expiry_date, NOW()) < 30 AND status='active';
EOF
)
    
    if [[ $expiring -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}⚠ Warning: $expiring certificate(s) expiring soon${NC}"
    fi
}

# Revoke certificate
revoke_certificate() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}Usage: revoke_certificate <domain>${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Revoking certificate for $domain...${NC}"
    
    certbot revoke --cert-name "$domain" --delete-after-revoke
    
    # Update database
    sudo mysql -D $DB_NAME << EOF
UPDATE ssl_certificates SET status='expired' WHERE domain='$domain';
EOF
    
    echo -e "${GREEN}✓${NC} Certificate revoked"
}

# Show certificate info
show_certificate_info() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        domain=$DOMAIN
    fi
    
    echo -e "${CYAN}Certificate Information: $domain${NC}"
    echo ""
    
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ -f "$cert_path" ]]; then
        openssl x509 -in "$cert_path" -noout -text | grep -E "Subject:|Issuer:|Not Before|Not After"
        
        echo ""
        echo -e "${CYAN}Certificate Files:${NC}"
        echo "  Cert: /etc/letsencrypt/live/$domain/cert.pem"
        echo "  Key:  /etc/letsencrypt/live/$domain/privkey.pem"
        echo "  Chain: /etc/letsencrypt/live/$domain/chain.pem"
        echo "  Full: /etc/letsencrypt/live/$domain/fullchain.pem"
    else
        echo -e "${RED}✗${NC} Certificate not found"
    fi
}

# Configure Nginx for SSL
configure_nginx_ssl() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        domain=$DOMAIN
    fi
    
    echo -e "${CYAN}Configuring Nginx for $domain...${NC}"
    
    cat > /etc/nginx/sites-available/$domain << NGINXCONF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    location / {
        root /var/www/html;
        index index.html;
    }
    
    location /v2ray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

    # Enable site
    ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
    
    # Test and reload
    nginx -t && systemctl reload nginx
    
    echo -e "${GREEN}✓${NC} Nginx configured for HTTPS"
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        SSL Certificate Management - VPS Manager Pro         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Obtain Certificate"
    echo -e "${GREEN}2.${NC} Renew Certificate"
    echo -e "${GREEN}3.${NC} Check All Certificates"
    echo -e "${GREEN}4.${NC} Show Certificate Info"
    echo -e "${GREEN}5.${NC} Revoke Certificate"
    echo -e "${GREEN}6.${NC} Configure Nginx SSL"
    echo -e "${GREEN}7.${NC} Setup Auto-Renewal"
    echo -e "${GREEN}8.${NC} Initialize Database"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo ""
}

# Main
main() {
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}Certbot not installed. Install now? (y/n)${NC}"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_certbot
        fi
    fi
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Domain [$DOMAIN]: " domain
                domain=${domain:-$DOMAIN}
                read -p "Email [$EMAIL]: " email
                email=${email:-$EMAIL}
                obtain_certificate "$domain" "$email"
                read -p "Press enter to continue..."
                ;;
            2)
                read -p "Domain (empty for all): " domain
                renew_certificate "$domain"
                read -p "Press enter to continue..."
                ;;
            3)
                check_certificates
                read -p "Press enter to continue..."
                ;;
            4)
                read -p "Domain [$DOMAIN]: " domain
                show_certificate_info "${domain:-$DOMAIN}"
                read -p "Press enter to continue..."
                ;;
            5)
                read -p "Domain to revoke: " domain
                revoke_certificate "$domain"
                read -p "Press enter to continue..."
                ;;
            6)
                read -p "Domain [$DOMAIN]: " domain
                configure_nginx_ssl "${domain:-$DOMAIN}"
                read -p "Press enter to continue..."
                ;;
            7)
                setup_auto_renewal
                read -p "Press enter to continue..."
                ;;
            8)
                init_ssl_database
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
