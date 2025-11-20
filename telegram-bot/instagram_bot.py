#!/usr/bin/env python3
"""
ALL IN ONE BIG BOSS Bot
Instagram, Facebook, TikTok Downloader
Sends both Video + MP3 Audio
"""

import requests
import time
import logging
import json
import os
import subprocess
from datetime import datetime
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CommandHandler

from config import TELEGRAM_TOKEN, SOCIAL_API_KEY, SOCIAL_API_HOST

# Logging setup
logging.basicConfig(
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Admin user ID (change this to your Telegram ID)
ADMIN_USER_ID = 144068979

def save_stats(platform, success=True):
    """Save download statistics"""
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
        
        logger.info(f"📊 Stats: Total={stats['total']}, IG={stats['instagram']}, FB={stats['facebook']}, TT={stats['tiktok']}")
    except Exception as e:
        logger.error(f"Stats save error: {e}")

def convert_to_mp3(video_path, user_id):
    """Convert video to MP3 audio"""
    try:
        audio_path = f"/tmp/audio_{user_id}_{int(time.time())}.mp3"
        
        # Use ffmpeg to extract audio
        result = subprocess.run([
            'ffmpeg', '-i', video_path,
            '-vn',  # No video
            '-acodec', 'libmp3lame',
            '-q:a', '2',  # Quality
            audio_path, '-y'
        ], check=True, capture_output=True, timeout=60)
        
        if os.path.exists(audio_path) and os.path.getsize(audio_path) > 0:
            logger.info(f"✅ MP3 converted: {os.path.getsize(audio_path)} bytes")
            return audio_path
        else:
            logger.error("MP3 file not created or empty")
            return None
            
    except subprocess.TimeoutExpired:
        logger.error("FFmpeg timeout")
        return None
    except Exception as e:
        logger.error(f"MP3 conversion error: {e}")
        return None

class SocialDownloader:
    """Social media downloader using RapidAPI"""
    
    def __init__(self):
        self.api_key = SOCIAL_API_KEY
        self.host = SOCIAL_API_HOST
        
    def download(self, url):
        """Download video from social media URL"""
        try:
            logger.info(f"📥 Downloading from: {url[:50]}...")
            
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
            
            logger.info(f"API Response: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                
                # Extract video URL from response
                video_url = None
                
                if 'medias' in result and isinstance(result['medias'], list) and len(result['medias']) > 0:
                    video_url = result['medias'][0].get('url')
                elif 'url' in result:
                    video_url = result['url']
                elif 'download_url' in result:
                    video_url = result['download_url']
                
                if video_url:
                    logger.info("✅ Video URL found!")
                    return {
                        'success': True,
                        'source': 'social_api',
                        'data': {
                            'video_url': video_url,
                            'type': 'video'
                        }
                    }
                else:
                    logger.error("No video URL in response")
                    return {'success': False, 'error': 'No video found in response'}
            else:
                error_msg = f'API Error: {response.status_code}'
                logger.error(error_msg)
                return {'success': False, 'error': error_msg}
                
        except Exception as e:
            logger.error(f"Download error: {e}")
            return {'success': False, 'error': str(e)}

# Initialize downloader
social_downloader = SocialDownloader()

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages with social media links"""
    text = update.message.text
    
    # Check if message contains social media link
    is_instagram = 'instagram.com' in text or 'instagr.am' in text
    is_facebook = 'facebook.com' in text or 'fb.watch' in text or 'fb.com' in text
    is_tiktok = 'tiktok.com' in text or 'vm.tiktok.com' in text
    
    if not (is_instagram or is_facebook or is_tiktok):
        return
    
    # Determine platform
    if is_instagram:
        platform = 'instagram'
    elif is_facebook:
        platform = 'facebook'
    else:
        platform = 'tiktok'
    
    user = update.message.from_user
    user_id = user.id
    logger.info(f"📨 Request from @{user.username or user.first_name} ({user_id}): {platform}")
    
    # Send waiting message
    status = await update.message.reply_text(
        "⏳ *Please Wait...*\n\n"
        "تکایە چاوەڕێ بکە، بە زووترین کات ڤیدیۆکەت داونلۆد دەکەم...\n\n"
        "🎬 ڤیدیۆ + 🎵 MP3 دەنێردرێت",
        parse_mode='Markdown'
    )
    
    try:
        # Download video
        result = social_downloader.download(text)
        
        if result['success']:
            video_url = result['data']['video_url']
            logger.info(f"📹 Sending video...")
            
            # Send video first
            try:
                await update.message.reply_video(
                    video_url, 
                    caption="📹 *Video Downloaded*\n\nبە سەرکەوتوویی داونلۆد کرا ✅",
                    parse_mode='Markdown'
                )
                logger.info("✅ Video sent")
            except Exception as e:
                logger.error(f"Video send error: {e}")
                await status.edit_text(f"❌ نەتوانرا ڤیدیۆ بنێردرێت\n\nError: {str(e)}")
                save_stats(platform, success=False)
                return
            
            # Update status for MP3 conversion
            await status.edit_text("🎵 گۆڕین بۆ MP3...\n\nConverting to audio...")
            
            # Download video file temporarily
            temp_video = f"/tmp/temp_video_{user_id}_{int(time.time())}.mp4"
            try:
                logger.info("📥 Downloading video file for conversion...")
                response = requests.get(video_url, timeout=60, stream=True)
                response.raise_for_status()
                
                with open(temp_video, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                logger.info(f"✅ Video downloaded: {os.path.getsize(temp_video)} bytes")
                
                # Convert to MP3
                audio_path = convert_to_mp3(temp_video, user_id)
                
                if audio_path and os.path.exists(audio_path):
                    logger.info("🎵 Sending MP3...")
                    with open(audio_path, 'rb') as f:
                        await update.message.reply_audio(
                            f, 
                            caption="🎵 *Audio (MP3)*\n\nMP3 ئامادەیە ✅",
                            parse_mode='Markdown'
                        )
                    logger.info("✅ MP3 sent")
                    os.remove(audio_path)
                else:
                    logger.warning("MP3 conversion failed, video only sent")
                
                # Cleanup
                os.remove(temp_video)
                
            except Exception as e:
                logger.error(f"MP3 process error: {e}")
                # Video already sent, so we don't fail completely
            
            # Delete status message
            await status.delete()
            
            # Save success stats
            save_stats(platform, success=True)
            logger.info(f"✅ Complete - {platform}")
            
        else:
            # Download failed
            error_msg = result.get('error', 'Unknown error')
            await status.edit_text(
                f"❌ *نەتوانرا داونلۆد بکرێت*\n\n"
                f"Error: {error_msg}\n\n"
                f"تکایە دووبارە هەوڵ بدەرەوە",
                parse_mode='Markdown'
            )
            save_stats(platform, success=False)
            logger.error(f"❌ Failed: {error_msg}")
            
    except Exception as e:
        logger.error(f"❌ Exception in handler: {e}", exc_info=True)
        try:
            await status.edit_text(
                "❌ *هەڵەیەک ڕوویدا*\n\n"
                "تکایە دووبارە هەوڵ بدەرەوە یان لینکێکی تر بنێرە",
                parse_mode='Markdown'
            )
        except:
            pass
        save_stats(platform, success=False)

async def stats_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show bot statistics (admin only)"""
    user_id = update.message.from_user.id
    
    if user_id != ADMIN_USER_ID:
        await update.message.reply_text("⛔️ تەنها خاوەنی بۆت دەتوانێت ئامارەکان ببینێت!")
        return
    
    try:
        with open('bot_stats.json', 'r') as f:
            stats = json.load(f)
        
        started = datetime.fromisoformat(stats.get('started', datetime.now().isoformat()))
        days = max((datetime.now() - started).days, 1)
        
        success_rate = (stats.get('success', 0) / max(stats.get('total', 1), 1)) * 100
        
        message = (
            f"📊 *Bot Statistics*\n\n"
            f"🔢 Total Requests: *{stats.get('total', 0)}*\n"
            f"📸 Instagram: *{stats.get('instagram', 0)}*\n"
            f"📘 Facebook: *{stats.get('facebook', 0)}*\n"
            f"🎵 TikTok: *{stats.get('tiktok', 0)}*\n\n"
            f"✅ Successful: *{stats.get('success', 0)}*\n"
            f"❌ Failed: *{stats.get('failed', 0)}*\n"
            f"📈 Success Rate: *{success_rate:.1f}%*\n\n"
            f"📅 Running for: *{days}* days\n"
            f"📊 Average: *{stats.get('total', 0) / days:.1f}* requests/day"
        )
        
        await update.message.reply_text(message, parse_mode='Markdown')
    except FileNotFoundError:
        await update.message.reply_text("📊 هێشتا هیچ ئامارێک نییە!\n\nNo statistics yet!")
    except Exception as e:
        logger.error(f"Stats command error: {e}")
        await update.message.reply_text(f"❌ Error: {str(e)}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    await update.message.reply_text(
        "🤖 *ALL IN ONE BIG BOSS Bot*\n\n"
        "لینک بنێرە لە:\n"
        "📸 *Instagram* (Posts/Reels/Stories)\n"
        "📘 *Facebook* (Videos/Posts)\n"
        "🎵 *TikTok* (Videos)\n\n"
        "بۆ هەر ڤیدیۆیەک:\n"
        "✅ 📹 *Video* دەنێردرێت\n"
        "✅ 🎵 *Audio (MP3)* دەنێردرێت\n\n"
        "هەردووکیان پێکەوە! 🚀\n\n"
        "💡 *Commands:*\n"
        "/start - دەستپێکردن\n"
        "/stats - ئامارەکان (admin only)\n"
        "/help - یارمەتی",
        parse_mode='Markdown'
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    await update.message.reply_text(
        "📖 *یارمەتی - Help*\n\n"
        "چۆن بەکاری بهێنیت:\n\n"
        "1️⃣ لینکێک لە Instagram, Facebook, یان TikTok کۆپی بکە\n"
        "2️⃣ لێرە بنێرە بۆ بۆت\n"
        "3️⃣ چاوەڕێی چەند چرکەیەک بکە\n"
        "4️⃣ هەردوو فۆرماتەکە دەگەیەنرێت: Video + MP3 🎉\n\n"
        "💡 *Supported:*\n"
        "• Instagram posts, reels, stories\n"
        "• Facebook videos\n"
        "• TikTok videos\n\n"
        "⚡️ *خێرا و ئاسان!*",
        parse_mode='Markdown'
    )

def main():
    """Main function to run the bot"""
    # Check if config is set
    if TELEGRAM_TOKEN == "YOUR_BOT_TOKEN_HERE":
        logger.error("❌ Please configure TELEGRAM_TOKEN in config.py!")
        return
    
    if SOCIAL_API_KEY == "YOUR_RAPIDAPI_KEY_HERE":
        logger.error("❌ Please configure SOCIAL_API_KEY in config.py!")
        return
    
    # Create application
    app = Application.builder().token(TELEGRAM_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("stats", stats_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    logger.info("🤖 ALL IN ONE BIG BOSS Bot Started!")
    logger.info("📹 Video + 🎵 MP3 Downloader")
    logger.info("📸 Instagram | 📘 Facebook | 🎵 TikTok")
    
    # Start polling
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
