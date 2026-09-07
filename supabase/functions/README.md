# Supabase Edge Functions

## Functions Overview

### 1. `fpl-proxy`
**Purpose:** Acts as a CORS proxy for FPL API calls from web browsers.

**Why needed:** FPL's API doesn't include CORS headers, so direct calls from web browsers fail. This proxy forwards requests server-side and adds proper CORS headers.

**Usage:** Automatically used by `FplProvider` when running on web platform.

### 2. `ai-assistant`
**Purpose:** Handles AI chat interactions using Anthropic Claude API.

**Why server-side:** API keys must never be exposed in client code (security).

---

## Deployment Instructions

### Prerequisites
1. Install Supabase CLI:
   ```powershell
   winget install --id Supabase.CLI
   ```

2. Login to Supabase:
   ```bash
   supabase login
   ```

3. Link your project:
   ```bash
   supabase link --project-ref psgqhiqcxnupzbbunydx
   ```

---

## Deploy FPL Proxy (Required for Web)

```bash
# Navigate to project root
cd c:\Users\Zayn\Projects\squadiq-mvp6\squadiq

# Deploy the function
supabase functions deploy fpl-proxy
```

**Verify deployment:**
- Test URL: `https://psgqhiqcxnupzbbunydx.supabase.co/functions/v1/fpl-proxy?path=/bootstrap-static/`
- Should return FPL data without CORS errors

---

## Deploy AI Assistant (Optional)

```bash
# Deploy the function
supabase functions deploy ai-assistant

# Set the API key
supabase secrets set ANTHROPIC_API_KEY=sk-ant-your-key-here
```

---

## Quick Deploy Script

Save as `deploy-functions.ps1` in project root:

```powershell
# Deploy all edge functions

Write-Host "Deploying FPL Proxy..." -ForegroundColor Cyan
supabase functions deploy fpl-proxy

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ FPL Proxy deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ FPL Proxy deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Deploy AI Assistant? (y/N)" -ForegroundColor Yellow
$deploy_ai = Read-Host

if ($deploy_ai -eq 'y' -or $deploy_ai -eq 'Y') {
    Write-Host "Deploying AI Assistant..." -ForegroundColor Cyan
    supabase functions deploy ai-assistant
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ AI Assistant deployed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Don't forget to set your Anthropic API key:" -ForegroundColor Yellow
        Write-Host "  supabase secrets set ANTHROPIC_API_KEY=sk-ant-..." -ForegroundColor Cyan
    } else {
        Write-Host "✗ AI Assistant deployment failed!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "✓ Deployment complete!" -ForegroundColor Green
```

---

## Testing Functions Locally

```bash
# Start local Supabase
supabase start

# Serve functions locally
supabase functions serve

# Test FPL proxy
curl http://localhost:54321/functions/v1/fpl-proxy?path=/bootstrap-static/
```

---

## Troubleshooting

### "Function not found"
- Make sure you deployed: `supabase functions deploy fpl-proxy`
- Check project is linked: `supabase projects list`

### "CORS errors still happening"
- Verify function deployed successfully
- Check browser network tab - should show requests going to Supabase URL
- Hot reload the app: press `r` in the Flutter terminal

### "401 Unauthorized"
- Edge functions need proper authentication
- Check your Supabase anon key is correct in `.env`

---

## Architecture Note

```
Flutter Web App (Browser)
    ↓
Supabase Edge Function (fpl-proxy)
    ↓ 
FPL API (fantasy.premierleague.com)
    ↓
Response with CORS headers
    ↓
Flutter App receives data ✓
```

On mobile/desktop, the app calls FPL directly (no proxy needed).
