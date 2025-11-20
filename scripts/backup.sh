#!/bin/bash
# Automated Backup Script

BACKUP_DIR="/opt/vps-manager/backups"
DATE=$(date +%Y%m%d_%H%M%S)
DB_USER="vps_admin"
DB_NAME="vps_manager"

mkdir -p $BACKUP_DIR

# Backup database
mysqldump -u$DB_USER -p$DB_NAME > "$BACKUP_DIR/db_$DATE.sql"

# Backup configs
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" /opt/vps-manager/config/

# Backup bot
tar -czf "$BACKUP_DIR/bot_$DATE.tar.gz" /opt/vps-manager/telegram-bot/

# Delete old backups (keep last 7 days)
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "✓ Backup completed: $DATE"
