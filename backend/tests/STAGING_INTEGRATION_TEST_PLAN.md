# PHASE 4 STAGING: Integration Test Plan

**Objective:** Execute all 10 staging validation requirements against live staging environment

**Environment:** Isolated staging (no production data, no production secrets)

**Timeline:** After Cloud Run + Supabase deployment

---

## PRE-REQUISITES

Before running integration tests:

- [ ] Cloud Run staging service deployed
- [ ] Supabase staging instance with migrations
- [ ] GCP Secret Manager secrets configured
- [ ] PingOne sandbox credentials available
- [ ] Flutter Web staging build ready
- [ ] Service URL available: `https://<staging-cloud-run-url>`

---

## TEST MATRIX

| # | Test | Type | Duration | Status |
|---|------|------|----------|--------|
| 1 | Rate limiting: 5/min auth_callback | Live | 1 min | ⏳ |
| 2 | Rate limiting: 10/min auth_refresh | Live | 1 min | ⏳ |
| 3 | Rate limiting: 100/min get_user_teams | Live | 1 min | ⏳ |
| 4 | Rate limiting: 429 response format | Live | 30s | ⏳ |
| 5 | RLS: Unauthorized user cannot read other's teams | Live | 2 min | ⏳ |
| 6 | RLS: Authorized user can read own teams | Live | 2 min | ⏳ |
| 7 | JWT: Invalid token returns 401 | Live | 1 min | ⏳ |
| 8 | JWT: Expired token returns 401 | Live | 2 min | ⏳ |
| 9 | JWT: Valid token passes validation | Live | 1 min | ⏳ |
| 10 | PKCE: Full OAuth 2.0 flow succeeds | E2E | 5 min | ⏳ |
| 11 | Token refresh: Refresh token works | Live | 2 min | ⏳ |
| 12 | Token rotation: Tokens rotate correctly | Live | 2 min | ⏳ |
| 13 | Secret Manager: Secrets accessible | Live | 1 min | ⏳ |
| 14 | Logging: No tokens in logs | Live | 2 min | ⏳ |
| 15 | Authorization: Fail-closed on error | Live | 2 min | ⏳ |
| 16 | Authorization: 403 on unauthorized access | Live | 1 min | ⏳ |
| 17 | Network: No FPL calls on auth failure | Live | 2 min | ⏳ |
| 18 | Security: No Authorization headers logged | Live | 2 min | ⏳ |
| 19 | Security: Encryption key not exposed | Live | 1 min | ⏳ |
| 20 | Security: HTTPS enforced | Live | 1 min | ⏳ |

---

## ITEM 1: RATE LIMITING (4 tests)

### Test 1.1: /auth/callback Rate Limit (5/minute)

**Setup:**
```bash
# Set variables
STAGING_URL="https://staging-cloud-run-url"
ENDPOINT="/auth/callback"
```

**Test:**
```bash
# Make 5 requests (should succeed)
for i in {1..5}; do
  curl -X POST "$STAGING_URL$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d '{"code":"test_code_$i","code_verifier":"verifier","redirect_uri":"http://localhost"}' \
    -w "\n%{http_code}\n"
  sleep 5  # Wait to avoid other rate limits
done

# Make 6th request (should return 429)
curl -X POST "$STAGING_URL$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"code":"test_code_6","code_verifier":"verifier","redirect_uri":"http://localhost"}' \
  -w "\n%{http_code}\n"
```

**Expected Results:**
- Requests 1-5: 200 or 400 (valid response, not rate limited)
- Request 6: 429 Too Many Requests

**Pass Criteria:** ✅ 429 returned after 5 requests

---

### Test 1.2: /auth/refresh Rate Limit (10/minute)

**Test:**
```bash
# Make 10 requests with same refresh token (should succeed)
for i in {1..10}; do
  curl -X POST "$STAGING_URL/auth/refresh" \
    -H "Content-Type: application/json" \
    -d '{"refresh_token":"encrypted_token"}' \
    -w "\n%{http_code}\n"
  sleep 3
done

# Make 11th request (should return 429)
curl -X POST "$STAGING_URL/auth/refresh" \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"encrypted_token"}' \
  -w "\n%{http_code}\n"
```

**Expected Results:**
- Requests 1-10: 200-400 (not rate limited)
- Request 11: 429 Too Many Requests

**Pass Criteria:** ✅ 429 returned after 10 requests

---

### Test 1.3: /api/teams/me Rate Limit (100/minute)

**Test:**
```bash
# Make 100 requests with valid Bearer token
TOKEN="<valid_staging_token>"

for i in {1..100}; do
  curl -X GET "$STAGING_URL/api/teams/me" \
    -H "Authorization: Bearer $TOKEN" \
    -w "\n%{http_code}\n"
done

# Request 101 should be rate limited
curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $TOKEN" \
  -w "\n%{http_code}\n"
```

**Expected Results:**
- Requests 1-100: 200 (success)
- Request 101: 429 Too Many Requests

**Pass Criteria:** ✅ 429 returned after 100 requests

---

### Test 1.4: 429 Response Format

**Test:**
```bash
# Trigger rate limit
for i in {1..6}; do
  RESPONSE=$(curl -X POST "$STAGING_URL/auth/callback" \
    -H "Content-Type: application/json" \
    -d '{"code":"test","code_verifier":"v","redirect_uri":"http://localhost"}')
  if [ $i -eq 6 ]; then
    echo "$RESPONSE"
  fi
  sleep 5
done
```

**Expected Response:**
```json
{
  "detail": "Rate limit exceeded. Please try again later."
}
```

**Pass Criteria:**
- ✅ Status: 429
- ✅ Content-Type: application/json
- ✅ Body contains "Rate limit exceeded"

---

## ITEM 2: RLS ENFORCEMENT (2 tests)

### Test 2.1: Unauthorized User Cannot Read Other's Teams

**Setup:**
```bash
# Create two test users in Supabase staging
USER_A_ID="user-a-uuid"
USER_B_ID="user-b-uuid"

# Link teams to users
# user-a owns team-1
# user-b owns team-2
```

**Test:**
```bash
# Get token for user A
TOKEN_A=$(login_and_get_token "user_a@test.local")

# Try to access user B's team (team-2)
curl -X GET "$STAGING_URL/api/teams/team-2" \
  -H "Authorization: Bearer $TOKEN_A"
```

**Expected Result:**
- Status: 403 Forbidden
- Reason: Authorization check fails (user_teams query returns no row)

**Pass Criteria:** ✅ 403 returned, user cannot access other's team

---

### Test 2.2: Authorized User Can Read Own Teams

**Test:**
```bash
# Get token for user A
TOKEN_A=$(login_and_get_token "user_a@test.local")

# Access own team (team-1)
curl -X GET "$STAGING_URL/api/teams/team-1" \
  -H "Authorization: Bearer $TOKEN_A"
```

**Expected Result:**
- Status: 200 OK
- Body: Team data for team-1

**Pass Criteria:** ✅ 200 returned, user can access own team

---

## ITEM 3: JWT VALIDATION (3 tests)

### Test 3.1: Invalid Token Returns 401

**Test:**
```bash
curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer invalid_token_12345"
```

**Expected Result:**
- Status: 401 Unauthorized

**Pass Criteria:** ✅ 401 returned for invalid token

---

### Test 3.2: Expired Token Returns 401

**Test:**
```bash
# Create a token that expires immediately (using test fixtures)
EXPIRED_TOKEN=$(create_expired_token)

curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $EXPIRED_TOKEN"
```

**Expected Result:**
- Status: 401 Unauthorized

**Pass Criteria:** ✅ 401 returned for expired token

---

### Test 3.3: Valid Token Passes Validation

**Test:**
```bash
# Get fresh valid token
VALID_TOKEN=$(login_and_get_token "test_user@test.local")

curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $VALID_TOKEN"
```

**Expected Result:**
- Status: 200 OK
- Body: User's teams

**Pass Criteria:** ✅ 200 returned, user authenticated

---

## ITEM 4: OAUTH 2.0 PKCE E2E FLOW (1 test)

### Test 4.1: Full OAuth 2.0 PKCE Flow

**Test Steps:**
1. Generate PKCE code_verifier and code_challenge
2. Redirect to PingOne authorize endpoint
3. User authenticates (using test user)
4. PingOne redirects back with auth code
5. Exchange code + code_verifier for tokens
6. Validate tokens and access protected resource

**Exact Test:**
```bash
# Step 1: Generate PKCE
CODE_VERIFIER=$(openssl rand -base64 32 | tr -d '=' | tr '+/' '-_')
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr -d '=' | tr '+/' '-_')

# Step 2-4: (Manual or Selenium test for UI flow)
# Simulate: User logs in to PingOne, gets redirected with AUTH_CODE

# Step 5: Exchange for tokens
AUTH_CODE="<code_from_redirect>"
RESPONSE=$(curl -X POST "$STAGING_URL/auth/callback" \
  -H "Content-Type: application/json" \
  -d "{
    \"code\": \"$AUTH_CODE\",
    \"code_verifier\": \"$CODE_VERIFIER\",
    \"redirect_uri\": \"http://localhost:3000/callback\"
  }")

# Step 6: Verify response
ACCESS_TOKEN=$(echo $RESPONSE | jq -r '.access_token')
REFRESH_TOKEN=$(echo $RESPONSE | jq -r '.refresh_token')

curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Result:**
- Step 5: 200 OK, tokens returned
- Step 6: 200 OK, user's teams returned

**Pass Criteria:** ✅ Complete E2E flow succeeds

---

## ITEM 5: TOKEN REFRESH & ROTATION (2 tests)

### Test 5.1: Refresh Token Works

**Test:**
```bash
# Get initial tokens
INITIAL_RESPONSE=$(login_and_get_tokens "test_user@test.local")
REFRESH_TOKEN=$(echo $INITIAL_RESPONSE | jq -r '.refresh_token')

# Refresh access token
REFRESH_RESPONSE=$(curl -X POST "$STAGING_URL/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")

NEW_ACCESS_TOKEN=$(echo $REFRESH_RESPONSE | jq -r '.access_token')

# Verify new token works
curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $NEW_ACCESS_TOKEN"
```

**Expected Result:**
- Refresh: 200 OK, new tokens returned
- Verify: 200 OK, user's teams returned

**Pass Criteria:** ✅ Token refresh works

---

### Test 5.2: Token Rotation

**Test:**
```bash
# Get tokens
TOKENS_1=$(login_and_get_tokens "test_user@test.local")
TOKEN_1=$(echo $TOKENS_1 | jq -r '.refresh_token')

# Refresh once
TOKENS_2=$(curl -X POST "$STAGING_URL/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\": \"$TOKEN_1\"}")
TOKEN_2=$(echo $TOKENS_2 | jq -r '.refresh_token')

# Verify tokens are different
if [ "$TOKEN_1" != "$TOKEN_2" ]; then
  echo "✅ PASS: Tokens rotated"
else
  echo "❌ FAIL: Tokens did not rotate"
fi
```

**Expected Result:**
- refresh_token changes on each refresh call
- Old token becomes invalid after new token issued

**Pass Criteria:** ✅ Refresh tokens rotate

---

## ITEM 6: GCP SECRET MANAGER (1 test)

### Test 6.1: Secrets Accessible

**Test:**
```bash
# Verify service account can access secrets
gcloud secrets versions access latest \
  --secret="squadiq-staging-supabase-url" \
  --project="$GCP_PROJECT_ID"

gcloud secrets versions access latest \
  --secret="squadiq-staging-oidc-client-id" \
  --project="$GCP_PROJECT_ID"
```

**Expected Result:**
- Status: 0 (success)
- Output: Secret values

**Pass Criteria:** ✅ Secrets accessible to service account

---

## ITEM 7: LOGGING SECURITY (3 tests)

### Test 7.1: No Tokens in Logs

**Test:**
```bash
# Make authenticated request
TOKEN=$(login_and_get_token "test_user@test.local")
curl -X GET "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $TOKEN"

# Check logs
gcloud run logs read squadiq-phase4-staging \
  --limit=100 \
  --project="$GCP_PROJECT_ID" \
  --region="$GCP_REGION" | grep -i "$TOKEN"
```

**Expected Result:**
- grep returns 0 matches (token not in logs)

**Pass Criteria:** ✅ No Bearer tokens in logs

---

### Test 7.2: No Authorization Headers in Logs

**Test:**
```bash
gcloud run logs read squadiq-phase4-staging \
  --limit=100 \
  --project="$GCP_PROJECT_ID" \
  --region="$GCP_REGION" | grep -i "authorization:"
```

**Expected Result:**
- grep returns 0 matches (no full auth header)

**Pass Criteria:** ✅ No Authorization headers in logs

---

### Test 7.3: No Encryption Keys in Logs

**Test:**
```bash
gcloud run logs read squadiq-phase4-staging \
  --limit=100 \
  --project="$GCP_PROJECT_ID" \
  --region="$GCP_REGION" | grep -i "kv_"
```

**Expected Result:**
- grep returns 0 matches (no encrypted tokens)

**Pass Criteria:** ✅ No encryption keys in logs

---

## ITEM 8: FAIL-CLOSED AUTHORIZATION (2 tests)

### Test 8.1: 403 on Unauthorized Access

**Test:**
```bash
# Get token for user A
TOKEN_A=$(login_and_get_token "user_a@test.local")

# Try to access user B's team
RESPONSE=$(curl -X GET "$STAGING_URL/api/teams/team-b-id" \
  -H "Authorization: Bearer $TOKEN_A" \
  -w "\n%{http_code}")

STATUS_CODE=$(echo "$RESPONSE" | tail -1)

if [ "$STATUS_CODE" = "403" ]; then
  echo "✅ PASS: 403 Forbidden returned"
else
  echo "❌ FAIL: Expected 403, got $STATUS_CODE"
fi
```

**Expected Result:**
- Status: 403 Forbidden

**Pass Criteria:** ✅ 403 returned for unauthorized access

---

### Test 8.2: No FPL API Call on Authorization Failure

**Test:**
```bash
# Monitor outbound network traffic to FPL API
# (using tcpdump, Wireshark, or API gateway logs)

tcpdump -i any -n "host api.fantasy.premierleague.com" &
PID=$!

# Make request that fails authorization
TOKEN=$(create_invalid_token)
curl -X GET "$STAGING_URL/api/teams/team-unauthorized" \
  -H "Authorization: Bearer $TOKEN"

sleep 2
kill $PID

# Check for FPL API calls in tcpdump output
# Expected: ZERO calls to FPL API
```

**Expected Result:**
- 0 outbound connections to fantasy.premierleague.com

**Pass Criteria:** ✅ No FPL API calls on auth failure

---

## ITEM 9: NETWORK VERIFICATION (1 test)

### Test 9.1: No Unauthorized Requests to FPL

**Test:**
```bash
# Set up network monitoring
# (VPC Flow Logs or Cloud NAT logs)

# Monitor for 5 minutes
MONITORING_DURATION=300

# Make various failing requests
for i in {1..20}; do
  # Invalid token
  curl -s "$STAGING_URL/api/teams/me" \
    -H "Authorization: Bearer invalid_token_$i" > /dev/null
  
  # Unauthorized team access
  curl -s "$STAGING_URL/api/teams/unauthorized-team-$i" \
    -H "Authorization: Bearer $(login_and_get_token 'user_a@test.local')" > /dev/null
  
  sleep 1
done

# Check logs for outbound FPL API calls
# Expected: ZERO
```

**Expected Result:**
- 0 connections to fantasy.premierleague.com from staging service

**Pass Criteria:** ✅ No unauthorized FPL API calls

---

## ITEM 10: FINAL SECURITY CHECKLIST (6 tests)

### Test 10.1: HTTPS Enforced

**Test:**
```bash
# Verify staging endpoint uses HTTPS
curl -I "http://staging-cloud-run-url/health" 2>&1 | grep -i "location.*https"
```

**Expected Result:**
- HTTP redirects to HTTPS

**Pass Criteria:** ✅ HTTPS enforced

---

### Test 10.2: Security Headers Present

**Test:**
```bash
curl -I "$STAGING_URL/health" | grep -E "strict-transport-security|x-content-type-options|x-frame-options"
```

**Expected Headers:**
- `Strict-Transport-Security: max-age=...`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`

**Pass Criteria:** ✅ Security headers present

---

### Test 10.3: CORS Properly Configured

**Test:**
```bash
# Request with invalid origin
curl -H "Origin: http://malicious.com" "$STAGING_URL/api/teams/me" \
  -H "Authorization: Bearer $(login_and_get_token 'test@test.local')" \
  -v 2>&1 | grep -i "access-control-allow-origin"
```

**Expected Result:**
- CORS headers only allow legitimate origins

**Pass Criteria:** ✅ CORS properly restricted

---

### Test 10.4: Rate Limiting Prevents DoS

**Test:**
```bash
# Send 1000 requests in parallel
parallel -j 100 \
  "curl -s '$STAGING_URL/health'" \
  ::: {1..1000}

# Verify health check still responds
curl -s "$STAGING_URL/health"
```

**Expected Result:**
- Some requests rate limited
- Service remains responsive

**Pass Criteria:** ✅ DoS protection working

---

### Test 10.5: Error Messages Don't Leak Information

**Test:**
```bash
# Try various attacks
curl "$STAGING_URL/nonexistent-endpoint"
curl "$STAGING_URL/api/teams/../../etc/passwd"
curl "$STAGING_URL/api/teams/<script>alert('xss')</script>"

# Verify generic error messages
# Expected: No stack traces, no path info, no database details
```

**Expected Result:**
- Generic error messages
- No sensitive information in errors

**Pass Criteria:** ✅ Error messages hardened

---

### Test 10.6: Encryption Working

**Test:**
```bash
# Verify encrypted tokens in database
# Query Supabase staging user_tokens table

SELECT id, encrypted_token 
FROM user_tokens 
LIMIT 5;

# Verify tokens start with "kv_" (key version prefix)
```

**Expected Result:**
- All tokens encrypted
- Tokens follow format: `kv_<version>_<ciphertext>`

**Pass Criteria:** ✅ Encryption active

---

## EXECUTION CHECKLIST

- [ ] All 4 rate limiting tests pass
- [ ] All 2 RLS tests pass
- [ ] All 3 JWT validation tests pass
- [ ] OAuth 2.0 PKCE E2E test passes
- [ ] Both token refresh tests pass
- [ ] Secret Manager test passes
- [ ] All 3 logging security tests pass
- [ ] Both authorization tests pass
- [ ] Network verification test passes
- [ ] All 6 security checklist tests pass

**Total: 20+ tests**

**Target Pass Rate: 100%**

---

## FAILURE HANDLING

If any test fails:

1. **Document the failure**
   - Test name
   - Expected result
   - Actual result
   - Logs/errors

2. **Root cause analysis**
   - Review application logs
   - Check infrastructure configuration
   - Verify test setup

3. **Fix & retest**
   - Make necessary changes
   - Re-run failed test
   - Verify no regressions

4. **Report findings**
   - Add to staging report
   - Document remediation
   - Identify impact

---

## SUCCESS CRITERIA

✅ **ALL TESTS MUST PASS** before proceeding to production

| Category | Tests | Target |
|----------|-------|--------|
| Rate Limiting | 4 | 4/4 ✅ |
| RLS | 2 | 2/2 ✅ |
| JWT | 3 | 3/3 ✅ |
| OAuth 2.0 | 1 | 1/1 ✅ |
| Token Management | 2 | 2/2 ✅ |
| Secret Management | 1 | 1/1 ✅ |
| Logging | 3 | 3/3 ✅ |
| Authorization | 2 | 2/2 ✅ |
| Network | 1 | 1/1 ✅ |
| Security | 6 | 6/6 ✅ |
| **TOTAL** | **25+** | **25+/25+** ✅ |

---

**Next Step:** Deploy staging environment and execute all tests
