"""
Authentication routes using Supabase email/password authentication.
"""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from app.database.db import get_supabase_client
import logging

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)


class AuthRequest(BaseModel):
    email: str
    password: str


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "Bearer"


@router.post("/register", response_model=AuthResponse)
async def register(data: AuthRequest) -> AuthResponse:
    try:
        client = await get_supabase_client()

        response = await client.auth.sign_up({
            "email": data.email,
            "password": data.password,
        })

        if not response.session:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration requires email confirmation",
            )

        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            expires_in=response.session.expires_in or 3600,
        )

    except HTTPException:
        raise
    except Exception:
        logger.exception("Registration failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration failed",
        )


@router.post("/login", response_model=AuthResponse)
async def login(data: AuthRequest) -> AuthResponse:
    try:
        client = await get_supabase_client()

        response = await client.auth.sign_in_with_password({
            "email": data.email,
            "password": data.password,
        })

        if not response.session:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password",
            )

        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            expires_in=response.session.expires_in or 3600,
        )

    except HTTPException:
        raise
    except Exception:
        logger.exception("Login failed")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
