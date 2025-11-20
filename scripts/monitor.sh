#!/bin/bash
# System Monitoring Script

echo "=== VPS Manager Pro - System Monitor ==="
echo ""

# Bot Status
echo "Bot Status:"
systemctl is-active vpsmanager-bot && echo "  ✓ Running" || echo "  ✗ Stopped"

# Services
echo ""
echo "Services:"
systemctl is-active nginx && echo "  ✓ Nginx" || echo "  ✗ Nginx"
systemctl is-active mysql && echo "  ✓ MySQL" || echo "  ✗ MySQL"
systemctl is-active squid && echo "  ✓ Squid" || echo "  ✗ Squid"
systemctl is-active v2ray && echo "  ✓ V2Ray" || echo "  ✗ V2Ray"

# Resources
echo ""
echo "Resources:"
echo "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "  Memory: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')"
echo "  Disk: $(df -h / | awk 'NR==2{print $5}')"

# Network
echo ""
echo "Network:"
echo "  Connections: $(ss -s | grep TCP: | awk '{print $2}')"
