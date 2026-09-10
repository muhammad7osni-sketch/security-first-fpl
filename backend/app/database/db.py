"""
PHASE 4: Supabase database operations.
Manages connection, user/team management, token storage.
"""

from supabase import create_client, Client
from typing import Optional, Dict, List, Any
from datetime import datetime, timedelta
from app.config import settings
import logging

logger = logging.getLogger(__name__)

# Global Supabase client
_supabase_client: Optional[Client] = None


async def get_supabase_client() -> Client:
    """Get or create Supabase client."""
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = create_client(
            settings.supabase_url,
            settings.supabase_service_role_key,
        )
    return _supabase_client


class UserRepository:
    """Repository for user operations."""

    def __init__(self, supabase_client: Client):
        self.client = supabase_client

    async def create_user(
        self,
        email: str,
        pingone_user_id: str,
    ) -> Optional[Dict[str, Any]]:
        """
        Create or update user in database.
        Linked to PingOne user via pingone_user_id (sub claim).
        """
        try:
            response = self.client.table("users").upsert(
                {
                    "email": email,
                    "pingone_user_id": pingone_user_id,
                }
            ).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("create_user_error", extra={"error": str(e)})
            return None

    async def get_user_by_pingone_id(self, pingone_user_id: str) -> Optional[Dict[str, Any]]:
        """Get user by PingOne ID (sub claim)."""
        try:
            response = self.client.table("users").select("*").eq(
                "pingone_user_id", pingone_user_id
            ).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("get_user_by_pingone_id_error", extra={"error": str(e)})
            return None

    async def get_user_by_id(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Get user by UUID."""
        try:
            response = self.client.table("users").select("*").eq("id", user_id).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("get_user_by_id_error", extra={"error": str(e)})
            return None


class TeamRepository:
    """Repository for user_teams operations (authorization binding)."""

    def __init__(self, supabase_client: Client):
        self.client = supabase_client

    async def bind_user_to_team(
        self,
        user_id: str,
        fpl_team_id: int,
        fpl_manager_id: str = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Bind user to FPL team (authorization mapping).
        CRITICAL: This is the single source of truth for resource access.
        Never trust user-supplied team_id as proof of ownership.
        """
        try:
            response = self.client.table("user_teams").upsert(
                {
                    "user_id": user_id,
                    "fpl_team_id": fpl_team_id,
                    "fpl_manager_id": fpl_manager_id,
                }
            ).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("bind_user_to_team_error", extra={"error": str(e)})
            return None

    async def get_user_teams(self, user_id: str) -> Optional[List[Dict[str, Any]]]:
        """Get all FPL teams associated with a user."""
        try:
            response = self.client.table("user_teams").select("*").eq(
                "user_id", user_id
            ).execute()

            return response.data or []
        except Exception as e:
            logger.error("get_user_teams_error", extra={"error": str(e)})
            return None

    async def check_user_team_access(self, user_id: str, fpl_team_id: int) -> bool:
        """
        Check if user has access to FPL team.
        CRITICAL: Fail-closed authorization (Blocker #3).
        Returns False if not found (no access).
        """
        try:
            response = self.client.table("user_teams").select("id").eq(
                "user_id", user_id
            ).eq(
                "fpl_team_id", fpl_team_id
            ).execute()

            # Access granted only if mapping exists
            return len(response.data) > 0
        except Exception as e:
            logger.error("check_user_team_access_error", extra={"error": str(e)})
            return False  # Fail-closed


class TokenRepository:
    """Repository for auth_tokens operations."""

    def __init__(self, supabase_client: Client):
        self.client = supabase_client

    async def store_refresh_token(
        self,
        user_id: str,
        encrypted_refresh_token: str,
        token_version: int = 1,
        ttl_days: int = 30,
    ) -> Optional[Dict[str, Any]]:
        """
        Store encrypted refresh token in database.
        Tokens are encrypted at application layer, never stored plaintext.
        """
        try:
            expires_at = datetime.utcnow() + timedelta(days=ttl_days)

            response = self.client.table("auth_tokens").insert(
                {
                    "user_id": user_id,
                    "encrypted_refresh_token": encrypted_refresh_token,
                    "token_version": token_version,
                    "expires_at": expires_at.isoformat(),
                }
            ).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("store_refresh_token_error", extra={"error": str(e)})
            return None

    async def get_active_refresh_token(self, user_id: str) -> Optional[Dict[str, Any]]:
        """
        Get active (non-revoked, non-expired) refresh token for user.
        Returns most recent token.
        """
        try:
            response = self.client.table("auth_tokens").select("*").eq(
                "user_id", user_id
            ).is_("revoked_at", True).gt(
                "expires_at", datetime.utcnow().isoformat()
            ).order(
                "created_at", desc=True
            ).limit(1).execute()

            if response.data and len(response.data) > 0:
                return response.data[0]
            return None
        except Exception as e:
            logger.error("get_active_refresh_token_error", extra={"error": str(e)})
            return None

    async def revoke_token(self, token_id: str) -> bool:
        """
        Revoke (invalidate) refresh token by marking revoked_at.
        Called on logout.
        """
        try:
            response = self.client.table("auth_tokens").update(
                {"revoked_at": datetime.utcnow().isoformat()}
            ).eq("id", token_id).execute()

            return len(response.data) > 0
        except Exception as e:
            logger.error("revoke_token_error", extra={"error": str(e)})
            return False

    async def revoke_all_tokens(self, user_id: str) -> bool:
        """
        Revoke all refresh tokens for user (logout all devices).
        """
        try:
            self.client.table("auth_tokens").update(
                {"revoked_at": datetime.utcnow().isoformat()}
            ).eq("user_id", user_id).is_(
                "revoked_at", True
            ).execute()

            return True
        except Exception as e:
            logger.error("revoke_all_tokens_error", extra={"error": str(e)})
            return False


class AuditRepository:
    """Repository for audit_logs operations."""

    def __init__(self, supabase_client: Client):
        self.client = supabase_client

    async def log_api_call(
        self,
        user_id: str,
        endpoint: str,
        method: str,
        fpl_team_id: int = None,
        status_code: int = 200,
        error_message: str = None,
        request_duration_ms: int = 0,
    ) -> bool:
        """
        Log API call to audit_logs table.
        Called after every API operation.
        """
        try:
            self.client.table("audit_logs").insert(
                {
                    "user_id": user_id,
                    "endpoint": endpoint,
                    "method": method,
                    "fpl_team_id": fpl_team_id,
                    "status_code": status_code,
                    "error_message": error_message,
                    "request_duration_ms": request_duration_ms,
                }
            ).execute()

            return True
        except Exception as e:
            logger.error("log_api_call_error", extra={"error": str(e)})
            return False

    async def get_recent_logs(self, user_id: str, hours: int = 24) -> Optional[List[Dict]]:
        """Get recent audit logs for user."""
        try:
            start_time = (datetime.utcnow() - timedelta(hours=hours)).isoformat()

            response = self.client.table("audit_logs").select("*").eq(
                "user_id", user_id
            ).gt(
                "created_at", start_time
            ).order(
                "created_at", desc=True
            ).execute()

            return response.data or []
        except Exception as e:
            logger.error("get_recent_logs_error", extra={"error": str(e)})
            return None
