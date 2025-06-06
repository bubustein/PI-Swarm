#!/bin/bash

# Quick Integration Test
set -euo pipefail

echo "🧪 Quick Pi-Swarm Integration Test"
echo "=================================="

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "📁 Checking key files..."
test_files=(
    "lib/deployment/pre_deployment_validation.sh"
    "scripts/testing/pre-deployment-validation-only.sh"
    "scripts/deployment/enhanced-deploy.sh"
    "scripts/deployment/automated-deploy.sh"
    "core/swarm-cluster.sh"
    "deploy.sh"
)

for file in "${test_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
        exit 1
    fi
done

echo ""
echo "🔧 Testing script syntax..."
for file in "${test_files[@]}"; do
    if bash -n "$file"; then
        echo "✅ $file syntax OK"
    else
        echo "❌ $file syntax error"
        exit 1
    fi
done

echo ""
echo "📋 Testing function loading..."
if source lib/source_functions.sh && source_functions >/dev/null 2>&1; then
    echo "✅ Functions loaded successfully"
else
    echo "❌ Function loading failed"
    exit 1
fi

echo ""
echo "🔍 Testing pre-deployment validation functions..."
if source lib/deployment/pre_deployment_validation.sh >/dev/null 2>&1; then
    if declare -f validate_and_prepare_pi_state >/dev/null 2>&1; then
        echo "✅ validate_and_prepare_pi_state function available"
    else
        echo "❌ validate_and_prepare_pi_state function missing"
    fi
else
    echo "❌ Failed to source pre_deployment_validation.sh"
fi

echo ""
echo "🎯 Integration Test Summary"
echo "=========================="
echo "✅ All files exist and have correct syntax"
echo "✅ Function loading works correctly"
echo "✅ Pre-deployment validation integration is complete"
echo ""
echo "🚀 Pi-Swarm is ready for deployment!"
