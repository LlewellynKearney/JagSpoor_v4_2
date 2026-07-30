# JagSpoor Telegram Bot - Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY *.py .

# Set environment variables
ENV TELEGRAM_BOT_TOKEN=""
ENV FIREBASE_SERVICE_ACCOUNT_JSON=""
ENV WEBHOOK_SECRET="your_secure_webhook_secret"
ENV WEBHOOK_URL=""
ENV PORT=8080

# Expose port
EXPOSE 8080

# Run the webhook server
CMD ["python", "webhook_server.py"]
