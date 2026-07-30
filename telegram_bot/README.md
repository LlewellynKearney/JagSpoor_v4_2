# 🦌 JagSpoor Telegram Bot

A comprehensive Telegram bot for the JagSpoor hunting app, providing quick access to hunting data, ballistics calculations, and outfitter management.

## Features

- **User Authentication** - Profile management and settings
- **Firearms & Licensing** - Track your firearms and license status
- **Ballistics Calculator** - DOPE cards, zero calculations, ammunition search
- **Navigation & Tracking** - Waypoints, GPS location, blood trail logging
- **Outfitter Tools** - Booking management, client roster, revenue tracking
- **Notifications** - Customizable alerts and subscriptions
- **Hunt Statistics** - Hunt logs and safari summaries

## Quick Setup

### Option 1: Polling Mode (Easiest - for local development)

```bash
cd telegram_bot
pip install -r requirements.txt
python bot.py
```

### Option 2: Webhook Mode (Production - requires public URL)

```bash
# 1. Run the setup script
python setup_webhook.py

# 2. Configure your webhook URL
export WEBHOOK_URL="https://your-public-url.com"
export WEBHOOK_SECRET="your_generated_secret"

# 3. Run the webhook server
python webhook_server.py
```

### Option 3: Docker (Recommended for production)

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your values

# 2. Build and run
docker-compose up -d
```

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Your Telegram bot token |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | No | Firebase service account JSON |
| `WEBHOOK_URL` | For webhook | Public HTTPS URL for webhook |
| `WEBHOOK_SECRET` | For webhook | Secret token for webhook verification |
| `PORT` | No | Server port (default: 8080) |

### Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a project (or use existing)
3. Go to Project Settings → Service Accounts
4. Generate new private key
5. Copy the JSON and either:
   - Set as `FIREBASE_SERVICE_ACCOUNT_JSON` environment variable
   - Save as `service_account.json` file

## Commands

### General
| Command | Description |
|---------|-------------|
| `/start` | Welcome menu |
| `/help` | Show all commands |
| `/profile` | View your profile |
| `/settings` | Configure preferences |

### Firearms & Licensing
| Command | Description |
|---------|-------------|
| `/firearms` | List your firearms |
| `/license STATUS` | Check license status |
| `/license RENEW` | Get renewal reminder |

### Ballistics
| Command | Description |
|---------|-------------|
| `/ballistics` | Ballistics menu |
| `/dope [distance]` | Calculate holdover for distance |
| `/zero [range]` | Zero your rifle |
| `/ammo [name]` | Search ammunition |

### Navigation
| Command | Description |
|---------|-------------|
| `/location` | Share GPS location |
| `/waypoints` | List waypoints |
| `/bloodtrail [text]` | Log blood trail sighting |
| `/offline` | Get offline maps |

### Outfitter (role-based)
| Command | Description |
|---------|-------------|
| `/bookings` | View bookings |
| `/clients` | List clients |
| `/trophies` | Trophy inventory |
| `/revenue` | Revenue summary |
| `/permit [id]` | Generate permit |

### Notifications
| Command | Description |
|---------|-------------|
| `/subscribe [event]` | Subscribe to notifications |
| `/unsubscribe [event]` | Unsubscribe |
| `/alerts` | View active alerts |
| `/weather` | Current weather |

### Stats
| Command | Description |
|---------|-------------|
| `/huntlog` | Hunt history |
| `/safari [date]` | Safari summary |

---

## 🔧 Development Commands

*For the JagSpoor development team and admin*

### Feature Suggestions (Everyone)
| Command | Description |
|---------|-------------|
| `/suggest [idea]` | Submit a feature idea |
| `/suggestions` | View all suggestions |
| `/view [id]` | View a specific suggestion |
| `/status` | Development status overview |

### Admin Workflow

**Step 1: Approve & Plan**
| Command | Description |
|---------|-------------|
| `/approve [id] [plan]` | Approve + create plan in one command |
| `/reject [id] [reason]` | Reject a suggestion |

**Step 2: Track Tasks**
| Command | Description |
|---------|-------------|
| `/addtask [id] [task]` | Add a task to a feature |
| `/tasks [id]` | List tasks for a feature |
| `/donetask [id] [num]` | Mark task as complete |

**Step 3: Build**
| Command | Description |
|---------|-------------|
| `/start_build [id] [msg]` | Start complete build workflow |
| `/analyze` | Run flutter analyze |
| `/commit [msg]` | Commit & push to git |
| `/build_apk` | Build debug APK |

### Bug Tracking
| Command | Description |
|---------|-------------|
| `/bug [description]` | Report a bug |
| `/bugs` | List all bugs |
| `/viewbug [id]` | View bug details |
| `/bugstats` | Bug statistics |

### Admin Bug Commands
| Command | Description |
|---------|-------------|
| `/fixbug [id] [note]` | Mark bug as fixed |
| `/closebug [id] [reason]` | Close a bug |

### Dev Tools (Admin Only)
| Command | Description |
|---------|-------------|
| `/analyze` | Run `flutter analyze` |
| `/commit [msg]` | Commit and push to git |
| `/build_apk` | Build debug APK |
| `/gitlog` | Recent git commits |
| `/branch` | Current git branch |
| `/test` | Run tests |
| `/devhelp` | Show all dev commands |

## Firebase Integration

The bot connects to your Firebase Firestore database. Make sure you have:

1. A Firebase project with Firestore enabled
2. A service account with Firestore read/write permissions
3. The service account JSON exported as `FIREBASE_SERVICE_ACCOUNT_JSON`

### Required Firestore Collections

- `users` - User profiles (with `telegramId` field)
- `firearms` - Firearm registrations
- `bookings` - Hunting bookings
- `trophies` - Trophy stock
- `waypoints` - GPS waypoints
- `ammunition` - Ammunition database
- `bloodtrails` - Blood trail logs

## Polling vs Webhook

The bot uses **polling mode** by default, which means it continuously checks Telegram for new messages.

To switch to **webhook mode** (recommended for production):

```python
# In bot.py, replace run_polling with:
application.run_webhook(
    listen="0.0.0.0",
    port=8443,
    url_path="webhook",
    webhook_url="https://your-domain.com/webhook"
)
```

## Troubleshooting

### Pending Updates
If you see "3 pending updates" when checking `getUpdates`, the bot may have been offline. The `drop_pending_updates=True` flag in `run_polling()` clears these.

### Firebase Connection
If Firebase isn't connecting, check:
1. Service account JSON is valid
2. Environment variable is set correctly
3. Firestore permissions are configured

## License

MIT License - See LICENSE file for details.
