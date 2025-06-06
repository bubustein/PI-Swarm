#!/bin/bash

# Final Integration Test for Pre-deployment Validation
# Tests all aspects of the pre-deployment validation integration
set -euo pipefail

echo "🧪 Pi-Swarm Pre-deployment Validation Integration Test"
echo "====================================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "🔍 Testing: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "   ✅ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "   ❌ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "📋 Test 1: File Existence and Permissions"
echo "=========================================="

run_test "Pre-deployment validation script exists" "[[ -f 'lib/deployment/pre_deployment_validation.sh' ]]"
run_test "Pre-deployment validation only script exists" "[[ -f 'scripts/testing/pre-deployment-validation-only.sh' ]]"
run_test "Pre-deployment validation only script is executable" "[[ -x 'scripts/testing/pre-deployment-validation-only.sh' ]]"
run_test "Enhanced deployment script exists" "[[ -f 'scripts/deployment/enhanced-deploy.sh' ]]"
run_test "Automated deployment script exists" "[[ -f 'scripts/deployment/automated-deploy.sh' ]]"
run_test "Core swarm cluster script exists" "[[ -f 'core/swarm-cluster.sh' ]]"

echo ""
echo "📋 Test 2: Script Syntax Validation"
echo "==================================="

run_test "Pre-deployment validation script syntax" "bash -n 'lib/deployment/pre_deployment_validation.sh'"
run_test "Pre-deployment validation only script syntax" "bash -n 'scripts/testing/pre-deployment-validation-only.sh'"
run_test "Enhanced deployment script syntax" "bash -n 'scripts/deployment/enhanced-deploy.sh'"
run_test "Automated deployment script syntax" "bash -n 'scripts/deployment/automated-deploy.sh'"
run_test "Core swarm cluster script syntax" "bash -n 'core/swarm-cluster.sh'"
run_test "Main deploy script syntax" "bash -n 'deploy.sh'"

echo ""
echo "📋 Test 3: Function Integration"
echo "=============================="

# Source the functions and test availability
source lib/source_functions.sh
source_functions

run_test "validate_and_prepare_pi_state function exists" "source 'lib/deployment/pre_deployment_validation.sh' && declare -f validate_and_prepare_pi_state >/dev/null"
run_test "cleanup_pi_disk_space function exists" "source 'lib/deployment/pre_deployment_validation.sh' && declare -f cleanup_pi_disk_space >/dev/null"
run_test "cleanup_existing_swarm function exists" "source 'lib/deployment/pre_deployment_validation.sh' && declare -f cleanup_existing_swarm >/dev/null"
run_test "validate_network_requirements function exists" "source 'lib/deployment/pre_deployment_validation.sh' && declare -f validate_network_requirements >/dev/null"

echo ""
echo "📋 Test 4: Script Integration Validation"
echo "========================================"

run_test "Enhanced deploy script contains pre-validation" "grep -q 'RUN_VALIDATION' 'scripts/deployment/enhanced-deploy.sh'"
run_test "Enhanced deploy script sources validation" "grep -q 'pre_deployment_validation.sh' 'scripts/deployment/enhanced-deploy.sh'"
run_test "Automated deploy script contains validation" "grep -q 'pre_deployment_validation.sh' 'scripts/deployment/automated-deploy.sh'"
run_test "Core script contains validation option" "grep -q 'PRE_VALIDATION' 'core/swarm-cluster.sh'"
run_test "Deploy script has validation option" "grep -q 'Pre-deployment Validation Only' 'deploy.sh'"

echo ""
echo "📋 Test 5: Configuration Integration"
echo "==================================="

run_test "Deploy script has correct option count" "grep -q 'Enter your choice (1-6)' 'deploy.sh'"
run_test "Deploy script calls correct validation script" "grep -q 'pre-deployment-validation-only.sh' 'deploy.sh'"

echo ""
echo "📋 Test 6: Documentation Updates"
echo "================================"

run_test "README contains pre-deployment validation section" "grep -q 'Pre-deployment Validation' 'README.md'"
run_test "README contains validation commands" "grep -q 'pre-deployment-validation-only.sh' 'README.md'"

echo ""
echo "🎯 Integration Test Summary"
echo "==========================="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "🎉 All integration tests PASSED!"
    echo ""
    echo "✅ Pre-deployment validation is fully integrated:"
    echo "   • Available in all deployment methods"
    echo "   • Standalone validation option added"
    echo "   • Function integration complete"
    echo "   • Documentation updated"
    echo ""
    echo "🚀 The system is ready for:"
    echo "   • Enhanced deployments with validation"
    echo "   • Automated deployments with validation"
    echo "   • Manual deployments with validation option"
    echo "   • Standalone pre-deployment validation"
    echo ""
    exit 0
else
    echo "❌ Some integration tests FAILED!"
    echo ""
    echo "Please review the failed tests above and address the issues."
    echo ""
    exit 1
fi
