-- PHASE 4: Row-Level Security (RLS) policies
-- Enforces fail-closed authorization:
-- - Service role (backend) can read/write all data
-- - Authenticated users (Supabase JWT) cannot directly access tables
-- - No anonymous access

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE encryption_keys ENABLE ROW LEVEL SECURITY;

-- USERS TABLE RLS
-- Only service role can read user data (backend only)
CREATE POLICY users_service_role_read
ON users
FOR SELECT
TO service_role
USING (true);

CREATE POLICY users_service_role_insert
ON users
FOR INSERT
TO service_role
WITH CHECK (true);

CREATE POLICY users_service_role_update
ON users
FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

-- Deny all for authenticated users (JWT)
CREATE POLICY users_authenticated_deny
ON users
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Deny all for anonymous
CREATE POLICY users_anon_deny
ON users
FOR ALL
TO anon
USING (false)
WITH CHECK (false);

-- USER_TEAMS TABLE RLS
-- Only service role can access user_teams
CREATE POLICY user_teams_service_role_read
ON user_teams
FOR SELECT
TO service_role
USING (true);

CREATE POLICY user_teams_service_role_insert
ON user_teams
FOR INSERT
TO service_role
WITH CHECK (true);

CREATE POLICY user_teams_service_role_update
ON user_teams
FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY user_teams_service_role_delete
ON user_teams
FOR DELETE
TO service_role
USING (true);

-- Deny all for authenticated users
CREATE POLICY user_teams_authenticated_deny
ON user_teams
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Deny all for anonymous
CREATE POLICY user_teams_anon_deny
ON user_teams
FOR ALL
TO anon
USING (false)
WITH CHECK (false);

-- AUTH_TOKENS TABLE RLS
-- Only service role can read/write tokens
CREATE POLICY auth_tokens_service_role_read
ON auth_tokens
FOR SELECT
TO service_role
USING (true);

CREATE POLICY auth_tokens_service_role_insert
ON auth_tokens
FOR INSERT
TO service_role
WITH CHECK (true);

CREATE POLICY auth_tokens_service_role_update
ON auth_tokens
FOR UPDATE
TO service_role
USING (true)
WITH CHECK (true);

-- Deny all for authenticated users
CREATE POLICY auth_tokens_authenticated_deny
ON auth_tokens
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Deny all for anonymous
CREATE POLICY auth_tokens_anon_deny
ON auth_tokens
FOR ALL
TO anon
USING (false)
WITH CHECK (false);

-- AUDIT_LOGS TABLE RLS
-- Only service role can write logs, read all
CREATE POLICY audit_logs_service_role_read
ON audit_logs
FOR SELECT
TO service_role
USING (true);

CREATE POLICY audit_logs_service_role_insert
ON audit_logs
FOR INSERT
TO service_role
WITH CHECK (true);

-- Deny reads/writes for authenticated
CREATE POLICY audit_logs_authenticated_deny
ON audit_logs
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Deny all for anonymous
CREATE POLICY audit_logs_anon_deny
ON audit_logs
FOR ALL
TO anon
USING (false)
WITH CHECK (false);

-- ENCRYPTION_KEYS TABLE RLS
-- Only service role can access encryption keys
CREATE POLICY encryption_keys_service_role_read
ON encryption_keys
FOR SELECT
TO service_role
USING (true);

CREATE POLICY encryption_keys_service_role_insert
ON encryption_keys
FOR INSERT
TO service_role
WITH CHECK (true);

-- Deny all for authenticated users
CREATE POLICY encryption_keys_authenticated_deny
ON encryption_keys
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Deny all for anonymous
CREATE POLICY encryption_keys_anon_deny
ON encryption_keys
FOR ALL
TO anon
USING (false)
WITH CHECK (false);
