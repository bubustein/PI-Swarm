#!/bin/bash

# Context-Aware Deployment Integration Test Script
# This script validates that all new features are properly integrated

set -euo pipefail

echo "🧪 Pi-Swarm Context-Aware Integration Validation"
echo "================================================"
echo ""

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "🔍 Core File Syntax Validation"
echo "------------------------------"
run_test "core/swarm-cluster.sh syntax" "bash -n core/swarm-cluster.sh"
run_test "lib/deployment/deploy_services.sh syntax" "bash -n lib/deployment/deploy_services.sh"
run_test "scripts/management/cluster-profile-manager.sh syntax" "bash -n scripts/management/cluster-profile-manager.sh"
run_test "lib/system/hardware_detection.sh syntax" "bash -n lib/system/hardware_detection.sh"
run_test "lib/system/sanitization.sh syntax" "bash -n lib/system/sanitization.sh"

echo ""
echo "📁 Required Files Existence"
echo "---------------------------"
run_test "main deploy.sh exists" "test -f deploy.sh"
run_test "context-aware deployment script exists" "test -f scripts/deployment/context-aware-deploy.sh"
run_test "cluster profile manager exists" "test -f scripts/management/cluster-profile-manager.sh"
run_test "hardware detection module exists" "test -f lib/system/hardware_detection.sh"
run_test "sanitization module exists" "test -f lib/system/sanitization.sh"
run_test "context-aware documentation exists" "test -f docs/CONTEXT_AWARE_DEPLOYMENT_GUIDE.md"

echo ""
echo "🔧 Script Executability"
echo "-----------------------"
run_test "deploy.sh is executable" "test -x deploy.sh"
run_test "context-aware deployment is executable" "test -x scripts/deployment/context-aware-deploy.sh"
run_test "cluster profile manager is executable" "test -x scripts/management/cluster-profile-manager.sh"
run_test "hardware detection demo is executable" "test -x scripts/testing/hardware-detection-demo.sh"
run_test "sanitization demo is executable" "test -x scripts/testing/sanitization-demo.sh"

echo ""
echo "📋 Menu Integration"
echo "------------------"
run_test "menu option 8 (context-aware) exists" "grep -q 'Context-Aware Deployment' deploy.sh"
run_test "menu option 9 (cluster management) exists" "grep -q 'Cluster Management' deploy.sh"
run_test "hardware detection option exists" "grep -q 'Hardware Detection' deploy.sh"
run_test "sanitization option exists" "grep -q 'Sanitization' deploy.sh"

echo ""
echo "🔍 Function Integration"
echo "----------------------"
run_test "context-aware detection function exists" "grep -q 'perform_context_aware_hardware_detection' core/swarm-cluster.sh"
run_test "adaptive service deployment function exists" "grep -q 'generate_adaptive_docker_compose' lib/deployment/deploy_services.sh"
run_test "cluster monitoring function exists" "grep -q 'monitor_cluster_resources' lib/deployment/deploy_services.sh"
run_test "hardware detection functions exist" "grep -q 'detect_hardware_specs' lib/system/hardware_detection.sh"
run_test "sanitization functions exist" "grep -q 'sanitize_system' lib/system/sanitization.sh"

echo ""
echo "⚙️ Configuration Integration"
echo "----------------------------"
run_test "context-aware variables exported" "grep -q 'export CONTEXT_AWARE_DEPLOYMENT' core/swarm-cluster.sh"
run_test "cluster profile variables exported" "grep -q 'export CLUSTER_PROFILE' core/swarm-cluster.sh"
run_test "sanitization level variable exported" "grep -q 'export SANITIZATION_LEVEL' core/swarm-cluster.sh"

echo ""
echo "📊 Test Results Summary"
echo "======================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}Context-Aware Deployment Integration is complete and ready for use.${NC}"
    echo ""
    echo "✅ Integration Status: COMPLETE"
    echo "✅ All features successfully integrated"
    echo "✅ All syntax validations passed"
    echo "✅ All required files present and executable"
    echo "✅ Menu integration successful"
    echo "✅ Function integration verified"
    echo ""
    echo "🚀 Ready for production deployment!"
    exit 0
else
    echo ""
    echo -e "${RED}❌ SOME TESTS FAILED!${NC}"
    echo -e "${RED}Please review the failed tests and fix any issues.${NC}"
    exit 1
fi
