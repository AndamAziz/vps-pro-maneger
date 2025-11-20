#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "BANNER"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   ██╗   ██╗██████╗ ███████╗    ███╗   ███╗ ██████╗ ██████╗  ║
║   ██║   ██║██╔══██╗██╔════╝    ████╗ ████║██╔════╝ ██╔══██╗ ║
║   ██║   ██║██████╔╝███████╗    ██╔████╔██║██║  ███╗██████╔╝ ║
║   ╚██╗ ██╔╝██╔═══╝ ╚════██║    ██║╚██╔╝██║██║   ██║██╔══██╗ ║
║    ╚████╔╝ ██║     ███████║    ██║ ╚═╝ ██║╚██████╔╝██║  ██║ ║
║     ╚═══╝  ╚═╝     ╚══════╝    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ║
║                                                              ║
║                    VPS MANAGER PRO v4.0                      ║
║                   KurdCloud Team © 2025                      ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}\n"
}

show_main_menu() {
    echo -e "${WHITE}━━━ VPN & PROXY SERVICES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} ${CYAN}👤 SSH User Management${NC}"
    echo -e "${GREEN}2.${NC} ${CYAN}🌐 Proxy User Management (Port 3128)${NC}"
    echo -e "${GREEN}3.${NC} ${CYAN}🔒 V2Ray VPN (VLESS/VMess/Trojan)${NC}"
    echo -e "${GREEN}4.${NC} ${CYAN}🔐 OpenVPN (UDP 1194 / TCP 1443)${NC}"
    echo ""
    echo -e "${WHITE}━━━ SYSTEM MANAGEMENT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}5.${NC} ${CYAN}🔑 SSL Certificate Management${NC}"
    echo -e "${GREEN}6.${NC} ${CYAN}💾 Database Management${NC}"
    echo -e "${GREEN}7.${NC} ${CYAN}📊 Statistics Dashboard${NC}"
    echo ""
    echo -e "${WHITE}━━━ QUICK ACTIONS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}8.${NC} ${YELLOW}⚡ Quick Status${NC}"
    echo -e "${GREEN}9.${NC} ${YELLOW}🔄 Restart All Services${NC}"
    echo ""
    echo -e "${GREEN}0.${NC} ${RED}Exit${NC}"
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

quick_status() {
    echo -e "${CYAN}System Status:${NC}"
    echo ""
    echo -e "${CYAN}Services:${NC}"
    systemctl is-active --quiet mysql && echo "  MySQL:    ✓ Running" || echo "  MySQL:    ✗ Stopped"
    systemctl is-active --quiet nginx && echo "  Nginx:    ✓ Running" || echo "  Nginx:    ✗ Stopped"
    systemctl is-active --quiet squid && echo "  Squid:    ✓ Running" || echo "  Squid:    ✗ Stopped"
    systemctl is-active --quiet v2ray && echo "  V2Ray:    ✓ Running" || echo "  V2Ray:    ✗ Stopped"
    systemctl is-active --quiet openvpn-server@server-udp && echo "  OpenVPN:  ✓ Running" || echo "  OpenVPN:  ✗ Stopped"
    echo ""
    echo -e "${CYAN}Resources:${NC}"
    echo "  CPU:      $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "  Memory:   $(free | awk '/Mem:/ {printf "%.1f%%", $3/$2 * 100}')"
    echo "  Disk:     $(df -h / | awk 'NR==2 {print $5}')"
}

restart_all() {
    echo -e "${CYAN}Restarting all services...${NC}"
    systemctl restart mysql 2>/dev/null && echo "✓ MySQL" || echo "✗ MySQL"
    systemctl restart nginx 2>/dev/null && echo "✓ Nginx" || echo "✗ Nginx"
    systemctl restart squid 2>/dev/null && echo "✓ Squid" || echo "✗ Squid"
    systemctl restart v2ray 2>/dev/null && echo "✓ V2Ray" || echo "✗ V2Ray"
    systemctl restart openvpn-server@server-udp 2>/dev/null && echo "✓ OpenVPN UDP" || echo "✗ OpenVPN UDP"
    systemctl restart openvpn-server@server-tcp 2>/dev/null && echo "✓ OpenVPN TCP" || echo "✗ OpenVPN TCP"
    echo -e "${GREEN}Done!${NC}"
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
                    echo -e "${RED}SSH manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            2)
                if [ -f "$SCRIPT_DIR/proxy_manager.sh" ]; then
                    bash "$SCRIPT_DIR/proxy_manager.sh"
                else
                    echo -e "${RED}Proxy manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            3)
                if [ -f "$SCRIPT_DIR/v2ray_manager.sh" ]; then
                    bash "$SCRIPT_DIR/v2ray_manager.sh"
                else
                    echo -e "${RED}V2Ray manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            4)
                if [ -f "$SCRIPT_DIR/openvpn_manager.sh" ]; then
                    bash "$SCRIPT_DIR/openvpn_manager.sh"
                else
                    echo -e "${RED}OpenVPN manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            5)
                if [ -f "$SCRIPT_DIR/ssl_manager.sh" ]; then
                    bash "$SCRIPT_DIR/ssl_manager.sh"
                else
                    echo -e "${RED}SSL manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            6)
                if [ -f "$SCRIPT_DIR/database_manager.sh" ]; then
                    bash "$SCRIPT_DIR/database_manager.sh"
                else
                    echo -e "${RED}Database manager not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            7)
                if [ -f "$SCRIPT_DIR/stats_dashboard.sh" ]; then
                    bash "$SCRIPT_DIR/stats_dashboard.sh"
                else
                    echo -e "${RED}Stats dashboard not found${NC}"
                    read -p "Press enter..."
                fi
                ;;
            8)
                quick_status
                read -p "Press enter..."
                ;;
            9)
                restart_all
                read -p "Press enter..."
                ;;
            0)
                echo -e "${GREEN}Thank you for using VPS Manager Pro!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

main
