"""
PHASE 4: JWT Validator for OAuth 2.0 OIDC tokens.
Implements 7-step validation:
1. Signature verification using JWKS
2. Expiration check
3. Issuer validation
4. Audience validation
5. Extract user_id (PingOne ID)
6. Validate token not tampered
7. Return validated claims or None
"""

import json
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
import httpx
from jwt import decode, get_unverified_header, InvalidTokenError
from app.config import settings


class JWTValidator:
    """Validates JWT tokens from PingOne OAuth 2.0 OIDC endpoint."""

    def __init__(self):
        self.jwks_uri = settings.oidc_jwks_uri
        self.jwks_cache = None
        self.jwks_cache_expires = None
        self.cache_ttl = timedelta(hours=24)

    async def _fetch_jwks(self) -> Optional[Dict[str, Any]]:
        """
        Fetch JWKS from PingOne endpoint.
        Cached for 24 hours.
        Never logs keys or tokens.
        """
        # Check cache
        if self.jwks_cache and self.jwks_cache_expires and datetime.utcnow() < self.jwks_cache_expires:
            return self.jwks_cache

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(self.jwks_uri)
                response.raise_for_status()
                self.jwks_cache = response.json()
                self.jwks_cache_expires = datetime.utcnow() + self.cache_ttl
                return self.jwks_cache
        except Exception:
            # Fail-closed: JWKS unavailable
            return None

    def _get_key_from_jwks(self, kid: str, jwks: Dict) -> Optional[Dict]:
        """Extract key by kid from JWKS."""
        if not jwks or "keys" not in jwks:
            return None
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                return key
        return None

    async def validate(self, token: str) -> Optional[Dict[str, Any]]:
        """
        PHASE 4: 7-Step JWT Validation
        
        1. Extract header and verify kid exists
        2. Fetch JWKS and extract public key
        3. Verify signature using public key
        4. Validate expiration (exp)
        5. Validate issuer (iss)
        6. Validate audience (aud)
        7. Extract and return user_id claim
        
        Returns validated claims or None if any step fails.
        Never logs token, signature, or key details.
        """
        if not token:
            return None

        try:
            # Step 1: Extract header to get kid
            unverified_header = get_unverified_header(token)
            kid = unverified_header.get("kid")
            if not kid:
                return None  # No kid in header

            # Step 2: Fetch JWKS and get public key
            jwks = await self._fetch_jwks()
            if not jwks:
                return None  # JWKS unavailable

            key_data = self._get_key_from_jwks(kid, jwks)
            if not key_data:
                return None  # Key not found

            # Step 3: Verify signature
            try:
                claims = decode(
                    token,
                    key_data,
                    algorithms=[settings.jwt_algorithm],
                    options={"verify_signature": True, "verify_exp": False},
                )
            except InvalidTokenError:
                return None  # Signature invalid

            # Step 4: Validate expiration
            exp = claims.get("exp")
            if not exp or datetime.fromtimestamp(exp) < datetime.utcnow():
                return None  # Token expired

            # Step 5: Validate issuer
            iss = claims.get("iss")
            if iss != settings.jwt_issuer:
                return None  # Issuer mismatch

            # Step 6: Validate audience
            aud = claims.get("aud")
            if not aud or settings.oidc_client_id not in (aud if isinstance(aud, list) else [aud]):
                return None  # Audience mismatch

            # Step 7: Extract user_id (sub claim contains PingOne user ID)
            user_id = claims.get("sub")
            if not user_id:
                return None  # No user_id

            # Return validated claims
            return {
                "user_id": user_id,
                "email": claims.get("email"),
                "iat": claims.get("iat"),
                "exp": claims.get("exp"),
                "raw_claims": claims,  # Keep for debugging (in secure logging only)
            }

        except Exception:
            # Fail-closed: any validation error returns None
            return None


# Global JWT validator instance
_jwt_validator: Optional[JWTValidator] = None


async def get_jwt_validator() -> JWTValidator:
    """Get or create global JWT validator."""
    global _jwt_validator
    if _jwt_validator is None:
        _jwt_validator = JWTValidator()
    return _jwt_validator
