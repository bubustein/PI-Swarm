#!/bin/bash
# ------------------------------------------------------------------------------
# Pi-Swarm Comprehensive Test Script
# ------------------------------------------------------------------------------
# This script validates the integrity of the Pi-Swarm project after restructuring.
# It checks function loading, lock mechanism, network utilities, and script syntax.
#
# Usage:
#   bash scripts/testing/comprehensive-test.sh
#
# Requirements:
#   - Run as a regular user (not root)
#   - All dependencies installed (see docs/README.md)
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

echo "[TEST] Comprehensive test PASSED"