#!/bin/bash
################################################################################
# MySQL Database Management Script
# Complete database management for VPS Manager Pro
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

DB_NAME="vps_manager"
DB_USER="root"
BACKUP_DIR="/opt/vps-manager/backups/database"
MAX_BACKUPS=7

# Initialize complete database
init_complete_database() {
    echo -e "${CYAN}Initializing complete database...${NC}"
    
    mysql -u root << 'EOF'
CREATE DATABASE IF NOT EXISTS vps_manager;
USE vps_manager;

-- SSH Users Table
CREATE TABLE IF NOT EXISTS ssh_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    connection_limit INT DEFAULT 2,
    last_login DATETIME,
    total_connections INT DEFAULT 0,
    INDEX(username),
    INDEX(status),
    INDEX(expiry_date)
);

-- Proxy Users Table
CREATE TABLE IF NOT EXISTS proxy_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    traffic_limit_gb INT DEFAULT 0,
    traffic_used_gb DECIMAL(10,2) DEFAULT 0,
    last_connection DATETIME,
    INDEX(username),
    INDEX(status)
);

-- V2Ray Users Table
CREATE TABLE IF NOT EXISTS v2ray_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    protocol ENUM('vless', 'vmess') DEFAULT 'vless',
    port INT DEFAULT 443,
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE NOT NULL,
    status ENUM('active', 'expired', 'disabled') DEFAULT 'active',
    traffic_limit_gb INT DEFAULT 0,
    traffic_used_gb DECIMAL(10,2) DEFAULT 0,
    last_connection DATETIME,
    INDEX(uuid),
    INDEX(status)
);

-- SSL Certificates Table
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

-- System Statistics Table
CREATE TABLE IF NOT EXISTS system_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_usage DECIMAL(5,2),
    memory_usage DECIMAL(5,2),
    disk_usage DECIMAL(5,2),
    network_in_mb DECIMAL(10,2),
    network_out_mb DECIMAL(10,2),
    active_connections INT,
    INDEX(timestamp)
);

-- Admin Logs Table
CREATE TABLE IF NOT EXISTS admin_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    admin_user VARCHAR(50),
    action VARCHAR(255),
    details TEXT,
    ip_address VARCHAR(45),
    INDEX(timestamp),
    INDEX(admin_user)
);

-- Settings Table
CREATE TABLE IF NOT EXISTS settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert default settings
INSERT IGNORE INTO settings (setting_key, setting_value) VALUES
('domain', 'v2ray.kurdcloud.xyz'),
('max_ssh_users', '100'),
('max_proxy_users', '100'),
('max_v2ray_users', '100'),
('backup_enabled', 'true'),
('backup_time', '02:00'),
('stats_retention_days', '30');

EOF

    echo -e "${GREEN}✓${NC} Complete database initialized"
}

# Create backup
create_backup() {
    echo -e "${CYAN}Creating database backup...${NC}"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Generate filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/vps_manager_$timestamp.sql"
    
    # Create backup
    mysqldump -u root "$DB_NAME" > "$backup_file"
    
    # Compress backup
    gzip "$backup_file"
    
    local backup_size=$(du -h "${backup_file}.gz" | cut -f1)
    
    echo -e "${GREEN}✓${NC} Backup created: ${backup_file}.gz ($backup_size)"
    
    # Cleanup old backups
    cleanup_old_backups
}

# Cleanup old backups
cleanup_old_backups() {
    local backup_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        echo -e "${YELLOW}Cleaning up old backups (keeping last $MAX_BACKUPS)...${NC}"
        ls -1t "$BACKUP_DIR"/*.sql.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
        echo -e "${GREEN}✓${NC} Old backups removed"
    fi
}

# Restore from backup
restore_backup() {
    echo -e "${CYAN}Available backups:${NC}"
    echo ""
    
    local backups=($(ls -1t "$BACKUP_DIR"/*.sql.gz 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}✗${NC} No backups found"
        return 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(basename "$backup" | sed 's/vps_manager_//;s/.sql.gz//')
        echo "$i. $date ($size)"
        ((i++))
    done
    
    echo ""
    read -p "Select backup number (0 to cancel): " selection
    
    if [[ $selection -eq 0 ]] || [[ $selection -gt ${#backups[@]} ]]; then
        echo "Cancelled"
        return
    fi
    
    local selected_backup="${backups[$((selection-1))]}"
    
    echo -e "${YELLOW}⚠ Warning: This will overwrite current database!${NC}"
    read -p "Continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled"
        return
    fi
    
    echo -e "${CYAN}Restoring from backup...${NC}"
    
    # Decompress and restore
    gunzip -c "$selected_backup" | mysql -u root "$DB_NAME"
    
    echo -e "${GREEN}✓${NC} Database restored successfully"
}

# Show database statistics
show_statistics() {
    echo -e "${CYAN}Database Statistics:${NC}"
    echo ""
    
    mysql -u root -D "$DB_NAME" << 'EOF'
SELECT 
    'SSH Users' as category,
    COUNT(*) as total,
    SUM(CASE WHEN status='active' THEN 1 ELSE 0 END) as active,
    SUM(CASE WHEN status='expired' THEN 1 ELSE 0 END) as expired
FROM ssh_users
UNION ALL
SELECT 
    'Proxy Users',
    COUNT(*),
    SUM(CASE WHEN status='active' THEN 1 ELSE 0 END),
    SUM(CASE WHEN status='expired' THEN 1 ELSE 0 END)
FROM proxy_users
UNION ALL
SELECT 
    'V2Ray Users',
    COUNT(*),
    SUM(CASE WHEN status='active' THEN 1 ELSE 0 END),
    SUM(CASE WHEN status='expired' THEN 1 ELSE 0 END)
FROM v2ray_users
UNION ALL
SELECT 
    'SSL Certificates',
    COUNT(*),
    SUM(CASE WHEN status='active' THEN 1 ELSE 0 END),
    SUM(CASE WHEN status='expired' THEN 1 ELSE 0 END)
FROM ssl_certificates;
EOF

    echo ""
    echo -e "${CYAN}Database Size:${NC}"
    mysql -u root -e "SELECT 
        table_schema AS 'Database',
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables 
    WHERE table_schema = '$DB_NAME'
    GROUP BY table_schema;"
}

# Optimize database
optimize_database() {
    echo -e "${CYAN}Optimizing database...${NC}"
    
    local tables=$(mysql -u root -D "$DB_NAME" -sN -e "SHOW TABLES;")
    
    while IFS= read -r table; do
        echo -n "  Optimizing $table... "
        mysql -u root -D "$DB_NAME" -e "OPTIMIZE TABLE $table;" > /dev/null 2>&1
        echo -e "${GREEN}✓${NC}"
    done <<< "$tables"
    
    echo -e "${GREEN}✓${NC} Database optimized"
}

# Export data
export_data() {
    local table=$1
    
    if [[ -z "$table" ]]; then
        echo -e "${RED}Usage: export_data <table>${NC}"
        return 1
    fi
    
    local export_file="/tmp/${table}_$(date +%Y%m%d_%H%M%S).csv"
    
    mysql -u root -D "$DB_NAME" -e "
        SELECT * FROM $table
        INTO OUTFILE '$export_file'
        FIELDS TERMINATED BY ','
        ENCLOSED BY '\"'
        LINES TERMINATED BY '\n';
    " 2>/dev/null || {
        # Fallback method
        mysql -u root -D "$DB_NAME" -e "SELECT * FROM $table;" > "$export_file"
    }
    
    echo -e "${GREEN}✓${NC} Data exported to: $export_file"
}

# Clean old data
clean_old_data() {
    local days=${1:-90}
    
    echo -e "${CYAN}Cleaning data older than $days days...${NC}"
    
    # Clean expired users
    mysql -u root -D "$DB_NAME" << EOF
DELETE FROM ssh_users WHERE status='expired' AND expiry_date < DATE_SUB(NOW(), INTERVAL $days DAY);
DELETE FROM proxy_users WHERE status='expired' AND expiry_date < DATE_SUB(NOW(), INTERVAL $days DAY);
DELETE FROM v2ray_users WHERE status='expired' AND expiry_date < DATE_SUB(NOW(), INTERVAL $days DAY);
DELETE FROM system_stats WHERE timestamp < DATE_SUB(NOW(), INTERVAL $days DAY);
DELETE FROM admin_logs WHERE timestamp < DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
    
    echo -e "${GREEN}✓${NC} Old data cleaned"
}

# Setup automatic backup
setup_auto_backup() {
    echo -e "${CYAN}Setting up automatic backup...${NC}"
    
    # Remove old cron jobs
    crontab -l 2>/dev/null | grep -v "database_manager.sh" | crontab -
    
    # Add new cron job (daily at 2 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/vps-manager/scripts/database_manager.sh backup >> /var/log/db-backup.log 2>&1") | crontab -
    
    echo -e "${GREEN}✓${NC} Auto-backup configured (daily at 2 AM)"
}

# Interactive query
interactive_query() {
    echo -e "${CYAN}Interactive SQL Query${NC}"
    echo "Enter SQL query (or 'exit' to quit):"
    echo ""
    
    while true; do
        read -p "SQL> " query
        
        if [[ "$query" == "exit" ]]; then
            break
        fi
        
        if [[ -z "$query" ]]; then
            continue
        fi
        
        mysql -u root -D "$DB_NAME" -t -e "$query" 2>&1
        echo ""
    done
}

# Menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Database Management - VPS Manager Pro                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${GREEN}1.${NC} Initialize Complete Database"
    echo -e "${GREEN}2.${NC} Create Backup"
    echo -e "${GREEN}3.${NC} Restore from Backup"
    echo -e "${GREEN}4.${NC} Show Statistics"
    echo -e "${GREEN}5.${NC} Optimize Database"
    echo -e "${GREEN}6.${NC} Export Table Data"
    echo -e "${GREEN}7.${NC} Clean Old Data"
    echo -e "${GREEN}8.${NC} Setup Auto Backup"
    echo -e "${GREEN}9.${NC} Interactive Query"
    echo -e "${GREEN}0.${NC} Exit"
    echo ""
}

# Main
main() {
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                init_complete_database
                read -p "Press enter to continue..."
                ;;
            2)
                create_backup
                read -p "Press enter to continue..."
                ;;
            3)
                restore_backup
                read -p "Press enter to continue..."
                ;;
            4)
                show_statistics
                read -p "Press enter to continue..."
                ;;
            5)
                optimize_database
                read -p "Press enter to continue..."
                ;;
            6)
                read -p "Table name: " table
                export_data "$table"
                read -p "Press enter to continue..."
                ;;
            7)
                read -p "Days to keep [90]: " days
                clean_old_data "${days:-90}"
                read -p "Press enter to continue..."
                ;;
            8)
                setup_auto_backup
                read -p "Press enter to continue..."
                ;;
            9)
                interactive_query
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

# Handle command line argument for cron
if [[ "$1" == "backup" ]]; then
    create_backup
    exit 0
fi

# If called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
