#!/bin/bash
# VPS Manager Pro - Admin Management Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_USER="vps_admin"
DB_NAME="vps_manager"

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          VPS Manager Pro - Admin Panel                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} List all users"
    echo -e "${GREEN}2.${NC} Add SSH user"
    echo -e "${GREEN}3.${NC} Add Proxy user"
    echo -e "${GREEN}4.${NC} Add V2Ray user"
    echo -e "${GREEN}5.${NC} Delete user"
    echo -e "${GREEN}6.${NC} Show statistics"
    echo -e "${GREEN}7.${NC} Backup database"
    echo -e "${GREEN}8.${NC} Bot status"
    echo -e "${GREEN}9.${NC} View logs"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
}

list_users() {
    echo -e "\n${CYAN}SSH Users:${NC}"
    mysql -u$DB_USER -p -D$DB_NAME -e "SELECT username, expiry_date, status FROM ssh_users;"
    
    echo -e "\n${CYAN}Proxy Users:${NC}"
    mysql -u$DB_USER -p -D$DB_NAME -e "SELECT username, port, expiry_date, status FROM proxy_users;"
    
    echo -e "\n${CYAN}V2Ray Users:${NC}"
    mysql -u$DB_USER -p -D$DB_NAME -e "SELECT username, protocol, port, expiry_date, status FROM v2ray_users;"
}

show_statistics() {
    echo -e "\n${CYAN}System Statistics:${NC}\n"
    
    ssh_count=$(mysql -u$DB_USER -p -D$DB_NAME -se "SELECT COUNT(*) FROM ssh_users WHERE status='active';")
    proxy_count=$(mysql -u$DB_USER -p -D$DB_NAME -se "SELECT COUNT(*) FROM proxy_users WHERE status='active';")
    v2ray_count=$(mysql -u$DB_USER -p -D$DB_NAME -se "SELECT COUNT(*) FROM v2ray_users WHERE status='active';")
    
    echo -e "Active SSH Users:   ${GREEN}$ssh_count${NC}"
    echo -e "Active Proxy Users: ${GREEN}$proxy_count${NC}"
    echo -e "Active V2Ray Users: ${GREEN}$v2ray_count${NC}"
    
    echo -e "\n${CYAN}Server Resources:${NC}\n"
    echo -e "CPU Usage:    $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo -e "Memory Usage: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')"
    echo -e "Disk Usage:   $(df -h / | awk 'NR==2{print $5}')"
}

backup_database() {
    BACKUP_DIR="/opt/vps-manager/backups"
    mkdir -p $BACKUP_DIR
    BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    echo -e "\n${CYAN}Creating backup...${NC}"
    mysqldump -u$DB_USER -p $DB_NAME > $BACKUP_FILE
    echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"
}

while true; do
    show_menu
    read -p "Select option: " choice
    
    case $choice in
        1) list_users; read -p "Press enter to continue..." ;;
        2) echo "Add SSH user feature coming soon..."; read -p "Press enter to continue..." ;;
        3) echo "Add Proxy user feature coming soon..."; read -p "Press enter to continue..." ;;
        4) echo "Add V2Ray user feature coming soon..."; read -p "Press enter to continue..." ;;
        5) echo "Delete user feature coming soon..."; read -p "Press enter to continue..." ;;
        6) show_statistics; read -p "Press enter to continue..." ;;
        7) backup_database; read -p "Press enter to continue..." ;;
        8) vpsbot status; read -p "Press enter to continue..." ;;
        9) tail -50 /opt/vps-manager/logs/telegram-bot.log; read -p "Press enter to continue..." ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option"; sleep 2 ;;
    esac
done
