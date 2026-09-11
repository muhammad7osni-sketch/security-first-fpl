"""
FPL Login route — proxies the FPL email/password login on behalf of
Flutter Web clients, which cannot POST to users.premierleague.com
directly due to browser CORS + SameSite cookie restrictions.

Security contract (matches the Supabase Edge Function it replaces):
  - Password is forwarded over HTTPS only and never stored or logged.
  - Only the public team_id integer is returned to the caller.
  - The pl_profile session cookie is used in-memory and never persisted.
  - Rate-limited to 5 attempts per IP per hour.
"""

import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import httpx
from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, field_validator

from app.database.db import get_supabase_client
from app.middleware.rate_limiter import limiter
import logging

router = APIRouter(prefix="/fpl", tags=["fpl-login"])
logger = logging.getLogger(__name__)

# ── Constants ──────────────────────────────────────────────────────────────────

_FPL_LOGIN_URL = "https://users.premierleague.com/accounts/login/"
_FPL_ME_URL = "https://fantasy.premierleague.com/api/me/"
_MAX_ATTEMPTS = 5
_WINDOW_HOURS = 1

_HEADERS = {
    "Content-Type": "application/x-www-form-urlencoded",
    "Referer": "https://fantasy.premierleague.com/",
    "Origin": "https://fantasy.premierleague.com",
    "User-Agent": "Mozilla/5.0 (compatible; SquadIQ/1.0)",
}

# ── Schemas ────────────────────────────────────────────────────────────────────


class FplLoginRequest(BaseModel):
    email: str
    password: str

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        v = v.strip().lower()
        if not re.match(r"^[^\s@]+@[^\s@]+\.[^\s@]+$", v):
            raise ValueError("Invalid email format")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if not v:
            raise ValueError("Password is required")
        return v


class FplLoginResponse(BaseModel):
    team_id: int
    team_name: str
    manager_name: str


# ── Route ──────────────────────────────────────────────────────────────────────


@router.post("/login", response_model=FplLoginResponse)
@limiter.limit("5/hour")
async def fpl_login(
    request: Request, body: FplLoginRequest
) -> FplLoginResponse:
    """
    POST /fpl/login

    Accepts { email, password } and returns { team_id, team_name, manager_name }.
    The password is never stored or logged.
    """
    client_ip = _get_client_ip(request)

    # ── Rate-limit check via Supabase ──────────────────────────────────
    try:
        db = await get_supabase_client()
        window_start = (
            datetime.now(timezone.utc) - timedelta(hours=_WINDOW_HOURS)
        ).isoformat()

        result = (
            await db.table("fpl_login_attempts")
            .select("id")
            .eq("ip_address", client_ip)
            .gte("attempted_at", window_start)
            .execute()
        )
        recent = len(result.data or [])
        if recent >= _MAX_ATTEMPTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many login attempts. Please wait 1 hour.",
            )
    except HTTPException:
        raise
    except Exception as exc:
        # Non-fatal: log and continue rather than blocking the user.
        logger.warning("rate_limit_check_failed: %s", exc)

    # ── POST to FPL ────────────────────────────────────────────────────
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(connect=15.0, read=20.0, write=10.0, pool=5.0),
        follow_redirects=False,
    ) as http:
        try:
            login_resp = await http.post(
                _FPL_LOGIN_URL,
                headers=_HEADERS,
                data={
                    "login": body.email,
                    "password": body.password,
                    "app": "plfpl-web",
                    "redirect_uri": "https://fantasy.premierleague.com/",
                },
            )
        except httpx.RequestError as exc:
            await _log_attempt(client_ip, success=False)
            logger.error("fpl_login_network_error: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Cannot reach FPL. Please try again later.",
            )

        # ── Extract pl_profile cookie ──────────────────────────────────
        pl_profile = _extract_pl_profile(login_resp)

        if not pl_profile:
            await _log_attempt(client_ip, success=False)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="FPL login failed. Check your email and password.",
            )

        # ── Call /me/ to get team ID ───────────────────────────────────
        try:
            me_resp = await http.get(
                _FPL_ME_URL,
                headers={
                    "Cookie": pl_profile,
                    "Referer": "https://fantasy.premierleague.com/",
                    "User-Agent": _HEADERS["User-Agent"],
                },
            )
            me_data: Dict[str, Any] = me_resp.json()
        except Exception as exc:
            await _log_attempt(client_ip, success=False)
            logger.error("fpl_me_error: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Unexpected response from FPL.",
            )

    entry = me_data.get("entry")
    player = me_data.get("player") or {}

    if not entry:
        await _log_attempt(client_ip, success=False)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "No FPL team found for this account. "
                "Create a team at fantasy.premierleague.com first."
            ),
        )

    team_id = entry.get("id")
    if not isinstance(team_id, int):
        await _log_attempt(client_ip, success=False)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not read team ID from FPL.",
        )

    await _log_attempt(client_ip, success=True)

    return FplLoginResponse(
        team_id=team_id,
        team_name=str(entry.get("name", "")),
        manager_name=f"{player.get('first_name', '')} {player.get('last_name', '')}".strip(),
    )


# ── Helpers ────────────────────────────────────────────────────────────────────


def _get_client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _extract_pl_profile(response: httpx.Response) -> Optional[str]:
    """Pull the pl_profile=... part from Set-Cookie headers."""
    for raw in response.headers.get_list("set-cookie"):
        for part in raw.split(";"):
            trimmed = part.strip()
            if trimmed.startswith("pl_profile="):
                return trimmed
    return None


async def _log_attempt(ip: str, *, success: bool) -> None:
    try:
        db = await get_supabase_client()
        await db.table("fpl_login_attempts").insert(
            {"ip_address": ip, "success": success}
        ).execute()
    except Exception as exc:
        logger.warning("log_attempt_failed: %s", exc)
