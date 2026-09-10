# PHASE 4 LOCAL DOCKER STAGING: Test Fixtures
# Pre-created test data for local integration testing
# DO NOT use these in production

import uuid
import json
from datetime import datetime, timedelta
from typing import Dict, Any
import base64

# ========== TEST USER FIXTURES ==========

TEST_USER_1_ID = str(uuid.uuid4())  # e.g., "550e8400-e29b-41d4-a716-446655440000"
TEST_USER_2_ID = str(uuid.uuid4())  # e.g., "550e8400-e29b-41d4-a716-446655440001"

TEST_USER_1 = {
    "id": TEST_USER_1_ID,
    "email": "test_user_1@staging.local",
    "pingone_user_id": "pingone-sub-user-1",
    "created_at": datetime.utcnow().isoformat(),
    "updated_at": datetime.utcnow().isoformat(),
}

TEST_USER_2 = {
    "id": TEST_USER_2_ID,
    "email": "test_user_2@staging.local",
    "pingone_user_id": "pingone-sub-user-2",
    "created_at": datetime.utcnow().isoformat(),
    "updated_at": datetime.utcnow().isoformat(),
}

# ========== TEST TEAM FIXTURES ==========

# FPL team IDs (simulating fantasy.premierleague.com teams)
TEST_TEAM_1_ID = 12345
TEST_TEAM_2_ID = 67890
TEST_TEAM_3_ID = 11111

TEST_TEAM_1 = {
    "user_id": TEST_USER_1_ID,
    "fpl_team_id": TEST_TEAM_1_ID,
    "fpl_manager_id": "fpl-manager-1",
    "created_at": datetime.utcnow().isoformat(),
    "updated_at": datetime.utcnow().isoformat(),
}

TEST_TEAM_2 = {
    "user_id": TEST_USER_1_ID,
    "fpl_team_id": TEST_TEAM_2_ID,
    "fpl_manager_id": "fpl-manager-2",
    "created_at": datetime.utcnow().isoformat(),
    "updated_at": datetime.utcnow().isoformat(),
}

TEST_TEAM_3 = {
    "user_id": TEST_USER_2_ID,
    "fpl_team_id": TEST_TEAM_3_ID,
    "fpl_manager_id": "fpl-manager-3",
    "created_at": datetime.utcnow().isoformat(),
    "updated_at": datetime.utcnow().isoformat(),
}

# ========== TEST JWT TOKEN FIXTURES ==========

# These are mock JWT tokens for local testing
# In real tests, use PyJWT to generate valid tokens with known secrets

TEST_JWT_PAYLOAD_USER_1 = {
    "sub": TEST_USER_1["pingone_user_id"],
    "email": TEST_USER_1["email"],
    "aud": "test-client-id-local",
    "iss": "https://account.premierleague.com/as",
    "iat": int(datetime.utcnow().timestamp()),
    "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
    "name": "Test User 1",
}

TEST_JWT_PAYLOAD_USER_2 = {
    "sub": TEST_USER_2["pingone_user_id"],
    "email": TEST_USER_2["email"],
    "aud": "test-client-id-local",
    "iss": "https://account.premierleague.com/as",
    "iat": int(datetime.utcnow().timestamp()),
    "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
    "name": "Test User 2",
}

# Expired JWT (exp in the past)
TEST_JWT_PAYLOAD_EXPIRED = {
    "sub": TEST_USER_1["pingone_user_id"],
    "email": TEST_USER_1["email"],
    "aud": "test-client-id-local",
    "iss": "https://account.premierleague.com/as",
    "iat": int((datetime.utcnow() - timedelta(hours=9)).timestamp()),
    "exp": int((datetime.utcnow() - timedelta(hours=1)).timestamp()),
    "name": "Test User 1",
}

# Invalid audience
TEST_JWT_PAYLOAD_INVALID_AUD = {
    "sub": TEST_USER_1["pingone_user_id"],
    "email": TEST_USER_1["email"],
    "aud": "wrong-audience",
    "iss": "https://account.premierleague.com/as",
    "iat": int(datetime.utcnow().timestamp()),
    "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
    "name": "Test User 1",
}

# Invalid issuer
TEST_JWT_PAYLOAD_INVALID_ISS = {
    "sub": TEST_USER_1["pingone_user_id"],
    "email": TEST_USER_1["email"],
    "aud": "test-client-id-local",
    "iss": "https://wrong-issuer.com",
    "iat": int(datetime.utcnow().timestamp()),
    "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
    "name": "Test User 1",
}

# ========== TEST REFRESH TOKEN FIXTURES ==========

# Encrypted refresh tokens (AES-256-GCM format: kv_<version>_<ciphertext>)
# These would normally be generated during /auth/callback
# Format: kv_1_<base64-encoded-ciphertext>

TEST_REFRESH_TOKEN_USER_1_ENCRYPTED = "kv_1_test-encrypted-refresh-token-user-1-base64"
TEST_REFRESH_TOKEN_USER_2_ENCRYPTED = "kv_1_test-encrypted-refresh-token-user-2-base64"

TEST_REFRESH_TOKEN_1 = {
    "user_id": TEST_USER_1_ID,
    "encrypted_refresh_token": TEST_REFRESH_TOKEN_USER_1_ENCRYPTED,
    "token_version": 1,
    "expires_at": (datetime.utcnow() + timedelta(days=30)).isoformat(),
    "created_at": datetime.utcnow().isoformat(),
    "revoked_at": None,
}

TEST_REFRESH_TOKEN_2 = {
    "user_id": TEST_USER_2_ID,
    "encrypted_refresh_token": TEST_REFRESH_TOKEN_USER_2_ENCRYPTED,
    "token_version": 1,
    "expires_at": (datetime.utcnow() + timedelta(days=30)).isoformat(),
    "created_at": datetime.utcnow().isoformat(),
    "revoked_at": None,
}

# ========== TEST AUTHORIZATION FIXTURES ==========

# Authorization test cases
AUTHORIZATION_TEST_CASES = [
    {
        "name": "User 1 accesses own Team 1",
        "user_id": TEST_USER_1_ID,
        "fpl_team_id": TEST_TEAM_1_ID,
        "expected": True,
        "reason": "User 1 owns Team 1",
    },
    {
        "name": "User 1 accesses own Team 2",
        "user_id": TEST_USER_1_ID,
        "fpl_team_id": TEST_TEAM_2_ID,
        "expected": True,
        "reason": "User 1 owns Team 2",
    },
    {
        "name": "User 1 accesses User 2's Team 3",
        "user_id": TEST_USER_1_ID,
        "fpl_team_id": TEST_TEAM_3_ID,
        "expected": False,
        "reason": "User 1 does not own Team 3 (User 2 owns it)",
    },
    {
        "name": "User 2 accesses User 1's Team 1",
        "user_id": TEST_USER_2_ID,
        "fpl_team_id": TEST_TEAM_1_ID,
        "expected": False,
        "reason": "User 2 does not own Team 1 (User 1 owns it)",
    },
    {
        "name": "User 2 accesses own Team 3",
        "user_id": TEST_USER_2_ID,
        "fpl_team_id": TEST_TEAM_3_ID,
        "expected": True,
        "reason": "User 2 owns Team 3",
    },
    {
        "name": "User 1 accesses non-existent Team 99999",
        "user_id": TEST_USER_1_ID,
        "fpl_team_id": 99999,
        "expected": False,
        "reason": "Team 99999 does not exist (not in user_teams)",
    },
]

# ========== TEST RATE LIMITING FIXTURES ==========

RATE_LIMIT_TEST_CASES = [
    {
        "endpoint": "/auth/callback",
        "limit": "5/minute",
        "requests_to_succeed": 5,
        "requests_to_fail": 1,
    },
    {
        "endpoint": "/auth/refresh",
        "limit": "10/minute",
        "requests_to_succeed": 10,
        "requests_to_fail": 1,
    },
    {
        "endpoint": "/auth/logout",
        "limit": "10/minute",
        "requests_to_succeed": 10,
        "requests_to_fail": 1,
    },
    {
        "endpoint": "/api/teams/me",
        "limit": "100/minute",
        "requests_to_succeed": 100,
        "requests_to_fail": 1,
    },
    {
        "endpoint": "/api/teams/link",
        "limit": "20/minute",
        "requests_to_succeed": 20,
        "requests_to_fail": 1,
    },
    {
        "endpoint": "/health",
        "limit": "1000/minute",
        "requests_to_succeed": 1000,
        "requests_to_fail": 1,
    },
]

# ========== TEST ENCRYPTION FIXTURES ==========

# Plaintext refresh token (before encryption)
TEST_PLAINTEXT_REFRESH_TOKEN = "refresh_token_eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"

# Associated data for GCM (binds token to specific user/request)
TEST_ASSOCIATED_DATA = f"{TEST_USER_1_ID}:{TEST_TEAM_1_ID}".encode()

# ========== TEST FPL API FIXTURES ==========

# Mock FPL /api/me/ response
MOCK_FPL_ME_RESPONSE = {
    "id": TEST_TEAM_1_ID,
    "name": "My Test Team",
    "player_first_name": "Test",
    "player_last_name": "User",
    "player_region_id": 1,
    "team": "Arsenal",
    "favourite_team": 1,
    "started_event": 1,
    "favourite_sport": 1,
    "stats": {
        "total_points": 1000,
        "rank": 1234,
    },
}

# Mock FPL /api/entry/{id}/ response
MOCK_FPL_ENTRY_RESPONSE = {
    "id": TEST_TEAM_1_ID,
    "entry_name": "My Test Team",
    "player_first_name": "Test",
    "player_last_name": "User",
    "summary_overall_points": 1000,
    "summary_overall_rank": 1234,
    "favourite_team": 1,
}

# ========== TEST AUDIT LOG FIXTURES ==========

AUDIT_LOG_AUTHORIZATION_SUCCESS = {
    "user_id": TEST_USER_1_ID,
    "endpoint": "/api/teams/me",
    "method": "GET",
    "fpl_team_id": TEST_TEAM_1_ID,
    "status_code": 200,
    "error_message": None,
    "request_duration_ms": 45,
}

AUDIT_LOG_AUTHORIZATION_FAILURE = {
    "user_id": TEST_USER_1_ID,
    "endpoint": "/api/teams/me",
    "method": "GET",
    "fpl_team_id": TEST_TEAM_3_ID,  # User 2 owns this
    "status_code": 403,
    "error_message": "User does not own this FPL team",
    "request_duration_ms": 12,
}

AUDIT_LOG_RATE_LIMITED = {
    "user_id": TEST_USER_1_ID,
    "endpoint": "/auth/callback",
    "method": "POST",
    "fpl_team_id": None,
    "status_code": 429,
    "error_message": "Rate limit exceeded",
    "request_duration_ms": 1,
}

# ========== HELPER FUNCTIONS ==========

def get_test_user(user_num: int) -> Dict[str, Any]:
    """Get test user by number (1 or 2)."""
    if user_num == 1:
        return TEST_USER_1
    elif user_num == 2:
        return TEST_USER_2
    else:
        raise ValueError(f"Invalid user number: {user_num}")


def get_test_team(team_num: int) -> Dict[str, Any]:
    """Get test team by number (1, 2, or 3)."""
    if team_num == 1:
        return TEST_TEAM_1
    elif team_num == 2:
        return TEST_TEAM_2
    elif team_num == 3:
        return TEST_TEAM_3
    else:
        raise ValueError(f"Invalid team number: {team_num}")


def get_test_jwt_payload(user_num: int, expired: bool = False) -> Dict[str, Any]:
    """Get test JWT payload."""
    if expired:
        return TEST_JWT_PAYLOAD_EXPIRED
    elif user_num == 1:
        return TEST_JWT_PAYLOAD_USER_1
    elif user_num == 2:
        return TEST_JWT_PAYLOAD_USER_2
    else:
        raise ValueError(f"Invalid user number: {user_num}")


# ========== TEST DATABASE INITIALIZATION SQL ==========

# SQL to insert test data into local database
INIT_TEST_DATA_SQL = f"""
-- Insert test users
INSERT INTO users (id, email, pingone_user_id, created_at, updated_at)
VALUES 
  ('{TEST_USER_1_ID}', '{TEST_USER_1["email"]}', '{TEST_USER_1["pingone_user_id"]}', NOW(), NOW()),
  ('{TEST_USER_2_ID}', '{TEST_USER_2["email"]}', '{TEST_USER_2["pingone_user_id"]}', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert test user-team mappings
INSERT INTO user_teams (user_id, fpl_team_id, fpl_manager_id, created_at, updated_at)
VALUES 
  ('{TEST_USER_1_ID}', {TEST_TEAM_1_ID}, 'fpl-manager-1', NOW(), NOW()),
  ('{TEST_USER_1_ID}', {TEST_TEAM_2_ID}, 'fpl-manager-2', NOW(), NOW()),
  ('{TEST_USER_2_ID}', {TEST_TEAM_3_ID}, 'fpl-manager-3', NOW(), NOW())
ON CONFLICT (user_id, fpl_team_id) DO NOTHING;

-- Insert test refresh tokens
INSERT INTO auth_tokens (user_id, encrypted_refresh_token, token_version, expires_at, created_at)
VALUES 
  ('{TEST_USER_1_ID}', '{TEST_REFRESH_TOKEN_USER_1_ENCRYPTED}', 1, NOW() + INTERVAL '30 days', NOW()),
  ('{TEST_USER_2_ID}', '{TEST_REFRESH_TOKEN_USER_2_ENCRYPTED}', 1, NOW() + INTERVAL '30 days', NOW())
ON CONFLICT DO NOTHING;
"""

# ========== SUMMARY ==========

"""
FIXTURE USAGE IN TESTS:

1. Unit Tests (JWT, Encryption, Authorization):
   from tests.fixtures_local import TEST_USER_1_ID, TEST_JWT_PAYLOAD_USER_1, etc.
   
2. Integration Tests (Full flow):
   # Insert test data using INIT_TEST_DATA_SQL
   # Use test fixtures to verify authorization, encryption, rate limiting
   
3. Mocking External Services:
   # Mock JWKS: return TEST_JWT_PAYLOAD_* with known signature
   # Mock FPL: return MOCK_FPL_*_RESPONSE for /api/me and /api/entry
   # Mock authorization: query local user_teams table with test data
"""
