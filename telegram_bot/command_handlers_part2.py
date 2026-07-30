"""
Command Handlers for JagSpoor Telegram Bot - Part 2
Outfitter and notification commands.
"""

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from firebase_service import FirebaseService

firebase = FirebaseService()


# =============================================================================
# OUTFITTER COMMANDS
# =============================================================================

async def bookings_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /bookings command."""
    user_id = str(update.effective_user.id)
    user_data = await firebase.get_user(user_id)
    role = user_data.get('role', 'hunter') if user_data else 'hunter'
    
    bookings = await firebase.get_bookings(user_id, role)
    
    if not bookings:
        await update.message.reply_text(
            "📋 *Bookings*\n\nNo bookings found.",
            parse_mode="Markdown"
        )
        return
    
    text = "📋 *Your Bookings*\n\n"
    for booking in bookings:
        status_emoji = {"pending": "⏳", "confirmed": "✅", "completed": "🏆"}.get(
            booking.get('status', ''), "📌"
        )
        text += f"{status_emoji} *{booking.get('client', 'Client')}*\n"
        text += f"   Species: {booking.get('species', 'N/A')}\n"
        text += f"   Date: {booking.get('date', 'TBD')}\n"
        text += f"   Status: {booking.get('status', 'unknown').title()}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def clients_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /clients command."""
    bookings = await firebase.get_bookings(str(update.effective_user.id), "outfitter")
    
    clients = {}
    for booking in bookings:
        client = booking.get('client', 'Unknown')
        if client not in clients:
            clients[client] = {"name": client, "bookings": 0, "status": booking.get('status', '')}
        clients[client]["bookings"] += 1
    
    if not clients:
        await update.message.reply_text(
            "👥 *Clients*\n\nNo clients found.",
            parse_mode="Markdown"
        )
        return
    
    text = "👥 *Your Clients*\n\n"
    for client_data in clients.values():
        text += f"👤 *{client_data['name']}*\n"
        text += f"   Bookings: {client_data['bookings']}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def trophies_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /trophies command."""
    user_id = str(update.effective_user.id)
    user_data = await firebase.get_user(user_id)
    role = user_data.get('role', 'hunter') if user_data else 'hunter'
    
    if role == 'outfitter':
        trophies = await firebase.get_trophies(outfitter_id=user_id)
    else:
        trophies = await firebase.get_trophies(user_id=user_id)
    
    if not trophies:
        await update.message.reply_text(
            "🏆 *Trophies*\n\nNo trophies found.",
            parse_mode="Markdown"
        )
        return
    
    text = "🏆 *Trophy Stock*\n\n"
    for trophy in trophies:
        text += f"🦌 *{trophy.get('species', 'Unknown')}*\n"
        text += f"   Count: {trophy.get('count', 'N/A')}\n"
        text += f"   Location: {trophy.get('location', 'N/A')}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def revenue_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /revenue command."""
    user_id = str(update.effective_user.id)
    revenue = await firebase.get_revenue_summary(user_id)
    
    text = (
        "💰 *Revenue Summary*\n\n"
        f"*Total Revenue:* R{revenue.get('totalRevenue', 0):,.0f}\n"
        f"*This Month:* R{revenue.get('thisMonth', 0):,.0f}\n"
        f"*Pending:* R{revenue.get('pendingPayments', 0):,.0f}\n"
        f"*Bookings:* {revenue.get('bookingsCount', 0)}\n"
    )
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def permit_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /permit command."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "📄 *Transport Permit Generator*\n\n"
            "Usage: /permit [booking_id]\n\n"
            "Example: /permit abc123",
            parse_mode="Markdown"
        )
        return
    
    permit_id = args[0]
    
    keyboard = [
        [InlineKeyboardButton("📄 Generate PDF", callback_data=f"permit_{permit_id}")],
        [InlineKeyboardButton("📧 Email Permit", callback_data=f"permit_email_{permit_id}")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"📄 *Transport Permit #{permit_id}*\n\n"
        "Click below to generate:",
        parse_mode="Markdown",
        reply_markup=reply_markup
    )


# =============================================================================
# NOTIFICATIONS COMMANDS
# =============================================================================

async def subscribe_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /subscribe command."""
    args = context.args
    
    if not args:
        keyboard = [
            [InlineKeyboardButton("📋 Bookings", callback_data="sub_bookings")],
            [InlineKeyboardButton("🌦️ Weather", callback_data="sub_weather")],
            [InlineKeyboardButton("🩸 Blood Trail", callback_data="sub_bloodtrail")],
            [InlineKeyboardButton("💰 Payments", callback_data="sub_payments")],
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            "🔔 *Subscribe to Notifications*\n\n"
            "Select what you'd like to subscribe to:",
            parse_mode="Markdown",
            reply_markup=reply_markup
        )
        return
    
    subscription_type = args[0].lower()
    await update.message.reply_text(
        f"✅ *Subscribed to {subscription_type}*\n\n"
        "You will now receive notifications for this event.",
        parse_mode="Markdown"
    )


async def unsubscribe_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /unsubscribe command."""
    args = context.args
    
    if not args:
        keyboard = [
            [InlineKeyboardButton("📋 Bookings", callback_data="unsub_bookings")],
            [InlineKeyboardButton("🌦️ Weather", callback_data="unsub_weather")],
            [InlineKeyboardButton("🩸 Blood Trail", callback_data="unsub_bloodtrail")],
            [InlineKeyboardButton("💰 Payments", callback_data="unsub_payments")],
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            "🔕 *Unsubscribe from Notifications*\n\n"
            "Select what you'd like to unsubscribe from:",
            parse_mode="Markdown",
            reply_markup=reply_markup
        )
        return
    
    subscription_type = args[0].lower()
    await update.message.reply_text(
        f"🔕 *Unsubscribed from {subscription_type}*\n\n"
        "You will no longer receive these notifications.",
        parse_mode="Markdown"
    )


async def alerts_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /alerts command."""
    # Mock alerts data
    alerts = [
        {"type": "weather", "message": "Storm warning for Limpopo region", "time": "2h ago"},
        {"type": "booking", "message": "New booking request from John Smith", "time": "5h ago"},
    ]
    
    if not alerts:
        await update.message.reply_text(
            "🔔 *Active Alerts*\n\nNo active alerts.",
            parse_mode="Markdown"
        )
        return
    
    text = "🔔 *Active Alerts*\n\n"
    for alert in alerts:
        emoji = {"weather": "🌦️", "booking": "📋", "payment": "💰"}.get(alert.get('type', ''), "📌")
        text += f"{emoji} *{alert['message']}*\n"
        text += f"   {alert['time']}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def weather_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /weather command."""
    # Mock weather data (in real app, fetch from weather API)
    weather_text = (
        "🌦️ *Weather for Hunting Area*\n\n"
        "*Location:* Limpopo Province\n"
        "*Temperature:* 24°C\n"
        "*Conditions:* Partly Cloudy\n"
        "*Wind:* 12 km/h NW\n"
        "*Pressure:* 1018 hPa (Rising)\n\n"
        "*Hunting Forecast:*\n"
        "🦌 Game Movement: 78% (Good)\n"
        "🌓 Moon Phase: First Quarter\n"
        "🌡️ Best Time: Dawn & Dusk"
    )
    
    keyboard = [
        [InlineKeyboardButton("🔄 Refresh", callback_data="weather_refresh")],
        [InlineKeyboardButton("📍 Change Location", callback_data="weather_location")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(weather_text, parse_mode="Markdown", reply_markup=reply_markup)


# =============================================================================
# STATS COMMANDS
# =============================================================================

async def huntlog_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /huntlog command."""
    # Mock hunt log data
    hunts = [
        {"date": "2026-07-15", "species": "Kudu", "result": "Successful", "location": "Limpopo"},
        {"date": "2026-06-22", "species": "Warthog", "result": "Successful", "location": "Mpumalanga"},
        {"date": "2026-05-10", "species": "Impala", "result": "No Shot", "location": "Limpopo"},
    ]
    
    text = "📊 *Your Hunt Log*\n\n"
    for hunt in hunts:
        emoji = "🏆" if hunt['result'] == 'Successful' else "❌"
        text += f"{emoji} *{hunt['date']}* - {hunt['species']}\n"
        text += f"   📍 {hunt['location']} - {hunt['result']}\n\n"
    
    text += "*Stats:* 2 Successful | 1 No Shot | 67% Success Rate"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def safari_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /safari command."""
    args = context.args
    
    if args:
        date = args[0]
        # Return summary for specific date
        text = (
            f"📅 *Safari Summary - {date}*\n\n"
            "🦌 Species Observed: 8\n"
            "🎯 Shots Fired: 2\n"
            "🏆 Successful: 1\n"
            "📍 Distance Traveled: 12 km"
        )
    else:
        # Return recent safari summary
        text = (
            "📅 *Recent Safari Summary*\n\n"
            "*Last 7 Days:*\n"
            "🦌 Total Observations: 24\n"
            "🎯 Shots Fired: 5\n"
            "🏆 Successful: 3\n"
            "📸 Photos: 47\n"
            "📍 Waypoints Added: 8"
        )
    
    await update.message.reply_text(text, parse_mode="Markdown")


# =============================================================================
# UNKNOWN COMMAND HANDLER
# =============================================================================

async def unknown_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle unknown messages."""
    await update.message.reply_text(
        "🤔 I didn't understand that.\n\n"
        "Use /help to see available commands.\n\n"
        f"Your ID: `{update.effective_user.id}`",
        parse_mode="Markdown"
    )


async def myid_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /myid command - Show user's ID."""
    user = update.effective_user
    await update.message.reply_text(
        f"👤 *Your Info*\n\n"
        f"*Name:* {user.full_name}\n"
        f"*User ID:* `{user.id}`\n"
        f"*Username:* @{user.username if user.username else 'None'}",
        parse_mode="Markdown"
    )
