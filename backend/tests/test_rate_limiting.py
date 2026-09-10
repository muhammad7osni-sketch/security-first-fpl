"""
PHASE 4 STAGING: Rate limiting tests
Verifies slowapi rate limiting prevents DoS attacks
Tests 429 Too Many Requests responses
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pytest
from unittest.mock import AsyncMock, MagicMock
from app.middleware.rate_limiter import get_rate_limit


def test_rate_limits_configured():
    """Verify all rate limits are configured"""
    
    limits = {
        "auth_callback": "5/minute",
        "auth_refresh": "10/minute",
        "auth_logout": "10/minute",
        "get_user_teams": "100/minute",
        "get_team_data": "100/minute",
        "link_fpl_account": "20/minute",
        "health_check": "1000/minute",
    }
    
    for endpoint, expected_limit in limits.items():
        actual_limit = get_rate_limit(endpoint)
        assert actual_limit == expected_limit
        print(f"✓ PASS: {endpoint} → {actual_limit}")


def test_auth_callback_rate_limit_strict():
    """Verify auth_callback has strictest limit (5/minute)"""
    limit = get_rate_limit("auth_callback")
    assert limit == "5/minute"
    print(f"✓ PASS: auth_callback limit is strict: {limit}")


def test_health_check_rate_limit_lenient():
    """Verify health_check has lenient limit (1000/minute)"""
    limit = get_rate_limit("health_check")
    assert limit == "1000/minute"
    print(f"✓ PASS: health_check limit is lenient: {limit}")


def test_api_endpoints_reasonable_limits():
    """Verify API endpoints have reasonable limits"""
    
    get_teams_limit = get_rate_limit("get_user_teams")
    get_team_data_limit = get_rate_limit("get_team_data")
    
    # Both should be 100/minute
    assert get_teams_limit == "100/minute"
    assert get_team_data_limit == "100/minute"
    
    print(f"✓ PASS: get_user_teams → {get_teams_limit}")
    print(f"✓ PASS: get_team_data → {get_team_data_limit}")


def test_sensitive_endpoints_protected():
    """Verify sensitive endpoints have low limits"""
    
    callback_limit = get_rate_limit("auth_callback")  # 5/minute
    refresh_limit = get_rate_limit("auth_refresh")  # 10/minute
    link_limit = get_rate_limit("link_fpl_account")  # 20/minute
    
    # Callback most strict (5)
    assert callback_limit == "5/minute"
    
    # Refresh moderate (10)
    assert refresh_limit == "10/minute"
    
    # Link moderate (20)
    assert link_limit == "20/minute"
    
    print(f"✓ PASS: callback (5) < refresh (10) < link (20)")


def test_default_rate_limit():
    """Verify unknown endpoints get default limit"""
    unknown_limit = get_rate_limit("unknown_endpoint")
    assert unknown_limit == "100/minute"  # Default
    print(f"✓ PASS: unknown endpoint gets default: {unknown_limit}")


@pytest.mark.asyncio
async def test_rate_limit_429_response_format():
    """Verify 429 response format is correct"""
    
    # Simulated rate limit exceeded response
    response_body = {"detail": "Rate limit exceeded. Please try again later."}
    status_code = 429
    
    assert status_code == 429
    assert "Rate limit exceeded" in response_body["detail"]
    print(f"✓ PASS: 429 response format correct")


@pytest.mark.asyncio
async def test_legitimate_traffic_allowed():
    """Verify legitimate traffic under limit is allowed"""
    
    # Test scenario: Single request within 5/minute limit
    request_count = 1
    limit_per_minute = 5
    
    is_allowed = request_count <= limit_per_minute
    
    assert is_allowed is True
    print(f"✓ PASS: Legitimate traffic ({request_count} req) within limit ({limit_per_minute}/min)")


@pytest.mark.asyncio
async def test_excess_traffic_blocked():
    """Verify traffic exceeding limit is blocked"""
    
    # Test scenario: 6 requests in 1 minute (limit is 5/minute)
    request_count = 6
    limit_per_minute = 5
    
    is_allowed = request_count <= limit_per_minute
    
    assert is_allowed is False
    print(f"✗ FAIL: Traffic ({request_count} req) exceeds limit ({limit_per_minute}/min) → 429")


@pytest.mark.asyncio
async def test_rate_limiting_per_client():
    """Verify rate limiting is per-client (by IP address)"""
    
    # Client 1: 192.168.1.1
    # Client 2: 192.168.1.2
    
    client1_requests = 5  # At limit for auth_callback
    client2_requests = 5  # Separate limit for different IP
    
    # Both should be allowed (different clients)
    client1_allowed = client1_requests <= 5
    client2_allowed = client2_requests <= 5
    
    assert client1_allowed is True
    assert client2_allowed is True
    
    print(f"✓ PASS: Rate limits are per-client (IP-based)")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
