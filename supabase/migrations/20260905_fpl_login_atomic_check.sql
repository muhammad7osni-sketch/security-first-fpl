-- Migration: Truly atomic rate limit check-and-log function
--
-- WHY SELECT + INSERT ALONE IS NOT ENOUGH:
--   Even inside a plpgsql function, two concurrent transactions can both
--   execute the SELECT COUNT(*) before either has committed an INSERT.
--   Both see count=4, both proceed, both insert → limit bypassed.
--   This is a classic "lost update" problem under default READ COMMITTED.
--
-- THE FIX — pg_advisory_xact_lock(bigint):
--   Acquires an exclusive session-level transaction lock keyed on the
--   user_id hash. Any concurrent call for the SAME user_id blocks at
--   this line until the first transaction commits (and releases the lock).
--   The second transaction then re-reads the updated count, sees count=5,
--   and is rejected. 100 concurrent requests for the same user collapse
--   into a serialised queue at the DB level — MAX_ATTEMPTS is enforced.
--
--   Lock scope:
--     pg_advisory_xact_lock  → released automatically on COMMIT/ROLLBACK
--     (no manual unlock needed, no risk of stale locks)
--
--   Key derivation:
--     hashtext(p_user_id::text) maps a UUID to a 32-bit int (bigint ok).
--     Different users get different lock keys → no unnecessary contention
--     between users.
--
-- FAIL-SAFE:
--   Any exception inside this function causes the transaction to roll back.
--   The calling Node code checks for RPC error and BLOCKS the HTTP request.
--   A broken rate-limit function can never become an open proxy.

CREATE OR REPLACE FUNCTION check_fpl_login_attempt(
  p_user_id     uuid,
  p_window_ms   bigint,
  p_max_attempts int,
  p_success     bool
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_window_start  timestamp with time zone;
  v_attempt_count int;
BEGIN
  -- 1. Acquire an exclusive transaction-scoped advisory lock keyed on this
  --    user_id. Concurrent calls for the same user BLOCK here until the
  --    current transaction commits, ensuring the SELECT + INSERT below are
  --    executed serially per user.
  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text)::bigint);

  -- 2. Count attempts inside the rolling window (now safe — serialised)
  v_window_start := NOW() - (p_window_ms || ' milliseconds')::interval;

  SELECT COUNT(*)
    INTO v_attempt_count
    FROM fpl_login_attempts
   WHERE user_id = p_user_id
     AND attempted_at >= v_window_start;

  -- 3. Reject if at or over the limit
  IF v_attempt_count >= p_max_attempts THEN
    RETURN json_build_object(
      'allowed',       false,
      'attempt_count', v_attempt_count
    );
  END IF;

  -- 4. Log the new attempt (same transaction, lock still held)
  INSERT INTO fpl_login_attempts (user_id, success, attempted_at)
  VALUES (p_user_id, p_success, NOW());

  -- 5. Return success — lock released on commit
  RETURN json_build_object(
    'allowed',       true,
    'attempt_count', v_attempt_count + 1
  );
END;
$$;

-- Grant execute to the roles Cloud Run uses
GRANT EXECUTE ON FUNCTION check_fpl_login_attempt(uuid, bigint, int, bool)
  TO authenticated;
GRANT EXECUTE ON FUNCTION check_fpl_login_attempt(uuid, bigint, int, bool)
  TO service_role;
