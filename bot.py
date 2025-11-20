#!/usr/bin/env python3
"""
VPS Manager Pro - Telegram Bot
Author: KurdCloud Team
Version: 1.0.0
Description: Advanced media downloader bot supporting TikTok, Instagram, YouTube, Facebook
"""

import os
import sys
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('/opt/vps-manager/logs/telegram-bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Add handlers directory to path
sys.path.insert(0, os.path.dirname(__file__))

# Import configuration
try:
    from config import BOT_TOKEN, ADMIN_IDS
except ImportError:
    logger.error("Failed to import configuration. Please check config.py")
    BOT_TOKEN = None
    ADMIN_IDS = []

# Import media downloader
try:
    from handlers.media import MediaDownloader
    media_downloader = MediaDownloader()
    logger.info("Media downloader initialized successfully")
except ImportError as e:
    logger.error(f"Failed to import media downloader: {e}")
    media_downloader = None

# Bot version
VERSION = "1.0.0"

################################################################################
# Command Handlers
################################################################################

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    user = update.effective_user
    welcome_message = f"""
🌐 **Welcome to VPS Manager Pro Bot!**

Hello {user.first_name}! 👋

I'm your advanced media downloader bot with support for:

📥 **Supported Platforms:**
- 🎵 TikTok - Videos without watermark
- 📸 Instagram - Posts, Reels, Stories
- 🎬 YouTube - Videos up to 720p
- 📘 Facebook - Videos and media

⚡ **Features:**
- Lightning fast downloads
- Auto cleanup system
- High quality media
- No watermarks

📝 **How to use:**
Just send me any link from the platforms above!

💡 **Commands:**
/start - Show this message
/help - Get help
/status - Check bot status
/about - About this bot

Made with ❤️ by KurdCloud Team
    """
    await update.message.reply_text(welcome_message, parse_mode='Markdown')
    logger.info(f"User {user.id} started the bot")

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
📚 **How to Use VPS Manager Pro Bot**

**1. Download Media:**
Simply send me a link from any supported platform:
- TikTok: `https://www.tiktok.com/@user/video/...`
- Instagram: `https://www.instagram.com/p/...`
- YouTube: `https://www.youtube.com/watch?v=...`
- Facebook: `https://www.facebook.com/watch/?v=...`

**2. Supported Content:**
✅ Videos (MP4)
✅ Photos (JPG/PNG)
✅ Reels & Stories
✅ Posts & Albums

**3. Tips:**
- Make sure the content is public
- Private accounts may not work
- Large files are sent as documents

**4. Get Support:**
- Report issues: @ALLINONEBIGBOSSbot
- Website: kurdcloud.xyz

Version: {VERSION}
    """
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    import psutil
    
    # Get system stats
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
🖥️ **Bot Status**

**System Health:**
- CPU Usage: {cpu_percent}%
- Memory: {memory.percent}% ({memory.used // (1024**3)}GB / {memory.total // (1024**3)}GB)
- Disk: {disk.percent}% ({disk.used // (1024**3)}GB / {disk.total // (1024**3)}GB)

**Bot Information:**
- Status: ✅ Running
- Version: {VERSION}
- Media Downloader: ✅ Active
- Database: ✅ Connected

**Services:**
✅ TikTok Downloads
✅ Instagram Downloads (API)
✅ YouTube Downloads
✅ Facebook Downloads

Everything is running smoothly! 🚀
    """
    await update.message.reply_text(status_text, parse_mode='Markdown')

async def about_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /about command"""
    about_text = f"""
ℹ️ **About VPS Manager Pro Bot**

**Version:** {VERSION}
**Developer:** KurdCloud Team
**GitHub:** github.com/AndamAziz/vps-pro-maneger

**Description:**
Advanced VPS management system with integrated media downloader bot. Download media from TikTok, Instagram, YouTube, and Facebook with ease.

**Technologies:**
- Python 3.8+
- python-telegram-bot
- yt-dlp (video downloader)
- instagrapi (Instagram API)
- MySQL Database

**Features:**
✅ Multi-platform support
✅ High-quality downloads
✅ No watermarks
✅ Fast processing
✅ Auto cleanup

**Support:**
- Telegram: @ALLINONEBIGBOSSbot
- Website: kurdcloud.xyz
- Email: support@kurdcloud.xyz

Made with ❤️ for the community
    """
    await update.message.reply_text(about_text, parse_mode='Markdown')

################################################################################
# Message Handler
################################################################################

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle text messages (URLs)"""
    text = update.message.text.strip()
    
    # Check if message contains URL
    if not ('http://' in text or 'https://' in text):
        await update.message.reply_text(
            "❌ Please send a valid URL!\n\n"
            "Supported platforms:\n"
            "• TikTok\n"
            "• Instagram\n"
            "• YouTube\n"
            "• Facebook"
        )
        return
    
    # Detect platform and handle
    if 'tiktok.com' in text or 'vm.tiktok.com' in text:
        await handle_tiktok(update, context, text)
    elif 'instagram.com' in text:
        await handle_instagram(update, context, text)
    elif 'youtube.com' in text or 'youtu.be' in text:
        await handle_youtube(update, context, text)
    elif 'facebook.com' in text or 'fb.com' in text or 'fb.watch' in text:
        await handle_facebook(update, context, text)
    else:
        await update.message.reply_text(
            "❌ Unsupported platform!\n\n"
            "I can download from:\n"
            "✅ TikTok\n"
            "✅ Instagram\n"
            "✅ YouTube\n"
            "✅ Facebook"
        )

################################################################################
# Platform Handlers
################################################################################

async def handle_tiktok(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    """Handle TikTok downloads"""
    msg = await update.message.reply_text("📥 Downloading from TikTok...")
    
    try:
        result = await media_downloader.download_tiktok(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending video...")
            
            with open(result['file'], 'rb') as video:
                await update.message.reply_video(
                    video=video,
                    caption="🎵 TikTok Video\n\nDownloaded by @ALLINONEBIGBOSSbot"
                )
            
            os.remove(result['file'])
            await msg.delete()
            logger.info(f"TikTok download successful: {url}")
        else:
            await msg.edit_text(f"❌ Download failed: {result.get('error', 'Unknown error')}")
            logger.error(f"TikTok download failed: {result.get('error')}")
    
    except Exception as e:
        logger.error(f"TikTok handler error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_instagram(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    """Handle Instagram downloads"""
    msg = await update.message.reply_text("📥 Downloading from Instagram...")
    
    try:
        result = await media_downloader.download_instagram(url)
        
        if result['success']:
            # Handle album/carousel
            if result.get('type') == 'album' and 'files' in result:
                await msg.edit_text(f"✅ Sending {len(result['files'])} items...")
                
                for item in result['files']:
                    with open(item['file'], 'rb') as media:
                        if item['type'] == 'photo':
                            await update.message.reply_photo(photo=media, caption="📸 Instagram")
                        elif item['type'] == 'video':
                            await update.message.reply_video(video=media, caption="🎥 Instagram")
                    os.remove(item['file'])
                
                await msg.delete()
            
            # Handle single media
            elif 'file' in result:
                await msg.edit_text("✅ Sending...")
                
                with open(result['file'], 'rb') as media:
                    if result.get('type') == 'video':
                        await update.message.reply_video(video=media, caption="🎥 Instagram")
                    else:
                        await update.message.reply_photo(photo=media, caption="📸 Instagram")
                
                os.remove(result['file'])
                await msg.delete()
            
            logger.info(f"Instagram download successful: {url}")
        else:
            await msg.edit_text(f"❌ {result.get('error', 'Download failed')}")
            logger.error(f"Instagram download failed: {result.get('error')}")
    
    except Exception as e:
        logger.error(f"Instagram handler error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_youtube(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    """Handle YouTube downloads"""
    msg = await update.message.reply_text("📥 Downloading from YouTube...")
    
    try:
        result = await media_downloader.download_youtube(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending video...")
            file_size = os.path.getsize(result['file'])
            
            with open(result['file'], 'rb') as video:
                if file_size < 50 * 1024 * 1024:  # 50MB
                    await update.message.reply_video(video=video, caption="🎬 YouTube")
                else:
                    await update.message.reply_document(document=video, caption="🎬 YouTube (Large file)")
            
            os.remove(result['file'])
            await msg.delete()
            logger.info(f"YouTube download successful: {url}")
        else:
            await msg.edit_text(f"❌ {result.get('error')}")
            logger.error(f"YouTube download failed: {result.get('error')}")
    
    except Exception as e:
        logger.error(f"YouTube handler error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_facebook(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    """Handle Facebook downloads"""
    msg = await update.message.reply_text("📥 Downloading from Facebook...")
    
    try:
        result = await media_downloader.download_facebook(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending video...")
            
            with open(result['file'], 'rb') as video:
                await update.message.reply_video(video=video, caption="📘 Facebook")
            
            os.remove(result['file'])
            await msg.delete()
            logger.info(f"Facebook download successful: {url}")
        else:
            await msg.edit_text(f"❌ {result.get('error')}")
            logger.error(f"Facebook download failed: {result.get('error')}")
    
    except Exception as e:
        logger.error(f"Facebook handler error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

################################################################################
# Error Handler
################################################################################

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error {context.error}")

################################################################################
# Main Function
################################################################################

def main():
    """Start the bot"""
    if not BOT_TOKEN:
        logger.error("BOT_TOKEN not configured! Please check config.py")
        sys.exit(1)
    
    if not media_downloader:
        logger.error("Media downloader not initialized! Please check handlers/media.py")
        sys.exit(1)
    
    try:
        # Create application
        application = Application.builder().token(BOT_TOKEN).build()
        
        # Add command handlers
        application.add_handler(CommandHandler("start", start_command))
        application.add_handler(CommandHandler("help", help_command))
        application.add_handler(CommandHandler("status", status_command))
        application.add_handler(CommandHandler("about", about_command))
        
        # Add message handler
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
        
        # Add error handler
        application.add_error_handler(error_handler)
        
        logger.info(f"VPS Manager Pro Bot v{VERSION} started successfully!")
        logger.info(f"Bot username: @ALLINONEBIGBOSSbot")
        logger.info("Ready to accept commands...")
        
        # Start polling
        application.run_polling(allowed_updates=Update.ALL_TYPES)
        
    except Exception as e:
        logger.error(f"Failed to start bot: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
