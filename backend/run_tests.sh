#!/bin/bash
# PHASE 4: Test suite runner
# Runs all tests with coverage reporting

set -e

echo "=============================================="
echo "PHASE 4: Running Test Suite"
echo "=============================================="
echo ""

# Install test dependencies
echo "Installing test dependencies..."
pip install -q -r requirements.txt

echo ""
echo "=============================================="
echo "Step 1: JWT Validator Tests"
echo "=============================================="
pytest tests/test_jwt_validator.py -v --tb=short

echo ""
echo "=============================================="
echo "Step 2: Encryption Service Tests"
echo "=============================================="
pytest tests/test_encryption.py -v --tb=short

echo ""
echo "=============================================="
echo "Step 3: Database Tests"
echo "=============================================="
pytest tests/test_database.py -v --tb=short

echo ""
echo "=============================================="
echo "Step 4: Authorization Tests (MANDATORY SECURITY)"
echo "=============================================="
pytest tests/test_authorization.py -v --tb=short

echo ""
echo "=============================================="
echo "ALL TESTS PASSED"
echo "=============================================="
echo ""

# Generate coverage report
echo "Generating coverage report..."
pytest tests/ --cov=app --cov-report=html --cov-report=term

echo ""
echo "Coverage report generated in htmlcov/index.html"
