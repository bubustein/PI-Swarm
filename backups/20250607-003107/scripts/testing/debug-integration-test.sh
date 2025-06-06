#!/bin/bash

# Debug version of integration test
set -euo pipefail

echo "🧪 Debug Integration Test"
echo "========================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "🔍 Testing: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "   ✅ PASSED"
        ((TESTS_PASSED++))
    else
        echo "   ❌ FAILED"
        echo "   Command: $test_command"
        ((TESTS_FAILED++))
    fi
}

echo "📋 Test 1: File Existence and Permissions"
echo "=========================================="

run_test "Pre-deployment validation script exists" "[[ -f 'lib/deployment/pre_deployment_validation.sh' ]]"

echo "Current test status: passed=$TESTS_PASSED failed=$TESTS_FAILED"

run_test "Pre-deployment validation only script exists" "[[ -f 'scripts/testing/pre-deployment-validation-only.sh' ]]"

echo "Current test status: passed=$TESTS_PASSED failed=$TESTS_FAILED"

run_test "Pre-deployment validation only script is executable" "[[ -x 'scripts/testing/pre-deployment-validation-only.sh' ]]"

echo "Current test status: passed=$TESTS_PASSED failed=$TESTS_FAILED"

echo ""
echo "📋 Test 2: Script Syntax Validation"
echo "==================================="

run_test "Pre-deployment validation script syntax" "bash -n 'lib/deployment/pre_deployment_validation.sh'"

echo "Current test status: passed=$TESTS_PASSED failed=$TESTS_FAILED"

echo ""
echo "🎯 Debug Summary"
echo "==============="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed!"
    exit 1
fi
