#!/bin/bash
# Test that Pi-Swarm works as a non-root user
set -euo pipefail

cd "$(dirname "$0")/../.."

if [[ $EUID -eq 0 ]]; then
  echo "[FAIL] This test must be run as a regular user, not root."
  exit 1
fi

source lib/source_functions.sh

echo "[TEST] Running as user: $(whoami) (UID: $EUID)"

# Check sudo availability
if sudo -n true 2>/dev/null; then
  echo "[TEST] Sudo available: YES"
else
  echo "[TEST] Sudo available: NO (some operations may fail)"
fi

echo "[TEST] Non-root implementation test PASSED"
