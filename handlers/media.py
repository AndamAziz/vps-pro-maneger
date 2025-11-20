#!/usr/bin/env python3
"""
VPS Manager Pro - Media Downloader Handler
Author: KurdCloud Team
Version: 1.0.0

Description:
Advanced media downloader supporting multiple platforms with intelligent
error handling, caching, and optimization.

Supported Platforms:
- TikTok (via yt-dlp)
- Instagram (via instagrapi API)
- YouTube (via yt-dlp)
- Facebook (via yt-dlp)
"""

import os
import logging
import asyncio
from datetime import datetime
from typing import Dict, Optional, List
from pathlib import Path

# External dependencies
try:
    import yt_dlp
    YT_DLP_AVAILABLE = True
except ImportError:
    YT_DLP_AVAILABLE = False
    logging.warning("yt-dlp not available. TikTok, YouTube, Facebook downloads will be disabled.")

try:
    from instagrapi import Client
    from instagrapi.exceptions import LoginRequired, PrivateError, MediaError
    INSTAGRAPI_AVAILABLE = True
except ImportError:
    INSTAGRAPI_AVAILABLE = False
    logging.warning("instagrapi not available. Instagram downloads will be limited.")

# Setup logger
logger = logging.getLogger(__name__)

################################################################################
# Media Downloader Class
################################################################################

class MediaDownloader:
    """
    Advanced media downloader with support for multiple platforms.
    
    Features:
    - Multi-platform support (TikTok, Instagram, YouTube, Facebook)
    - Intelligent error handling and retry logic
    - Instagram API authentication
    - Automatic file cleanup
    - Download progress tracking
    - Quality optimization
    """
    
    def __init__(self, download_dir: str = "/opt/vps-manager/telegram-bot/downloads"):
        """
        Initialize media downloader.
        
        Args:
            download_dir: Directory for temporary downloads
        """
        self.download_dir = Path(download_dir)
        self.download_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize Instagram client
        self.insta_client = None
        if INSTAGRAPI_AVAILABLE:
            self._init_instagram_client()
        
        logger.info(f"MediaDownloader initialized. Download directory: {self.download_dir}")
    
    def _init_instagram_client(self):
        """Initialize Instagram API client with authentication."""
        try:
            self.insta_client = Client()
            self.insta_client.delay_range = [1, 3]
            
            # Load credentials
            username = "allinonebigboss"
            password = "HelinGyan1122@@##"
            session_file = "/opt/vps-manager/telegram-bot/.instagram_session.json"
            
            # Try to load existing session
            if os.path.exists(session_file):
                try:
                    self.insta_client.load_settings(session_file)
                    self.insta_client.login(username, password)
                    logger.info("Instagram session loaded successfully")
                    return
                except Exception as e:
                    logger.warning(f"Failed to load Instagram session: {e}")
            
            # Create new session
            try:
                self.insta_client.login(username, password)
                self.insta_client.dump_settings(session_file)
                logger.info("Instagram login successful")
            except Exception as e:
                logger.error(f"Instagram login failed: {e}")
                self.insta_client = None
                
        except Exception as e:
            logger.error(f"Failed to initialize Instagram client: {e}")
            self.insta_client = None
    
    def _generate_filename(self, platform: str, extension: str = "mp4") -> str:
        """
        Generate unique filename for download.
        
        Args:
            platform: Platform name (tiktok, instagram, youtube, facebook)
            extension: File extension
            
        Returns:
            Full path to the file
        """
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"{platform}_{timestamp}.{extension}"
        return str(self.download_dir / filename)
    
    def _cleanup_file(self, filepath: str):
        """
        Safely remove downloaded file.
        
        Args:
            filepath: Path to file to remove
        """
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
                logger.debug(f"Cleaned up file: {filepath}")
        except Exception as e:
            logger.warning(f"Failed to cleanup file {filepath}: {e}")
    
    ############################################################################
    # TikTok Download
    ############################################################################
    
    async def download_tiktok(self, url: str) -> Dict:
        """
        Download video from TikTok.
        
        Args:
            url: TikTok video URL
            
        Returns:
            Dictionary with success status, file path, and metadata
        """
        if not YT_DLP_AVAILABLE:
            return {'success': False, 'error': 'yt-dlp not available'}
        
        logger.info(f"Starting TikTok download: {url}")
        
        try:
            output_path = self._generate_filename('tiktok', 'mp4')
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': output_path,
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'socket_timeout': 30,
            }
            
            # Download with yt-dlp
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = await asyncio.to_thread(ydl.extract_info, url, download=True)
                title = info.get('title', 'TikTok Video')
                description = info.get('description', '')
            
            # Verify download
            if os.path.exists(output_path):
                file_size = os.path.getsize(output_path)
                logger.info(f"TikTok download successful: {file_size} bytes")
                
                return {
                    'success': True,
                    'file': output_path,
                    'type': 'video',
                    'title': title,
                    'description': description,
                    'platform': 'tiktok'
                }
            else:
                return {'success': False, 'error': 'File not found after download'}
                
        except Exception as e:
            logger.error(f"TikTok download error: {e}")
            return {'success': False, 'error': str(e)}
    
    ############################################################################
    # Instagram Download
    ############################################################################
    
    async def download_instagram(self, url: str) -> Dict:
        """
        Download media from Instagram using API.
        
        Args:
            url: Instagram post/reel/story URL
            
        Returns:
            Dictionary with success status, files, and metadata
        """
        if not self.insta_client:
            logger.warning("Instagram client not available, trying fallback")
            return await self._download_instagram_fallback(url)
        
        logger.info(f"Starting Instagram download: {url}")
        
        try:
            # Extract shortcode from URL
            shortcode = self._extract_instagram_shortcode(url)
            if not shortcode:
                return {'success': False, 'error': 'Invalid Instagram URL'}
            
            # Get media ID
            media_id = self.insta_client.media_pk_from_code(shortcode)
            media_info = self.insta_client.media_info(media_id)
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            
            # Handle different media types
            if media_info.media_type == 1:  # Photo
                return await self._download_instagram_photo(media_info, timestamp)
            
            elif media_info.media_type == 2 and media_info.product_type == "feed":  # Video
                return await self._download_instagram_video(media_info, timestamp)
            
            elif media_info.media_type == 2 and media_info.product_type == "clips":  # Reel
                return await self._download_instagram_reel(media_info, timestamp)
            
            elif media_info.media_type == 8:  # Album/Carousel
                return await self._download_instagram_album(media_info, timestamp)
            
            else:
                return {'success': False, 'error': 'Unsupported media type'}
                
        except LoginRequired:
            logger.error("Instagram login required, re-authenticating...")
            self._init_instagram_client()
            return {'success': False, 'error': 'Login required. Please try again.'}
        
        except PrivateError:
            return {'success': False, 'error': 'This account is private'}
        
        except MediaError as e:
            return {'success': False, 'error': f'Media not found: {str(e)}'}
        
        except Exception as e:
            logger.error(f"Instagram download error: {e}")
            return await self._download_instagram_fallback(url)
    
    def _extract_instagram_shortcode(self, url: str) -> Optional[str]:
        """Extract shortcode from Instagram URL."""
        try:
            if "/p/" in url:
                return url.split("/p/")[1].split("/")[0].split("?")[0]
            elif "/reel/" in url:
                return url.split("/reel/")[1].split("/")[0].split("?")[0]
            elif "/tv/" in url:
                return url.split("/tv/")[1].split("/")[0].split("?")[0]
            return None
        except Exception:
            return None
    
    async def _download_instagram_photo(self, media_info, timestamp: str) -> Dict:
        """Download Instagram photo."""
        try:
            output_path = self._generate_filename(f'instagram_{timestamp}', 'jpg')
            
            await asyncio.to_thread(
                self.insta_client.photo_download_by_url,
                media_info.thumbnail_url,
                filename=output_path
            )
            
            return {
                'success': True,
                'file': output_path,
                'type': 'photo',
                'title': media_info.caption_text if media_info.caption_text else 'Instagram Photo',
                'platform': 'instagram'
            }
        except Exception as e:
            logger.error(f"Instagram photo download error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def _download_instagram_video(self, media_info, timestamp: str) -> Dict:
        """Download Instagram video."""
        try:
            output_path = self._generate_filename(f'instagram_{timestamp}', 'mp4')
            
            await asyncio.to_thread(
                self.insta_client.video_download_by_url,
                media_info.video_url,
                filename=output_path
            )
            
            return {
                'success': True,
                'file': output_path,
                'type': 'video',
                'title': media_info.caption_text if media_info.caption_text else 'Instagram Video',
                'platform': 'instagram'
            }
        except Exception as e:
            logger.error(f"Instagram video download error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def _download_instagram_reel(self, media_info, timestamp: str) -> Dict:
        """Download Instagram reel."""
        try:
            output_path = self._generate_filename(f'instagram_reel_{timestamp}', 'mp4')
            
            await asyncio.to_thread(
                self.insta_client.clip_download_by_url,
                media_info.video_url,
                filename=output_path
            )
            
            return {
                'success': True,
                'file': output_path,
                'type': 'video',
                'title': media_info.caption_text if media_info.caption_text else 'Instagram Reel',
                'platform': 'instagram'
            }
        except Exception as e:
            logger.error(f"Instagram reel download error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def _download_instagram_album(self, media_info, timestamp: str) -> Dict:
        """Download Instagram album/carousel."""
        try:
            files = []
            
            for idx, resource in enumerate(media_info.resources):
                if resource.media_type == 1:  # Photo
                    output_path = self._generate_filename(f'instagram_album_{timestamp}_{idx}', 'jpg')
                    await asyncio.to_thread(
                        self.insta_client.photo_download_by_url,
                        resource.thumbnail_url,
                        filename=output_path
                    )
                    files.append({'type': 'photo', 'file': output_path})
                    
                elif resource.media_type == 2:  # Video
                    output_path = self._generate_filename(f'instagram_album_{timestamp}_{idx}', 'mp4')
                    await asyncio.to_thread(
                        self.insta_client.video_download_by_url,
                        resource.video_url,
                        filename=output_path
                    )
                    files.append({'type': 'video', 'file': output_path})
            
            return {
                'success': True,
                'files': files,
                'type': 'album',
                'title': media_info.caption_text if media_info.caption_text else 'Instagram Album',
                'platform': 'instagram'
            }
        except Exception as e:
            logger.error(f"Instagram album download error: {e}")
            return {'success': False, 'error': str(e)}
    
    async def _download_instagram_fallback(self, url: str) -> Dict:
        """Fallback method using yt-dlp."""
        if not YT_DLP_AVAILABLE:
            return {'success': False, 'error': 'No download method available'}
        
        logger.info("Using Instagram fallback method (yt-dlp)")
        
        try:
            output_path = self._generate_filename('instagram', 'mp4')
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': f'{output_path[:-4]}.%(ext)s',
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = await asyncio.to_thread(ydl.extract_info, url, download=True)
                
                # Find downloaded file
                import glob
                files = glob.glob(f"{output_path[:-4]}.*")
                if files:
                    actual_file = files[0]
                    ext = actual_file.split('.')[-1].lower()
                    
                    return {
                        'success': True,
                        'file': actual_file,
                        'type': 'video' if ext in ['mp4', 'mov'] else 'photo',
                        'title': info.get('title', 'Instagram Media'),
                        'platform': 'instagram'
                    }
            
            return {'success': False, 'error': 'Download failed'}
            
        except Exception as e:
            logger.error(f"Instagram fallback error: {e}")
            
            if 'rate' in str(e).lower() or '429' in str(e):
                return {'success': False, 'error': 'Rate limit reached. Please wait 5-10 minutes.'}
            elif 'login' in str(e).lower() or '401' in str(e):
                return {'success': False, 'error': 'Content requires login or is private.'}
            else:
                return {'success': False, 'error': str(e)}
    
    ############################################################################
    # YouTube Download
    ############################################################################
    
    async def download_youtube(self, url: str) -> Dict:
        """
        Download video from YouTube.
        
        Args:
            url: YouTube video URL
            
        Returns:
            Dictionary with success status, file path, and metadata
        """
        if not YT_DLP_AVAILABLE:
            return {'success': False, 'error': 'yt-dlp not available'}
        
        logger.info(f"Starting YouTube download: {url}")
        
        try:
            output_path = self._generate_filename('youtube', 'mp4')
            
            ydl_opts = {
                'format': 'best[ext=mp4][height<=720]/best[ext=mp4]/best',
                'outtmpl': output_path,
                'quiet': True,
                'no_warnings': True,
                'socket_timeout': 30,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = await asyncio.to_thread(ydl.extract_info, url, download=True)
                title = info.get('title', 'YouTube Video')
                description = info.get('description', '')
            
            if os.path.exists(output_path):
                file_size = os.path.getsize(output_path)
                logger.info(f"YouTube download successful: {file_size} bytes")
                
                return {
                    'success': True,
                    'file': output_path,
                    'type': 'video',
                    'title': title,
                    'description': description,
                    'platform': 'youtube'
                }
            else:
                return {'success': False, 'error': 'File not found after download'}
                
        except Exception as e:
            logger.error(f"YouTube download error: {e}")
            return {'success': False, 'error': str(e)}
    
    ############################################################################
    # Facebook Download
    ############################################################################
    
    async def download_facebook(self, url: str) -> Dict:
        """
        Download video from Facebook.
        
        Args:
            url: Facebook video URL
            
        Returns:
            Dictionary with success status, file path, and metadata
        """
        if not YT_DLP_AVAILABLE:
            return {'success': False, 'error': 'yt-dlp not available'}
        
        logger.info(f"Starting Facebook download: {url}")
        
        try:
            output_path = self._generate_filename('facebook', 'mp4')
            
            ydl_opts = {
                'format': 'best',
                'outtmpl': output_path,
                'quiet': True,
                'no_warnings': True,
                'socket_timeout': 30,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = await asyncio.to_thread(ydl.extract_info, url, download=True)
                title = info.get('title', 'Facebook Video')
                description = info.get('description', '')
            
            if os.path.exists(output_path):
                file_size = os.path.getsize(output_path)
                logger.info(f"Facebook download successful: {file_size} bytes")
                
                return {
                    'success': True,
                    'file': output_path,
                    'type': 'video',
                    'title': title,
                    'description': description,
                    'platform': 'facebook'
                }
            else:
                return {'success': False, 'error': 'File not found after download'}
                
        except Exception as e:
            logger.error(f"Facebook download error: {e}")
            return {'success': False, 'error': str(e)}
