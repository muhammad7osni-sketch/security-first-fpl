-- Rate limiting table for FPL login attempts
-- Tracks login attempts by IP to prevent brute force attacks

CREATE TABLE IF NOT EXISTS fpl_login_attempts (
  id BIGSERIAL PRIMARY KEY,
  ip_address INET NOT NULL,
  success BOOLEAN DEFAULT FALSE,
  attempted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Index for efficient rate limit checking (IP + recent time window)
CREATE INDEX IF NOT EXISTS idx_fpl_login_attempts_ip_time 
ON fpl_login_attempts(ip_address, attempted_at DESC);

-- Index for cleanup queries (delete old entries)
CREATE INDEX IF NOT EXISTS idx_fpl_login_attempts_timestamp 
ON fpl_login_attempts(attempted_at DESC);

-- Disable RLS for this table (it's rate limiting, not user data)
-- The Edge Function has service role to write here
ALTER TABLE fpl_login_attempts DISABLE ROW LEVEL SECURITY;

-- Auto-cleanup: delete attempts older than 7 days
-- (Run this as a scheduled job if Supabase supports it)
-- For now, manually via: DELETE FROM fpl_login_attempts WHERE attempted_at < NOW() - INTERVAL '7 days';
