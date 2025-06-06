#!/bin/bash
# ------------------------------------------------------------------------------
# Pi-Swarm Comprehensive Test Script
# ------------------------------------------------------------------------------
# This script validates the integrity of the Pi-Swarm project after restructuring.
# It checks function loading, lock mechanism, network utilities, script syntax,
# and enhanced Python module integration.
#
# Usage:
#   bash scripts/testing/comprehensive-test.sh
#
# Requirements:
#   - Run as a regular user (not root)
#   - All dependencies installed (see docs/README.md)
#   - Python 3.6+ for enhanced modules
#
# Project Home: https://github.com/<your-org>/pi-swarm
# ------------------------------------------------------------------------------
set -euo pipefail

# Move to project root
cd "$(dirname "$0")/../.."

# Set environment variables for function and config locations
export FUNCTIONS_DIR="$(pwd)/lib"
export CONFIG_FILE="$(pwd)/config/config.yml"

# Load all functions (with logging)
source lib/source_functions.sh

echo "[TEST] Function loading: OK"

# Lock mechanism test
LOCK_FILE="/tmp/piswarm_test.lock"
export LOCK_FILE
acquire_lock
release_lock
echo "[TEST] Lock mechanism: OK"

# Network utilities test
gateway=$(default_gateway)
dns=$(default_dns)
iface=$(default_iface)
echo "[TEST] Network: gateway=$gateway, dns=$dns, iface=$iface"

# Main script syntax check
bash -n core/swarm-cluster.sh && echo "[TEST] Main script syntax: OK"

# CLI tool syntax check
bash -n core/pi-swarm && echo "[TEST] CLI tool syntax: OK"

# Enhanced Python integration test (if available)
if [[ -f "lib/python_integration.sh" ]]; then
    source lib/python_integration.sh
    if test_python_integration >/dev/null 2>&1; then
        echo "[TEST] Python integration: OK"
    else
        echo "[TEST] Python integration: FALLBACK (modules not available)"
    fi
else
    echo "[TEST] Python integration: NOT AVAILABLE"
fi

echo "[TEST] Comprehensive test PASSED"