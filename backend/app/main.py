"""
PHASE 4: Main FastAPI application.
OAuth 2.0 OIDC + Supabase + JWT validation + Authorization.
"""

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from slowapi.errors import RateLimitExceeded
import logging

from app.config import settings
from app.middleware.logging import setup_logging
from app.middleware.rate_limiter import limiter, create_rate_limit_error_handler
from app.routes import auth, teams

# Setup logging first
setup_logging()
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="SquadIQ Phase 4 Backend",
    description="OAuth 2.0 OIDC + Supabase JWT validation",
    version="0.1.0",
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, create_rate_limit_error_handler())

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

# Trusted host middleware
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=[
        "*.premierleague.com",
        "localhost",
        "127.0.0.1",
    ],
)


@app.on_event("startup")
async def startup_event():
    """Initialize on startup."""
    logger.info("startup", extra={"environment": settings.environment})


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown."""
    logger.info("shutdown")


# Health check
@app.get("/health")
@limiter.limit("1000/minute")  # Rate limit: 1000 calls per minute (essentially unlimited)
async def health_check(request: Request):
    """Health check endpoint."""
    return {"status": "ok"}


# Include routers
app.include_router(auth.router)
app.include_router(teams.router)


# Exception handlers
@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle uncaught exceptions without exposing details."""
    logger.error("unhandled_exception", extra={"error": str(exc)})
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error"},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.debug,
        log_level=settings.log_level.lower(),
    )
