#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║${WHITE}        VPS MANAGER PRO - MENU STRUCTURE                 ${CYAN}║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${WHITE}🎛️  MASTER CONTROL:${NC} vps_manager.sh"
echo -e "${GREEN}   1.${NC} SSH User Management"
echo -e "${GREEN}   2.${NC} Proxy User Management"
echo -e "${GREEN}   3.${NC} V2Ray VPN Management"
echo -e "${GREEN}   4.${NC} SSL Certificate Management"
echo -e "${GREEN}   5.${NC} Database Management"
echo -e "${GREEN}   6.${NC} Statistics Dashboard"
echo -e "${GREEN}   7.${NC} Quick Status"
echo -e "${GREEN}   8.${NC} Restart All Services"
echo -e "${GREEN}   9.${NC} View System Logs"
echo ""

echo -e "${WHITE}👤 SSH MANAGEMENT:${NC} ssh_manager.sh"
echo -e "${CYAN}   • Add/Delete Users"
echo -e "   • Expiration Dates"
echo -e "   • Connection Limits"
echo -e "   • Auto-Expire Check${NC}"
echo ""

echo -e "${WHITE}🌐 PROXY MANAGEMENT:${NC} proxy_manager.sh"
echo -e "${CYAN}   • Port 3128"
echo -e "   • Authentication"
echo -e "   • Traffic Limits"
echo -e "   • Test Connectivity${NC}"
echo ""

echo -e "${WHITE}🔒 V2RAY VPN:${NC} v2ray_manager.sh"
echo -e "${CYAN}   • VLESS/VMess Protocols"
echo -e "   • QR Code Generation"
echo -e "   • WebSocket Support"
echo -e "   • Domain: v2ray.kurdcloud.xyz${NC}"
echo ""

echo -e "${WHITE}🔑 SSL CERTIFICATES:${NC} ssl_manager.sh"
echo -e "${CYAN}   • Let's Encrypt Auto"
echo -e "   • Auto-Renewal"
echo -e "   • Nginx Configuration"
echo -e "   • Expiry Monitoring${NC}"
echo ""

echo -e "${WHITE}💾 DATABASE:${NC} database_manager.sh"
echo -e "${CYAN}   • Backup/Restore"
echo -e "   • Optimize Tables"
echo -e "   • Export Data"
echo -e "   • SQL Query Interface${NC}"
echo ""

echo -e "${WHITE}📊 STATISTICS:${NC} stats_dashboard.sh"
echo -e "${CYAN}   • Real-time Monitoring"
echo -e "   • CPU/RAM/Disk Usage"
echo -e "   • Network Statistics"
echo -e "   • Service Status${NC}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Total Scripts: 7 | Total Lines: 2,467+${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
