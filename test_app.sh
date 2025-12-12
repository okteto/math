#!/bin/bash
# Note: Not using 'set -e' because we want to continue running all tests even if some fail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Django + Celery App Test Suite"
echo "======================================"
echo ""

# Set the base URL - use Kubernetes service DNS
# In Kubernetes, services are accessed as <service-name>.<namespace>.svc.cluster.local
# Or simply <service-name> if in the same namespace
BASE_URL="http://web.${OKTETO_NAMESPACE}.svc.cluster.local:8080"

# Wait for services to be ready
echo -e "${YELLOW}Waiting for web service to be ready...${NC}"
echo "Using base URL: ${BASE_URL}"
echo "Namespace: ${OKTETO_NAMESPACE}"
echo "Checking DNS resolution..."
nslookup web.${OKTETO_NAMESPACE}.svc.cluster.local || echo "DNS lookup failed, but continuing..."

echo "Checking if web service port 8080 is reachable..."
nc -zv web.${OKTETO_NAMESPACE}.svc.cluster.local 8080 2>&1 || echo "Port check inconclusive, attempting HTTP requests..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/ 2>&1)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo -e "${GREEN}Web service is ready! (HTTP $HTTP_CODE)${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Attempt $RETRY_COUNT/$MAX_RETRIES - Web service not ready (HTTP $HTTP_CODE), waiting..."
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}ERROR: Web service did not become ready in time${NC}"
    echo "Last HTTP code: $HTTP_CODE"
    exit 1
fi

echo "Waiting additional 5 seconds for all services to stabilize..."
sleep 5

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run tests
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -e "\n${YELLOW}Running: ${test_name}${NC}"

    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASSED: ${test_name}${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED: ${test_name}${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Health check - Root endpoint
run_test "Test 1: API root endpoint is accessible" \
    "curl -f -s ${BASE_URL}/ > /dev/null"

# Test 2: Jobs list endpoint
run_test "Test 2: Jobs list endpoint returns valid JSON" \
    "curl -f -s ${BASE_URL}/jobs/ | python3 -m json.tool > /dev/null"

# Test 3: Create a power job
echo -e "\n${YELLOW}Running: Test 3: Create a power job (2^10)${NC}"
POWER_JOB=$(curl -s -X POST ${BASE_URL}/jobs/ \
    -H "Content-Type: application/json" \
    -d '{"type": "power", "status": "pending", "argument": 10}')

if echo "$POWER_JOB" | grep -q '"type":"power"'; then
    echo -e "${GREEN}✓ PASSED: Test 3: Power job created${NC}"
    ((TESTS_PASSED++))
    POWER_JOB_ID=$(echo "$POWER_JOB" | python3 -c "import sys, json; print(json.load(sys.stdin)['url'].rstrip('/').split('/')[-1])")
    echo "  Job ID: $POWER_JOB_ID"
else
    echo -e "${RED}✗ FAILED: Test 3: Power job creation failed${NC}"
    ((TESTS_FAILED++))
fi

# Test 4: Create a fibonacci job
echo -e "\n${YELLOW}Running: Test 4: Create a fibonacci job (fib(15))${NC}"
FIB_JOB=$(curl -s -X POST ${BASE_URL}/jobs/ \
    -H "Content-Type: application/json" \
    -d '{"type": "fibonacci", "status": "pending", "argument": 15}')

if echo "$FIB_JOB" | grep -q '"type":"fibonacci"'; then
    echo -e "${GREEN}✓ PASSED: Test 4: Fibonacci job created${NC}"
    ((TESTS_PASSED++))
    FIB_JOB_ID=$(echo "$FIB_JOB" | python3 -c "import sys, json; print(json.load(sys.stdin)['url'].rstrip('/').split('/')[-1])")
    echo "  Job ID: $FIB_JOB_ID"
else
    echo -e "${RED}✗ FAILED: Test 4: Fibonacci job creation failed${NC}"
    ((TESTS_FAILED++))
fi

# Test 5: Wait for power job to complete
if [ -n "$POWER_JOB_ID" ]; then
    echo -e "\n${YELLOW}Running: Test 5: Power job completes successfully${NC}"
    echo "Waiting for job to be processed (up to 15 seconds)..."
    MAX_WAIT=15
    WAIT_COUNT=0
    JOB_FINISHED=false

    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        POWER_RESULT=$(curl -s ${BASE_URL}/jobs/${POWER_JOB_ID}/)
        if echo "$POWER_RESULT" | grep -q '"status":"finished"'; then
            JOB_FINISHED=true
            break
        fi
        WAIT_COUNT=$((WAIT_COUNT + 1))
        sleep 1
    done

    if [ "$JOB_FINISHED" = true ] && echo "$POWER_RESULT" | grep -q '"result":1024'; then
        echo -e "${GREEN}✓ PASSED: Test 5: Power job completed with correct result (1024)${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED: Test 5: Power job did not complete correctly${NC}"
        echo "  Response: $POWER_RESULT"
        ((TESTS_FAILED++))
    fi
fi

# Test 6: Wait for fibonacci job to complete
if [ -n "$FIB_JOB_ID" ]; then
    echo -e "\n${YELLOW}Running: Test 6: Fibonacci job completes successfully${NC}"
    echo "Waiting for job to be processed (up to 15 seconds)..."
    MAX_WAIT=15
    WAIT_COUNT=0
    JOB_FINISHED=false

    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        FIB_RESULT=$(curl -s ${BASE_URL}/jobs/${FIB_JOB_ID}/)
        if echo "$FIB_RESULT" | grep -q '"status":"finished"'; then
            JOB_FINISHED=true
            break
        fi
        WAIT_COUNT=$((WAIT_COUNT + 1))
        sleep 1
    done

    FIB_RESULT=$(curl -s ${BASE_URL}/jobs/${FIB_JOB_ID}/)

    if [ "$JOB_FINISHED" = true ] && echo "$FIB_RESULT" | grep -q '"result":610'; then
        echo -e "${GREEN}✓ PASSED: Test 6: Fibonacci job completed with correct result (610)${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED: Test 6: Fibonacci job did not complete correctly${NC}"
        echo "  Response: $FIB_RESULT"
        ((TESTS_FAILED++))
    fi
fi

# Test 7: Test edge case - Fibonacci of 0
run_test "Test 7: Fibonacci edge case (fib(0) = 0)" \
    "curl -s -X POST ${BASE_URL}/jobs/ -H 'Content-Type: application/json' \
     -d '{\"type\": \"fibonacci\", \"status\": \"pending\", \"argument\": 0}' | grep -q '\"argument\":0'"

# Test 8: Test edge case - Fibonacci of 1
run_test "Test 8: Fibonacci edge case (fib(1) = 1)" \
    "curl -s -X POST ${BASE_URL}/jobs/ -H 'Content-Type: application/json' \
     -d '{\"type\": \"fibonacci\", \"status\": \"pending\", \"argument\": 1}' | grep -q '\"argument\":1'"

# Test 9: Test power with 0
run_test "Test 9: Power edge case (2^0 = 1)" \
    "curl -s -X POST ${BASE_URL}/jobs/ -H 'Content-Type: application/json' \
     -d '{\"type\": \"power\", \"status\": \"pending\", \"argument\": 0}' | grep -q '\"argument\":0'"

# Test 10: Verify all jobs are in the list
echo -e "\n${YELLOW}Running: Test 10: All created jobs appear in job list${NC}"
ALL_JOBS=$(curl -s ${BASE_URL}/jobs/)
JOB_COUNT=$(echo "$ALL_JOBS" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")

if [ "$JOB_COUNT" -ge 5 ]; then
    echo -e "${GREEN}✓ PASSED: Test 10: Job list contains $JOB_COUNT jobs${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAILED: Test 10: Expected at least 5 jobs, found $JOB_COUNT${NC}"
    ((TESTS_FAILED++))
fi

# Test 11: Test invalid job type
echo -e "\n${YELLOW}Running: Test 11: API rejects invalid job type${NC}"
INVALID_JOB=$(curl -s -X POST ${BASE_URL}/jobs/ \
    -H "Content-Type: application/json" \
    -d '{"type": "invalid", "status": "pending", "argument": 5}')

if echo "$INVALID_JOB" | grep -q "error\|not a valid choice"; then
    echo -e "${GREEN}✓ PASSED: Test 11: Invalid job type rejected${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAILED: Test 11: Invalid job type was not rejected${NC}"
    ((TESTS_FAILED++))
fi

# Test 12: Test missing required fields
echo -e "\n${YELLOW}Running: Test 12: API rejects incomplete job data${NC}"
INCOMPLETE_JOB=$(curl -s -X POST ${BASE_URL}/jobs/ \
    -H "Content-Type: application/json" \
    -d '{"type": "power"}')

if echo "$INCOMPLETE_JOB" | grep -q "required"; then
    echo -e "${GREEN}✓ PASSED: Test 12: Incomplete job data rejected${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAILED: Test 12: Incomplete job data was not rejected${NC}"
    ((TESTS_FAILED++))
fi

# Test 13: Verify job retrieval by ID
if [ -n "$POWER_JOB_ID" ]; then
    run_test "Test 13: Individual job can be retrieved by ID" \
        "curl -f -s ${BASE_URL}/jobs/${POWER_JOB_ID}/ | grep -q '\"url\".*jobs/${POWER_JOB_ID}'"
fi

# Test 14: Test larger power calculation
echo -e "\n${YELLOW}Running: Test 14: Large power calculation (2^20)${NC}"
LARGE_POWER=$(curl -s -X POST ${BASE_URL}/jobs/ \
    -H "Content-Type: application/json" \
    -d '{"type": "power", "status": "pending", "argument": 20}')

if echo "$LARGE_POWER" | grep -q '"argument":20'; then
    LARGE_POWER_ID=$(echo "$LARGE_POWER" | python3 -c "import sys, json; print(json.load(sys.stdin)['url'].rstrip('/').split('/')[-1])")
    sleep 5
    LARGE_POWER_RESULT=$(curl -s ${BASE_URL}/jobs/${LARGE_POWER_ID}/)

    if echo "$LARGE_POWER_RESULT" | grep -q '"result":1048576'; then
        echo -e "${GREEN}✓ PASSED: Test 14: Large power calculation correct (1048576)${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED: Test 14: Large power calculation incorrect${NC}"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗ FAILED: Test 14: Large power job creation failed${NC}"
    ((TESTS_FAILED++))
fi

# Test 15: Test concurrent job processing
echo -e "\n${YELLOW}Running: Test 15: Multiple concurrent jobs${NC}"
curl -s -X POST ${BASE_URL}/jobs/ -H "Content-Type: application/json" -d '{"type": "power", "status": "pending", "argument": 5}' > /dev/null &
curl -s -X POST ${BASE_URL}/jobs/ -H "Content-Type: application/json" -d '{"type": "fibonacci", "status": "pending", "argument": 10}' > /dev/null &
curl -s -X POST ${BASE_URL}/jobs/ -H "Content-Type: application/json" -d '{"type": "power", "status": "pending", "argument": 7}' > /dev/null &
wait

sleep 5
FINAL_JOBS=$(curl -s ${BASE_URL}/jobs/)
FINISHED_COUNT=$(echo "$FINAL_JOBS" | grep -o '"status":"finished"' | wc -l)

if [ "$FINISHED_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✓ PASSED: Test 15: Multiple concurrent jobs processed successfully${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAILED: Test 15: Not all concurrent jobs completed${NC}"
    ((TESTS_FAILED++))
fi

# Summary
echo ""
echo "======================================"
echo "Test Suite Summary"
echo "======================================"
echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo "======================================"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi
