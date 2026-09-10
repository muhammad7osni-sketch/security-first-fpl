-- Migration: add user_id to fpl_login_attempts
--
-- The Cloud Run service uses the authenticated Supabase user ID for
-- rate limiting instead of IP address. IP-based limiting is unreliable
-- (spoofable via proxies, shared IPs on mobile networks). User ID is
-- verified server-side via JWT so it cannot be spoofed.
--
-- ip_address is kept nullable for backward compatibility with the
-- existing Supabase Edge Function which still logs by IP.

ALTER TABLE fpl_login_attempts
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Partial index: fast rate limit check for Cloud Run path (by user_id)
CREATE INDEX IF NOT EXISTS idx_fpl_login_attempts_user_time
  ON fpl_login_attempts(user_id, attempted_at DESC)
  WHERE user_id IS NOT NULL;

-- Make ip_address nullable so Cloud Run inserts (user_id only) don't fail
ALTER TABLE fpl_login_attempts
  ALTER COLUMN ip_address DROP NOT NULL;
