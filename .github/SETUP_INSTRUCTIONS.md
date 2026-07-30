# GitHub Actions Setup for Jagspoor

## Required GitHub Secrets

Go to your repository Settings → Secrets and Variables → Actions and add:

### 1. FIREBASE_SERVICE_ACCOUNT
This is a JSON key for a Firebase service account with App Distribution permissions.

**How to get it:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings → Service Accounts
4. Click "Generate new private key"
5. Copy the entire JSON content

**Paste this as the secret value.**

### 2. GOOGLE_SERVICES_JSON
This is the google-services.json file for your Android app.

**How to get it:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project → Project Settings
3. Under "Your apps", download the `google-services.json`

### 3. TESTER_EMAILS (Optional)
Comma-separated list of email addresses to notify of new builds.
Example: `tester1@email.com,tester2@email.com`

### 4. DISCORD_WEBHOOK (Optional)
Discord webhook URL for deployment notifications.

---

## Firebase App Distribution Setup

### 1. Enable App Distribution
1. Go to Firebase Console → App Distribution
2. Accept terms of service if prompted

### 2. Create Tester Group
1. In Firebase Console → App Distribution → Testers & Groups
2. Create a group called "testers"
3. Add email addresses of your dev team

### 3. Add Service Account Permissions
The service account needs these roles:
- Firebase App Distribution Admin
- Firebase Admin (or broader permissions)

---

## GitHub Variables (non-secrets)

Go to Settings → Variables and add:

- `DISCORD_WEBHOOK` - Your Discord webhook URL (can be a variable, not secret)

---

## Testing the Workflow

1. Push a commit to `main` branch
2. Go to Actions tab in GitHub
3. Watch the workflow run
4. Check Firebase App Distribution for the new build

---

## How It Works

1. **Push to main** → Triggers workflow
2. **Build** → Creates debug APK (Android) and iOS build
3. **Deploy** → Uploads to Firebase App Distribution
4. **Email** → Firebase automatically emails all testers in the "testers" group
5. **Notification** → Sends Discord notification if configured

---

## Manual Trigger

You can also trigger builds manually:
1. Go to Actions → Build & Deploy
2. Click "Run workflow"
3. Optionally add release notes
