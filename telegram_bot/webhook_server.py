"""
Telegram Bot Webhook Server
Handles incoming webhook updates from Telegram.
"""

import os
import logging
from flask import Flask, request, jsonify
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler
from firebase_service import FirebaseService

# Import handlers
from command_handlers import (
    start_handler, help_handler, profile_handler, settings_handler,
    firearms_handler, license_handler, ballistics_handler, dope_handler,
    zero_handler, ammo_handler, location_handler, waypoints_handler,
    bloodtrail_handler, offline_handler,
)
from command_handlers_part2 import (
    bookings_handler, clients_handler, trophies_handler, revenue_handler,
    permit_handler, subscribe_handler, unsubscribe_handler, alerts_handler,
    weather_handler, huntlog_handler, safari_handler,
)

# Enable logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Configuration
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "7734509027:AAGZApa6VdfipsHSqxJ0zvOrBgr2nRFtWUg")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "your_webhook_secret_here")

# Initialize Firebase
firebase = FirebaseService()

# Build application for webhook
application = ApplicationBuilder().token(TELEGRAM_BOT_TOKEN).build()

# Register command handlers
application.add_handler(CommandHandler("start", start_handler))
application.add_handler(CommandHandler("help", help_handler))
application.add_handler(CommandHandler("profile", profile_handler))
application.add_handler(CommandHandler("settings", settings_handler))
application.add_handler(CommandHandler("firearms", firearms_handler))
application.add_handler(CommandHandler("license", license_handler))
application.add_handler(CommandHandler("ballistics", ballistics_handler))
application.add_handler(CommandHandler("dope", dope_handler))
application.add_handler(CommandHandler("zero", zero_handler))
application.add_handler(CommandHandler("ammo", ammo_handler))
application.add_handler(CommandHandler("location", location_handler))
application.add_handler(CommandHandler("waypoints", waypoints_handler))
application.add_handler(CommandHandler("bloodtrail", bloodtrail_handler))
application.add_handler(CommandHandler("offline", offline_handler))
application.add_handler(CommandHandler("bookings", bookings_handler))
application.add_handler(CommandHandler("clients", clients_handler))
application.add_handler(CommandHandler("trophies", trophies_handler))
application.add_handler(CommandHandler("revenue", revenue_handler))
application.add_handler(CommandHandler("permit", permit_handler))
application.add_handler(CommandHandler("subscribe", subscribe_handler))
application.add_handler(CommandHandler("unsubscribe", unsubscribe_handler))
application.add_handler(CommandHandler("alerts", alerts_handler))
application.add_handler(CommandHandler("weather", weather_handler))
application.add_handler(CommandHandler("huntlog", huntlog_handler))
application.add_handler(CommandHandler("safari", safari_handler))

# Get dispatcher
dispatcher = application.dispatcher


@app.route(f"/webhook/{WEBHOOK_SECRET}", methods=["POST"])
def webhook():
    """Handle incoming Telegram updates."""
    try:
        # Get the update from JSON
        update_dict = request.get_json(force=True)
        logger.info(f"Received update: {update_dict}")
        
        # Create Update object and process
        update = Update.de_json(update_dict, application.bot)
        dispatcher.process_update(update)
        
        return jsonify({"status": "ok"})
    except Exception as e:
        logger.error(f"Error processing update: {e}")
        return jsonify({"status": "error", "error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy", "bot": "@jagspoor_bot"})


@app.route("/", methods=["GET"])
def index():
    """Root endpoint."""
    return jsonify({
        "bot": "JagSpoor Telegram Bot",
        "status": "running",
        "webhook_path": f"/webhook/{WEBHOOK_SECRET}"
    })


def setup_webhook():
    """Set up the webhook with Telegram."""
    import requests
    
    webhook_url = os.getenv("WEBHOOK_URL")
    if not webhook_url:
        logger.error("WEBHOOK_URL not set!")
        return False
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/setWebhook"
    data = {
        "url": f"{webhook_url}/webhook/{WEBHOOK_SECRET}",
        "secret_token": WEBHOOK_SECRET
    }
    
    response = requests.post(url, json=data)
    result = response.json()
    
    if result.get("ok"):
        logger.info(f"Webhook set to: {webhook_url}/webhook/{WEBHOOK_SECRET}")
        return True
    else:
        logger.error(f"Failed to set webhook: {result}")
        return False


if __name__ == "__main__":
    # Set up webhook if WEBHOOK_URL is provided
    if os.getenv("WEBHOOK_URL"):
        setup_webhook()
    
    # Run Flask server
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
