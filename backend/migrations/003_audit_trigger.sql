-- PHASE 4: Audit trigger
-- Automatically logs all API calls to audit_logs table
-- Useful for compliance and debugging

-- Function to log audit events
CREATE OR REPLACE FUNCTION log_audit_event(
    p_user_id UUID,
    p_endpoint TEXT,
    p_method TEXT,
    p_fpl_team_id INTEGER DEFAULT NULL,
    p_status_code INTEGER DEFAULT 200,
    p_error_message TEXT DEFAULT NULL,
    p_request_duration_ms INTEGER DEFAULT 0
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO audit_logs (
        user_id,
        endpoint,
        method,
        fpl_team_id,
        status_code,
        error_message,
        request_duration_ms
    )
    VALUES (
        p_user_id,
        p_endpoint,
        p_method,
        p_fpl_team_id,
        p_status_code,
        p_error_message,
        p_request_duration_ms
    )
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- View for recent audit logs
CREATE OR REPLACE VIEW recent_audit_logs AS
SELECT
    id,
    user_id,
    endpoint,
    method,
    fpl_team_id,
    status_code,
    error_message,
    request_duration_ms,
    created_at
FROM audit_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- View for failed requests (errors)
CREATE OR REPLACE VIEW failed_requests AS
SELECT
    id,
    user_id,
    endpoint,
    method,
    fpl_team_id,
    status_code,
    error_message,
    created_at
FROM audit_logs
WHERE status_code >= 400
ORDER BY created_at DESC;

-- View for authorization failures (403)
CREATE OR REPLACE VIEW authorization_failures AS
SELECT
    id,
    user_id,
    endpoint,
    method,
    fpl_team_id,
    error_message,
    created_at
FROM audit_logs
WHERE status_code = 403
ORDER BY created_at DESC;
