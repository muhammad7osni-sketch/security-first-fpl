-- PHASE 4: Database initialization
-- Creates:
-- 1. users table (managed by Supabase auth)
-- 2. user_teams table (authorization: user_id -> team_id mapping)
-- 3. auth_tokens table (refresh token storage)
-- 4. audit_logs table (all API calls)
-- 5. encryption_keys table (key versioning)

-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create users table (if not exists, since Supabase auth may create it)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    pingone_user_id TEXT UNIQUE NOT NULL,  -- PingOne sub claim
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user_teams table (authorization binding)
-- Blocker #3: Never trust user-supplied team_id as proof of ownership
-- This table is the SINGLE SOURCE OF TRUTH for FPL resource access
CREATE TABLE IF NOT EXISTS user_teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fpl_team_id INTEGER NOT NULL,  -- FPL entry_id or team_id from /api/me/
    fpl_manager_id TEXT,  -- Optional: PingOne ID of FPL account owner
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, fpl_team_id)  -- One mapping per user
);

-- Create auth_tokens table (refresh token storage)
-- Tokens are encrypted at application layer
CREATE TABLE IF NOT EXISTS auth_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_refresh_token TEXT NOT NULL,  -- AES-256-GCM encrypted
    token_version INTEGER DEFAULT 1,  -- Supports key versioning
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,  -- Refresh token TTL (30 days per PingOne)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,  -- Logout timestamp
    CONSTRAINT token_not_expired CHECK (expires_at > NOW())
);

-- Create audit_logs table (immutable, append-only)
-- All API calls logged for compliance
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    endpoint TEXT NOT NULL,  -- e.g., /api/me, /api/entry/123
    method TEXT NOT NULL,  -- GET, POST, PUT, DELETE
    fpl_team_id INTEGER,  -- Requested resource (for authorization audits)
    status_code INTEGER,
    error_message TEXT,  -- If request failed
    request_duration_ms INTEGER,  -- Performance monitoring
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create encryption_keys table (key versioning for rotation)
CREATE TABLE IF NOT EXISTS encryption_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key_version INTEGER NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    rotated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    is_current BOOLEAN DEFAULT FALSE  -- Current key for encryption
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_teams_user_id ON user_teams(user_id);
CREATE INDEX IF NOT EXISTS idx_user_teams_fpl_team_id ON user_teams(fpl_team_id);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_user_id ON auth_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_expires_at ON auth_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_endpoint ON audit_logs(endpoint);

-- Update triggers for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_user_teams_updated_at
BEFORE UPDATE ON user_teams
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE users IS 'Application users, managed by Supabase auth + PingOne OIDC';
COMMENT ON TABLE user_teams IS 'Authorization mapping: user_id -> fpl_team_id (single source of truth)';
COMMENT ON TABLE auth_tokens IS 'Refresh tokens, encrypted and server-side only';
COMMENT ON TABLE audit_logs IS 'Immutable audit log of all API calls';
COMMENT ON TABLE encryption_keys IS 'Key versioning for backward-compatible rotation';

COMMENT ON COLUMN users.pingone_user_id IS 'PingOne sub claim from OIDC token';
COMMENT ON COLUMN user_teams.fpl_team_id IS 'FPL entry_id from /api/me/';
COMMENT ON COLUMN auth_tokens.encrypted_refresh_token IS 'AES-256-GCM ciphertext (never plaintext)';
COMMENT ON COLUMN audit_logs.fpl_team_id IS 'Requested resource for authorization audits';
