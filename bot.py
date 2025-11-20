#!/usr/bin/env python3
import os
import sys
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

sys.path.insert(0, '/opt/vps-manager/telegram-bot')
from handlers.media import MediaDownloader

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

BOT_TOKEN = "8442510366:AAGDQAW1Lp_25eTdIb1lCuj2jTNuviQDt5g"
media_downloader = MediaDownloader()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"🌐 Welcome {update.effective_user.first_name}!\n\n"
        "📥 Send links from:\n"
        "✅ TikTok\n"
        "✅ Instagram (with API - no limits!)\n"
        "✅ YouTube\n"
        "✅ Facebook\n\n"
        "Just send me a link!"
    )

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    
    if not ('http://' in text or 'https://' in text):
        await update.message.reply_text("Please send a valid link!")
        return
    
    if 'tiktok.com' in text or 'vm.tiktok.com' in text:
        await handle_tiktok(update, context, text)
    elif 'instagram.com' in text:
        await handle_instagram(update, context, text)
    elif 'youtube.com' in text or 'youtu.be' in text:
        await handle_youtube(update, context, text)
    elif 'facebook.com' in text or 'fb.com' in text:
        await handle_facebook(update, context, text)
    else:
        await update.message.reply_text("❌ Unsupported platform!")

async def handle_instagram(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    msg = await update.message.reply_text("📥 Downloading from Instagram...")
    
    try:
        result = await media_downloader.download_instagram(url)
        
        if result['success']:
            # Handle album/carousel
            if result.get('type') == 'album' and 'files' in result:
                await msg.edit_text(f"✅ Sending {len(result['files'])} items...")
                
                for item in result['files']:
                    if item['type'] == 'photo':
                        await update.message.reply_photo(photo=open(item['file'], 'rb'))
                    elif item['type'] == 'video':
                        await update.message.reply_video(video=open(item['file'], 'rb'))
                    os.remove(item['file'])
                
                await msg.delete()
            
            # Handle single media
            elif 'file' in result:
                await msg.edit_text("✅ Sending...")
                
                if result.get('type') == 'video':
                    await update.message.reply_video(
                        video=open(result['file'], 'rb'),
                        caption="🎥 Instagram"
                    )
                else:
                    await update.message.reply_photo(
                        photo=open(result['file'], 'rb'),
                        caption="📸 Instagram"
                    )
                
                os.remove(result['file'])
                await msg.delete()
        else:
            await msg.edit_text(f"❌ {result.get('error', 'Download failed')}")
    
    except Exception as e:
        logger.error(f"Instagram error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_tiktok(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    msg = await update.message.reply_text("📥 Downloading from TikTok...")
    
    try:
        result = await media_downloader.download_tiktok(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending...")
            await update.message.reply_video(video=open(result['file'], 'rb'), caption="🎵 TikTok")
            os.remove(result['file'])
            await msg.delete()
        else:
            await msg.edit_text(f"❌ {result.get('error')}")
    
    except Exception as e:
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_youtube(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    msg = await update.message.reply_text("📥 Downloading from YouTube...")
    
    try:
        result = await media_downloader.download_youtube(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending...")
            file_size = os.path.getsize(result['file'])
            
            if file_size < 50 * 1024 * 1024:
                await update.message.reply_video(video=open(result['file'], 'rb'), caption="🎬 YouTube")
            else:
                await update.message.reply_document(document=open(result['file'], 'rb'), caption="🎬 YouTube")
            
            os.remove(result['file'])
            await msg.delete()
        else:
            await msg.edit_text(f"❌ {result.get('error')}")
    
    except Exception as e:
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def handle_facebook(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    msg = await update.message.reply_text("📥 Downloading from Facebook...")
    
    try:
        result = await media_downloader.download_facebook(url)
        
        if result['success']:
            await msg.edit_text("✅ Sending...")
            await update.message.reply_video(video=open(result['file'], 'rb'), caption="📘 Facebook")
            os.remove(result['file'])
            await msg.delete()
        else:
            await msg.edit_text(f"❌ {result.get('error')}")
    
    except Exception as e:
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

def main():
    application = Application.builder().token(BOT_TOKEN).build()
    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    logger.info("Bot started with Instagram API!")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
