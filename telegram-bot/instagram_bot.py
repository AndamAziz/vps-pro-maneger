import requests
import time
import logging
import re
import json
import os
import subprocess
from datetime import datetime
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CommandHandler

from config import TELEGRAM_TOKEN, SOCIAL_API_KEY, SOCIAL_API_HOST

logging.basicConfig(
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

ADMIN_USER_ID = 144068979

def save_stats(platform, success=True):
    try:
        try:
            with open('bot_stats.json', 'r') as f:
                stats = json.load(f)
        except:
            stats = {
                'total': 0,
                'instagram': 0,
                'facebook': 0,
                'tiktok': 0,
                'success': 0,
                'failed': 0,
                'started': datetime.now().isoformat()
            }
        
        stats['total'] = stats.get('total', 0) + 1
        stats[platform] = stats.get(platform, 0) + 1
        
        if success:
            stats['success'] = stats.get('success', 0) + 1
        else:
            stats['failed'] = stats.get('failed', 0) + 1
        
        stats['last_update'] = datetime.now().isoformat()
        
        with open('bot_stats.json', 'w') as f:
            json.dump(stats, f, indent=2)
        
        logger.info(f"📊 Total: {stats['total']}, IG: {stats['instagram']}, FB: {stats['facebook']}")
    except Exception as e:
        logger.error(f"Stats error: {e}")

def convert_to_mp3(video_path, user_id):
    """گۆڕینی ڤیدیۆ بۆ MP3"""
    try:
        audio_path = f"/tmp/audio_{user_id}_{int(time.time())}.mp3"
        
        subprocess.run([
            'ffmpeg', '-i', video_path,
            '-vn', '-acodec', 'libmp3lame',
            '-q:a', '2', audio_path, '-y'
        ], check=True, capture_output=True, timeout=60)
        
        logger.info("MP3 converted successfully!")
        return audio_path
    except Exception as e:
        logger.error(f"MP3 conversion error: {e}")
        return None

class SocialDownloader:
    def __init__(self):
        self.api_key = SOCIAL_API_KEY
        self.host = SOCIAL_API_HOST
        
    def download(self, url):
        try:
            logger.info("Social Download API...")
            
            headers = {
                'x-rapidapi-key': self.api_key,
                'x-rapidapi-host': self.host,
                'Content-Type': 'application/json'
            }
            
            data = {"url": url}
            
            response = requests.post(
                f"https://{self.host}/v1/social/autolink",
                headers=headers,
                json=data,
                timeout=30
            )
            
            logger.info(f"Social API Status: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                
                video_url = None
                
                if 'medias' in result and isinstance(result['medias'], list) and len(result['medias']) > 0:
                    video_url = result['medias'][0].get('url')
                elif 'url' in result:
                    video_url = result['url']
                elif 'download_url' in result:
                    video_url = result['download_url']
                
                if video_url:
                    logger.info("Social API success!")
                    return {
                        'success': True,
                        'source': 'social_api',
                        'data': {
                            'video_url': video_url,
                            'type': 'video'
                        }
                    }
                else:
                    return {'success': False, 'error': 'No video found'}
            else:
                return {'success': False, 'error': f'API Error: {response.status_code}'}
                
        except Exception as e:
            logger.error(f"Social API error: {e}")
            return {'success': False, 'error': str(e)}

social_downloader = SocialDownloader()

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    
    is_instagram = 'instagram.com' in text
    is_facebook = 'facebook.com' in text or 'fb.watch' in text or 'fb.com' in text
    is_tiktok = 'tiktok.com' in text
    
    if not (is_instagram or is_facebook or is_tiktok):
        return
    
    if is_instagram:
        platform = 'instagram'
    elif is_facebook:
        platform = 'facebook'
    else:
        platform = 'tiktok'
    
    user = update.message.from_user
    user_id = user.id
    logger.info(f"Request from {user.first_name}: {text[:50]}...")
    
    status = await update.message.reply_text("Please Wait...⏳❤️\n\nتکایە چاوەڕێ بکە، بە زووترین کات ڤیدیۆکەت داونلۆد دەکەم")
    
    try:
        result = social_downloader.download(text)
        
        if result['success']:
            video_url = result['data']['video_url']
            
            # ناردنی ڤیدیۆ
            await update.message.reply_video(video_url, caption="📹 Video")
            
            # داونلۆد و گۆڕین بۆ MP3
            await status.edit_text("⏳ گۆڕین بۆ MP3...")
            
            temp_video = f"/tmp/temp_video_{user_id}_{int(time.time())}.mp4"
            response = requests.get(video_url, timeout=60)
            with open(temp_video, 'wb') as f:
                f.write(response.content)
            
            audio_path = convert_to_mp3(temp_video, user_id)
            
            if audio_path:
                with open(audio_path, 'rb') as f:
                    await update.message.reply_audio(f, caption="🎵 Audio (MP3)")
                os.remove(audio_path)
            
            os.remove(temp_video)
            await status.delete()
            
            save_stats(platform, success=True)
            logger.info(f"Success - both formats sent")
        else:
            await status.edit_text("❌ نەتوانرا داونلۆد بکرێت\n\nتکایە دووبارە هەوڵ بدەوە")
            save_stats(platform, success=False)
            logger.error(f"Failed: {result.get('error')}")
            
    except Exception as e:
        try:
            await status.edit_text("❌ هەڵەیەک ڕوویدا\n\nتکایە دووبارە هەوڵ بدەوە")
        except:
            pass
        save_stats(platform, success=False)
        logger.error(f"Exception: {e}", exc_info=True)

async def stats_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.message.from_user.id
    
    if user_id != ADMIN_USER_ID:
        await update.message.reply_text("⛔️ تەنها خاوەنی بۆت دەتوانێت ئامارەکان ببینێت!")
        return
    
    try:
        with open('bot_stats.json', 'r') as f:
            stats = json.load(f)
        
        started = datetime.fromisoformat(stats.get('started', datetime.now().isoformat()))
        days = max((datetime.now() - started).days, 1)
        
        message = (
            f"📊 *ئاماری بۆت*\n\n"
            f"🔢 کۆی گشتی: *{stats.get('total', 0)}*\n"
            f"📸 Instagram: *{stats.get('instagram', 0)}*\n"
            f"📘 Facebook: *{stats.get('facebook', 0)}*\n"
            f"🎵 TikTok: *{stats.get('tiktok', 0)}*\n\n"
            f"✅ سەرکەوتوو: *{stats.get('success', 0)}*\n"
            f"❌ شکستخواردوو: *{stats.get('failed', 0)}*\n\n"
            f"📅 دەستپێکردن: {days} ڕۆژ لەمەوپێش\n"
            f"📈 ڕێژە: {stats.get('total', 0) / days:.1f} request/ڕۆژ"
        )
        
        await update.message.reply_text(message, parse_mode='Markdown')
    except FileNotFoundError:
        await update.message.reply_text("📊 هێشتا هیچ ئامارێک نییە!")
    except Exception as e:
        await update.message.reply_text(f"❌ هەڵە: {str(e)}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 *ALL IN ONE BIG BOSS Bot*\n\n"
        "لینک بنێرە لە:\n"
        "📸 Instagram (Posts/Reels)\n"
        "📘 Facebook (Videos)\n"
        "🎵 TikTok (Videos)\n\n"
        "بۆ ڤیدیۆ:\n"
        "• 📹 Video دەنێرێت\n"
        "• 🎵 Audio (MP3) دەنێرێت\n\n"
        "هەردووکیان پێکەوە! 🚀",
        parse_mode='Markdown'
    )

def main():
    app = Application.builder().token(TELEGRAM_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("stats", stats_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    logger.info("ALL IN ONE BIG BOSS Bot - Auto Video + MP3!")
    app.run_polling()

if __name__ == '__main__':
    main()
