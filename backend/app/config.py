"""
PHASE 4: Configuration management for FastAPI backend.
Loads environment variables and GCP Secret Manager secrets.
Never logs sensitive values.
"""

import os
from typing import Optional
from pydantic_settings import BaseSettings
from google.cloud import secretmanager


class Settings(BaseSettings):
    """Application settings loaded from environment and GCP Secret Manager."""

    # Application
    environment: str = os.getenv("ENVIRONMENT", "development")
    debug: bool = environment == "development"
    app_name: str = "SquadIQ Phase 4 Backend"

    # OAuth 2.0 OIDC Configuration
    oidc_authority: str = "https://account.premierleague.com/as"
    oidc_client_id: str = os.getenv("OIDC_CLIENT_ID", "")
    oidc_jwks_uri: str = "https://account.premierleague.com/as/jwks"
    oidc_token_endpoint: str = "https://account.premierleague.com/as/token"

    # FPL API Configuration
    fpl_api_base_url: str = "https://fantasy.premierleague.com/api"
    fpl_max_retries: int = 3
    fpl_timeout_seconds: int = 30

    # JWT Configuration
    jwt_algorithm: str = "RS256"
    jwt_expiration_seconds: int = 28800  # 8 hours
    jwt_audience: str = "squadiq-fpl"
    jwt_issuer: str = "https://account.premierleague.com/as"

    # Supabase Configuration
    supabase_url: str = os.getenv("SUPABASE_URL", "")
    supabase_service_role_key: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

    # Encryption Configuration
    encryption_algorithm: str = "AES-256-GCM"
    encryption_key_rotation_days: int = 90

    # Logging & Monitoring
    sentry_dsn: Optional[str] = os.getenv("SENTRY_DSN", None)
    log_level: str = os.getenv("LOG_LEVEL", "INFO")

    # Security: Rate Limiting
    rate_limit_requests: int = 100
    rate_limit_window_seconds: int = 60

    # Security: CORS (configurable via ALLOWED_ORIGINS env var)
    allowed_origins_str: str = os.getenv(
        "ALLOWED_ORIGINS",
        "https://fantasy.premierleague.com,http://localhost:3000,http://localhost:5000"
    )
    allowed_origins: list = [url.strip() for url in allowed_origins_str.split(",")]

    class Config:
        env_file = ".env"
        case_sensitive = False

    def get_secret(self, secret_name: str) -> str:
        """
        Retrieve secret from GCP Secret Manager.
        Returns empty string if not found (fail-closed).
        Never logs the secret value.
        """
        if self.environment == "development":
            # In development, use environment variables
            return os.getenv(secret_name, "")

        try:
            project_id = os.getenv("GCP_PROJECT_ID")
            if not project_id:
                return ""

            client = secretmanager.SecretManagerServiceClient()
            name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            return response.payload.data.decode("UTF-8")
        except Exception:
            # Fail-closed: log error but do not expose details
            return ""


# Global settings instance
settings = Settings()

