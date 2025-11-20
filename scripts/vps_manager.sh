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

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
                if [ -f "$SCRIPT_DIR/ssh_manager.sh" ]; then
                    bash "$SCRIPT_DIR/ssh_manager.sh"
                else
                    echo -e "${RED}Error: ssh_manager.sh not found${NC}"
                    echo "Expected location: $SCRIPT_DIR/ssh_manager.sh"
                    read -p "Press enter to continue..."
                fi
                ;;
            2)
                if [ -f "$SCRIPT_DIR/proxy_manager.sh" ]; then
                    bash "$SCRIPT_DIR/proxy_manager.sh"
                else
                    echo -e "${RED}Error: proxy_manager.sh not found${NC}"
                    read -p "Press enter to continue..."
                fi
                ;;
            3)
                if [ -f "$SCRIPT_DIR/v2ray_manager.sh" ]; then
                    bash "$SCRIPT_DIR/v2ray_manager.sh"
                else
                    echo -e "${RED}Error: v2ray_manager.sh not found${NC}"
                    read -p "Press enter to continue..."
                fi
                ;;
            4)
                if [ -f "$SCRIPT_DIR/ssl_manager.sh" ]; then
                    bash "$SCRIPT_DIR/ssl_manager.sh"
                else
                    echo -e "${RED}Error: ssl_manager.sh not found${NC}"
                    read -p "Press enter to continue..."
                fi
                ;;
            5)
                if [ -f "$SCRIPT_DIR/database_manager.sh" ]; then
                    bash "$SCRIPT_DIR/database_manager.sh"
                else
                    echo -e "${RED}Error: database_manager.sh not found${NC}"
                    read -p "Press enter to continue..."
                fi
                ;;
            6)
                if [ -f "$SCRIPT_DIR/stats_dashboard.sh" ]; then
                    bash "$SCRIPT_DIR/stats_dashboard.sh"
                else
                    echo -e "${RED}Error: stats_dashboard.sh not found${NC}"
                    read -p "Press enter to continue..."
                fi
                ;;
            7)
                echo -e "${CYAN}Quick Status:${NC}"
                echo ""
                echo -e "${CYAN}System:${NC}"
                echo "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
                echo "  Memory: $(free | awk '/Mem:/ {printf "%.1f%%", $3/$2 * 100}')"
                echo "  Disk: $(df -h / | awk 'NR==2 {print $5}')"
                echo ""
                echo -e "${CYAN}Services:${NC}"
                systemctl is-active --quiet mysql && echo "  MySQL: ✓ Running" || echo "  MySQL: ✗ Stopped"
                systemctl is-active --quiet nginx && echo "  Nginx: ✓ Running" || echo "  Nginx: ✗ Stopped"
                systemctl is-active --quiet squid && echo "  Squid: ✓ Running" || echo "  Squid: ✗ Stopped"
                echo ""
                read -p "Press enter to continue..."
                ;;
            8)
                echo -e "${CYAN}Restarting all services...${NC}"
                systemctl restart mysql 2>/dev/null && echo "✓ MySQL restarted" || echo "✗ MySQL failed"
                systemctl restart nginx 2>/dev/null && echo "✓ Nginx restarted" || echo "✗ Nginx failed"
                systemctl restart squid 2>/dev/null && echo "✓ Squid restarted" || echo "✗ Squid failed"
                echo ""
                read -p "Press enter to continue..."
                ;;
            9)
                echo "Select log:"
                echo "1. System log"
                echo "2. Nginx access"
                echo "3. Nginx error"
                read -p "Choice: " log_choice
                case $log_choice in
                    1) tail -f /var/log/syslog 2>/dev/null || tail -f /var/log/messages ;;
                    2) tail -f /var/log/nginx/access.log 2>/dev/null || echo "Log not found" ;;
                    3) tail -f /var/log/nginx/error.log 2>/dev/null || echo "Log not found" ;;
                    *) echo "Invalid choice" ;;
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
