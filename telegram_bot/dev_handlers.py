"""
Development Commands for JagSpoor Bot
Feature suggestions, planning, and dev workflow management.
"""

import os
import re
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

logger = logging.getLogger(__name__)

# Admin user ID (set via environment or config)
ADMIN_USER_ID = os.getenv("ADMIN_USER_ID", "8664039399")  # Llewellyn's Telegram ID
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "Llewellynkearney")  # Llewellyn's Telegram username

# In-memory storage for feature requests (in production, use a database)
FEATURE_REQUESTS: Dict[str, dict] = {}
TASKS: Dict[str, dict] = {}

# Bug tickets storage
BUG_TICKETS: Dict[str, dict] = {}


def is_admin(user_id: int, username: str = None) -> bool:
    """Check if user is admin by ID or username."""
    if str(user_id) == str(ADMIN_USER_ID):
        return True
    if username and username.lower() == ADMIN_USERNAME.lower():
        return True
    return False


# =============================================================================
# FEATURE SUGGESTION COMMANDS
# =============================================================================

async def suggest_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /suggest command - Submit a feature idea."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "💡 *Feature Suggestion*\n\n"
            "Usage: `/suggest [your idea]`\n\n"
            "Example:\n"
            "`/suggest Add offline map caching for hunting areas`\n\n"
            "Your idea will be reviewed by the admin and may be implemented!",
            parse_mode="Markdown"
        )
        return
    
    idea = " ".join(args)
    user = update.effective_user
    feature_id = f"FR-{len(FEATURE_REQUESTS) + 1:04d}"
    
    # Store the feature request
    FEATURE_REQUESTS[feature_id] = {
        "id": feature_id,
        "idea": idea,
        "submitted_by": user.full_name,
        "user_id": user.id,
        "username": user.username,
        "status": "pending",
        "created_at": datetime.now().isoformat(),
        "plan": None,
        "approved": False,
        "tasks": []
    }
    
    keyboard = [
        [InlineKeyboardButton("👀 View All Suggestions", callback_data="dev_list_suggestions")],
    ]
    
    await update.message.reply_text(
        f"✅ *Feature Submitted!*\n\n"
        f"*ID:* `{feature_id}`\n"
        f"*Your Idea:* {idea}\n\n"
        f"The admin will review your suggestion and create a plan.\n"
        f"You'll be notified when it's approved!",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    
    # Notify admin
    try:
        admin_keyboard = [
            [InlineKeyboardButton("📋 Review Suggestion", callback_data=f"dev_review_{feature_id}")],
            [InlineKeyboardButton("📊 All Suggestions", callback_data="dev_list_suggestions")],
        ]
        await context.bot.send_message(
            chat_id=int(ADMIN_USER_ID),
            text=f"🔔 *New Feature Suggestion!*\n\n"
                 f"*ID:* `{feature_id}`\n"
                 f"*From:* @{user.username or user.full_name}\n"
                 f"*Idea:* {idea}",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(admin_keyboard)
        )
    except Exception as e:
        logger.error(f"Failed to notify admin: {e}")


async def list_suggestions_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /suggestions command - List all feature suggestions."""
    if not FEATURE_REQUESTS:
        await update.message.reply_text(
            "📋 *Feature Suggestions*\n\n"
            "No suggestions yet! Be the first to suggest a feature!",
            parse_mode="Markdown"
        )
        return
    
    status_filter = context.args[0].lower() if context.args else None
    
    text = "📋 *Feature Suggestions*\n\n"
    
    for fr_id, fr in sorted(FEATURE_REQUESTS.items()):
        if status_filter and fr["status"] != status_filter:
            continue
        
        status_emoji = {
            "pending": "⏳",
            "planned": "📝",
            "approved": "✅",
            "in_progress": "🔨",
            "completed": "🏁"
        }.get(fr["status"], "📌")
        
        text += f"{status_emoji} *{fr_id}* - {fr['submitted_by']}\n"
        text += f"   {fr['idea'][:60]}{'...' if len(fr['idea']) > 60 else ''}\n\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def view_suggestion_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /view command - View a specific suggestion."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🔍 *View Suggestion*\n\n"
            "Usage: `/view [feature-id]`\n\n"
            "Example: `/view FR-0001`",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    fr = FEATURE_REQUESTS[feature_id]
    
    status_text = {
        "pending": "⏳ Pending Review",
        "planned": "📝 Plan Created",
        "approved": "✅ Approved",
        "in_progress": "🔨 In Progress",
        "completed": "🏁 Completed"
    }.get(fr["status"], fr["status"])
    
    text = (
        f"🔍 *Feature: {feature_id}*\n\n"
        f"*Status:* {status_text}\n"
        f"*Submitted by:* {fr['submitted_by']}\n"
        f"*Date:* {fr['created_at'][:10]}\n\n"
        f"*💡 Idea:*\n"
        f"{fr['idea']}\n"
    )
    
    if fr.get("plan"):
        text += f"\n*📝 Plan:*\n"
        for i, step in enumerate(fr["plan"].split("\n"), 1):
            if step.strip():
                text += f"{i}. {step}\n"
    
    if fr.get("tasks"):
        text += f"\n*📋 Tasks:*\n"
        for task in fr["tasks"]:
            text += f"☐ {task}\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


# =============================================================================
# ADMIN COMMANDS - PLANNING
# =============================================================================

async def plan_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /plan command - Create a plan for a feature (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can create plans.")
        return
    
    args = context.args
    
    if len(args) < 2:
        await update.message.reply_text(
            "📝 *Create Plan*\n\n"
            "Usage: `/plan [feature-id] [plan description]`\n\n"
            "Example:\n"
            "`/plan FR-0001 1. Create database schema\\n2. Add API endpoint\\n3. Create UI`",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    plan = " ".join(args[1:])
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    FEATURE_REQUESTS[feature_id]["plan"] = plan
    FEATURE_REQUESTS[feature_id]["status"] = "planned"
    
    fr = FEATURE_REQUESTS[feature_id]
    
    await update.message.reply_text(
        f"✅ *Plan Created for {feature_id}*\n\n"
        f"*Plan:*\n{plan}\n\n"
        f"Use `/approve {feature_id}` to approve and start implementation.",
        parse_mode="Markdown"
    )
    
    # Notify user
    try:
        await context.bot.send_message(
            chat_id=fr["user_id"],
            text=f"🔔 *Update on Your Suggestion*\n\n"
                 f"Your idea has been reviewed and a plan has been created!\n\n"
                 f"*Feature:* {fr['idea'][:50]}...\n"
                 f"*Plan:*\n{plan[:200]}{'...' if len(plan) > 200 else ''}",
            parse_mode="Markdown"
        )
    except:
        pass


async def approve_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /approve command - Approve a feature and create plan (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can approve features.")
        return
    
    args = context.args
    
    if len(args) < 2:
        await update.message.reply_text(
            "✅ *Approve & Plan Feature*\n\n"
            "Usage: `/approve [feature-id] [plan steps]`\n\n"
            "Example:\n"
            "`/approve FR-0001 1. Create dark theme\\n2. Update screens\\n3. Add settings toggle`\n\n"
            "The plan should be numbered steps on separate lines.",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    plan = " ".join(args[1:]).replace("\\n", "\n")
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    fr = FEATURE_REQUESTS[feature_id]
    
    # Update status
    fr["status"] = "approved"
    fr["approved"] = True
    fr["plan"] = plan
    fr["approved_at"] = datetime.now().isoformat()
    
    # Extract tasks from plan
    steps = [s.strip() for s in plan.split("\n") if s.strip() and s.strip()[0].isdigit()]
    fr["tasks"] = [f"[ ] {s}" for s in steps]
    
    task_count = len(fr["tasks"])
    
    keyboard = [
        [InlineKeyboardButton("📋 View Tasks", callback_data=f"dev_view_tasks_{feature_id}")],
        [InlineKeyboardButton("🚀 Start Build", callback_data=f"dev_start_build_{feature_id}")],
    ]
    
    await update.message.reply_text(
        f"✅ *Feature {feature_id} APPROVED & PLANNED!*\n\n"
        f"*Feature:* {fr['idea'][:100]}...\n\n"
        f"*📝 Plan ({task_count} steps):*\n{plan[:500]}{'...' if len(plan) > 500 else ''}\n\n"
        f"*📋 Tasks auto-generated from plan*\n\n"
        f"Ready for implementation! Use `/tasks {feature_id}` to view all tasks.",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    
    # Notify the suggester
    try:
        await context.bot.send_message(
            chat_id=fr["user_id"],
            text=f"🎉 *Your Suggestion Was Approved!*\n\n"
                 f"*Feature:* {fr['idea'][:100]}...\n\n"
                 f"A plan has been created with {task_count} steps.\n"
                 f"The admin will start building soon!",
            parse_mode="Markdown"
        )
    except:
        pass


async def reject_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /reject command - Reject a feature (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can reject features.")
        return
    
    args = context.args
    
    if len(args) < 2:
        await update.message.reply_text(
            "❌ *Reject Feature*\n\n"
            "Usage: `/reject [feature-id] [reason]`\n\n"
            "Example: `/reject FR-0001 Already covered by existing feature`",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    reason = " ".join(args[1:])
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    FEATURE_REQUESTS[feature_id]["status"] = "rejected"
    fr = FEATURE_REQUESTS[feature_id]
    
    await update.message.reply_text(
        f"❌ *Feature {feature_id} Rejected*\n\n"
        f"*Reason:* {reason}",
        parse_mode="Markdown"
    )
    
    # Notify user
    try:
        await context.bot.send_message(
            chat_id=fr["user_id"],
            text=f"😔 *Suggestion Update*\n\n"
                 f"Your suggestion wasn't approved at this time.\n\n"
                 f"*Reason:* {reason}",
            parse_mode="Markdown"
        )
    except:
        pass


# =============================================================================
# TASK MANAGEMENT
# =============================================================================

async def add_task_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /addtask command - Add a task to a feature."""
    args = context.args
    
    if len(args) < 2:
        await update.message.reply_text(
            "📋 *Add Task*\n\n"
            "Usage: `/addtask [feature-id] [task description]`\n\n"
            "Example: `/addtask FR-0001 Create user model`",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    task = " ".join(args[1:])
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    if "tasks" not in FEATURE_REQUESTS[feature_id]:
        FEATURE_REQUESTS[feature_id]["tasks"] = []
    
    task_id = f"T-{len(FEATURE_REQUESTS[feature_id]['tasks']) + 1:02d}"
    FEATURE_REQUESTS[feature_id]["tasks"].append(f"[ ] {task_id}: {task}")
    FEATURE_REQUESTS[feature_id]["status"] = "in_progress"
    
    await update.message.reply_text(
        f"✅ *Task Added to {feature_id}*\n\n"
        f"*Task:* {task}\n\n"
        f"Use `/tasks {feature_id}` to see all tasks.",
        parse_mode="Markdown"
    )


async def tasks_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /tasks command - List tasks for a feature."""
    args = context.args
    
    if not args:
        # List all tasks across all features
        text = "📋 *All Tasks*\n\n"
        for fr_id, fr in sorted(FEATURE_REQUESTS.items()):
            if fr.get("tasks"):
                text += f"*Feature {fr_id}:*\n"
                for task in fr["tasks"]:
                    text += f"  {task}\n"
                text += "\n"
        
        if not text.strip():
            text = "No tasks created yet."
        
        await update.message.reply_text(text, parse_mode="Markdown")
        return
    
    feature_id = args[0].upper()
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    fr = FEATURE_REQUESTS[feature_id]
    
    if not fr.get("tasks"):
        await update.message.reply_text(
            f"📋 *Tasks for {feature_id}*\n\n"
            f"No tasks yet. Use `/addtask {feature_id} [task]` to add one.",
            parse_mode="Markdown"
        )
        return
    
    completed = sum(1 for t in fr["tasks"] if t.startswith("[x]"))
    total = len(fr["tasks"])
    progress = "▓" * completed + "░" * (total - completed)
    
    text = (
        f"📋 *Tasks for {feature_id}*\n\n"
        f"*Feature:* {fr['idea'][:50]}...\n\n"
        f"Progress: [{progress}] {completed}/{total}\n\n"
    )
    
    for task in fr["tasks"]:
        text += f"{task}\n"
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def complete_task_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /donetask command - Mark a task as complete."""
    args = context.args
    
    if len(args) < 2:
        await update.message.reply_text(
            "✅ *Complete Task*\n\n"
            "Usage: `/donetask [feature-id] [task-number]`\n\n"
            "Example: `/donetask FR-0001 1`",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    try:
        task_num = int(args[1])
    except ValueError:
        await update.message.reply_text("Task number must be a number.")
        return
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    fr = FEATURE_REQUESTS[feature_id]
    
    if not fr.get("tasks") or task_num > len(fr["tasks"]):
        await update.message.reply_text(
            f"❌ Task {task_num} not found.",
            parse_mode="Markdown"
        )
        return
    
    # Mark task as complete
    task = fr["tasks"][task_num - 1]
    fr["tasks"][task_num - 1] = task.replace("[ ]", "[x]")
    
    # Check if all tasks are complete
    all_done = all(t.startswith("[x]") for t in fr["tasks"])
    if all_done:
        fr["status"] = "completed"
    
    await update.message.reply_text(
        f"✅ *Task {task_num} Completed!*\n\n"
        f"{task.replace('[ ]', '[x]')}\n\n"
        f"{'🎉 All tasks complete! Feature marked as done!' if all_done else 'Use /tasks for progress.'}",
        parse_mode="Markdown"
    )


# =============================================================================
# BUG TICKET SYSTEM
# =============================================================================

async def bug_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /bug command - Report a bug."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🐛 *Report a Bug*\n\n"
            "Usage: `/bug [description]`\n\n"
            "Example:\n"
            "`/bug App crashes when opening camera on Android 14`\n\n"
            "Include as much detail as possible:\n"
            "- What happened?\n"
            "- Expected behavior?\n"
            "- Device/Android version?",
            parse_mode="Markdown"
        )
        return
    
    description = " ".join(args)
    user = update.effective_user
    bug_id = f"BUG-{len(BUG_TICKETS) + 1:04d}"
    
    # Store the bug ticket
    BUG_TICKETS[bug_id] = {
        "id": bug_id,
        "description": description,
        "reported_by": user.full_name,
        "user_id": user.id,
        "username": user.username,
        "status": "open",
        "priority": "medium",
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
        "notes": []
    }
    
    keyboard = [
        [InlineKeyboardButton("🔍 View All Bugs", callback_data="dev_list_bugs")],
    ]
    
    await update.message.reply_text(
        f"🐛 *Bug Reported!*\n\n"
        f"*ID:* `{bug_id}`\n"
        f"*Description:* {description[:100]}{'...' if len(description) > 100 else ''}\n\n"
        f"The admin will review your bug report.",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )
    
    # Notify admin
    try:
        admin_keyboard = [
            [InlineKeyboardButton("🔧 Fix Bug", callback_data=f"dev_fix_bug_{bug_id}")],
            [InlineKeyboardButton("❌ Close Bug", callback_data=f"dev_close_bug_{bug_id}")],
            [InlineKeyboardButton("📋 All Bugs", callback_data="dev_list_bugs")],
        ]
        await context.bot.send_message(
            chat_id=int(ADMIN_USER_ID),
            text=f"🐛 *New Bug Report!*\n\n"
                 f"*ID:* `{bug_id}`\n"
                 f"*From:* @{user.username or user.full_name}\n"
                 f"*Bug:* {description[:100]}{'...' if len(description) > 100 else ''}",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(admin_keyboard)
        )
    except Exception as e:
        logger.error(f"Failed to notify admin: {e}")


async def list_bugs_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /bugs command - List all bug tickets."""
    if not BUG_TICKETS:
        await update.message.reply_text(
            "🐛 *Bug Tickets*\n\n"
            "No bugs reported yet! The app is running smoothly! 🎉",
            parse_mode="Markdown"
        )
        return
    
    status_filter = context.args[0].lower() if context.args and context.args[0].lower() in ["open", "fixed", "closed"] else None
    
    text = "🐛 *Bug Tickets*\n\n"
    
    for bug_id, bug in sorted(BUG_TICKETS.items()):
        if status_filter and bug["status"] != status_filter:
            continue
        
        status_emoji = {
            "open": "🔴",
            "in_progress": "🟡",
            "fixed": "🟢",
            "closed": "⚫"
        }.get(bug["status"], "⚪")
        
        priority_indicator = "🔴" if bug["priority"] == "high" else ("🟡" if bug["priority"] == "medium" else "🟢")
        
        text += f"{status_emoji} *{bug_id}* {priority_indicator} - {bug['reported_by']}\n"
        text += f"   {bug['description'][:50]}{'...' if len(bug['description']) > 50 else ''}\n\n"
    
    keyboard = [
        [InlineKeyboardButton("🔴 Open", callback_data="dev_list_bugs_open")],
        [InlineKeyboardButton("🟢 Fixed", callback_data="dev_list_bugs_fixed")],
        [InlineKeyboardButton("⚫ Closed", callback_data="dev_list_bugs_closed")],
    ]
    
    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup(keyboard))


async def view_bug_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /viewbug command - View a specific bug."""
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🔍 *View Bug*\n\n"
            "Usage: `/viewbug [bug-id]`\n\n"
            "Example: `/viewbug BUG-0001`",
            parse_mode="Markdown"
        )
        return
    
    bug_id = args[0].upper()
    
    if bug_id not in BUG_TICKETS:
        await update.message.reply_text(
            f"❌ Bug `{bug_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    bug = BUG_TICKETS[bug_id]
    
    status_text = {
        "open": "🔴 Open",
        "in_progress": "🟡 In Progress",
        "fixed": "🟢 Fixed",
        "closed": "⚫ Closed"
    }.get(bug["status"], bug["status"])
    
    priority_text = {
        "low": "🟢 Low",
        "medium": "🟡 Medium",
        "high": "🔴 High",
        "critical": "🚨 Critical"
    }.get(bug["priority"], bug["priority"])
    
    text = (
        f"🔍 *Bug: {bug_id}*\n\n"
        f"*Status:* {status_text}\n"
        f"*Priority:* {priority_text}\n"
        f"*Reported by:* {bug['reported_by']}\n"
        f"*Date:* {bug['created_at'][:10]}\n\n"
        f"*🐛 Description:*\n"
        f"{bug['description']}\n"
    )
    
    if bug.get("notes"):
        text += f"\n*📝 Notes:*\n"
        for note in bug["notes"]:
            text += f"- {note}\n"
    
    # Add action buttons for admin
    if is_admin(update.effective_user.id, update.effective_user.username):
        keyboard = [
            [InlineKeyboardButton("🔧 Mark Fixed", callback_data=f"dev_fix_bug_{bug_id}")],
            [InlineKeyboardButton("❌ Close Bug", callback_data=f"dev_close_bug_{bug_id}")],
            [InlineKeyboardButton("⬆️ Set High Priority", callback_data=f"dev_bug_priority_high_{bug_id}")],
        ]
        await update.message.reply_text(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup(keyboard))
    else:
        await update.message.reply_text(text, parse_mode="Markdown")


async def fix_bug_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /fixbug command - Mark a bug as fixed (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can update bugs.")
        return
    
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🔧 *Fix Bug*\n\n"
            "Usage: `/fixbug [bug-id] [optional note]`\n\n"
            "Example: `/fixbug BUG-0001 Fixed in commit abc123`",
            parse_mode="Markdown"
        )
        return
    
    bug_id = args[0].upper()
    
    if bug_id not in BUG_TICKETS:
        await update.message.reply_text(f"❌ Bug `{bug_id}` not found.", parse_mode="Markdown")
        return
    
    note = " ".join(args[1:]) if len(args) > 1 else "Marked as fixed"
    BUG_TICKETS[bug_id]["status"] = "fixed"
    BUG_TICKETS[bug_id]["updated_at"] = datetime.now().isoformat()
    BUG_TICKETS[bug_id]["notes"].append(f"[FIXED] {note}")
    
    await update.message.reply_text(
        f"🟢 *Bug {bug_id} Marked as Fixed!*\n\n"
        f"*Note:* {note}",
        parse_mode="Markdown"
    )
    
    # Notify reporter
    bug = BUG_TICKETS[bug_id]
    try:
        await context.bot.send_message(
            chat_id=bug["user_id"],
            text=f"🔧 *Bug Update*\n\n"
                 f"Your bug report ({bug_id}) has been fixed!\n\n"
                 f"*Bug:* {bug['description'][:100]}...\n"
                 f"*Fix:* {note}",
            parse_mode="Markdown"
        )
    except:
        pass


async def close_bug_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /closebug command - Close a bug (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can update bugs.")
        return
    
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "❌ *Close Bug*\n\n"
            "Usage: `/closebug [bug-id] [reason]`\n\n"
            "Example: `/closebug BUG-0001 Cannot reproduce`",
            parse_mode="Markdown"
        )
        return
    
    bug_id = args[0].upper()
    
    if bug_id not in BUG_TICKETS:
        await update.message.reply_text(f"❌ Bug `{bug_id}` not found.", parse_mode="Markdown")
        return
    
    reason = " ".join(args[1:]) if len(args) > 1 else "Closed"
    BUG_TICKETS[bug_id]["status"] = "closed"
    BUG_TICKETS[bug_id]["updated_at"] = datetime.now().isoformat()
    BUG_TICKETS[bug_id]["notes"].append(f"[CLOSED] {reason}")
    
    await update.message.reply_text(
        f"⚫ *Bug {bug_id} Closed!*\n\n"
        f"*Reason:* {reason}",
        parse_mode="Markdown"
    )


async def bug_stats_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /bugstats command - Show bug statistics."""
    total = len(BUG_TICKETS)
    open_count = sum(1 for b in BUG_TICKETS.values() if b["status"] == "open")
    in_progress = sum(1 for b in BUG_TICKETS.values() if b["status"] == "in_progress")
    fixed = sum(1 for b in BUG_TICKETS.values() if b["status"] == "fixed")
    closed = sum(1 for b in BUG_TICKETS.values() if b["status"] == "closed")
    
    high_priority = sum(1 for b in BUG_TICKETS.values() if b["priority"] == "high" and b["status"] == "open")
    
    text = (
        "🐛 *JagSpoor Bug Statistics*\n\n"
        f"*Total Bugs Reported:* {total}\n\n"
        f"🔴 Open: {open_count}\n"
        f"🟡 In Progress: {in_progress}\n"
        f"🟢 Fixed: {fixed}\n"
        f"⚫ Closed: {closed}\n\n"
    )
    
    if high_priority > 0:
        text += f"🚨 *High Priority Open:* {high_priority}\n"
    
    resolution_rate = ((fixed + closed) / total * 100) if total > 0 else 0
    text += f"\n*Resolution Rate:* {resolution_rate:.1f}%"
    
    await update.message.reply_text(text, parse_mode="Markdown")


# =============================================================================
# DEV TOOLS
# =============================================================================

async def status_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command - Show project status."""
    total = len(FEATURE_REQUESTS)
    pending = sum(1 for fr in FEATURE_REQUESTS.values() if fr["status"] == "pending")
    planned = sum(1 for fr in FEATURE_REQUESTS.values() if fr["status"] == "planned")
    approved = sum(1 for fr in FEATURE_REQUESTS.values() if fr["status"] == "approved")
    in_progress = sum(1 for fr in FEATURE_REQUESTS.values() if fr["status"] == "in_progress")
    completed = sum(1 for fr in FEATURE_REQUESTS.values() if fr["status"] == "completed")
    
    text = (
        "📊 *JagSpoor Development Status*\n\n"
        f"*Total Suggestions:* {total}\n\n"
        f"⏳ Pending: {pending}\n"
        f"📝 Planned: {planned}\n"
        f"✅ Approved: {approved}\n"
        f"🔨 In Progress: {in_progress}\n"
        f"🏁 Completed: {completed}\n"
    )
    
    await update.message.reply_text(text, parse_mode="Markdown")


async def dev_help_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /devhelp command - Show development commands."""
    text = """
🔧 *JagSpoor Dev Bot Commands*

*💡 For Everyone:*
/suggest [idea] - Submit a feature idea
/suggestions - View all suggestions
/view [id] - View a specific suggestion
/status - Development status

*👑 Admin Only:*
/plan [id] [plan] - Create implementation plan
/approve [id] - Approve a suggestion
/reject [id] [reason] - Reject a suggestion

*📋 Task Management:*
/addtask [id] [task] - Add a task
/tasks [id] - List tasks for a feature
/donetask [id] [num] - Mark task complete

*🛠️ Dev Tools:*
/gitlog - Recent commits
/diff [branch] - Show changes
/test - Run tests
/build - Build project
"""
    await update.message.reply_text(text, parse_mode="Markdown")


async def gitlog_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /gitlog command - Show recent commits."""
    import subprocess
    
    try:
        result = subprocess.run(
            ["git", "log", "--oneline", "-10"],
            capture_output=True, text=True, timeout=10,
            cwd="/workspace/project/JagSpoor_v4_2"
        )
        
        if result.returncode == 0:
            commits = result.stdout.strip()
            await update.message.reply_text(
                f"📜 *Recent Commits*\n\n```\n{commits}\n```",
                parse_mode="Markdown"
            )
        else:
            await update.message.reply_text("❌ Could not get git log.")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)}")


async def branch_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /branch command - Show current branch."""
    import subprocess
    
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=10,
            cwd="/workspace/project/JagSpoor_v4_2"
        )
        
        if result.returncode == 0:
            branch = result.stdout.strip()
            await update.message.reply_text(
                f"🌿 *Current Branch:* `{branch}`",
                parse_mode="Markdown"
            )
        else:
            await update.message.reply_text("❌ Could not get branch info.")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)}")


async def test_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /test command - Run tests."""
    await update.message.reply_text(
        "🧪 *Running Tests...*\n\n"
        "This feature will be available once the bot has local access to the project.",
        parse_mode="Markdown"
    )


async def build_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /build command - Build project."""
    await update.message.reply_text(
        "🏗️ *Build Project*\n\n"
        "Use `/start_build [feature-id]` to build a feature.\n"
        "Use `/build_apk` to build the full APK.",
        parse_mode="Markdown"
    )


async def start_build_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start_build command - Start the complete build workflow (admin only)."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can start builds.")
        return
    
    args = context.args
    
    if not args:
        await update.message.reply_text(
            "🚀 *Start Build*\n\n"
            "Usage: `/start_build [feature-id] [commit-message]`\n\n"
            "Example:\n"
            "`/start_build FR-0001 Add dark mode feature`\n\n"
            "This will:\n"
            "1. Run flutter analyze\n"
            "2. Commit & push to git\n"
            "3. Build APK\n"
            "4. Provide download link",
            parse_mode="Markdown"
        )
        return
    
    feature_id = args[0].upper()
    commit_message = " ".join(args[1:]) if len(args) > 1 else f"Feature: {feature_id}"
    
    if feature_id not in FEATURE_REQUESTS:
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` not found.",
            parse_mode="Markdown"
        )
        return
    
    fr = FEATURE_REQUESTS[feature_id]
    
    # Check if approved
    if not fr.get("approved"):
        await update.message.reply_text(
            f"❌ Feature `{feature_id}` has not been approved yet.\n"
            f"Use `/approve {feature_id} [plan]` to approve first.",
            parse_mode="Markdown"
        )
        return
    
    # Check tasks completion
    if fr.get("tasks"):
        incomplete = [t for t in fr["tasks"] if t.startswith("[ ]")]
        if incomplete:
            await update.message.reply_text(
                f"⚠️ *Incomplete Tasks*\n\n"
                f"Feature `{feature_id}` has {len(incomplete)} incomplete tasks:\n\n"
                + "\n".join(f"- {t}" for t in incomplete[:5])
                + (f"\n... and {len(incomplete)-5} more" if len(incomplete) > 5 else ""),
                parse_mode="Markdown"
            )
            return
    
    await update.message.reply_text(
        f"🚀 *Starting Build for {feature_id}...*\n\n"
        "Step 1/4: Running Flutter Analyze...",
        parse_mode="Markdown"
    )
    
    import subprocess
    import threading
    
    async def send_message(text):
        await update.message.reply_text(text, parse_mode="Markdown")
    
    def run_build():
        import asyncio
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
        # Set up environment
        env = os.environ.copy()
        env["JAVA_HOME"] = "/workspace/java"
        env["ANDROID_HOME"] = "/workspace/android-sdk"
        env["ANDROID_SDK_ROOT"] = "/workspace/android-sdk"
        env["PATH"] = f"/workspace/flutter/bin:/workspace/java/bin:/workspace/android-sdk/cmdline-tools/latest/bin:/workspace/android-sdk/platform-tools:{env.get('PATH', '')}"
        
        try:
            # Step 1: Analyze
            result = subprocess.run(
                ["/workspace/flutter/bin/flutter", "analyze"],
                capture_output=True, text=True, timeout=300,
                cwd="/workspace/project/JagSpoor_v4_2",
                env=env
            )
            
            output = result.stdout + result.stderr
            error_count = output.count("error •")
            
            if error_count > 0:
                loop.run_until_complete(send_message(
                    f"❌ *Analyze Failed!*\n\n"
                    f"Found {error_count} errors. Fix them before building."
                ))
                loop.close()
                return
            
            loop.run_until_complete(send_message(
                f"✅ *Step 1/4 Complete: Analyze*\n\n"
                "No errors found!\n\n"
                "Step 2/4: Committing & pushing to git..."
            ))
            
            # Step 2: Commit & Push
            subprocess.run(["git", "add", "-A"], cwd="/workspace/project/JagSpoor_v4_2", check=True)
            
            commit_result = subprocess.run(
                ["git", "commit", "-m", f"{commit_message}\n\nFeature: {feature_id}\n\nCo-authored-by: OpenHands Bot <bot@openhands.dev>"],
                cwd="/workspace/project/JagSpoor_v4_2",
                capture_output=True, text=True
            )
            
            if commit_result.returncode != 0 and "nothing to commit" not in commit_result.stdout.lower():
                loop.run_until_complete(send_message(f"❌ *Commit failed:*\n```\n{commit_result.stderr[-500:]}\n```"))
                loop.close()
                return
            
            # Push
            remote_result = subprocess.run(
                ["git", "remote", "get-url", "origin"],
                cwd="/workspace/project/JagSpoor_v4_2",
                capture_output=True, text=True
            )
            remote_url = remote_result.stdout.strip() if remote_result.returncode == 0 else ""
            if "GITHUB_TOKEN" in os.environ and "github.com" in remote_url:
                token = os.environ.get("GITHUB_TOKEN")
                new_url = remote_url.replace("https://", f"https://{token}@")
                subprocess.run(["git", "remote", "set-url", "origin", new_url], cwd="/workspace/project/JagSpoor_v4_2")
            
            push_result = subprocess.run(
                ["git", "push", "origin", "main"],
                cwd="/workspace/project/JagSpoor_v4_2",
                capture_output=True, text=True, timeout=60
            )
            
            if push_result.returncode != 0:
                loop.run_until_complete(send_message(f"⚠️ *Push skipped:* Unable to push. Code is committed locally."))
            else:
                loop.run_until_complete(send_message(
                    f"✅ *Step 2/4 Complete: Committed & Pushed*\n\n"
                    "Step 3/4: Building APK..."
                ))
            
            # Step 3: Build APK
            loop.run_until_complete(send_message("🏗️ *Step 3/4: Building APK...*"))
            
            build_result = subprocess.run(
                ["/workspace/flutter/bin/flutter", "build", "apk", "--debug"],
                capture_output=True, text=True, timeout=600,
                cwd="/workspace/project/JagSpoor_v4_2",
                env=env
            )
            
            if build_result.returncode != 0:
                loop.run_until_complete(send_message(
                    f"❌ *Build Failed*\n\n```\n{build_result.stderr[-1000:]}\n```"
                ))
                loop.close()
                return
            
            # Find APK
            apk_result = subprocess.run(
                ["find", "/workspace/project/JagSpoor_v4_2/build", "-name", "*.apk"],
                capture_output=True, text=True
            )
            apk_paths = [p for p in apk_result.stdout.strip().split('\n') if 'app-debug' in p]
            
            if apk_paths:
                apk_path = apk_paths[0]
                dest_path = "/workspace/project/JagSpoor_v4_2/telegram_bot/jagspoor_latest.apk"
                subprocess.run(["cp", apk_path, dest_path])
                size_mb = os.path.getsize(dest_path) / (1024*1024)
                
                # Update feature status
                FEATURE_REQUESTS[feature_id]["status"] = "completed"
                
                loop.run_until_complete(send_message(
                    f"🎉 *BUILD COMPLETE!*\n\n"
                    f"✅ Step 1: Analyze - Passed\n"
                    f"✅ Step 2: Commit & Push - Done\n"
                    f"✅ Step 3: Build APK - Done\n\n"
                    f"📦 *APK Ready!*\n"
                    f"Size: {size_mb:.1f} MB\n"
                    f"Location: `/workspace/project/JagSpoor_v4_2/telegram_bot/jagspoor_latest.apk`\n\n"
                    f"🚀 Feature {feature_id} is complete!"
                ))
            else:
                loop.run_until_complete(send_message("⚠️ Build succeeded but APK not found."))
            
        except subprocess.TimeoutExpired:
            loop.run_until_complete(send_message("❌ Build timed out."))
        except Exception as e:
            loop.run_until_complete(send_message(f"❌ Error: {str(e)}"))
        finally:
            loop.close()
    
    # Run build in background
    thread = threading.Thread(target=run_build)
    thread.start()


async def analyze_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /analyze command - Run flutter analyze."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can run analysis.")
        return
    
    import subprocess
    
    await update.message.reply_text(
        "🔍 *Running Flutter Analyze...*\n\n"
        "This may take a moment.",
        parse_mode="Markdown"
    )
    
    # Set up environment
    env = os.environ.copy()
    env["JAVA_HOME"] = "/workspace/java"
    env["ANDROID_HOME"] = "/workspace/android-sdk"
    env["ANDROID_SDK_ROOT"] = "/workspace/android-sdk"
    env["PATH"] = f"/workspace/flutter/bin:/workspace/java/bin:/workspace/android-sdk/cmdline-tools/latest/bin:/workspace/android-sdk/platform-tools:{env.get('PATH', '')}"
    
    try:
        result = subprocess.run(
            ["flutter", "analyze"],
            capture_output=True, text=True, timeout=300,
            cwd="/workspace/project/JagSpoor_v4_2",
            env=env
        )
        
        output = result.stdout + result.stderr
        
        # Count issues
        error_count = output.count("error •")
        warning_count = output.count("warning •")
        info_count = output.count("info •")
        
        # Parse for issues
        if "No issues found!" in output:
            keyboard = [[InlineKeyboardButton("✅ Commit & Push", callback_data="dev_commit_push")]]
            await update.message.reply_text(
                "✅ *Flutter Analyze: No Issues Found!*\n\n"
                "The code is clean and ready to commit!",
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        else:
            # Show summary and first 15 lines
            lines = output.split('\n')
            issues_lines = [l for l in lines if '•' in l][:15]
            issues_text = '\n'.join(issues_lines) if issues_lines else output[-500:]
            
            # Truncate if too long (Telegram limit is ~4096)
            if len(issues_text) > 1000:
                issues_text = issues_text[:1000] + "\n... (truncated)"
            
            keyboard = []
            if error_count == 0:
                keyboard.append(
                    [InlineKeyboardButton("✅ Commit Anyway", callback_data="dev_commit_push")]
                )
            
            summary = f"⚠️ *Analysis Complete*\n\n"
            summary += f"*Errors:* {error_count} ❌\n"
            summary += f"*Warnings:* {warning_count} ⚠️\n"
            summary += f"*Info:* {info_count} ℹ️\n\n"
            summary += f"*Issues:*\n```\n{issues_text}\n```"
            
            # Truncate entire message if needed
            if len(summary) > 4000:
                summary = summary[:4000] + "\n```\n... (truncated)"
            
            await update.message.reply_text(
                summary,
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup(keyboard) if keyboard else None
            )
            
    except subprocess.TimeoutExpired:
        await update.message.reply_text("❌ Analysis timed out.")
    except FileNotFoundError:
        await update.message.reply_text("❌ Flutter not found. Install Flutter SDK.")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)}")


async def commit_push_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /commit command - Commit and push changes."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can commit.")
        return
    
    import subprocess
    
    args = context.args
    commit_message = " ".join(args) if args else "Update from Telegram bot"
    
    await update.message.reply_text(
        f"📦 *Committing Changes...*\n\n"
        f"Message: `{commit_message}`",
        parse_mode="Markdown"
    )
    
    try:
        # Stage all changes
        subprocess.run(["git", "add", "-A"], cwd="/workspace/project/JagSpoor_v4_2", check=True)
        
        # Commit
        result = subprocess.run(
            ["git", "commit", "-m", f"{commit_message}\n\nCo-authored-by: OpenHands Bot <bot@openhands.dev>"],
            cwd="/workspace/project/JagSpoor_v4_2",
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            if "nothing to commit" in result.stdout.lower():
                await update.message.reply_text("ℹ️ Nothing to commit - working tree is clean.")
                return
            await update.message.reply_text(f"❌ Commit failed:\n```\n{result.stderr}\n```", parse_mode="Markdown")
            return
        
        # Push (get remote URL to check if we have token)
        remote_result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd="/workspace/project/JagSpoor_v4_2",
            capture_output=True, text=True
        )
        
        remote_url = remote_result.stdout.strip() if remote_result.returncode == 0 else ""
        
        # If GITHUB_TOKEN is available and URL is https, add it
        if "GITHUB_TOKEN" in os.environ and "github.com" in remote_url and remote_url.startswith("https://"):
            token = os.environ.get("GITHUB_TOKEN")
            new_url = remote_url.replace("https://", f"https://{token}@")
            subprocess.run(["git", "remote", "set-url", "origin", new_url], cwd="/workspace/project/JagSpoor_v4_2")
        
        result = subprocess.run(
            ["git", "push", "origin", "main"],
            cwd="/workspace/project/JagSpoor_v4_2",
            capture_output=True, text=True, timeout=60
        )
        
        if result.returncode == 0:
            await update.message.reply_text(
                "✅ *Successfully Committed & Pushed!*\n\n"
                "Changes are now on GitHub.",
                parse_mode="Markdown"
            )
        else:
            await update.message.reply_text(f"❌ Push failed:\n```\n{result.stderr}\n```", parse_mode="Markdown")
            
    except subprocess.TimeoutExpired:
        await update.message.reply_text("❌ Push timed out.")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)}")


async def build_apk_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /build_apk command - Build debug APK."""
    if not is_admin(update.effective_user.id, update.effective_user.username):
        await update.message.reply_text("❌ Only the admin can build APK.")
        return
    
    import subprocess
    import threading
    
    await update.message.reply_text(
        "🏗️ *Building APK...*\n\n"
        "This will take a few minutes. I'll notify you when it's done.",
        parse_mode="Markdown"
    )
    
    async def send_message(text):
        await update.message.reply_text(text, parse_mode="Markdown")
    
    def run_build():
        # Set up environment
        env = os.environ.copy()
        env["JAVA_HOME"] = "/workspace/java"
        env["ANDROID_HOME"] = "/workspace/android-sdk"
        env["ANDROID_SDK_ROOT"] = "/workspace/android-sdk"
        env["PATH"] = f"/workspace/flutter/bin:/workspace/java/bin:/workspace/android-sdk/cmdline-tools/latest/bin:/workspace/android-sdk/platform-tools:{env.get('PATH', '')}"
        
        try:
            # Build the APK
            result = subprocess.run(
                ["/workspace/flutter/bin/flutter", "build", "apk", "--debug"],
                capture_output=True, text=True, timeout=600,
                cwd="/workspace/project/JagSpoor_v4_2",
                env=env
            )
            
            output = result.stdout + result.stderr
            
            if result.returncode == 0:
                # Find the APK path
                apk_result = subprocess.run(
                    ["find", "/workspace/project/JagSpoor_v4_2/build", "-name", "*.apk"],
                    capture_output=True, text=True
                )
                apk_paths = [p for p in apk_result.stdout.strip().split('\n') if 'app-debug' in p]
                
                if apk_paths:
                    apk_path = apk_paths[0]
                    dest_path = "/workspace/project/JagSpoor_v4_2/telegram_bot/jagspoor_latest.apk"
                    subprocess.run(["cp", apk_path, dest_path])
                    size_mb = os.path.getsize(dest_path) / (1024*1024)
                    
                    # Send message in new event loop
                    import asyncio
                    loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(loop)
                    loop.run_until_complete(send_message(
                        f"✅ *APK Build Complete!*\n\n"
                        f"📁 Size: {size_mb:.1f} MB\n\n"
                        f"Location: `{dest_path}`\n\n"
                        "The APK is ready for download!"
                    ))
                    loop.close()
                else:
                    loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(loop)
                    loop.run_until_complete(send_message("⚠️ Build succeeded but APK path not found."))
                    loop.close()
            else:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                loop.run_until_complete(send_message(f"❌ *Build Failed*\n\n```\n{output[-2000:]}\n```"))
                loop.close()
        except subprocess.TimeoutExpired:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            loop.run_until_complete(send_message("❌ Build timed out (10 min limit)."))
            loop.close()
        except Exception as e:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            loop.run_until_complete(send_message(f"❌ Error: {str(e)}"))
            loop.close()
    
    # Run build in background thread
    thread = threading.Thread(target=run_build)
    thread.start()
