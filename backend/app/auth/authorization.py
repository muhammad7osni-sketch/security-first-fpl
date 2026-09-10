"""
PHASE 4: Authorization service (Blocker #3).
Implements fail-closed authorization:
- Bind authenticated user to FPL resource
- Query user_teams table (single source of truth)
- Return 403 if ownership cannot be established
- Never call FPL API without verified ownership
"""

from typing import Optional, Tuple
from app.database.db import get_supabase_client, TeamRepository
import logging

logger = logging.getLogger(__name__)


class AuthorizationService:
    """
    Fail-closed authorization for FPL resources.
    Blocker #3: Ownership validation is UNKNOWN but implementation is defensive.
    """

    def __init__(self):
        self.team_repo = None

    async def _get_team_repo(self) -> TeamRepository:
        """Get TeamRepository lazily."""
        if self.team_repo is None:
            client = await get_supabase_client()
            self.team_repo = TeamRepository(client)
        return self.team_repo

    async def authorize_team_access(
        self,
        user_id: str,
        fpl_team_id: int,
    ) -> Tuple[bool, Optional[str]]:
        """
        PHASE 4: Fail-Closed Authorization (Blocker #3)
        
        Check if user has access to FPL team.
        
        Args:
            user_id: Authenticated user UUID from JWT
            fpl_team_id: FPL entry_id or team_id (from user request)
        
        Returns:
            (is_authorized: bool, error_message: Optional[str])
            - (True, None): User owns this team
            - (False, "..."): User does not own, 403 should be returned
        
        CRITICAL:
        1. Never trust user-supplied team_id as proof of ownership
        2. Query user_teams table (single source of truth)
        3. Return False if not found (fail-closed)
        4. Never call FPL API without verified ownership
        5. Log all authorization checks for audit trail
        
        Implementation:
        - user_teams.user_id == authenticated user_id
        - user_teams.fpl_team_id == requested fpl_team_id
        - If not found in database, return 403 (fail-closed)
        """
        try:
            if not user_id or not fpl_team_id:
                return False, "Missing user_id or team_id"

            team_repo = await self._get_team_repo()

            # Query user_teams for ownership
            has_access = await team_repo.check_user_team_access(user_id, fpl_team_id)

            if has_access:
                logger.info(
                    "authorization_granted",
                    extra={
                        "user_id": user_id,
                        "fpl_team_id": fpl_team_id,
                    },
                )
                return True, None
            else:
                logger.warning(
                    "authorization_denied",
                    extra={
                        "user_id": user_id,
                        "fpl_team_id": fpl_team_id,
                        "reason": "team_id_not_in_user_teams",
                    },
                )
                return False, "User does not own this FPL team"

        except Exception as e:
            # Fail-closed: any error denies access
            logger.error(
                "authorization_error",
                extra={
                    "user_id": user_id,
                    "fpl_team_id": fpl_team_id,
                    "error": str(e),
                },
            )
            return False, "Authorization check failed"

    async def authorize_fpl_api_call(
        self,
        user_id: str,
        endpoint: str,
        fpl_team_id: Optional[int] = None,
    ) -> Tuple[bool, Optional[str]]:
        """
        Authorize FPL API call (general method).
        
        Args:
            user_id: Authenticated user UUID
            endpoint: FPL endpoint path (e.g., /api/entry/123)
            fpl_team_id: Optional team_id (extracted from endpoint if needed)
        
        Returns:
            (is_authorized: bool, error_message: Optional[str])
        
        Common FPL endpoints:
        - /api/me/ — Gets user's teams (user_id only)
        - /api/entry/{id}/ — Gets specific entry/team (requires ownership)
        - /api/my-team/{id}/ — Gets team details (requires ownership)
        """
        try:
            # For /api/me/, user_id is sufficient (read own profile)
            if endpoint == "/api/me/":
                logger.info(
                    "authorization_fpl_api_call",
                    extra={
                        "user_id": user_id,
                        "endpoint": endpoint,
                    },
                )
                return True, None

            # For endpoints with team_id, verify ownership
            if fpl_team_id:
                return await self.authorize_team_access(user_id, fpl_team_id)

            # Unknown endpoint or missing team_id
            logger.warning(
                "authorization_fpl_api_call_unknown",
                extra={
                    "user_id": user_id,
                    "endpoint": endpoint,
                    "fpl_team_id": fpl_team_id,
                },
            )
            return False, "Cannot verify authorization for this endpoint"

        except Exception as e:
            logger.error(
                "authorization_fpl_api_call_error",
                extra={
                    "user_id": user_id,
                    "endpoint": endpoint,
                    "error": str(e),
                },
            )
            return False, "Authorization check failed"


# Global authorization service
_auth_service: Optional[AuthorizationService] = None


async def get_authorization_service() -> AuthorizationService:
    """Get or create global authorization service."""
    global _auth_service
    if _auth_service is None:
        _auth_service = AuthorizationService()
    return _auth_service
