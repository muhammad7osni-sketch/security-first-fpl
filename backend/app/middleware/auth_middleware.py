"""
PHASE 4: Authorization middleware for FastAPI.
Validates Bearer tokens and enforces fail-closed authorization.
"""

from fastapi import Request, HTTPException, status
from typing import Optional, Dict, Any
from app.auth.jwt_validator import get_jwt_validator
import logging

logger = logging.getLogger(__name__)


class AuthContext:
    """Container for authenticated user context."""

    def __init__(self, user_id: str, claims: Dict[str, Any]):
        self.user_id = user_id
        self.claims = claims
        self.timestamp = None


async def extract_bearer_token(request: Request) -> Optional[str]:
    """
    Extract Bearer token from Authorization header.
    Never logs the token value.
    Fail-closed: any format error returns None.
    """
    try:
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return None
        return auth_header[7:]  # Remove "Bearer " prefix
    except Exception:
        return None


async def validate_bearer_token(token: str) -> Optional[AuthContext]:
    """
    Validate Bearer token using JWT validator.
    Returns AuthContext if valid, None otherwise.
    Never logs token.
    """
    try:
        validator = await get_jwt_validator()
        claims = await validator.validate(token)
        if not claims:
            return None

        user_id = claims.get("user_id")
        if not user_id:
            return None

        return AuthContext(user_id=user_id, claims=claims)

    except Exception:
        return None


async def require_auth(request: Request) -> AuthContext:
    """
    FastAPI dependency to require Bearer token.
    Raises 401 Unauthorized if token missing or invalid.
    """
    token = await extract_bearer_token(request)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    auth_context = await validate_bearer_token(token)
    if not auth_context:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return auth_context


async def optional_auth(request: Request) -> Optional[AuthContext]:
    """
    FastAPI dependency for optional Bearer token.
    Returns AuthContext if valid token, None otherwise.
    Never raises exception.
    """
    token = await extract_bearer_token(request)
    if not token:
        return None

    return await validate_bearer_token(token)
