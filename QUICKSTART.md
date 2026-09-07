# ⚡ Quick Start - SquadIQ

## 📋 Prerequisites

- Flutter SDK installed
- Supabase account
- (Optional) Supabase CLI for easier setup

---

## 🚀 3-Step Setup

### Step 1: Apply Database Schema

**Option A: Manual (Dashboard)**
1. Open: https://supabase.com/dashboard/project/YOUR_PROJECT/editor
2. Copy all content from `supabase/schema.sql`
3. Paste in SQL Editor → Click **Run**

**Option B: Using PowerShell Script**
```powershell
.\apply-schema.ps1
```

### Step 2: Setup Environment Variables

```powershell
# Copy the example file
Copy-Item .env.example .env

# Edit .env and add your credentials
notepad .env
```

Get your credentials from:
- URL: https://supabase.com/dashboard/project/YOUR_PROJECT/settings/api
- Copy **Project URL** → `SUPABASE_URL`
- Copy **anon public** key → `SUPABASE_ANON_KEY`

### Step 3: Run the App

**⚠️ For Web Users:** You need to deploy the FPL proxy first to fix CORS:

```powershell
.\deploy-functions.ps1
```

See **`CORS-FIX.md`** for details.

**Then run:**

```powershell
# Using the convenience script (recommended)
.\run.ps1

# Or manually
flutter run `
  --dart-define=SUPABASE_URL=your-url `
  --dart-define=SUPABASE_ANON_KEY=your-key
```

---

## ✅ Verify Setup

After running, you should see:
1. ✅ Sign In/Sign Up screen
2. ✅ Create account & login
3. ✅ Link FPL Manager ID screen
4. ✅ Dashboard with deadline countdown

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Missing config" screen | Check `.env` file exists and has correct values |
| Database errors | Verify `schema.sql` was applied successfully |
| Auth errors | Enable Email Auth in Supabase Dashboard → Authentication → Providers |
| Can't find Supabase project | Make sure you created a project at supabase.com |

---

## 📚 Next Steps

1. Read `SETUP.md` for detailed setup guide
2. Read `README.md` to understand architecture & stubs
3. Run `flutter test` to verify everything works
4. Check `lib/features/` to explore the codebase

---

## 🔒 Security Notes

- ✅ `.env` is in `.gitignore` - never commit it!
- ✅ Use **anon key** in Flutter app (protected by RLS)
- ❌ Never use **service_role** key in client code
- ✅ API keys for AI go in Edge Functions (server-side only)

---

## 📱 Features Status

| Feature | Status | Notes |
|---------|--------|-------|
| Auth | ✅ Working | Email/password only |
| Dashboard | ✅ Working | Shows squad, deadline, fixtures |
| Statistics Engine | ✅ Working | Player ratings, expected points |
| Emergency Coach | ✅ Working | Detects issues, suggests fixes |
| AI Assistant | ✅ Working | Needs Edge Function deployed |
| Players Browser | ✅ Working | Search/filter players |
| Transfers | ✅ Working | Suggestions only (read-only) |
| Fixtures | ✅ Working | Gameweek-tabbed view |
| Settings | ✅ Working | Notification prefs, AI tone |
| Wallet | ⚠️ Read-only | No purchase flow yet |
| Shop | ⚠️ Placeholder | Button doesn't work (stub) |
| Push Notifications | ❌ Not wired | Local notifications only |

See README.md for detailed feature status and known stubs.
