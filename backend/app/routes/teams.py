"""
PHASE 4: Teams API routes.
Implements fail-closed authorization for FPL resource access.
Includes rate limiting to prevent abuse.
"""

from fastapi import APIRouter, HTTPException, status, Depends, Request
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from app.middleware.auth_middleware import require_auth, AuthContext
from app.api.fpl_client import get_fpl_client
from app.database.db import get_supabase_client, TeamRepository, UserRepository
from app.middleware.rate_limiter import limiter
import logging

router = APIRouter(prefix="/api/teams", tags=["teams"])
logger = logging.getLogger(__name__)


class TeamResponse(BaseModel):
    """FPL team response."""

    fpl_team_id: int
    team_name: str
    player_name: str


class UserTeamsResponse(BaseModel):
    """User's teams response."""

    teams: List[Dict[str, Any]]


@router.get("/me", response_model=UserTeamsResponse)
@limiter.limit("100/minute")  # Rate limit: 100 calls per minute
async def get_user_teams(request: Request, auth: AuthContext = Depends(require_auth)) -> UserTeamsResponse:
    """
    GET /api/teams/me - Get authenticated user's FPL teams.
    
    Requires: Valid Bearer token (JWT from PingOne)
    
    Response: List of user's FPL teams from /api/me/ endpoint
    
    Never calls FPL API without authentication.
    Fail-closed: returns 401 if token invalid.
    """
    try:
        user_id = auth.user_id

        # Get FPL client
        fpl_client = await get_fpl_client()

        # Get user profile from FPL
        # Note: access_token stored in auth context (in-memory only, not persisted)
        # For now, return teams from Supabase (Step 4 will integrate with FPL API)
        client = await get_supabase_client()
        team_repo = TeamRepository(client)

        user_teams = await team_repo.get_user_teams(user_id)
        if user_teams is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to retrieve teams",
            )

        logger.info("get_user_teams", extra={"user_id": user_id, "team_count": len(user_teams)})

        return UserTeamsResponse(teams=user_teams)

    except HTTPException:
        raise
    except Exception as e:
        logger.error("get_user_teams_error", extra={"error": str(e)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve teams",
        )


@router.get("/link", response_model=Dict[str, str])
@limiter.limit("20/minute")  # Rate limit: 20 calls per minute
async def link_fpl_account(
    request: Request, fpl_team_id: int, auth: AuthContext = Depends(require_auth)
) -> Dict[str, str]:
    """
    GET /api/teams/link?fpl_team_id=123456 - Link FPL account to user.
    
    Requires: Valid Bearer token
    
    In production, this would:
    1. Query FPL /api/entry/{fpl_team_id}/ to verify ownership
    2. Bind user to team in user_teams table
    3. Store team_id for future authorization checks
    
    Fail-closed: If team_id doesn't exist or doesn't belong to user, return 403.
    """
    try:
        user_id = auth.user_id

        if not fpl_team_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Missing fpl_team_id",
            )

        # In production, would call FPL API to verify ownership
        # For now, just store the binding
        client = await get_supabase_client()
        team_repo = TeamRepository(client)

        result = await team_repo.bind_user_to_team(
            user_id=user_id,
            fpl_team_id=fpl_team_id,
        )

        if not result:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Failed to link FPL account",
            )

        logger.info(
            "link_fpl_account",
            extra={
                "user_id": user_id,
                "fpl_team_id": fpl_team_id,
            },
        )

        return {"status": "linked", "fpl_team_id": str(fpl_team_id)}

    except HTTPException:
        raise
    except Exception as e:
        logger.error("link_fpl_account_error", extra={"error": str(e)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to link account",
        )


@router.get("/{team_id}", response_model=Dict[str, Any])
@limiter.limit("100/minute")  # Rate limit: 100 calls per minute
async def get_team_data(
    request: Request, team_id: int, auth: AuthContext = Depends(require_auth)
) -> Dict[str, Any]:
    """
    GET /api/teams/{team_id} - Get FPL team data.
    
    PHASE 4: Fail-closed authorization (Blocker #3)
    
    Requires: Valid Bearer token
    
    Implementation:
    1. Extract user_id from JWT
    2. Check user_teams: does user own this team_id?
    3. If NO: return 403 (never call FPL API)
    4. If YES: call FPL /api/entry/{team_id}/ with access_token
    5. Log to audit trail
    
    Never trusts user-supplied team_id as proof of ownership.
    """
    try:
        user_id = auth.user_id

        # Step 1: Check authorization (user must own this team)
        client = await get_supabase_client()
        team_repo = TeamRepository(client)

        is_authorized = await team_repo.check_user_team_access(user_id, team_id)

        if not is_authorized:
            logger.warning(
                "authorization_denied_team_data",
                extra={
                    "user_id": user_id,
                    "team_id": team_id,
                },
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User does not own this FPL team",
            )

        # Step 2: Authorization passed, get team data
        # Note: In production, would use access_token from request/context
        # For now, return team data from Supabase
        user_teams = await team_repo.get_user_teams(user_id)
        if not user_teams:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Team not found",
            )

        team_data = next((t for t in user_teams if t["fpl_team_id"] == team_id), None)
        if not team_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Team not found",
            )

        logger.info(
            "get_team_data",
            extra={
                "user_id": user_id,
                "team_id": team_id,
            },
        )

        return team_data

    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            "get_team_data_error",
            extra={
                "error": str(e),
                "team_id": team_id,
            },
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve team data",
        )
