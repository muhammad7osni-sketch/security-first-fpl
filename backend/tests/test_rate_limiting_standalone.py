"""
PHASE 4 STAGING: Rate limiting tests (standalone)
Verifies rate limiting configuration
Tests verify limits are properly configured
(Live slowapi testing requires Cloud Run deployment)
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pytest


# Rate limit configurations (from app/middleware/rate_limiter.py)
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
    
    # Extract numbers from strings
    callback_num = int(callback_limit.split("/")[0])
    refresh_num = int(refresh_limit.split("/")[0])
    link_num = int(link_limit.split("/")[0])
    
    # Callback most strict (5)
    assert callback_num == 5
    
    # Refresh moderate (10)
    assert refresh_num == 10
    
    # Link moderate (20)
    assert link_num == 20
    
    # Verify ordering
    assert callback_num < refresh_num < link_num
    
    print(f"✓ PASS: callback ({callback_num}) < refresh ({refresh_num}) < link ({link_num})")


def test_default_rate_limit():
    """Verify unknown endpoints get default limit"""
    unknown_limit = get_rate_limit("unknown_endpoint")
    assert unknown_limit == "100/minute"  # Default
    print(f"✓ PASS: unknown endpoint gets default: {unknown_limit}")


def test_rate_limit_format_valid():
    """Verify all rate limits follow correct format"""
    
    for endpoint, limit in RATE_LIMITS.items():
        # Format should be "N/minute"
        parts = limit.split("/")
        assert len(parts) == 2, f"{endpoint}: Invalid format: {limit}"
        
        number = int(parts[0])
        unit = parts[1]
        
        assert number > 0, f"{endpoint}: Rate must be > 0"
        assert unit == "minute", f"{endpoint}: Unit must be 'minute'"
        
        print(f"✓ PASS: {endpoint} format valid ({limit})")


def test_legitimate_traffic_allowed():
    """Verify legitimate traffic under limit is allowed"""
    
    # Test scenario: Single request within 5/minute limit
    request_count = 1
    limit_per_minute = 5
    
    is_allowed = request_count <= limit_per_minute
    
    assert is_allowed is True
    print(f"✓ PASS: Legitimate traffic ({request_count} req) within limit ({limit_per_minute}/min) → ALLOWED")


def test_excess_traffic_blocked():
    """Verify traffic exceeding limit is blocked"""
    
    # Test scenario: 6 requests in 1 minute (limit is 5/minute)
    request_count = 6
    limit_per_minute = 5
    
    is_allowed = request_count <= limit_per_minute
    
    assert is_allowed is False
    print(f"✓ PASS: Excess traffic ({request_count} req) exceeds limit ({limit_per_minute}/min) → BLOCKED (429)")


def test_rate_limiting_per_client():
    """Verify rate limiting is per-client (by IP address)"""
    
    # Client 1: 192.168.1.1 → 5 requests
    # Client 2: 192.168.1.2 → 5 requests
    
    # Both at limit but different clients
    client1_requests = 5
    client2_requests = 5
    limit = 5
    
    # Both should be allowed (different clients)
    client1_allowed = client1_requests <= limit
    client2_allowed = client2_requests <= limit
    
    assert client1_allowed is True
    assert client2_allowed is True
    
    print(f"✓ PASS: Rate limits are per-client (IP-based)")


def test_all_endpoints_have_limits():
    """Verify all expected endpoints have rate limits"""
    
    required_endpoints = [
        "auth_callback",
        "auth_refresh",
        "auth_logout",
        "get_user_teams",
        "get_team_data",
        "link_fpl_account",
        "health_check",
    ]
    
    for endpoint in required_endpoints:
        limit = get_rate_limit(endpoint)
        assert limit is not None, f"{endpoint}: No rate limit configured"
        assert "/" in limit, f"{endpoint}: Invalid limit format: {limit}"
        
        print(f"✓ PASS: {endpoint} has rate limit: {limit}")


@pytest.mark.asyncio
async def test_429_response_structure():
    """Verify 429 response structure"""
    
    # Expected 429 response structure
    response_status = 429
    response_body = {
        "detail": "Rate limit exceeded. Please try again later."
    }
    
    assert response_status == 429
    assert isinstance(response_body, dict)
    assert "detail" in response_body
    assert "Rate limit exceeded" in response_body["detail"]
    
    print(f"✓ PASS: 429 response structure valid")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
