"""
PHASE 4: Pytest configuration and fixtures.
"""

import pytest
import os

try:
    from dotenv import load_dotenv
    load_dotenv(".env.test")
except ImportError:
    pass  # dotenv optional for testing

# Set test environment variables
os.environ["ENVIRONMENT"] = "test"
os.environ["DEBUG"] = "true"
os.environ["OIDC_CLIENT_ID"] = "test-client-id"
os.environ["SUPABASE_URL"] = "http://localhost:54321"
os.environ["SUPABASE_SERVICE_ROLE_KEY"] = "test-key"
