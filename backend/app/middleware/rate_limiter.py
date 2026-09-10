"""
PHASE 4: Rate limiting middleware.
Uses slowapi for per-endpoint and per-user rate limiting.
Prevents DoS attacks while allowing legitimate traffic.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, status
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)

# Create limiter with remote address as key
limiter = Limiter(key_func=get_remote_address)


def create_rate_limit_error_handler():
    """Create custom error handler for rate limit exceeded."""
    
    async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
        """Handle rate limit exceeded errors."""
        logger.warning(
            "rate_limit_exceeded",
            extra={
                "client": get_remote_address(request),
                "path": request.url.path,
                "limit": exc.detail,
            },
        )
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content={"detail": "Rate limit exceeded. Please try again later."},
        )
    
    return rate_limit_exceeded_handler


# Rate limit configurations
RATE_LIMITS = {
    # Authentication endpoints (sensitive, low limit)
    "auth_callback": "5/minute",  # 5 calls per minute
    "auth_refresh": "10/minute",  # 10 calls per minute
    "auth_logout": "10/minute",  # 10 calls per minute
    
    # API endpoints (standard limit)
    "get_user_teams": "100/minute",  # 100 calls per minute
    "get_team_data": "100/minute",  # 100 calls per minute
    "link_fpl_account": "20/minute",  # 20 calls per minute
    
    # Health check (unrestricted)
    "health_check": "1000/minute",  # 1000 calls per minute (essentially unlimited)
}


def get_rate_limit(endpoint_name: str) -> str:
    """Get rate limit for endpoint."""
    return RATE_LIMITS.get(endpoint_name, "100/minute")
