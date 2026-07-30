#!/usr/bin/env python3
"""
Setup script to configure Telegram webhook.
Run this once to register your webhook URL with Telegram.
"""

import os
import sys
import requests
import secrets
import json

# Configuration
TELEGRAM_API = "https://api.telegram.org"
WEBHOOK_SECRET = secrets.token_hex(16)


def get_bot_token():
    """Get bot token from environment or prompt."""
    token = os.getenv("TELEGRAM_BOT_TOKEN", "7734509027:AAGZApa6VdfipsHSqxJ0zvOrBgr2nRFtWUg")
    return token


def verify_webhook_url(url):
    """Verify the webhook URL is accessible."""
    try:
        response = requests.get(url, timeout=5)
        return response.status_code == 200
    except:
        return False


def set_webhook(bot_token, webhook_url, secret_token):
    """Set the webhook with Telegram."""
    url = f"{TELEGRAM_API}/bot{bot_token}/setWebhook"
    data = {
        "url": webhook_url,
        "secret_token": secret_token
    }
    
    print(f"📡 Setting webhook to: {webhook_url}")
    
    response = requests.post(url, json=data)
    result = response.json()
    
    if result.get("ok"):
        print("✅ Webhook set successfully!")
        return True
    else:
        print(f"❌ Failed to set webhook: {result}")
        return False


def get_webhook_info(bot_token):
    """Get current webhook info."""
    url = f"{TELEGRAM_API}/bot{bot_token}/getWebhookInfo"
    response = requests.get(url)
    return response.json()


def delete_webhook(bot_token):
    """Delete the current webhook."""
    url = f"{TELEGRAM_API}/bot{bot_token}/deleteWebhook"
    response = requests.delete(url)
    return response.json()


def main():
    print("🦌 JagSpoor Telegram Bot - Webhook Setup")
    print("=" * 50)
    
    bot_token = get_bot_token()
    
    # Check current webhook status
    print("\n📊 Current webhook status:")
    info = get_webhook_info(bot_token)
    result = info.get("result", {})
    if result.get("url"):
        print(f"   URL: {result['url']}")
        print(f"   Has certificate: {result.get('has_custom_certificate', False)}")
        print(f"   Pending updates: {result.get('pending_update_count', 0)}")
    else:
        print("   No webhook configured (using polling)")
    
    print("\n" + "=" * 50)
    print("🔧 Webhook Configuration")
    print("=" * 50)
    
    # Get webhook URL
    webhook_url = input("Enter your webhook URL (e.g., https://your-domain.com/webhook): ").strip()
    
    if not webhook_url:
        print("❌ Webhook URL is required")
        sys.exit(1)
    
    # Verify URL format
    if not webhook_url.startswith("https://"):
        print("❌ Webhook URL must use HTTPS")
        sys.exit(1)
    
    # Generate or use provided secret
    print(f"\n🔐 Generated webhook secret: {WEBHOOK_SECRET}")
    print("   (Save this secret - you'll need it for your server)")
    
    # Confirm
    confirm = input("\n⚠️ This will update your bot's webhook. Continue? (y/N): ").strip().lower()
    if confirm != 'y':
        print("❌ Cancelled")
        sys.exit(0)
    
    # Set webhook
    print()
    if set_webhook(bot_token, webhook_url, WEBHOOK_SECRET):
        print("\n" + "=" * 50)
        print("📝 Configuration for your server:")
        print("=" * 50)
        print(f"""
Environment Variables:
  TELEGRAM_BOT_TOKEN={bot_token}
  WEBHOOK_URL={webhook_url}
  WEBHOOK_SECRET={WEBHOOK_SECRET}
  PORT=8080

Run with:
  python webhook_server.py

Or with Docker:
  docker-compose up -d
""")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
