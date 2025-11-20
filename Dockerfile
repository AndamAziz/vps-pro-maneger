FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl wget git ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bot.py config.py ./
COPY handlers ./handlers/

RUN mkdir -p /app/downloads /app/logs

ENV PYTHONUNBUFFERED=1
ENV DOWNLOAD_DIR=/app/downloads
ENV LOG_DIR=/app/logs

CMD ["python", "bot.py"]
