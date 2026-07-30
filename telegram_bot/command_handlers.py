"""
Command Handlers for JagSpoor Telegram Bot
All command implementations.
"""

import logging
from typing import Dict, List
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from firebase_service import FirebaseService

logger = logging.getLogger(__name__)
firebase = FirebaseService()

# =============================================================================
# USER & AUTHENTICATION COMMANDS
# =============================================================================

async def start_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command."""
    user = update.effective_user
    
    keyboard = [
        [InlineKeyboardButton("🎯 Ballistics", callback_data="menu_ballistics")],
        [InlineKeyboardButton("🔫 Firearms", callback_data="menu_firearms")],
        [InlineKeyboardButton("🗺️ Navigation", callback_data="menu_navigation")],
        [InlineKeyboardButton("🏠 Outfitter", callback_data="menu_outfitter")],
        [InlineKeyboardButton("🔔 Notifications", callback_data="menu_notifications")],
        [InlineKeyboardButton("⚙️ Settings", callback_data="settings")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"🦌 *Welcome to JagSpoor Bot, {user.first_name}!*\n\n"
        "I'm here to help you manage your hunting activities.\n\n"
        "Use /help to see all available commands.",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )


async def help_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command."""
    help_text = """
🦌 *JagSpoor Bot Commands*

*📱 General*
/start - Welcome menu
/help - Show all commands (this)
/profile - View your profile
/settings - Configure preferences

*🔫 Firearms & Licensing*
/firearms - List your firearms
/license - Check license status

*🎯 Ballistics*
/ballistics - Ballistics menu
/dope [distance] - Calculate holdover
/zero [range] - Zero your rifle
/ammo [name] - Search ammunition

*🗺️ Navigation*
/location - Share GPS location
/waypoints - List waypoints
/bloodtrail - Log blood trail
/offline - Get offline maps

*🏠 Outfitter*
/bookings - View bookings
/clients - List clients
/trophies - Trophy inventory
/revenue - Revenue summary
/permit [id] - Generate permit

*🔔 Notifications*
/subscribe [event] - Subscribe
/unsubscribe [event] - Unsubscribe
/alerts - View active alerts
/weather - Current weather

*📊 Stats*
/huntlog - Hunt history
/safari [date] - Safari summary

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
*🔧 DEVELOPMENT COMMANDS*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

*💡 Feature Suggestions (Everyone):*
/suggest [idea] - Submit feature idea
/suggestions - View all suggestions
/view [id] - View suggestion
/status - Dev status dashboard

*🐛 Bug Tracking (Everyone):*
/bug [description] - Report a bug
/bugs - List all bugs
/viewbug [id] - View bug details
/bugstats - Bug statistics

*👑 Admin Commands:*
/approve [id] [plan] - Approve + plan feature
/reject [id] [reason] - Reject suggestion
/fixbug [id] [note] - Mark bug fixed
/closebug [id] [reason] - Close bug

*📋 Task Management:*
/addtask [id] [task] - Add task
/tasks [id] - List tasks
/donetask [id] [num] - Complete task

*🚀 Build & Deploy:*
/start_build [id] [msg] - Full build workflow
/analyze - Run flutter analyze
/commit [msg] - Commit & push to git
/build_apk - Build debug APK

*🛠️ Dev Tools:*
/gitlog - Recent commits
/branch - Current branch
/devhelp - This list (or use /help)
"""
    await update.message.reply_text(help_text, parse_mode="Markdown")


async def profile_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /profile command."""
    user = update.effective_user
    user_data = await firebase.get_user(str(user.id))
    
    if not user_data:
        user_data = {"name": user.first_name, "role": "hunter"}
    
    profile_text = f"""
👤 *Your Profile*

*Name:* {user_data.get('name', user.first_name)}
*Role:* {user_data.get('role', 'Hunter').title()}
*Telegram:* @{user.username or 'N/A'}

📊 *Stats*
🔫 Firearms: {user_data.get('firearmsCount', 'N/A')}
🏆 Trophies: {user_data.get('trophiesCount', 'N/A')}
🎯 Hunts: {user_data.get('huntsCompleted', 'N/A')}
"""
    await update.message.reply_text(profile_text, parse_mode="Markdown")


async def settings_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /settings command."""
    keyboard = [
        [InlineKeyboardButton("🔔 Notifications", callback_data="settings_notifications")],
        [InlineKeyboardButton("📍 Location Sharing", callback_data="settings_location")],
        [InlineKeyboardButton("💬 Messages", callback_data="settings_messages")],
        [InlineKeyboardButton("🔙 Back", callback_data="back_main")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        "⚙️ *Settings*\n\nConfigure your preferences:",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )


# =============================================================================
# FIREARMS & LICENSING COMMANDS
# =============================================================================

async def firearms_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /firearms command."""
    user_id = str(update.effective_user.id)
    firearms = await firebase.get_user_firearms(user_id)
    
    if not firearms:
        await update.message.reply_text("🔫 You have no firearms registered.")
        return
    
    text = "🔫 *Your Registered Firearms*\n\n"
    for i, gun in enumerate(firearms, 1):
        text += f"{i}. {gun.get('make', 'Unknown')} {gun.get('model', '')}\n"
        text += f"   Caliber: {gun.get('caliber', 'N/A')}\n"
        text += f"   License: {gun.get('licenseExpiry', 'N/A')}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def license_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /license command."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "📋 *License Commands*\n\n"
            "/license STATUS - Check license status\n"
            "/license RENEW - Get renewal reminder",
            parse_mode="Markdown"
        )
        return
    
    action = args[0].upper()
    
    if action == "STATUS":
        firearms = await firebase.get_user_firearms(str(update.effective_user.id))
        text = "📋 *License Status*\n\n"
        for gun in firearms:
            expiry = gun.get('licenseExpiry', 'N/A')
            text += f"🔫 {gun.get('make', 'Unknown')} - Expires: {expiry}\n"
        await update.message.reply_text(text, parse_mode="Markdown")
    
    elif action == "RENEW":
        keyboard = [
            [InlineKeyboardButton("🔗 SAPS Portal", url="https://www.saps.gov.za")],
            [InlineKeyboardButton("📧 Email Reminder", callback_data="license_reminder")],
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            "📧 *License Renewal*\n\nClick below to renew your license:",
            parse_mode="Markdown",
            reply_markup=reply_markup
        )
    else:
        await update.message.reply_text("Unknown action. Use STATUS or RENEW.")


# =============================================================================
# BALLISTICS COMMANDS
# =============================================================================

async def ballistics_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /ballistics command."""
    keyboard = [
        [InlineKeyboardButton("📊 Calculate DOPE", callback_data="ballistics_dope")],
        [InlineKeyboardButton("🎯 Zero Calculator", callback_data="ballistics_zero")],
        [InlineKeyboardButton("🔍 Search Ammo", callback_data="ballistics_ammo")],
        [InlineKeyboardButton("📐 Trajectory Table", callback_data="ballistics_trajectory")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        "🎯 *Ballistics Calculator*\n\n"
        "Choose an option:",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )


async def dope_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /dope command - Drop At Zero."""
    args = context.args
    
    # Example ballistic data (in real app, fetch from Firebase)
    ballistic_data = {
        100: 0,
        150: -1.2,
        200: -3.5,
        250: -6.8,
        300: -11.2,
        350: -16.5,
        400: -23.0,
        450: -30.8,
        500: -40.0,
    }
    
    if not args:
        text = "🎯 *DOPE Card (Drop At Zero)*\n\n"
        text += "Usage: /dope [distance]\n\n"
        text += "*Example distances:*\n"
        for dist, drop in ballistic_data.items():
            text += f"  {dist}m: {drop:.1f} MOA\n"
        await update.message.reply_text(text, parse_mode="Markdown")
        return
    
    try:
        distance = int(args[0])
        if distance in ballistic_data:
            drop = ballistic_data[distance]
            await update.message.reply_text(
                f"🎯 *DOPE for {distance}m*\n\n"
                f"Drop: {drop:.1f} MOA\n"
                f"Hold: {abs(drop):.1f} MOA {('up' if drop < 0 else 'down')}",
                parse_mode="Markdown"
            )
        else:
            await update.message.reply_text(f"No data for {distance}m. Try: {', '.join(str(k) for k in ballistic_data.keys())}")
    except ValueError:
        await update.message.reply_text("Please provide a valid distance in meters.")


async def zero_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /zero command."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🎯 *Zero Calculator*\n\n"
            "Usage: /zero [range]\n\n"
            "Example: /zero 100",
            parse_mode="Markdown"
        )
        return
    
    try:
        zero_range = int(args[0])
        text = f"🎯 *Zero Settings @ {zero_range}m*\n\n"
        text += f"*Atmospheric:*\n"
        text += f"  Temperature: 15°C\n"
        text += f"  Pressure: 1013 hPa\n"
        text += f"  Humidity: 50%\n\n"
        text += f"*Calculated:*\n"
        text += f"  Windage: 0 MOA\n"
        text += f"  Elevation: Set for {zero_range}m zero"
        await update.message.reply_text(text, parse_mode="Markdown")
    except ValueError:
        await update.message.reply_text("Please provide a valid range in meters.")


async def ammo_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /ammo command."""
    args = context.args
    query = " ".join(args) if args else ""
    
    results = await firebase.search_ammo(query)
    
    if not results:
        await update.message.reply_text("🔍 No ammunition found matching your query.")
        return
    
    text = "🔍 *Ammunition Search Results*\n\n"
    for ammo in results[:5]:
        text += f"*{ammo.get('brand', 'Unknown')} {ammo.get('name', '')}*\n"
        text += f"  Grain: {ammo.get('grain', 'N/A')}\n"
        text += f"  BC: {ammo.get('bc', 'N/A')}\n"
        text += f"  MV: {ammo.get('muzzle_vel', 'N/A')} fps\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


# =============================================================================
# NAVIGATION & TRACKING COMMANDS
# =============================================================================

async def location_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /location command."""
    await update.message.reply_text(
        "📍 *Location*\n\n"
        "To share your GPS location:\n"
        "1. Tap the 📎 attachment button\n"
        "2. Select 'Location'\n"
        "3. Share your current position\n\n"
        "Your waypoints will be displayed on the map.",
        parse_mode="Markdown"
    )


async def waypoints_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /waypoints command."""
    user_id = str(update.effective_user.id)
    waypoints = await firebase.get_waypoints(user_id)
    
    if not waypoints:
        await update.message.reply_text(
            "📍 *Waypoints*\n\nNo waypoints saved yet.\n"
            "Use the JagSpoor app to add waypoints.",
            parse_mode="Markdown"
        )
        return
    
    text = "📍 *Your Waypoints*\n\n"
    for i, wp in enumerate(waypoints, 1):
        text += f"{i}. *{wp.get('name', 'Waypoint')}* ({wp.get('type', 'marker')})\n"
        text += f"   📌 {wp.get('lat', 0):.4f}, {wp.get('lon', 0):.4f}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def bloodtrail_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /bloodtrail command."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🩸 *Blood Trail Logger*\n\n"
            "Usage: /bloodtrail [description]\n\n"
            "Example: /bloodtrail Heavy drip, dark red, 50m from shot",
            parse_mode="Markdown"
        )
        return
    
    description = " ".join(args)
    success = await firebase.log_bloodtrail(str(update.effective_user.id), {
        "description": description,
        "timestamp": "now"
    })
    
    if success:
        await update.message.reply_text(
            "✅ *Blood Trail Logged*\n\n"
            f"_{description}_",
            parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("❌ Failed to log blood trail. Please try again.")


async def offline_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /offline command."""
    keyboard = [
        [InlineKeyboardButton("🗺️ Download Map", callback_data="offline_map")],
        [InlineKeyboardButton("📥 Export Data", callback_data="offline_export")],
        [InlineKeyboardButton("🔄 Sync Queue", callback_data="offline_sync")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        "📴 *Offline Mode*\n\n"
        "Access your maps without internet.\n"
        "Your data will sync when connected.",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )
