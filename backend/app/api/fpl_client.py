"""
PHASE 4: FPL API client with fail-closed authorization.
Wraps FPL API calls, enforces user ownership before calling FPL.
"""

import httpx
from typing import Optional, Dict, Any
import time
from app.config import settings
from app.auth.authorization import get_authorization_service
from app.database.db import get_supabase_client, UserRepository, TeamRepository, AuditRepository
import logging

logger = logging.getLogger(__name__)


class FPLApiClient:
    """
    Client for FPL API with authorization enforcement.
    Never calls FPL API without verified ownership (Blocker #3).
    """

    def __init__(self):
        self.base_url = settings.fpl_api_base_url
        self.timeout = settings.fpl_timeout_seconds
        self.max_retries = settings.fpl_max_retries

    async def _log_api_call(
        self,
        user_id: str,
        endpoint: str,
        method: str,
        status_code: int,
        error_message: str = None,
        duration_ms: int = 0,
        fpl_team_id: int = None,
    ) -> None:
        """Log API call to audit trail."""
        try:
            client = await get_supabase_client()
            audit_repo = AuditRepository(client)
            await audit_repo.log_api_call(
                user_id=user_id,
                endpoint=endpoint,
                method=method,
                fpl_team_id=fpl_team_id,
                status_code=status_code,
                error_message=error_message,
                request_duration_ms=duration_ms,
            )
        except Exception as e:
            logger.error("audit_log_error", extra={"error": str(e)})

    async def get_user_profile(self, user_id: str, access_token: str) -> Optional[Dict[str, Any]]:
        """
        GET /api/me/ - Get user's FPL profile.
        No team_id required (read own profile).
        """
        endpoint = "/api/me/"
        start_time = time.time()

        try:
            # Authorization not required for /api/me/ (user's own profile)
            url = f"{self.base_url}{endpoint}"

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    url,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "User-Agent": "SquadIQ-Phase4",
                    },
                )

            duration_ms = int((time.time() - start_time) * 1000)

            if response.status_code == 200:
                data = response.json()
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=200,
                    duration_ms=duration_ms,
                )
                return data
            elif response.status_code == 401:
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=401,
                    error_message="Invalid access token",
                    duration_ms=duration_ms,
                )
                return None
            else:
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=response.status_code,
                    error_message=f"FPL API error: {response.status_code}",
                    duration_ms=duration_ms,
                )
                return None

        except Exception as e:
            duration_ms = int((time.time() - start_time) * 1000)
            logger.error(
                "fpl_api_error",
                extra={
                    "endpoint": endpoint,
                    "error": str(e),
                },
            )
            await self._log_api_call(
                user_id=user_id,
                endpoint=endpoint,
                method="GET",
                status_code=500,
                error_message=str(e),
                duration_ms=duration_ms,
            )
            return None

    async def get_entry(
        self,
        user_id: str,
        fpl_team_id: int,
        access_token: str,
    ) -> Optional[Dict[str, Any]]:
        """
        GET /api/entry/{id}/ - Get FPL entry/team data.
        CRITICAL: Fail-closed authorization check before calling FPL.
        """
        endpoint = f"/api/entry/{fpl_team_id}/"
        start_time = time.time()

        try:
            # PHASE 4: Fail-closed authorization (Blocker #3)
            # Never trust user-supplied team_id
            auth_service = await get_authorization_service()
            is_authorized, error_msg = await auth_service.authorize_team_access(
                user_id=user_id,
                fpl_team_id=fpl_team_id,
            )

            duration_ms = int((time.time() - start_time) * 1000)

            if not is_authorized:
                # Log and return 403 (do NOT call FPL API)
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=403,
                    error_message=error_msg or "User does not own this team",
                    duration_ms=duration_ms,
                    fpl_team_id=fpl_team_id,
                )
                logger.warning(
                    "authorization_denied_fpl_api",
                    extra={
                        "user_id": user_id,
                        "fpl_team_id": fpl_team_id,
                        "endpoint": endpoint,
                    },
                )
                return None

            # Authorization passed, now call FPL API
            url = f"{self.base_url}{endpoint}"

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    url,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "User-Agent": "SquadIQ-Phase4",
                    },
                )

            duration_ms = int((time.time() - start_time) * 1000)

            if response.status_code == 200:
                data = response.json()
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=200,
                    duration_ms=duration_ms,
                    fpl_team_id=fpl_team_id,
                )
                return data
            else:
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=response.status_code,
                    error_message=f"FPL API error: {response.status_code}",
                    duration_ms=duration_ms,
                    fpl_team_id=fpl_team_id,
                )
                return None

        except Exception as e:
            duration_ms = int((time.time() - start_time) * 1000)
            logger.error(
                "fpl_api_error",
                extra={
                    "endpoint": endpoint,
                    "error": str(e),
                },
            )
            await self._log_api_call(
                user_id=user_id,
                endpoint=endpoint,
                method="GET",
                status_code=500,
                error_message=str(e),
                duration_ms=duration_ms,
                fpl_team_id=fpl_team_id,
            )
            return None

    async def get_fixtures(self, user_id: str, access_token: str) -> Optional[list]:
        """GET /api/fixtures/ - Get all fixtures (no team_id required)."""
        endpoint = "/api/fixtures/"
        start_time = time.time()

        try:
            url = f"{self.base_url}{endpoint}"

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    url,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "User-Agent": "SquadIQ-Phase4",
                    },
                )

            duration_ms = int((time.time() - start_time) * 1000)

            if response.status_code == 200:
                data = response.json()
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=200,
                    duration_ms=duration_ms,
                )
                return data
            else:
                await self._log_api_call(
                    user_id=user_id,
                    endpoint=endpoint,
                    method="GET",
                    status_code=response.status_code,
                    error_message=f"FPL API error: {response.status_code}",
                    duration_ms=duration_ms,
                )
                return None

        except Exception as e:
            duration_ms = int((time.time() - start_time) * 1000)
            await self._log_api_call(
                user_id=user_id,
                endpoint=endpoint,
                method="GET",
                status_code=500,
                error_message=str(e),
                duration_ms=duration_ms,
            )
            return None


# Global FPL client
_fpl_client: Optional[FPLApiClient] = None


async def get_fpl_client() -> FPLApiClient:
    """Get or create global FPL client."""
    global _fpl_client
    if _fpl_client is None:
        _fpl_client = FPLApiClient()
    return _fpl_client
