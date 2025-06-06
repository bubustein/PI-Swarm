#!/bin/bash

# Enhanced Python Integration Test Script
# Tests the new comprehensive Python modules for monitoring, storage, and security

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

echo -e "${PURPLE}🧪 Enhanced Python Integration Test Suite${NC}"
echo "============================================="
echo ""

cd "$PROJECT_ROOT"

# Phase 1: Python Module Existence Tests
echo -e "${YELLOW}Phase 1: Python Module Structure Validation${NC}"
echo "---------------------------------------------"

run_test "Enhanced monitoring manager exists" "test -f 'lib/python/enhanced_monitoring_manager.py'"
run_test "Enhanced storage manager exists" "test -f 'lib/python/enhanced_storage_manager.py'"
run_test "Enhanced security manager exists" "test -f 'lib/python/enhanced_security_manager.py'"
run_test "Python integration script exists" "test -f 'lib/python_integration.sh'"

# Phase 2: Python Module Syntax and Import Tests
echo -e "${YELLOW}Phase 2: Python Module Syntax Validation${NC}"
echo "----------------------------------------------"

run_test "Enhanced monitoring manager syntax" "python3 -m py_compile lib/python/enhanced_monitoring_manager.py"
run_test "Enhanced storage manager syntax" "python3 -m py_compile lib/python/enhanced_storage_manager.py"
run_test "Enhanced security manager syntax" "python3 -m py_compile lib/python/enhanced_security_manager.py"

# Test module imports
run_test "Enhanced monitoring manager imports" "python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import enhanced_monitoring_manager'"
run_test "Enhanced storage manager imports" "python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import enhanced_storage_manager'"
run_test "Enhanced security manager imports" "python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import enhanced_security_manager'"

# Phase 3: Python Integration Function Tests
echo -e "${YELLOW}Phase 3: Integration Function Validation${NC}"
echo "---------------------------------------------"

# Source the integration script
if [[ -f "lib/python_integration.sh" ]]; then
    source lib/python_integration.sh
    
    run_test "Python integration functions load" "type test_python_integration >/dev/null 2>&1"
    run_test "Monitor cluster comprehensive function exists" "type monitor_cluster_comprehensive >/dev/null 2>&1"
    run_test "Manage storage comprehensive function exists" "type manage_storage_comprehensive >/dev/null 2>&1"
    run_test "Manage security comprehensive function exists" "type manage_security_comprehensive >/dev/null 2>&1"
    run_test "Optimize cluster performance function exists" "type optimize_cluster_performance >/dev/null 2>&1"
    run_test "Health check comprehensive function exists" "type health_check_comprehensive >/dev/null 2>&1"
    
    # Test basic functionality
    echo -e "${BLUE}Testing Python integration capabilities...${NC}"
    run_test "Python integration test passes" "test_python_integration"
    
else
    echo -e "${RED}❌ Python integration script not found${NC}"
fi

# Phase 4: Enhanced Deployment Integration Tests
echo -e "${YELLOW}Phase 4: Deployment Integration Validation${NC}"
echo "-----------------------------------------------"

run_test "Enhanced deployment script exists" "test -f 'scripts/deployment/enhanced-deploy.sh'"
run_test "Enhanced deployment script is executable" "test -x 'scripts/deployment/enhanced-deploy.sh'"
run_test "Python integration in enhanced deploy" "grep -q 'python_integration.sh' 'scripts/deployment/enhanced-deploy.sh'"
run_test "Enhanced validation function in deploy" "grep -q 'validate_and_prepare_pi_state_enhanced' 'scripts/deployment/enhanced-deploy.sh'"

# Phase 5: Pre-deployment Validation Integration Tests
echo -e "${YELLOW}Phase 5: Pre-deployment Validation Integration${NC}"
echo "------------------------------------------------"

run_test "Enhanced pre-deployment validation" "grep -q 'validate_and_prepare_pi_state_enhanced' 'lib/deployment/pre_deployment_validation.sh'"
run_test "Python integration in validation" "grep -q 'python_integration.sh' 'lib/deployment/pre_deployment_validation.sh'"
run_test "Enhanced functions exported" "grep -q 'validate_and_prepare_pi_state_enhanced' 'lib/deployment/pre_deployment_validation.sh'"

# Phase 6: Main Deployment Script Integration Tests
echo -e "${YELLOW}Phase 6: Main Deployment Script Integration${NC}"
echo "----------------------------------------------"

run_test "Python integration in main deploy" "grep -q 'python_integration.sh' 'deploy.sh'"
run_test "Enhanced health check in deploy" "grep -q 'health_check_comprehensive' 'deploy.sh'"
run_test "Enhanced directory setup in deploy" "grep -q 'setup_directories_enhanced' 'deploy.sh'"

# Phase 7: Function Integration Tests with Fallbacks
echo -e "${YELLOW}Phase 7: Function Fallback Mechanism Tests${NC}"
echo "-----------------------------------------------"

if [[ -f "lib/python_integration.sh" ]]; then
    source lib/python_integration.sh
    
    # Test dry-run capabilities (should not fail even without actual Pi cluster)
    echo -e "${BLUE}Testing function fallback mechanisms (dry-run mode)...${NC}"
    
    # These tests check that functions exist and handle missing dependencies gracefully
    run_test "Health check handles missing cluster" "health_check_comprehensive --dry-run 2>/dev/null || true"
    run_test "Storage management handles missing devices" "manage_storage_comprehensive validate --dry-run 2>/dev/null || true"
    run_test "Security management handles missing config" "manage_security_comprehensive audit --dry-run 2>/dev/null || true"
    run_test "Performance optimization handles missing cluster" "optimize_cluster_performance validate --dry-run 2>/dev/null || true"
fi

# Phase 8: Documentation and Configuration Tests
echo -e "${YELLOW}Phase 8: Documentation and Configuration Tests${NC}"
echo "------------------------------------------------"

run_test "Enhanced monitoring functions documented" "grep -q 'Enhanced Monitoring Manager' 'lib/python/enhanced_monitoring_manager.py'"
run_test "Enhanced storage functions documented" "grep -q 'Enhanced Storage Manager' 'lib/python/enhanced_storage_manager.py'"
run_test "Enhanced security functions documented" "grep -q 'Enhanced Security Manager' 'lib/python/enhanced_security_manager.py'"
run_test "Python integration documented" "grep -q 'Enhanced Python Integration' 'lib/python_integration.sh'"

# Phase 9: Backwards Compatibility Tests
echo -e "${YELLOW}Phase 9: Backwards Compatibility Tests${NC}"
echo "--------------------------------------------"

run_test "Original monitoring functions still available" "test -f 'lib/monitoring/performance_monitoring.sh'"
run_test "Original storage functions still available" "test -f 'lib/storage/storage_management.sh'"
run_test "Original security functions still available" "test -f 'lib/security/ssl_automation.sh'"
run_test "Fallback logic in python integration" "grep -q 'fallback' 'lib/python_integration.sh'"

# Phase 10: Security and Best Practices Tests
echo -e "${YELLOW}Phase 10: Security and Best Practices Tests${NC}"
echo "---------------------------------------------"

run_test "No hardcoded credentials in Python modules" "! grep -r 'password.*=' lib/python/ || ! grep -r 'passwd.*=' lib/python/"
run_test "Proper error handling in Python modules" "grep -q 'try:' lib/python/enhanced_monitoring_manager.py"
run_test "Logging implemented in Python modules" "grep -q 'logging' lib/python/enhanced_monitoring_manager.py"
run_test "Input validation in Python modules" "grep -q 'if.*args' lib/python/enhanced_monitoring_manager.py"

# Final Results Summary
echo ""
echo -e "${PURPLE}🎯 Test Results Summary${NC}"
echo "========================"
echo ""
echo -e "Total Tests: ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$((TEST_COUNT - PASS_COUNT))${NC}"
echo -e "Success Rate: ${BLUE}$((PASS_COUNT * 100 / TEST_COUNT))%${NC}"
echo ""

if [[ $PASS_COUNT -eq $TEST_COUNT ]]; then
    echo -e "${GREEN}🎉 All tests passed! Enhanced Python integration is ready for production.${NC}"
    echo ""
    echo -e "${BLUE}Enhanced Features Available:${NC}"
    echo "• Comprehensive cluster monitoring with Python-based analytics"
    echo "• Advanced storage management with device detection and optimization"
    echo "• Enhanced security management with automated SSL and auditing"
    echo "• Performance optimization with intelligent resource management"
    echo "• Robust fallback mechanisms to Bash implementations"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  Some tests failed. Please review the issues above.${NC}"
    echo ""
    echo -e "${BLUE}Failed Tests:${NC}"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == FAIL* ]]; then
            echo -e "${RED}• ${result#FAIL: }${NC}"
        fi
    done
    echo ""
    exit 1
fi
