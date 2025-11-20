"""
VPS Manager Pro - Configuration File
Author: KurdCloud Team
Version: 1.0.0
"""

import os

################################################################################
# Telegram Bot Configuration
################################################################################

# Bot token from @BotFather
BOT_TOKEN = "8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g"

# Admin user IDs (list of integers)
ADMIN_IDS = [144068979]

################################################################################
# Instagram Configuration
################################################################################

# Instagram credentials for API access
INSTAGRAM_USERNAME = "allinonebigboss"
INSTAGRAM_PASSWORD = "HelinGyan1122@@##"
INSTAGRAM_SESSION_FILE = "/opt/vps-manager/telegram-bot/.instagram_session.json"

################################################################################
# Server Configuration
################################################################################

# Domain name
DOMAIN = "v2ray.kurdcloud.xyz"

################################################################################
# Database Configuration
################################################################################

DB_HOST = "localhost"
DB_PORT = 3306
DB_NAME = "vps_manager"
DB_USER = "vps_admin"
DB_PASSWORD = ""  # Will be set during installation

################################################################################
# File Storage Configuration
################################################################################

# Download directory
DOWNLOAD_DIR = "/opt/vps-manager/telegram-bot/downloads"

# Create download directory if it doesn't exist
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)

################################################################################
# Logging Configuration
################################################################################

LOG_DIR = "/opt/vps-manager/logs"
LOG_FILE = os.path.join(LOG_DIR, "telegram-bot.log")

# Create log directory if it doesn't exist
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR, exist_ok=True)

################################################################################
# Feature Flags
################################################################################

# Enable/disable features
ENABLE_TIKTOK = True
ENABLE_INSTAGRAM = True
ENABLE_YOUTUBE = True
ENABLE_FACEBOOK = True

# File size limits (in bytes)
MAX_VIDEO_SIZE = 50 * 1024 * 1024  # 50MB
MAX_PHOTO_SIZE = 10 * 1024 * 1024  # 10MB

# Download timeout (in seconds)
DOWNLOAD_TIMEOUT = 300  # 5 minutes

################################################################################
# Bot Information
################################################################################

BOT_VERSION = "1.0.0"
BOT_NAME = "VPS Manager Pro Bot"
BOT_USERNAME = "@ALLINONEBIGBOSSbot"
DEVELOPER = "KurdCloud Team"
WEBSITE = "https://kurdcloud.xyz"
GITHUB = "https://github.com/AndamAziz/vps-pro-maneger"
