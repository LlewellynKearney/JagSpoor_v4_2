"""
JagSpoor Telegram Bot
A comprehensive bot for the JagSpoor hunting & development app.
"""

import os
import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    ContextTypes,
    filters,
)
from firebase_service import FirebaseService
from command_handlers import (
    start_handler,
    help_handler,
    profile_handler,
    settings_handler,
    firearms_handler,
    license_handler,
    ballistics_handler,
    dope_handler,
    zero_handler,
    ammo_handler,
    location_handler,
    waypoints_handler,
    bloodtrail_handler,
    offline_handler,
)
from command_handlers_part2 import (
    bookings_handler,
    clients_handler,
    trophies_handler,
    revenue_handler,
    permit_handler,
    subscribe_handler,
    unsubscribe_handler,
    alerts_handler,
    weather_handler,
    huntlog_handler,
    safari_handler,
    unknown_handler,
    myid_handler,
)
# Development handlers
from dev_handlers import (
    suggest_handler,
    list_suggestions_handler,
    view_suggestion_handler,
    plan_handler,
    approve_handler,
    reject_handler,
    add_task_handler,
    tasks_handler,
    complete_task_handler,
    status_handler,
    dev_help_handler,
    gitlog_handler,
    branch_handler,
    test_handler,
    build_handler,
    start_build_handler,
    analyze_handler,
    commit_push_handler,
    build_apk_handler,
    # Bug handlers
    bug_handler,
    list_bugs_handler,
    view_bug_handler,
    fix_bug_handler,
    close_bug_handler,
    bug_stats_handler,
)

# Enable logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Configuration
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "7734509027:AAGZApa6VdfipsHSqxJ0zvOrBgr2nRFtWUg")
ADMIN_USER_ID = os.getenv("ADMIN_USER_ID", "8664039399")


async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors."""
    logger.error(f"Exception while handling an update: {context.error}")


def extract_command(text):
    """Extract command and args from text, handling @mention."""
    if not text:
        return None, []
    
    text = text.strip()
    if not text.startswith('/'):
        return None, []
    
    parts = text.split()
    if not parts:
        return None, []
    
    cmd = parts[0]
    
    # Strip @mention if present
    if '@' in cmd:
        cmd = cmd.split('@')[0]
    
    # Return command without @ and args
    return cmd[1:], parts[1:]  # Remove the '/' from command


def main():
    """Start the bot."""
    logger.info("Starting JagSpoor Telegram Bot (Dev Edition)...")
    
    # Initialize Firebase
    firebase_service = FirebaseService()
    
    # Build application
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    
    # ====== App Commands ======
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
    
    # ====== Development Commands ======
    application.add_handler(CommandHandler("suggest", suggest_handler))
    application.add_handler(CommandHandler("suggestions", list_suggestions_handler))
    application.add_handler(CommandHandler("view", view_suggestion_handler))
    application.add_handler(CommandHandler("plan", plan_handler))
    application.add_handler(CommandHandler("approve", approve_handler))
    application.add_handler(CommandHandler("reject", reject_handler))
    application.add_handler(CommandHandler("addtask", add_task_handler))
    application.add_handler(CommandHandler("tasks", tasks_handler))
    application.add_handler(CommandHandler("donetask", complete_task_handler))
    application.add_handler(CommandHandler("status", status_handler))
    application.add_handler(CommandHandler("devhelp", dev_help_handler))
    application.add_handler(CommandHandler("gitlog", gitlog_handler))
    application.add_handler(CommandHandler("branch", branch_handler))
    application.add_handler(CommandHandler("test", test_handler))
    application.add_handler(CommandHandler("build", build_handler))
    application.add_handler(CommandHandler("start_build", start_build_handler))
    application.add_handler(CommandHandler("analyze", analyze_handler))
    application.add_handler(CommandHandler("commit", commit_push_handler))
    application.add_handler(CommandHandler("build_apk", build_apk_handler))
    
    # ====== Bug Ticket Commands ======
    application.add_handler(CommandHandler("bug", bug_handler))
    application.add_handler(CommandHandler("bugs", list_bugs_handler))
    application.add_handler(CommandHandler("viewbug", view_bug_handler))
    application.add_handler(CommandHandler("fixbug", fix_bug_handler))
    application.add_handler(CommandHandler("closebug", close_bug_handler))
    application.add_handler(CommandHandler("bugstats", bug_stats_handler))
    
    # Handle callbacks
    application.add_handler(CallbackQueryHandler(firebase_service.handle_callback))
    
    # Handle commands in groups (strips @mention)
    async def group_command_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
        message = update.message
        if not message or not message.text:
            return
        
        cmd, args = extract_command(message.text)
        if not cmd:
            return
        
        context.args = args
        
        # Map commands to handlers
        handlers_map = {
            'start': start_handler,
            'help': help_handler,
            'profile': profile_handler,
            'settings': settings_handler,
            'firearms': firearms_handler,
            'license': license_handler,
            'ballistics': ballistics_handler,
            'dope': dope_handler,
            'zero': zero_handler,
            'ammo': ammo_handler,
            'location': location_handler,
            'waypoints': waypoints_handler,
            'bloodtrail': bloodtrail_handler,
            'offline': offline_handler,
            'bookings': bookings_handler,
            'clients': clients_handler,
            'trophies': trophies_handler,
            'revenue': revenue_handler,
            'permit': permit_handler,
            'subscribe': subscribe_handler,
            'unsubscribe': unsubscribe_handler,
            'alerts': alerts_handler,
            'weather': weather_handler,
            'huntlog': huntlog_handler,
            'safari': safari_handler,
            'myid': myid_handler,
            # Dev handlers
            'suggest': suggest_handler,
            'suggestions': list_suggestions_handler,
            'view': view_suggestion_handler,
            'plan': plan_handler,
            'approve': approve_handler,
            'reject': reject_handler,
            'addtask': add_task_handler,
            'tasks': tasks_handler,
            'donetask': complete_task_handler,
            'status': status_handler,
            'devhelp': dev_help_handler,
            'gitlog': gitlog_handler,
            'branch': branch_handler,
            'test': test_handler,
            'build': build_handler,
            'start_build': start_build_handler,
            'analyze': analyze_handler,
            'commit': commit_push_handler,
            'build_apk': build_apk_handler,
            'bug': bug_handler,
            'bugs': list_bugs_handler,
            'viewbug': view_bug_handler,
            'fixbug': fix_bug_handler,
            'closebug': close_bug_handler,
            'bugstats': bug_stats_handler,
        }
        
        handler = handlers_map.get(cmd.lower())
        if handler:
            await handler(update, context)
        else:
            await unknown_handler(update, context)
    
    application.add_handler(MessageHandler(filters.COMMAND, group_command_handler))
    
    # Handle unknown commands
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, unknown_handler))
    
    # Error handler
    application.add_error_handler(error_handler)
    
    # Start polling with error recovery
    logger.info("Bot is polling for updates...")
    application.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True,  # Clear old pending updates
    )


if __name__ == "__main__":
    main()
