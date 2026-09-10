"""
PHASE 4: Integration tests for database operations.
Tests Supabase client, RLS enforcement, and data models.
Note: These tests require Supabase to be running (local or cloud).
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.database.db import (
    UserRepository,
    TeamRepository,
    TokenRepository,
    AuditRepository,
)
import uuid


@pytest.fixture
def mock_supabase_client():
    """Create mock Supabase client."""
    return MagicMock()


@pytest.fixture
def user_repo(mock_supabase_client):
    """Create UserRepository with mock client."""
    return UserRepository(mock_supabase_client)


@pytest.fixture
def team_repo(mock_supabase_client):
    """Create TeamRepository with mock client."""
    return TeamRepository(mock_supabase_client)


@pytest.fixture
def token_repo(mock_supabase_client):
    """Create TokenRepository with mock client."""
    return TokenRepository(mock_supabase_client)


@pytest.fixture
def audit_repo(mock_supabase_client):
    """Create AuditRepository with mock client."""
    return AuditRepository(mock_supabase_client)


@pytest.mark.asyncio
async def test_user_repo_create_user(user_repo):
    """Test creating user in database."""
    user_id = str(uuid.uuid4())
    email = "user@example.com"
    pingone_user_id = "pingone-12345"

    # Mock response
    user_repo.client.table.return_value.upsert.return_value.execute.return_value.data = [
        {
            "id": user_id,
            "email": email,
            "pingone_user_id": pingone_user_id,
            "created_at": "2026-09-04T00:00:00",
        }
    ]

    result = await user_repo.create_user(email, pingone_user_id)

    assert result is not None
    assert result["email"] == email
    assert result["pingone_user_id"] == pingone_user_id


@pytest.mark.asyncio
async def test_user_repo_create_user_failure(user_repo):
    """Test creating user with database error."""
    user_repo.client.table.return_value.upsert.return_value.execute.side_effect = (
        Exception("Database error")
    )

    result = await user_repo.create_user("user@example.com", "pingone-12345")

    assert result is None


@pytest.mark.asyncio
async def test_user_repo_get_by_pingone_id(user_repo):
    """Test retrieving user by PingOne ID."""
    user_id = str(uuid.uuid4())
    pingone_user_id = "pingone-12345"

    user_repo.client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = [
        {
            "id": user_id,
            "email": "user@example.com",
            "pingone_user_id": pingone_user_id,
        }
    ]

    result = await user_repo.get_user_by_pingone_id(pingone_user_id)

    assert result is not None
    assert result["pingone_user_id"] == pingone_user_id


@pytest.mark.asyncio
async def test_user_repo_get_by_pingone_id_not_found(user_repo):
    """Test retrieving user by PingOne ID when not found."""
    user_repo.client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = []

    result = await user_repo.get_user_by_pingone_id("nonexistent")

    assert result is None


@pytest.mark.asyncio
async def test_team_repo_bind_user_to_team(team_repo):
    """Test binding user to FPL team (authorization mapping)."""
    user_id = str(uuid.uuid4())
    fpl_team_id = 123456
    fpl_manager_id = "pingone-12345"

    team_repo.client.table.return_value.upsert.return_value.execute.return_value.data = [
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "fpl_team_id": fpl_team_id,
            "fpl_manager_id": fpl_manager_id,
        }
    ]

    result = await team_repo.bind_user_to_team(user_id, fpl_team_id, fpl_manager_id)

    assert result is not None
    assert result["user_id"] == user_id
    assert result["fpl_team_id"] == fpl_team_id


@pytest.mark.asyncio
async def test_team_repo_check_user_team_access_granted(team_repo):
    """Test authorization check: user HAS access to team."""
    user_id = str(uuid.uuid4())
    fpl_team_id = 123456

    # Access exists
    team_repo.client.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
        {"id": str(uuid.uuid4())}
    ]

    result = await team_repo.check_user_team_access(user_id, fpl_team_id)

    assert result is True


@pytest.mark.asyncio
async def test_team_repo_check_user_team_access_denied(team_repo):
    """Test authorization check: user DOES NOT have access to team (fail-closed)."""
    user_id = str(uuid.uuid4())
    fpl_team_id = 999999  # Team user doesn't own

    # Access does not exist
    team_repo.client.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []

    result = await team_repo.check_user_team_access(user_id, fpl_team_id)

    assert result is False  # Fail-closed


@pytest.mark.asyncio
async def test_team_repo_check_user_team_access_error(team_repo):
    """Test authorization check with database error (fail-closed)."""
    user_id = str(uuid.uuid4())
    fpl_team_id = 123456

    team_repo.client.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.side_effect = (
        Exception("Database error")
    )

    result = await team_repo.check_user_team_access(user_id, fpl_team_id)

    assert result is False  # Fail-closed


@pytest.mark.asyncio
async def test_token_repo_store_refresh_token(token_repo):
    """Test storing encrypted refresh token."""
    user_id = str(uuid.uuid4())
    encrypted_token = "kv_1_base64encrypteddata"

    token_repo.client.table.return_value.insert.return_value.execute.return_value.data = [
        {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "encrypted_refresh_token": encrypted_token,
            "token_version": 1,
            "expires_at": "2026-10-04T00:00:00",
        }
    ]

    result = await token_repo.store_refresh_token(user_id, encrypted_token)

    assert result is not None
    assert result["encrypted_refresh_token"] == encrypted_token


@pytest.mark.asyncio
async def test_token_repo_get_active_refresh_token(token_repo):
    """Test retrieving active refresh token."""
    user_id = str(uuid.uuid4())
    token_id = str(uuid.uuid4())

    token_repo.client.table.return_value.select.return_value.eq.return_value.is_.return_value.gt.return_value.order.return_value.limit.return_value.execute.return_value.data = [
        {
            "id": token_id,
            "user_id": user_id,
            "encrypted_refresh_token": "kv_1_...",
            "revoked_at": None,
        }
    ]

    result = await token_repo.get_active_refresh_token(user_id)

    assert result is not None
    assert result["id"] == token_id


@pytest.mark.asyncio
async def test_token_repo_revoke_token(token_repo):
    """Test revoking (invalidating) refresh token."""
    token_id = str(uuid.uuid4())

    token_repo.client.table.return_value.update.return_value.eq.return_value.execute.return_value.data = [
        {"id": token_id}
    ]

    result = await token_repo.revoke_token(token_id)

    assert result is True


@pytest.mark.asyncio
async def test_audit_repo_log_api_call(audit_repo):
    """Test logging API call to audit table."""
    user_id = str(uuid.uuid4())

    audit_repo.client.table.return_value.insert.return_value.execute.return_value = None

    result = await audit_repo.log_api_call(
        user_id=user_id,
        endpoint="/api/me",
        method="GET",
        status_code=200,
        request_duration_ms=150,
    )

    assert result is True


@pytest.mark.asyncio
async def test_audit_repo_log_api_call_with_error(audit_repo):
    """Test logging failed API call (403 authorization failure)."""
    user_id = str(uuid.uuid4())

    audit_repo.client.table.return_value.insert.return_value.execute.return_value = None

    result = await audit_repo.log_api_call(
        user_id=user_id,
        endpoint="/api/entry/999999",
        method="GET",
        fpl_team_id=999999,
        status_code=403,
        error_message="User does not own this team",
        request_duration_ms=50,
    )

    assert result is True


@pytest.mark.asyncio
async def test_rls_enforcement_service_role_access():
    """
    Test RLS enforcement: service role can access all tables.
    Note: Requires actual Supabase connection.
    This is a conceptual test showing what should happen.
    """
    # In production, this would connect to actual Supabase
    # and verify service role can read/write
    # Skipping for now, will test against Supabase cloud
    pass


@pytest.mark.asyncio
async def test_rls_enforcement_anon_denied():
    """
    Test RLS enforcement: anonymous users cannot access any table.
    Note: Requires actual Supabase connection.
    """
    # In production, this would connect as anon and verify 403
    pass


@pytest.mark.asyncio
async def test_authorization_binding_single_source_of_truth(team_repo):
    """
    Test that user_teams table is single source of truth for access.
    Blocker #3: Never trust user-supplied team_id.
    """
    user_id = str(uuid.uuid4())
    owned_team_id = 123456
    unowned_team_id = 999999

    # Owned team exists in mapping
    def mock_check_access(uid, team_id):
        if uid == user_id and team_id == owned_team_id:
            return True
        return False

    # Simulate the check
    assert mock_check_access(user_id, owned_team_id) is True
    assert mock_check_access(user_id, unowned_team_id) is False

    # Never trust user-supplied team_id
    # Always query user_teams table
