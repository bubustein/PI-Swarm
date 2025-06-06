#!/bin/bash

# Test script to verify Pi-Swarm deployment with shared storage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🧪 Pi-Swarm Storage Integration Test"
echo "==================================="
echo ""

# Load functions first
if [[ -f "$PROJECT_ROOT/lib/source_functions.sh" ]]; then
    source "$PROJECT_ROOT/lib/source_functions.sh"
fi

# Test 1: Check if storage configuration exists
echo "Test 1: Checking storage configuration..."
if [[ -f "$PROJECT_ROOT/data/storage-config.env" ]]; then
    echo "✅ Storage configuration file found"
    source "$PROJECT_ROOT/data/storage-config.env"
    echo "   Storage solution: $STORAGE_SOLUTION"
    echo "   Shared storage path: $SHARED_STORAGE_PATH"
    echo "   Docker storage path: $DOCKER_STORAGE_PATH"
else
    echo "⚠️  No storage configuration found (will be created during deployment)"
fi
echo ""

# Test 2: Check if required storage functions are available
echo "Test 2: Checking storage modules..."
if [[ -f "$PROJECT_ROOT/lib/storage/storage_management.sh" ]]; then
    echo "✅ Storage management module found"
else
    echo "❌ Storage management module not found"
fi

if [[ -f "$PROJECT_ROOT/lib/storage/glusterfs_setup.sh" ]]; then
    echo "✅ GlusterFS setup module found"
else
    echo "❌ GlusterFS setup module not found"
fi

if [[ -f "$PROJECT_ROOT/lib/source_functions.sh" ]]; then
    echo "✅ Function loader available"
else
    echo "❌ Function loader not found"
fi
echo ""

# Test 3: Check function availability
echo "Test 3: Verifying function availability..."
if declare -f setup_cluster_storage >/dev/null 2>&1; then
    echo "✅ setup_cluster_storage function available"
else
    echo "❌ setup_cluster_storage function not available"
fi

if declare -f setup_glusterfs_storage >/dev/null 2>&1; then
    echo "✅ setup_glusterfs_storage function available"
else
    echo "❌ setup_glusterfs_storage function not available"
fi

if declare -f detect_storage_devices >/dev/null 2>&1; then
    echo "✅ detect_storage_devices function available"
else
    echo "❌ detect_storage_devices function not available"
fi
echo ""

# Test 4: Check deploy.sh storage integration
echo "Test 4: Checking deploy.sh integration..."
if grep -q "STORAGE_SOLUTION" "$PROJECT_ROOT/deploy.sh"; then
    echo "✅ Storage configuration integrated in deploy.sh"
else
    echo "❌ Storage configuration not found in deploy.sh"
fi
echo ""

# Test 5: Check core deployment script integration
echo "Test 5: Checking core deployment integration..."
if grep -q "setup_cluster_storage" "$PROJECT_ROOT/core/swarm-cluster.sh"; then
    echo "✅ Storage setup integrated in swarm-cluster.sh"
else
    echo "❌ Storage setup not integrated in swarm-cluster.sh"
fi
echo ""

echo "📋 Test Summary:"
echo "=================="
echo "If all tests show ✅, your Pi-Swarm is ready for deployment with shared storage."
echo ""
echo "To deploy with shared storage:"
echo "1. Run: ./deploy.sh"
echo "2. Choose 'Y' when prompted for shared storage"
echo "3. Select your preferred deployment option"
echo ""
echo "The deployment will:"
echo "• Auto-detect your 250GB SSDs on each Pi"
echo "• Install and configure GlusterFS"
echo "• Create distributed storage across all Pis"
echo "• Configure Docker to use shared storage for volumes"
echo "• Set up high-availability storage for your services"
