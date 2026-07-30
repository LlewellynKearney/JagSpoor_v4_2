"""
Firebase Service for JagSpoor Telegram Bot
Handles all Firebase Firestore interactions.
"""

import os
import json
import logging
from typing import Dict, List, Optional, Any
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes
from datetime import datetime

logger = logging.getLogger(__name__)


class FirebaseService:
    """Service class for Firebase operations."""
    
    def __init__(self):
        """Initialize Firebase connection."""
        self._initialized = False
        self._db = None
        self._initialize_firebase()
    
    def _initialize_firebase(self):
        """Initialize Firebase Admin SDK."""
        try:
            import firebase_admin
            from firebase_admin import credentials, firestore
            
            # Check if already initialized
            if firebase_admin._apps:
                self._db = firestore.client()
                self._initialized = True
                logger.info("Firebase already initialized")
                return
            
            # Try to load from environment variable
            service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            if service_account_json:
                cred = credentials.Certificate(json.loads(service_account_json))
                firebase_admin.initialize_app(cred)
                self._db = firestore.client()
                self._initialized = True
                logger.info("Firebase initialized from environment variable")
                return
            
            # Try to load from file
            service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "service_account.json")
            if os.path.exists(service_account_path):
                cred = credentials.Certificate(service_account_path)
                firebase_admin.initialize_app(cred)
                self._db = firestore.client()
                self._initialized = True
                logger.info("Firebase initialized from file")
                return
            
            logger.warning("Firebase not initialized - no credentials found")
            
        except ImportError:
            logger.warning("firebase-admin not installed - using mock data")
        except Exception as e:
            logger.error(f"Firebase initialization error: {e}")
    
    async def get_user(self, telegram_id: str) -> Optional[Dict]:
        """Get user by Telegram ID."""
        if not self._initialized:
            return self._get_mock_user(telegram_id)
        
        try:
            users_ref = self._db.collection("users")
            query = users_ref.where("telegramId", "==", telegram_id).limit(1)
            docs = query.get()
            if docs:
                return docs[0].to_dict()
            return None
        except Exception as e:
            logger.error(f"Error getting user: {e}")
            return self._get_mock_user(telegram_id)
    
    def _get_mock_user(self, telegram_id: str) -> Dict:
        """Return mock user data for testing."""
        return {
            "id": telegram_id,
            "name": "Test Hunter",
            "role": "hunter",  # or "outfitter"
            "telegramId": telegram_id,
            "firearmsCount": 2,
            "trophiesCount": 5,
            "huntsCompleted": 12,
        }
    
    async def get_user_firearms(self, user_id: str) -> List[Dict]:
        """Get user's registered firearms."""
        if not self._initialized:
            return self._get_mock_firearms()
        
        try:
            firearms_ref = self._db.collection("firearms").where("userId", "==", user_id)
            docs = firearms_ref.get()
            return [doc.to_dict() for doc in docs]
        except Exception as e:
            logger.error(f"Error getting firearms: {e}")
            return self._get_mock_firearms()
    
    def _get_mock_firearms(self) -> List[Dict]:
        """Return mock firearms data."""
        return [
            {"id": "1", "make": "Ruger", "model": "M77", "caliber": ".270 Winchester", "licenseExpiry": "2026-12-31"},
            {"id": "2", "make": "Browning", "model": "X-Bolt", "caliber": "7mm Rem Mag", "licenseExpiry": "2027-06-15"},
        ]
    
    async def get_bookings(self, user_id: str, role: str = "outfitter") -> List[Dict]:
        """Get bookings for an outfitter or hunter."""
        if not self._initialized:
            return self._get_mock_bookings()
        
        try:
            bookings_ref = self._db.collection("bookings")
            if role == "outfitter":
                query = bookings_ref.where("outfitterId", "==", user_id)
            else:
                query = bookings_ref.where("hunterId", "==", user_id)
            docs = query.get()
            return [doc.to_dict() for doc in docs]
        except Exception as e:
            logger.error(f"Error getting bookings: {e}")
            return self._get_mock_bookings()
    
    def _get_mock_bookings(self) -> List[Dict]:
        """Return mock bookings data."""
        return [
            {"id": "b1", "client": "John Smith", "species": "Kudu", "date": "2026-08-15", "status": "pending"},
            {"id": "b2", "client": "Jane Doe", "species": "Warthog", "date": "2026-09-01", "status": "confirmed"},
        ]
    
    async def get_trophies(self, user_id: str = None, outfitter_id: str = None) -> List[Dict]:
        """Get trophy stock."""
        if not self._initialized:
            return self._get_mock_trophies()
        
        try:
            trophies_ref = self._db.collection("trophies")
            if outfitter_id:
                query = trophies_ref.where("outfitterId", "==", outfitter_id)
            elif user_id:
                query = trophies_ref.where("hunterId", "==", user_id)
            else:
                query = trophies_ref
            docs = query.limit(20).get()
            return [doc.to_dict() for doc in docs]
        except Exception as e:
            logger.error(f"Error getting trophies: {e}")
            return self._get_mock_trophies()
    
    def _get_mock_trophies(self) -> List[Dict]:
        """Return mock trophies data."""
        return [
            {"id": "t1", "species": "Kudu", "count": 5, "location": "Limpopo"},
            {"id": "t2", "species": "Impala", "count": 12, "location": "Mpumalanga"},
            {"id": "t3", "species": "Warthog", "count": 8, "location": "Limpopo"},
        ]
    
    async def get_waypoints(self, user_id: str) -> List[Dict]:
        """Get user's waypoints."""
        if not self._initialized:
            return self._get_mock_waypoints()
        
        try:
            waypoints_ref = self._db.collection("waypoints").where("userId", "==", user_id)
            docs = waypoints_ref.get()
            return [doc.to_dict() for doc in docs]
        except Exception as e:
            logger.error(f"Error getting waypoints: {e}")
            return self._get_mock_waypoints()
    
    def _get_mock_waypoints(self) -> List[Dict]:
        """Return mock waypoints data."""
        return [
            {"id": "w1", "name": "Camp Alpha", "lat": -25.7479, "lon": 28.2293, "type": "camp"},
            {"id": "w2", "name": "Waterhole", "lat": -25.7520, "lon": 28.2350, "type": "water"},
            {"id": "w3", "name": "Blind 1", "lat": -25.7550, "lon": 28.2400, "type": "blind"},
        ]
    
    async def search_ammo(self, query: str) -> List[Dict]:
        """Search ammunition database."""
        if not self._initialized:
            return self._get_mock_ammo(query)
        
        try:
            ammo_ref = self._db.collection("ammunition")
            docs = ammo_ref.limit(10).get()
            results = []
            for doc in docs:
                data = doc.to_dict()
                if query.lower() in str(data).lower():
                    results.append(data)
            return results
        except Exception as e:
            logger.error(f"Error searching ammo: {e}")
            return self._get_mock_ammo(query)
    
    def _get_mock_ammo(self, query: str) -> List[Dict]:
        """Return mock ammunition data."""
        ammo_list = [
            {"brand": "Federal", "name": "Premium 7mm Rem Mag", "grain": 154, "bc": 0.487, "muzzle_vel": 2980},
            {"brand": "Nosler", "name": "AccuBond 7mm", "grain": 160, "bc": 0.511, "muzzle_vel": 2900},
            {"brand": "Hornady", "name": "Superformance .270", "grain": 130, "bc": 0.400, "muzzle_vel": 3140},
            {"brand": "Remington", "name": "Core-Lokt .270", "grain": 140, "bc": 0.385, "muzzle_vel": 2900},
        ]
        return [a for a in ammo_list if query.lower() in str(a).lower()] or ammo_list[:3]
    
    async def get_revenue_summary(self, outfitter_id: str) -> Dict:
        """Get revenue summary for outfitter."""
        if not self._initialized:
            return self._get_mock_revenue()
        
        try:
            # This would aggregate booking totals
            bookings = await self.get_bookings(outfitter_id, "outfitter")
            total = sum(b.get("totalPrice", 0) for b in bookings)
            return {"totalRevenue": total, "bookingsCount": len(bookings)}
        except Exception as e:
            logger.error(f"Error getting revenue: {e}")
            return self._get_mock_revenue()
    
    def _get_mock_revenue(self) -> Dict:
        """Return mock revenue data."""
        return {
            "totalRevenue": 125000,
            "currency": "ZAR",
            "bookingsCount": 8,
            "thisMonth": 45000,
            "pendingPayments": 25000,
        }
    
    async def log_bloodtrail(self, user_id: str, data: Dict) -> bool:
        """Log a blood trail sighting."""
        if not self._initialized:
            logger.info(f"Mock: Blood trail logged for user {user_id}")
            return True
        
        try:
            self._db.collection("bloodtrails").add({
                "userId": user_id,
                "timestamp": datetime.now(),
                **data
            })
            return True
        except Exception as e:
            logger.error(f"Error logging blood trail: {e}")
            return False
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle inline keyboard callbacks."""
        query = update.callback_query
        await query.answer()
        
        # Parse callback data
        data = query.data
        user_id = query.from_user.id
        
        if data == "settings_notifications":
            await query.edit_message_text("🔔 Notification Settings:\n\nEnabled:\n✅ Booking updates\n✅ Weather alerts\n✅ Blood trail notifications")
        elif data == "settings_profile":
            await query.edit_message_text("⚙️ Profile Settings:\n\nEdit your profile details here.")
        elif data == "back_main":
            keyboard = self._get_main_menu_keyboard()
            await query.edit_message_text(
                "🦌 Welcome to JagSpoor Bot!\n\nWhat would you like to do?",
                reply_markup=keyboard
            )
        # Dev callbacks - handle inline button clicks
        elif data == "dev_commit_push":
            await query.edit_message_text(
                "🚀 Use `/commit [message]` to commit and push to git.\n\n"
                "Or use `/start_build [feature-id] [message]` for the full build workflow.",
                parse_mode="Markdown"
            )
        elif data == "dev_list_suggestions":
            await query.edit_message_text("Use `/suggestions` to view all suggestions.")
        elif data.startswith("dev_review_"):
            feature_id = data.replace("dev_review_", "")
            await query.edit_message_text(f"Use `/view {feature_id}` to review suggestion {feature_id}.")
        elif data.startswith("dev_view_tasks_"):
            feature_id = data.replace("dev_view_tasks_", "")
            await query.edit_message_text(f"Use `/tasks {feature_id}` to view tasks for {feature_id}.")
        elif data.startswith("dev_start_build_"):
            feature_id = data.replace("dev_start_build_", "")
            await query.edit_message_text(
                f"🚀 Use `/start_build {feature_id} [commit message]` to build this feature.",
                parse_mode="Markdown"
            )
        elif data.startswith("dev_fix_bug_"):
            bug_id = data.replace("dev_fix_bug_", "")
            await query.edit_message_text(f"Use `/fixbug {bug_id} [note]` to mark bug {bug_id} as fixed.")
        elif data.startswith("dev_close_bug_"):
            bug_id = data.replace("dev_close_bug_", "")
            await query.edit_message_text(f"Use `/closebug {bug_id} [reason]` to close bug {bug_id}.")
        elif data == "dev_list_bugs":
            await query.edit_message_text("Use `/bugs` to view all bug tickets.")
        elif data == "dev_list_bugs_open":
            await query.edit_message_text("Use `/bugs open` to view open bugs.")
        elif data == "dev_list_bugs_fixed":
            await query.edit_message_text("Use `/bugs fixed` to view fixed bugs.")
        elif data == "dev_list_bugs_closed":
            await query.edit_message_text("Use `/bugs closed` to view closed bugs.")
        elif data.startswith("dev_bug_priority_high_"):
            bug_id = data.replace("dev_bug_priority_high_", "")
            await query.edit_message_text(f"Use `/fixbug {bug_id} [note]` to set priority and fix bug.")
    
    def _get_main_menu_keyboard(self) -> InlineKeyboardMarkup:
        """Get main menu keyboard."""
        keyboard = [
            [InlineKeyboardButton("🎯 Ballistics", callback_data="menu_ballistics")],
            [InlineKeyboardButton("🔫 Firearms", callback_data="menu_firearms")],
            [InlineKeyboardButton("🗺️ Navigation", callback_data="menu_navigation")],
            [InlineKeyboardButton("🔔 Notifications", callback_data="menu_notifications")],
            [InlineKeyboardButton("⚙️ Settings", callback_data="settings_profile")],
        ]
        return InlineKeyboardMarkup(keyboard)
