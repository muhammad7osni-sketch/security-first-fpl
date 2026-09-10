"""
PHASE 4: Unit tests for JWT validator.
Tests 7-step JWT validation process.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime, timedelta
import json
from app.auth.jwt_validator import JWTValidator
from jwt import encode


@pytest.fixture
def jwt_validator():
    """Create JWT validator for testing."""
    return JWTValidator()


@pytest.fixture
def mock_jwks():
    """Mock JWKS response from PingOne."""
    return {
        "keys": [
            {
                "kid": "test-key-id",
                "kty": "RSA",
                "use": "sig",
                "alg": "RS256",
                "n": "test-modulus",
                "e": "AQAB",
            }
        ]
    }


@pytest.fixture
def valid_token_claims():
    """Valid token claims."""
    return {
        "sub": "pingone-user-id-123",
        "email": "user@example.com",
        "iss": "https://account.premierleague.com/as",
        "aud": "test-client-id",
        "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
        "iat": int(datetime.utcnow().timestamp()),
    }


@pytest.mark.asyncio
async def test_jwt_validator_fetch_jwks_success(jwt_validator, mock_jwks):
    """Test JWKS fetching with successful response."""
    with patch("httpx.AsyncClient") as mock_client:
        mock_response = AsyncMock()
        mock_response.json.return_value = mock_jwks
        mock_response.raise_for_status = AsyncMock()

        mock_client.return_value.__aenter__.return_value.get = AsyncMock(
            return_value=mock_response
        )

        result = await jwt_validator._fetch_jwks()
        assert result == mock_jwks
        assert jwt_validator.jwks_cache == mock_jwks


@pytest.mark.asyncio
async def test_jwt_validator_fetch_jwks_cache(jwt_validator, mock_jwks):
    """Test JWKS caching (should not refetch within 24 hours)."""
    jwt_validator.jwks_cache = mock_jwks
    jwt_validator.jwks_cache_expires = datetime.utcnow() + timedelta(hours=1)

    result = await jwt_validator._fetch_jwks()
    assert result == mock_jwks


@pytest.mark.asyncio
async def test_jwt_validator_fetch_jwks_failure(jwt_validator):
    """Test JWKS fetching with network error."""
    with patch("httpx.AsyncClient") as mock_client:
        mock_client.return_value.__aenter__.return_value.get = AsyncMock(
            side_effect=Exception("Network error")
        )

        result = await jwt_validator._fetch_jwks()
        assert result is None


def test_get_key_from_jwks(jwt_validator, mock_jwks):
    """Test extracting key from JWKS by kid."""
    key = jwt_validator._get_key_from_jwks("test-key-id", mock_jwks)
    assert key is not None
    assert key["kid"] == "test-key-id"


def test_get_key_from_jwks_not_found(jwt_validator, mock_jwks):
    """Test key not found in JWKS."""
    key = jwt_validator._get_key_from_jwks("nonexistent-key", mock_jwks)
    assert key is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_missing_token(jwt_validator):
    """Test validation with missing token."""
    result = await jwt_validator.validate("")
    assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_missing_kid(jwt_validator):
    """Test validation with missing kid in header."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"alg": "RS256"}  # No kid

        result = await jwt_validator.validate("fake-token")
        assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_jwks_unavailable(jwt_validator):
    """Test validation when JWKS is unavailable."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("httpx.AsyncClient") as mock_client:
            mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                side_effect=Exception("JWKS unavailable")
            )

            result = await jwt_validator.validate("fake-token")
            assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_expired_token(jwt_validator, mock_jwks):
    """Test validation with expired token."""
    expired_claims = {
        "sub": "user-123",
        "exp": int((datetime.utcnow() - timedelta(hours=1)).timestamp()),
    }

    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("httpx.AsyncClient") as mock_client:
            mock_response = AsyncMock()
            mock_response.json.return_value = mock_jwks
            mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                return_value=mock_response
            )

            result = await jwt_validator.validate("fake-token")
            assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_issuer_mismatch(jwt_validator, mock_jwks):
    """Test validation with issuer mismatch."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("jwt.decode") as mock_decode:
            mock_decode.return_value = {
                "sub": "user-123",
                "iss": "https://wrong-issuer.com",  # Wrong issuer
                "aud": "test-client-id",
                "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
            }

            with patch("httpx.AsyncClient") as mock_client:
                mock_response = AsyncMock()
                mock_response.json.return_value = mock_jwks
                mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                    return_value=mock_response
                )

                result = await jwt_validator.validate("fake-token")
                assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_audience_mismatch(jwt_validator, mock_jwks):
    """Test validation with audience mismatch."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("jwt.decode") as mock_decode:
            mock_decode.return_value = {
                "sub": "user-123",
                "iss": "https://account.premierleague.com/as",
                "aud": "wrong-audience",  # Wrong audience
                "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
            }

            with patch("httpx.AsyncClient") as mock_client:
                mock_response = AsyncMock()
                mock_response.json.return_value = mock_jwks
                mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                    return_value=mock_response
                )

                result = await jwt_validator.validate("fake-token")
                assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_missing_user_id(jwt_validator, mock_jwks):
    """Test validation with missing user_id (sub)."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("jwt.decode") as mock_decode:
            mock_decode.return_value = {
                # Missing "sub"
                "iss": "https://account.premierleague.com/as",
                "aud": "test-client-id",
                "exp": int((datetime.utcnow() + timedelta(hours=8)).timestamp()),
            }

            with patch("httpx.AsyncClient") as mock_client:
                mock_response = AsyncMock()
                mock_response.json.return_value = mock_jwks
                mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                    return_value=mock_response
                )

                result = await jwt_validator.validate("fake-token")
                assert result is None


@pytest.mark.asyncio
async def test_jwt_validator_validate_success(jwt_validator, mock_jwks, valid_token_claims):
    """Test successful validation (all 7 steps pass)."""
    with patch("jwt.get_unverified_header") as mock_get_header:
        mock_get_header.return_value = {"kid": "test-key-id"}

        with patch("jwt.decode") as mock_decode:
            mock_decode.return_value = valid_token_claims

            with patch("httpx.AsyncClient") as mock_client:
                mock_response = AsyncMock()
                mock_response.json.return_value = mock_jwks
                mock_client.return_value.__aenter__.return_value.get = AsyncMock(
                    return_value=mock_response
                )

                result = await jwt_validator.validate("fake-token")
                assert result is not None
                assert result["user_id"] == "pingone-user-id-123"
                assert result["email"] == "user@example.com"
