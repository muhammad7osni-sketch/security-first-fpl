"""
PHASE 4: MANDATORY SECURITY TESTS FOR AUTHORIZATION (Blocker #3)
Fail-closed authorization implementation - 5 tests required before production.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.auth.authorization import AuthorizationService
import uuid


@pytest.fixture
def auth_service():
    """Create AuthorizationService for testing."""
    return AuthorizationService()


@pytest.fixture
def mock_supabase_client():
    """Create mock Supabase client."""
    return MagicMock()


@pytest.fixture
def user_id():
    """Test user ID."""
    return str(uuid.uuid4())


@pytest.fixture
def owned_team_id():
    """FPL team_id that user owns."""
    return 123456


@pytest.fixture
def unowned_team_id():
    """FPL team_id that user does NOT own."""
    return 999999


# ============================================================================
# MANDATORY SECURITY TEST #1: Authorized Resource Access (200 OK)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_granted_user_owns_team(auth_service, user_id, owned_team_id):
    """
    TEST #1: Authorized Resource Access
    
    Given: User owns FPL team_id
    When: User requests access to /api/entry/{team_id}/
    Then: Authorization passes (return True)
    
    Security: Verifies that users CAN access their own teams.
    Implementation: user_teams table contains (user_id, team_id) mapping.
    """
    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        mock_team_repo.check_user_team_access.return_value = True

        auth_service.team_repo = mock_team_repo

        is_authorized, error_msg = await auth_service.authorize_team_access(user_id, owned_team_id)

        assert is_authorized is True
        assert error_msg is None


# ============================================================================
# MANDATORY SECURITY TEST #2: Unauthorized Resource Access (403 Forbidden)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_denied_user_does_not_own_team(
    auth_service, user_id, unowned_team_id
):
    """
    TEST #2: Unauthorized Resource Access (Fail-Closed)
    
    Given: User does NOT own FPL team_id
    When: User requests access to /api/entry/{team_id}/
    Then: Authorization fails (return False) → 403 Forbidden
    
    Security: Verifies fail-closed behavior. Users CANNOT access teams they don't own.
    Implementation: user_teams table does NOT contain (user_id, unowned_team_id).
    Never call FPL API without authorization check.
    """
    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        mock_team_repo.check_user_team_access.return_value = False

        auth_service.team_repo = mock_team_repo

        is_authorized, error_msg = await auth_service.authorize_team_access(
            user_id, unowned_team_id
        )

        assert is_authorized is False
        assert error_msg is not None
        assert "does not own" in error_msg.lower()


# ============================================================================
# MANDATORY SECURITY TEST #3: Missing Identity Mapping (403 Forbidden)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_denied_missing_identity_mapping(auth_service):
    """
    TEST #3: Missing Identity Mapping (Fail-Closed)
    
    Given: User_id exists, but no mapping in user_teams table
    When: Attempting to access any FPL resource
    Then: Authorization fails (return False) → 403 Forbidden
    
    Security: Verifies that missing identity binding denies access.
    No user_teams entry = no FPL resource access.
    """
    unknown_user_id = str(uuid.uuid4())
    team_id = 123456

    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        # Database query returns no results (no mapping)
        mock_team_repo.check_user_team_access.return_value = False

        auth_service.team_repo = mock_team_repo

        is_authorized, error_msg = await auth_service.authorize_team_access(
            unknown_user_id, team_id
        )

        assert is_authorized is False
        assert error_msg is not None


# ============================================================================
# MANDATORY SECURITY TEST #4: Expired/Invalid Token (401 Unauthorized)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_denied_empty_user_id(auth_service, owned_team_id):
    """
    TEST #4: Expired/Invalid Token (Fail-Closed)
    
    Given: User_id is empty or None (token invalid/expired)
    When: Attempting authorization check
    Then: Authorization fails (return False)
    
    Security: Verifies that invalid authentication prevents resource access.
    Note: JWT validation is tested separately in test_jwt_validator.py
    This test ensures authorization layer also validates user_id.
    """
    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        auth_service.team_repo = mock_team_repo

        # Empty user_id
        is_authorized, error_msg = await auth_service.authorize_team_access("", owned_team_id)

        assert is_authorized is False

        # None user_id
        is_authorized, error_msg = await auth_service.authorize_team_access(None, owned_team_id)

        assert is_authorized is False


# ============================================================================
# MANDATORY SECURITY TEST #5: Tampered Resource Identifier (403 Forbidden)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_denied_tampered_team_id(auth_service, user_id):
    """
    TEST #5: Tampered Resource Identifier (Fail-Closed)
    
    Given: User attempts to access a team_id that has been tampered/altered
    When: Requesting /api/entry/{altered_team_id}/
    Then: Authorization fails (return False) → 403 Forbidden
    
    Security: Verifies that altered resource identifiers are rejected.
    Attack scenario: User modifies team_id in request (e.g., 123456 → 123457).
    Expected: Authorization check queries user_teams, finds no mapping, denies access.
    """
    original_team_id = 123456
    tampered_team_id = 123457  # Attacker modifies +1

    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        # User owns original_team_id but NOT tampered_team_id
        async def check_access(uid, tid):
            return uid == user_id and tid == original_team_id

        mock_team_repo.check_user_team_access.side_effect = check_access

        auth_service.team_repo = mock_team_repo

        # Attempt to access tampered team_id
        is_authorized, error_msg = await auth_service.authorize_team_access(
            user_id, tampered_team_id
        )

        assert is_authorized is False
        assert error_msg is not None


# ============================================================================
# ADDITIONAL AUTHORIZATION TESTS (Supporting Security)
# ============================================================================


@pytest.mark.asyncio
async def test_authorization_database_error_fail_closed(auth_service, user_id, owned_team_id):
    """
    TEST (Additional): Database Error Handling (Fail-Closed)
    
    Given: Database connection fails
    When: Authorization check is attempted
    Then: Authorization fails (return False) — never allow access
    
    Security: Fail-closed principle — if we can't verify ownership, deny access.
    """
    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)
        mock_team_repo.check_user_team_access.side_effect = Exception("Database connection error")

        auth_service.team_repo = mock_team_repo

        is_authorized, error_msg = await auth_service.authorize_team_access(user_id, owned_team_id)

        assert is_authorized is False
        assert "failed" in error_msg.lower()


@pytest.mark.asyncio
async def test_authorization_api_me_endpoint_no_team_required(auth_service, user_id):
    """
    TEST (Additional): /api/me/ Endpoint (No Team_id Required)
    
    Given: User authenticates with valid JWT
    When: Requesting /api/me/
    Then: Authorization passes (no team_id verification needed)
    
    Security: /api/me/ is user's own profile, requires only authentication (not ownership).
    """
    is_authorized, error_msg = await auth_service.authorize_fpl_api_call(
        user_id=user_id,
        endpoint="/api/me/",
    )

    assert is_authorized is True
    assert error_msg is None


@pytest.mark.asyncio
async def test_authorization_multiple_teams_per_user(auth_service, user_id):
    """
    TEST (Additional): Multiple Teams Per User
    
    Given: User owns multiple FPL teams
    When: User requests access to each team
    Then: Authorization passes for all owned teams, fails for unowned teams
    
    Security: Verifies that user can manage multiple teams independently.
    """
    owned_teams = [123456, 234567, 345678]
    unowned_team = 999999

    with patch("app.auth.authorization.get_supabase_client") as mock_get_client:
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        from app.database.db import TeamRepository

        mock_team_repo = AsyncMock(spec=TeamRepository)

        async def check_access(uid, tid):
            return uid == user_id and tid in owned_teams

        mock_team_repo.check_user_team_access.side_effect = check_access

        auth_service.team_repo = mock_team_repo

        # All owned teams should pass
        for team_id in owned_teams:
            is_authorized, _ = await auth_service.authorize_team_access(user_id, team_id)
            assert is_authorized is True

        # Unowned team should fail
        is_authorized, _ = await auth_service.authorize_team_access(user_id, unowned_team)
        assert is_authorized is False
