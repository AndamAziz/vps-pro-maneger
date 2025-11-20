#!/usr/bin/env python3
import os
import logging
import yt_dlp
from datetime import datetime

logger = logging.getLogger(__name__)

# Try to import instagrapi
try:
    from instagrapi import Client
    INSTAGRAPI_AVAILABLE = True
except ImportError:
    INSTAGRAPI_AVAILABLE = False
    logger.warning("instagrapi not available, Instagram downloads may be limited")

class MediaDownloader:
    def __init__(self):
        self.download_dir = "/opt/vps-manager/telegram-bot/downloads"
        if not os.path.exists(self.download_dir):
            os.makedirs(self.download_dir)
        
        # Initialize Instagram client
        self.insta_client = None
        if INSTAGRAPI_AVAILABLE:
            try:
                self.insta_client = Client()
                self.insta_client.delay_range = [1, 3]
                
                # Login to Instagram
                username = "allinonebigboss"
                password = "HelinGyan1122@@##"
                session_file = "/opt/vps-manager/telegram-bot/.instagram_session.json"
                
                try:
                    if os.path.exists(session_file):
                        self.insta_client.load_settings(session_file)
                        self.insta_client.login(username, password)
                    else:
                        self.insta_client.login(username, password)
                        self.insta_client.dump_settings(session_file)
                    
                    logger.info("Instagram API login successful!")
                except Exception as e:
                    logger.warning(f"Instagram login failed: {e}")
                    self.insta_client = None
            except Exception as e:
                logger.error(f"Instagram client initialization failed: {e}")
                self.insta_client = None
    
    async def download_instagram(self, url):
        """Download Instagram media using instagrapi API"""
        if not self.insta_client:
            return await self._download_instagram_fallback(url)
        
        try:
            # Extract media ID from URL
            if "/p/" in url:
                shortcode = url.split("/p/")[1].split("/")[0]
            elif "/reel/" in url:
                shortcode = url.split("/reel/")[1].split("/")[0]
            elif "/tv/" in url:
                shortcode = url.split("/tv/")[1].split("/")[0]
            else:
                return {'success': False, 'error': 'Invalid Instagram URL'}
            
            # Get media ID from shortcode
            media_id = self.insta_client.media_pk_from_code(shortcode)
            
            # Get media info
            media_info = self.insta_client.media_info(media_id)
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            
            # Download based on media type
            if media_info.media_type == 1:  # Photo
                file_path = f"{self.download_dir}/instagram_photo_{timestamp}.jpg"
                self.insta_client.photo_download(media_id, folder=self.download_dir)
                
                # Find the downloaded file
                import glob
                files = glob.glob(f"{self.download_dir}/*.jpg")
                if files:
                    latest_file = max(files, key=os.path.getctime)
                    os.rename(latest_file, file_path)
                    
                    return {
                        'success': True,
                        'file': file_path,
                        'type': 'photo',
                        'title': media_info.caption_text if media_info.caption_text else 'Instagram Photo'
                    }
            
            elif media_info.media_type == 2 and media_info.product_type == "feed":  # Video
                file_path = f"{self.download_dir}/instagram_video_{timestamp}.mp4"
                self.insta_client.video_download(media_id, folder=self.download_dir)
                
                # Find the downloaded file
                import glob
                files = glob.glob(f"{self.download_dir}/*.mp4")
                if files:
                    latest_file = max(files, key=os.path.getctime)
                    os.rename(latest_file, file_path)
                    
                    return {
                        'success': True,
                        'file': file_path,
                        'type': 'video',
                        'title': media_info.caption_text if media_info.caption_text else 'Instagram Video'
                    }
            
            elif media_info.media_type == 2 and media_info.product_type == "clips":  # Reel
                file_path = f"{self.download_dir}/instagram_reel_{timestamp}.mp4"
                self.insta_client.clip_download(media_id, folder=self.download_dir)
                
                # Find the downloaded file
                import glob
                files = glob.glob(f"{self.download_dir}/*.mp4")
                if files:
                    latest_file = max(files, key=os.path.getctime)
                    os.rename(latest_file, file_path)
                    
                    return {
                        'success': True,
                        'file': file_path,
                        'type': 'video',
                        'title': media_info.caption_text if media_info.caption_text else 'Instagram Reel'
                    }
            
            elif media_info.media_type == 8:  # Album/Carousel
                files_downloaded = []
                
                # Download all media in album
                for idx, resource in enumerate(media_info.resources):
                    if resource.media_type == 1:  # Photo
                        file_path = f"{self.download_dir}/instagram_album_{timestamp}_{idx}.jpg"
                        self.insta_client.photo_download_by_url(resource.thumbnail_url, filename=file_path)
                        files_downloaded.append({'type': 'photo', 'file': file_path})
                    elif resource.media_type == 2:  # Video
                        file_path = f"{self.download_dir}/instagram_album_{timestamp}_{idx}.mp4"
                        self.insta_client.video_download_by_url(resource.video_url, filename=file_path)
                        files_downloaded.append({'type': 'video', 'file': file_path})
                
                if files_downloaded:
                    return {
                        'success': True,
                        'files': files_downloaded,
                        'type': 'album',
                        'title': media_info.caption_text if media_info.caption_text else 'Instagram Album'
                    }
            
            return {'success': False, 'error': 'Unsupported media type'}
        
        except Exception as e:
            logger.error(f"Instagram API download error: {e}")
            # Try fallback method
            return await self._download_instagram_fallback(url)
    
    async def _download_instagram_fallback(self, url):
        """Fallback method using yt-dlp"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_path = f"{self.download_dir}/instagram_{timestamp}"
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': f'{output_path}.%(ext)s',
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                
                if 'requested_downloads' in info and len(info['requested_downloads']) > 0:
                    actual_file = info['requested_downloads'][0]['filepath']
                else:
                    import glob
                    files = glob.glob(f"{output_path}.*")
                    if files:
                        actual_file = files[0]
                    else:
                        return {'success': False, 'error': 'File not found'}
                
                ext = actual_file.split('.')[-1].lower()
                
                return {
                    'success': True,
                    'file': actual_file,
                    'type': 'video' if ext in ['mp4', 'mov'] else 'photo',
                    'title': info.get('title', 'Instagram Media')
                }
        
        except Exception as e:
            logger.error(f"Instagram fallback error: {e}")
            error_msg = str(e)
            if 'rate' in error_msg.lower() or '429' in error_msg:
                error_msg = "Rate limit reached. Try again in a few minutes."
            elif 'login' in error_msg.lower() or '401' in error_msg:
                error_msg = "Content requires login or is private."
            
            return {'success': False, 'error': error_msg}
    
    async def download_tiktok(self, url):
        """Download TikTok video"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_path = f"{self.download_dir}/tiktok_{timestamp}.mp4"
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': output_path,
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                title = info.get('title', 'TikTok Video')
            
            if os.path.exists(output_path):
                return {'success': True, 'file': output_path, 'title': title, 'type': 'video'}
            else:
                return {'success': False, 'error': 'Download failed'}
        except Exception as e:
            logger.error(f"TikTok error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def download_youtube(self, url):
        """Download YouTube video"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_path = f"{self.download_dir}/youtube_{timestamp}.mp4"
            
            ydl_opts = {
                'format': 'best[ext=mp4][height<=720]',
                'outtmpl': output_path,
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                title = info.get('title', 'YouTube Video')
            
            if os.path.exists(output_path):
                return {'success': True, 'file': output_path, 'title': title, 'type': 'video'}
            else:
                return {'success': False, 'error': 'Download failed'}
        except Exception as e:
            logger.error(f"YouTube error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def download_facebook(self, url):
        """Download Facebook video"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_path = f"{self.download_dir}/facebook_{timestamp}.mp4"
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': output_path,
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                title = info.get('title', 'Facebook Video')
            
            if os.path.exists(output_path):
                return {'success': True, 'file': output_path, 'title': title, 'type': 'video'}
            else:
                return {'success': False, 'error': 'Download failed'}
        except Exception as e:
            logger.error(f"Facebook error: {e}")
            return {'success': False, 'error': str(e)}
