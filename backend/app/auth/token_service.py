"""
PHASE 4: Token Service for OAuth 2.0 OIDC code exchange and refresh.
Handles:
- Authorization code exchange (PKCE flow)
- Access token retrieval
- Refresh token rotation and storage
- Token logout (invalidation)

Never logs tokens, codes, or sensitive HTTP headers.
"""

import httpx
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
from app.config import settings
from app.auth.encryption import get_encryption_service


class TokenService:
    """Manages OAuth 2.0 token operations."""

    def __init__(self):
        self.token_endpoint = settings.oidc_token_endpoint
        self.client_id = settings.oidc_client_id
        self.timeout = settings.fpl_timeout_seconds

    async def exchange_code_for_tokens(
        self,
        code: str,
        code_verifier: str,
        redirect_uri: str,
    ) -> Optional[Dict[str, Any]]:
        """
        Exchange authorization code for access and refresh tokens.
        Uses PKCE flow (code_challenge already verified by PingOne).
        
        Returns:
            {
                "access_token": "...",
                "refresh_token": "..." (encrypted),
                "expires_in": 28800,
                "token_type": "Bearer"
            }
        
        Never logs code, access_token, or refresh_token.
        """
        if not code or not code_verifier:
            return None

        try:
            # Prepare token request (PKCE flow, no client_secret for public client)
            payload = {
                "grant_type": "authorization_code",
                "code": code,
                "client_id": self.client_id,
                "redirect_uri": redirect_uri,
                "code_verifier": code_verifier,
            }

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(self.token_endpoint, data=payload)
                response.raise_for_status()

            token_response = response.json()

            # Encrypt refresh token before returning
            refresh_token = token_response.get("refresh_token")
            if refresh_token:
                encryption_service = get_encryption_service()
                encrypted_refresh_token = encryption_service.encrypt(
                    refresh_token,
                    associated_data=code,  # Bind to code for integrity
                )
                token_response["refresh_token"] = encrypted_refresh_token

            return {
                "access_token": token_response.get("access_token"),
                "refresh_token": token_response.get("refresh_token"),  # encrypted
                "expires_in": token_response.get("expires_in", 28800),
                "token_type": token_response.get("token_type", "Bearer"),
            }

        except Exception:
            # Fail-closed: token exchange failure
            return None

    async def refresh_access_token(
        self,
        encrypted_refresh_token: str,
        associated_data: str = "",
    ) -> Optional[Dict[str, Any]]:
        """
        Use refresh token to get new access token.
        
        According to PingOne docs: refresh tokens are rotated and old token invalidated.
        Caller must store new encrypted_refresh_token.
        
        Returns:
            {
                "access_token": "...",
                "refresh_token": "..." (new, encrypted),
                "expires_in": 28800,
            }
        
        Never logs tokens.
        """
        if not encrypted_refresh_token:
            return None

        try:
            # Decrypt refresh token
            encryption_service = get_encryption_service()
            refresh_token = encryption_service.decrypt(
                encrypted_refresh_token,
                associated_data=associated_data,
            )

            if not refresh_token:
                return None  # Decryption failed

            # Request new tokens
            payload = {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": self.client_id,
            }

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(self.token_endpoint, data=payload)
                response.raise_for_status()

            token_response = response.json()

            # Encrypt new refresh token
            new_refresh_token = token_response.get("refresh_token")
            if new_refresh_token:
                encrypted_new_refresh_token = encryption_service.encrypt(
                    new_refresh_token,
                    associated_data=associated_data,
                )
                token_response["refresh_token"] = encrypted_new_refresh_token

            return {
                "access_token": token_response.get("access_token"),
                "refresh_token": token_response.get("refresh_token"),  # encrypted, rotated
                "expires_in": token_response.get("expires_in", 28800),
            }

        except Exception:
            # Fail-closed: refresh failure
            return None

    async def logout(self, access_token: str) -> bool:
        """
        Invalidate tokens (revoke at PingOne).
        PingOne may not support revocation endpoint, but attempt gracefully.
        
        Never logs tokens.
        """
        if not access_token:
            return False

        try:
            # Attempt token revocation (may not be supported)
            revocation_endpoint = f"{settings.oidc_authority}/revocation"
            payload = {
                "token": access_token,
                "client_id": self.client_id,
            }

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(revocation_endpoint, data=payload)
                # 200 or 400 (already revoked) are both acceptable
                return response.status_code in [200, 400]

        except Exception:
            # Fail-closed: revocation attempt failed, but don't block logout
            return False


# Global token service instance
_token_service: Optional[TokenService] = None


async def get_token_service() -> TokenService:
    """Get or create global token service."""
    global _token_service
    if _token_service is None:
        _token_service = TokenService()
    return _token_service
