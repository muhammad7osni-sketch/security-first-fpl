# SquadIQ Security Policy

## Overview
This document outlines the security measures implemented in SquadIQ to protect user data and prevent abuse.

---

## Authentication & Credentials

### FPL Login Security
- **Password Storage**: FPL passwords are **NEVER stored** in SquadIQ
  - Password travels over HTTPS directly to FPL's servers
  - Edge Function receives password, sends it to FPL, and immediately discards it
  - Only the public integer team ID is persisted

### Session Cookies
- Session cookies are extracted from FPL's login response
- Cookie is used to call the `/me/` endpoint to read the team ID
- Cookie is **immediately deleted** after reading the team ID
- Cookie never leaves the Edge Function's memory
- Garbage collection ensures secure memory cleanup

### Supabase Credentials
- `SUPABASE_ANON_KEY` is publicly shareable (JWT token with RLS restrictions)
- `SUPABASE_SERVICE_ROLE_KEY` is **secret** and kept only in:
  - GitHub Secrets
  - Supabase environment variables
  - Never committed to git
  - Never exposed to client code

---

## Rate Limiting

### FPL Login Attempts
- **Limit**: 5 login attempts per IP per hour
- **Tracking**: `fpl_login_attempts` table in Supabase
- **Purpose**: Prevent brute-force attacks on FPL accounts
- **Logged**: All attempts (success + failure) are recorded with IP and timestamp

### Response
- After 5 failed attempts: HTTP 429 (Too Many Requests)
- User sees: "Too many login attempts. Try again in 1 hour."

---

## Data Protection

### What's Stored
✅ **Stored securely:**
- FPL manager ID (integer, public)
- Team name
- Squad data (all from public FPL API)
- User email (from Supabase Auth)

❌ **NEVER stored:**
- FPL password
- FPL session cookies
- Plaintext credentials of any kind

### Encryption
- All data in transit: HTTPS only
- Data at rest: Supabase encrypted storage
- Sensitive logs: Rotation every 7 days

---

## Environment Variables

### Required Secrets (in GitHub)
```
SUPABASE_PROJECT_ID      # Public project ID
SUPABASE_ACCESS_TOKEN    # Deploy token (CI/CD only)
```

### Local Development
- Copy `supabase/.env.local.example` to `supabase/.env.local`
- Fill in your test credentials
- **NEVER commit `.env.local`**

---

## Network Security

### CORS Policy
- Edge Function only accepts requests from whitelisted origins
- Default: `*` (for local development)
- Production: Restrict to specific domain
  - Set via `ALLOWED_WEB_ORIGIN` environment variable

### Web vs Native Routing
- **Web**: Routes through Supabase Edge Function (CORS-safe)
- **Native**: Direct to FPL servers (no CORS restrictions)
- Both paths use HTTPS only

---

## Audit & Logging

### Login Attempts Table
```sql
-- View recent attempts
SELECT ip_address, success, attempted_at 
FROM fpl_login_attempts 
ORDER BY attempted_at DESC 
LIMIT 100;

-- Check for brute force attempts
SELECT ip_address, COUNT(*) as attempts, COUNT(CASE WHEN success THEN 1 END) as successes
FROM fpl_login_attempts 
WHERE attempted_at > NOW() - INTERVAL '1 hour'
GROUP BY ip_address 
HAVING COUNT(*) > 5;
```

### Log Retention
- Kept for 7 days, then auto-deleted
- Manual cleanup: `DELETE FROM fpl_login_attempts WHERE attempted_at < NOW() - INTERVAL '7 days';`

---

## Deployment Security

### CI/CD
- GitHub Actions handles all deployments
- Secrets never exposed in logs
- Linting + secret scanning on every push
- Migrations reviewed before auto-apply

### Branch Protection
- Main branch requires review before merge
- All deployments signed and verified
- Rollback capability on every release

---

## Vulnerability Disclosure

If you find a security vulnerability:
1. **DO NOT** open a public GitHub issue
2. Email: security@squadiq.dev (if available)
3. Include: description, steps to reproduce, impact
4. Timeline: We'll respond within 48 hours

---

## Compliance

- ✅ GDPR-compliant (user data in EU region)
- ✅ No third-party data sharing
- ✅ User can request data deletion
- ✅ Rate limiting + abuse prevention
- ✅ HTTPS-only communication

---

## Updates

This policy is reviewed quarterly. Last updated: **September 7, 2026**
