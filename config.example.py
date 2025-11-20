"""
VPS Manager Pro - Example Configuration
Copy this file to config_local.py and update with your credentials
"""

import os

# Telegram Bot Configuration
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"  # Get from @BotFather
ADMIN_IDS = [123456789]  # Your Telegram user ID

# Instagram Configuration
INSTAGRAM_USERNAME = "your_instagram_username"
INSTAGRAM_PASSWORD = "your_instagram_password"
INSTAGRAM_SESSION_FILE = "/opt/vps-manager/telegram-bot/.instagram_session.json"

# Server Configuration
DOMAIN = "your-domain.com"

# Database Configuration
DB_HOST = "localhost"
DB_PORT = 3306
DB_NAME = "vps_manager"
DB_USER = "vps_admin"
DB_PASSWORD = "your_db_password"

# File Storage
DOWNLOAD_DIR = "/opt/vps-manager/telegram-bot/downloads"
LOG_DIR = "/opt/vps-manager/logs"

# Feature Flags
ENABLE_TIKTOK = True
ENABLE_INSTAGRAM = True
ENABLE_YOUTUBE = True
ENABLE_FACEBOOK = True

# Limits
MAX_VIDEO_SIZE = 50 * 1024 * 1024  # 50MB
MAX_PHOTO_SIZE = 10 * 1024 * 1024  # 10MB
DOWNLOAD_TIMEOUT = 300  # 5 minutes
