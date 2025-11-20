# VPS Manager Pro - Docker Container
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY bot.py .
COPY config.py .
COPY handlers ./handlers/

# Create necessary directories
RUN mkdir -p /app/downloads /app/logs

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DOWNLOAD_DIR=/app/downloads
ENV LOG_DIR=/app/logs

# Expose ports (if needed)
EXPOSE 8080

# Run bot
CMD ["python", "bot.py"]
