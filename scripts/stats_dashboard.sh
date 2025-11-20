#!/bin/bash
################################################################################
# Real-time Statistics Dashboard
# Live monitoring for VPS Manager Pro
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

DB_NAME="vps_manager"

# Get system stats
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

get_memory_usage() {
    free | awk '/Mem:/ {printf "%.2f", $3/$2 * 100}'
}

get_memory_details() {
    free -h | awk '/Mem:/ {print $3 "/" $2}'
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1
}

get_disk_details() {
    df -h / | awk 'NR==2 {print $3 "/" $2}'
}

get_network_stats() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -n "$interface" ]]; then
        local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        
        # Convert to MB
        local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc)
        local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc)
        
        echo "$rx_mb $tx_mb"
    else
        echo "0 0"
    fi
}

get_uptime() {
    uptime -p | sed 's/up //'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | xargs
}

get_active_connections() {
    ss -s | grep TCP: | awk '{print $2}'
}

get_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}●${NC} Running"
    else
        echo -e "${RED}●${NC} Stopped"
    fi
}

# Get user statistics
get_user_stats() {
    local ssh_total=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM ssh_users;" 2>/dev/null || echo "0")
    local ssh_active=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM ssh_users WHERE status='active';" 2>/dev/null || echo "0")
    
    local proxy_total=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM proxy_users;" 2>/dev/null || echo "0")
    local proxy_active=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM proxy_users WHERE status='active';" 2>/dev/null || echo "0")
    
    local v2ray_total=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM v2ray_users;" 2>/dev/null || echo "0")
    local v2ray_active=$(sudo mysql -D "$DB_NAME" -sN -e "SELECT COUNT(*) FROM v2ray_users WHERE status='active';" 2>/dev/null || echo "0")
    
    echo "$ssh_total $ssh_active $proxy_total $proxy_active $v2ray_total $v2ray_active"
}

# Draw progress bar
draw_progress_bar() {
    local value=$1
    local max=100
    local width=30
    
    local filled=$(echo "scale=0; $value * $width / $max" | bc)
    local empty=$((width - filled))
    
    # Color based on value
    local color=$GREEN
    if (( $(echo "$value > 70" | bc -l) )); then
        color=$YELLOW
    fi
    if (( $(echo "$value > 90" | bc -l) )); then
        color=$RED
    fi
    
    printf "${color}"
    printf '█%.0s' $(seq 1 $filled)
    printf "${NC}"
    printf '░%.0s' $(seq 1 $empty)
    printf " %5.1f%%" $value
}

# Save stats to database
save_stats_to_db() {
    local cpu=$1
    local memory=$2
    local disk=$3
    local net_in=$4
    local net_out=$5
    local connections=$6
    
    sudo mysql -D "$DB_NAME" << EOF 2>/dev/null || true
INSERT INTO system_stats (cpu_usage, memory_usage, disk_usage, network_in_mb, network_out_mb, active_connections)
VALUES ($cpu, $memory, $disk, $net_in, $net_out, $connections);
EOF
}

# Main dashboard
show_dashboard() {
    while true; do
        clear
        
        # Header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                                                              ║${NC}"
        echo -e "${CYAN}║${WHITE}           VPS MANAGER PRO - LIVE DASHBOARD              ${CYAN}║${NC}"
        echo -e "${CYAN}║                                                              ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # System Info
        echo -e "${WHITE}━━━ SYSTEM INFORMATION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}Hostname:${NC} $(hostname)"
        echo -e "${CYAN}Server IP:${NC} $(hostname -I | awk '{print $1}')"
        echo -e "${CYAN}Domain:${NC} v2ray.kurdcloud.xyz"
        echo -e "${CYAN}Uptime:${NC} $(get_uptime)"
        echo -e "${CYAN}Load Average:${NC} $(get_load_average)"
        echo ""
        
        # Resource Usage
        echo -e "${WHITE}━━━ RESOURCE USAGE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local cpu=$(get_cpu_usage)
        local memory=$(get_memory_usage)
        local disk=$(get_disk_usage)
        local mem_details=$(get_memory_details)
        local disk_details=$(get_disk_details)
        
        echo -e "${CYAN}CPU Usage:${NC}    $(draw_progress_bar $cpu)"
        echo -e "${CYAN}Memory:${NC}       $(draw_progress_bar $memory) ($mem_details)"
        echo -e "${CYAN}Disk:${NC}         $(draw_progress_bar $disk) ($disk_details)"
        echo ""
        
        # Network Stats
        echo -e "${WHITE}━━━ NETWORK STATISTICS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local net_stats=($(get_network_stats))
        local connections=$(get_active_connections)
        
        echo -e "${CYAN}Network In:${NC}   ${GREEN}${net_stats[0]} MB${NC}"
        echo -e "${CYAN}Network Out:${NC}  ${YELLOW}${net_stats[1]} MB${NC}"
        echo -e "${CYAN}Connections:${NC}  ${BLUE}$connections${NC}"
        echo ""
        
        # Services Status
        echo -e "${WHITE}━━━ SERVICES STATUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        echo -e "${CYAN}Bot Service:${NC}  $(get_service_status vpsmanager-bot)"
        echo -e "${CYAN}MySQL:${NC}        $(get_service_status mysql)"
        echo -e "${CYAN}Nginx:${NC}        $(get_service_status nginx)"
        echo -e "${CYAN}Squid:${NC}        $(get_service_status squid)"
        echo -e "${CYAN}V2Ray:${NC}        $(get_service_status v2ray)"
        echo ""
        
        # User Statistics
        echo -e "${WHITE}━━━ USER STATISTICS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local user_stats=($(get_user_stats))
        
        printf "${CYAN}%-15s${NC} Total: ${WHITE}%3s${NC}  Active: ${GREEN}%3s${NC}\n" \
            "SSH Users:" "${user_stats[0]}" "${user_stats[1]}"
        printf "${CYAN}%-15s${NC} Total: ${WHITE}%3s${NC}  Active: ${GREEN}%3s${NC}\n" \
            "Proxy Users:" "${user_stats[2]}" "${user_stats[3]}"
        printf "${CYAN}%-15s${NC} Total: ${WHITE}%3s${NC}  Active: ${GREEN}%3s${NC}\n" \
            "V2Ray Users:" "${user_stats[4]}" "${user_stats[5]}"
        
        echo ""
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Press Ctrl+C to exit | Updates every 3 seconds${NC}"
        
        # Save to database
        save_stats_to_db "$cpu" "$memory" "$disk" "${net_stats[0]}" "${net_stats[1]}" "$connections"
        
        sleep 3
    done
}

# Show historical stats
show_historical_stats() {
    echo -e "${CYAN}Historical Statistics (Last 24 Hours)${NC}"
    echo ""
    
    sudo mysql -D "$DB_NAME" -t << 'EOF'
SELECT 
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i') as time,
    ROUND(cpu_usage, 1) as cpu,
    ROUND(memory_usage, 1) as memory,
    ROUND(disk_usage, 1) as disk,
    active_connections as connections
FROM system_stats
WHERE timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY timestamp DESC
LIMIT 20;
EOF
}

# Show peak usage
show_peak_usage() {
    echo -e "${CYAN}Peak Usage Statistics${NC}"
    echo ""
    
    sudo mysql -D "$DB_NAME" << 'EOF'
SELECT 
    'CPU Peak' as metric,
    CONCAT(ROUND(MAX(cpu_usage), 2), '%') as peak_value,
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i') as occurred_at
FROM system_stats
WHERE timestamp > DATE_SUB(NOW(), INTERVAL 7 DAY)
UNION ALL
SELECT 
    'Memory Peak',
    CONCAT(ROUND(MAX(memory_usage), 2), '%'),
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i')
FROM system_stats
WHERE timestamp > DATE_SUB(NOW(), INTERVAL 7 DAY)
UNION ALL
SELECT 
    'Disk Peak',
    CONCAT(ROUND(MAX(disk_usage), 2), '%'),
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i')
FROM system_stats
WHERE timestamp > DATE_SUB(NOW(), INTERVAL 7 DAY);
EOF
}

# Export stats
export_stats() {
    local days=${1:-7}
    local export_file="/tmp/stats_$(date +%Y%m%d_%H%M%S).csv"
    
    echo -e "${CYAN}Exporting last $days days of statistics...${NC}"
    
    sudo mysql -D "$DB_NAME" << EOF > "$export_file"
SELECT 
    timestamp,
    cpu_usage,
    memory_usage,
    disk_usage,
    network_in_mb,
    network_out_mb,
    active_connections
FROM system_stats
WHERE timestamp > DATE_SUB(NOW(), INTERVAL $days DAY)
ORDER BY timestamp DESC;
EOF
    
    echo -e "${GREEN}✓${NC} Stats exported to: $export_file"
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Statistics Dashboard - VPS Manager Pro             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Live Dashboard (Real-time)"
    echo -e "${GREEN}2.${NC} Historical Stats (24h)"
    echo -e "${GREEN}3.${NC} Peak Usage Report"
    echo -e "${GREEN}4.${NC} Export Statistics"
    echo -e "${GREEN}5.${NC} Quick Status"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
}

# Quick status
show_quick_status() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    QUICK STATUS                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    local cpu=$(get_cpu_usage)
    local memory=$(get_memory_usage)
    local disk=$(get_disk_usage)
    
    echo -e "${CYAN}CPU:${NC}    ${cpu}%"
    echo -e "${CYAN}Memory:${NC} ${memory}%"
    echo -e "${CYAN}Disk:${NC}   ${disk}%"
    echo ""
    
    echo -e "${CYAN}Services:${NC}"
    echo -e "  Bot:   $(get_service_status vpsmanager-bot)"
    echo -e "  MySQL: $(get_service_status mysql)"
    echo -e "  Nginx: $(get_service_status nginx)"
    echo -e "  Squid: $(get_service_status squid)"
    echo -e "  V2Ray: $(get_service_status v2ray)"
    echo ""
    
    local user_stats=($(get_user_stats))
    echo -e "${CYAN}Active Users:${NC}"
    echo -e "  SSH:   ${user_stats[1]}"
    echo -e "  Proxy: ${user_stats[3]}"
    echo -e "  V2Ray: ${user_stats[5]}"
}

# Main
main() {
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                show_dashboard
                ;;
            2)
                show_historical_stats
                read -p "Press enter to continue..."
                ;;
            3)
                show_peak_usage
                read -p "Press enter to continue..."
                ;;
            4)
                read -p "Export last N days [7]: " days
                export_stats "${days:-7}"
                read -p "Press enter to continue..."
                ;;
            5)
                show_quick_status
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
