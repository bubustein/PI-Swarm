#!/bin/bash
# Test for clean directory and function structure
set -euo pipefail

cd "$(dirname "$0")/../.."

# Check essential directories
for d in config core data docs lib scripts templates web; do
  [[ -d $d ]] || { echo "[FAIL] Missing directory: $d"; exit 1; }
done
echo "[TEST] Directory structure: OK"

# Check essential functions
source lib/source_functions.sh
echo "[TEST] Function loading: OK"

# Check for duplicate/empty files in root
empty=$(find . -maxdepth 1 -type f -empty)
if [[ -n "$empty" ]]; then
  echo "[FAIL] Empty files in root: $empty"; exit 1;
fi

echo "[TEST] Clean structure test PASSED"
