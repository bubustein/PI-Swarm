#!/bin/bash

# PI-Swarm End-to-End Integration Test
# Tests storage and DNS integration together

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_RESULTS=()
TEST_COUNT=0
PASS_COUNT=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    ((TEST_COUNT++))
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    if eval "$test_command"; then
        if [[ "$expected_result" == "0" ]]; then
            echo -e "${GREEN}✅ PASS: $test_name${NC}"
            TEST_RESULTS+=("PASS: $test_name")
            ((PASS_COUNT++))
        else
            echo -e "${RED}❌ FAIL: $test_name (expected failure but succeeded)${NC}"
            TEST_RESULTS+=("FAIL: $test_name")
        fi
    else
        if [[ "$expected_result" != "0" ]]; then
            echo -e "${GREEN}✅ PASS: $test_name (expected failure)${NC}"
            TEST_RESULTS+=("PASS: $test_name")
            ((PASS_COUNT++))
        else
            echo -e "${RED}❌ FAIL: $test_name${NC}"
            TEST_RESULTS+=("FAIL: $test_name")
        fi
    fi
    echo ""
}

echo -e "${BLUE}🧪 PI-Swarm End-to-End Integration Test${NC}"
echo "================================================="
echo ""

# Test 1: Check if all required files exist
echo -e "${YELLOW}Phase 1: File Structure Validation${NC}"
echo "-----------------------------------"

run_test "Deploy script exists" "test -f '$PROJECT_ROOT/deploy.sh'"
run_test "Main cluster script exists" "test -f '$PROJECT_ROOT/core/swarm-cluster.sh'"
run_test "Storage management module exists" "test -f '$PROJECT_ROOT/lib/storage/storage_management.sh'"
run_test "GlusterFS setup module exists" "test -f '$PROJECT_ROOT/lib/storage/glusterfs_setup.sh'"
run_test "Pi-hole DNS module exists" "test -f '$PROJECT_ROOT/lib/networking/pihole_dns.sh'"
run_test "Functions loader exists" "test -f '$PROJECT_ROOT/lib/source_functions.sh'"

echo -e "${YELLOW}Phase 2: Configuration Validation${NC}"
echo "-----------------------------------"

# Test 2: Check if scripts are executable
run_test "Deploy script is executable" "test -x '$PROJECT_ROOT/deploy.sh'"
run_test "Main cluster script is executable" "test -x '$PROJECT_ROOT/core/swarm-cluster.sh'"

# Test 3: Check function loading
echo "Testing function loading..."
cd "$PROJECT_ROOT"
run_test "Storage functions can be loaded" "source lib/storage/storage_management.sh && type setup_cluster_storage >/dev/null 2>&1"
run_test "Pi-hole functions can be loaded" "source lib/networking/pihole_dns.sh && type setup_pihole_dns >/dev/null 2>&1"

# Test enhanced Python modules if available
if [[ -f "$PROJECT_ROOT/lib/python_integration.sh" ]]; then
    echo "Testing enhanced Python integration..."
    source "$PROJECT_ROOT/lib/python_integration.sh"
    run_test "Python integration functions load" "type test_python_integration >/dev/null 2>&1"
    run_test "Enhanced monitoring functions available" "type monitor_cluster_comprehensive >/dev/null 2>&1"
    run_test "Enhanced storage functions available" "type manage_storage_comprehensive >/dev/null 2>&1"
    run_test "Enhanced security functions available" "type manage_security_comprehensive >/dev/null 2>&1"
    run_test "Python integration test passes" "test_python_integration >/dev/null 2>&1"
else
    echo "Enhanced Python integration not available - using standard functions only"
fi

# Test 4: Check integration points
echo -e "${YELLOW}Phase 3: Integration Point Validation${NC}"
echo "-------------------------------------"

run_test "Storage integration in swarm script" "grep -q 'setup_cluster_storage' '$PROJECT_ROOT/core/swarm-cluster.sh'"
run_test "DNS integration in swarm script" "grep -q 'setup_pihole_dns' '$PROJECT_ROOT/core/swarm-cluster.sh'"
run_test "Storage functions sourced properly" "grep -q 'storage/storage_management.sh' '$PROJECT_ROOT/lib/source_functions.sh'"
run_test "DNS functions sourced properly" "grep -q 'networking/pihole_dns.sh' '$PROJECT_ROOT/lib/source_functions.sh'"

# Test 5: Environment variable handling
echo -e "${YELLOW}Phase 4: Environment Variable Tests${NC}"
echo "-----------------------------------"

run_test "Storage env vars in deploy script" "grep -q 'ENABLE_STORAGE' '$PROJECT_ROOT/deploy.sh'"
run_test "DNS env vars in deploy script" "grep -q 'ENABLE_PIHOLE' '$PROJECT_ROOT/deploy.sh'"

# Test 6: Script syntax validation
echo -e "${YELLOW}Phase 5: Syntax Validation${NC}"
echo "-------------------------------"

run_test "Deploy script syntax" "bash -n '$PROJECT_ROOT/deploy.sh'"
run_test "Swarm cluster script syntax" "bash -n '$PROJECT_ROOT/core/swarm-cluster.sh'"
run_test "Storage management syntax" "bash -n '$PROJECT_ROOT/lib/storage/storage_management.sh'"
run_test "GlusterFS setup syntax" "bash -n '$PROJECT_ROOT/lib/storage/glusterfs_setup.sh'"
run_test "Pi-hole DNS syntax" "bash -n '$PROJECT_ROOT/lib/networking/pihole_dns.sh'"

# Test 7: Documentation checks
echo -e "${YELLOW}Phase 6: Documentation Validation${NC}"
echo "-----------------------------------"

run_test "Storage integration guide exists" "test -f '$PROJECT_ROOT/docs/STORAGE_INTEGRATION_GUIDE.md'"
run_test "Main README exists" "test -f '$PROJECT_ROOT/README.md'"

# Summary
echo "================================================="
echo -e "${BLUE}📊 Test Results Summary${NC}"
echo "================================================="
echo ""
echo -e "Total tests run: ${BLUE}$TEST_COUNT${NC}"
echo -e "Tests passed:   ${GREEN}$PASS_COUNT${NC}"
echo -e "Tests failed:   ${RED}$((TEST_COUNT - PASS_COUNT))${NC}"
echo ""

if [[ $PASS_COUNT -eq $TEST_COUNT ]]; then
    echo -e "${GREEN}🎉 All tests passed! The integration looks good.${NC}"
    echo ""
    echo -e "${GREEN}✅ Storage and DNS integration is ready for deployment!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run ./deploy.sh to start the deployment"
    echo "2. Enable both storage and DNS when prompted"
    echo "3. Monitor the deployment logs for any issues"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please review the issues above.${NC}"
    echo ""
    echo "Failed tests:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == FAIL* ]]; then
            echo -e "${RED}  • ${result#FAIL: }${NC}"
        fi
    done
    exit 1
fi
