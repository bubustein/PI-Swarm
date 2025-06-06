#!/bin/bash
# Test for Pi discovery
set -euo pipefail

cd "$(dirname "$0")/../.."

source lib/source_functions.sh

echo "[TEST] Pi discovery function:"
discover_pis || echo "[INFO] No Pis found (expected in test environment)"
echo "[TEST] Discovery test complete"
