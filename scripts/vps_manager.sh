#!/bin/bash
################################################################################
# VPS Manager Pro - Master Control Script
# Central management for all VPS services
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_DIR="/opt/vps-manager/scripts"

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   ██╗   ██╗██████╗ ███████╗    ███╗   ███╗ ██████╗ ██████╗  ║
║   ██║   ██║██╔══██╗██╔════╝    ████╗ ████║██╔════╝ ██╔══██╗ ║
║   ██║   ██║██████╔╝███████╗    ██╔████╔██║██║  ███╗██████╔╝ ║
║   ╚██╗ ██╔╝██╔═══╝ ╚════██║    ██║╚██╔╝██║██║   ██║██╔══██╗ ║
║    ╚████╔╝ ██║     ███████║    ██║ ╚═╝ ██║╚██████╔╝██║  ██║ ║
║     ╚═══╝  ╚═╝     ╚══════╝    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ║
║                                                              ║
║                    VPS MANAGER PRO v3.0                      ║
║                   KurdCloud Team © 2025                      ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

show_main_menu() {
    echo -e "${WHITE}━━━ MANAGEMENT MODULES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} ${CYAN}👤 SSH User Management${NC}"
    echo -e "${GREEN}2.${NC} ${CYAN}🌐 Proxy User Management${NC}"
    echo -e "${GREEN}3.${NC} ${CYAN}🔒 V2Ray VPN Management${NC}"
    echo -e "${GREEN}4.${NC} ${CYAN}🔑 SSL Certificate Management${NC}"
    echo -e "${GREEN}5.${NC} ${CYAN}💾 Database Management${NC}"
    echo -e "${GREEN}6.${NC} ${CYAN}📊 Statistics Dashboard${NC}"
    echo ""
    echo -e "${WHITE}━━━ QUICK ACTIONS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}7.${NC} ${YELLOW}⚡ Quick Status${NC}"
    echo -e "${GREEN}8.${NC} ${YELLOW}🔄 Restart All Services${NC}"
    echo -e "${GREEN}9.${NC} ${YELLOW}📋 View System Logs${NC}"
    echo ""
    echo -e "${GREEN}0.${NC} ${RED}Exit${NC}"
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

main() {
    while true; do
        show_banner
        show_main_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                bash "$SCRIPT_DIR/ssh_manager.sh"
                ;;
            2)
                bash "$SCRIPT_DIR/proxy_manager.sh"
                ;;
            3)
                bash "$SCRIPT_DIR/v2ray_manager.sh"
                ;;
            4)
                bash "$SCRIPT_DIR/ssl_manager.sh"
                ;;
            5)
                bash "$SCRIPT_DIR/database_manager.sh"
                ;;
            6)
                bash "$SCRIPT_DIR/stats_dashboard.sh"
                ;;
            7)
                bash "$SCRIPT_DIR/stats_dashboard.sh" <<< "5"
                read -p "Press enter to continue..."
                ;;
            8)
                echo -e "${CYAN}Restarting all services...${NC}"
                systemctl restart vpsmanager-bot
                systemctl restart mysql
                systemctl restart nginx
                systemctl restart squid
                systemctl restart v2ray
                echo -e "${GREEN}✓${NC} All services restarted"
                read -p "Press enter to continue..."
                ;;
            9)
                echo "Select log:"
                echo "1. Bot logs"
                echo "2. Nginx logs"
                echo "3. System logs"
                read -p "Choice: " log_choice
                case $log_choice in
                    1) tail -f /opt/vps-manager/logs/bot.log ;;
                    2) tail -f /var/log/nginx/access.log ;;
                    3) tail -f /var/log/syslog ;;
                esac
                ;;
            0)
                echo -e "${GREEN}Thank you for using VPS Manager Pro!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 2
                ;;
        esac
    done
}

main
