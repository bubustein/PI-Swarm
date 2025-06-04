#!/bin/bash

# Debug script to show SSH authentication variables
set -euo pipefail

echo "=== SSH Authentication Debug ==="
echo ""

# Show environment variables
echo "Current environment variables:"
echo "USER (local system): $USER"
echo "LOGNAME: ${LOGNAME:-not set}"
echo "USERNAME: ${USERNAME:-not set}"
echo "PI_USER: ${PI_USER:-not set}"
echo "NODES_DEFAULT_USER: ${NODES_DEFAULT_USER:-not set}"
echo ""

# Simulate what the pre-deployment validation does
echo "Simulating pre-deployment validation logic:"
echo ""

# Test 1: What happens when USER is not overridden
echo "Test 1 - Using \$USER directly:"
echo "Would try SSH to: $USER@192.168.3.201"
echo ""

# Test 2: Set USERNAME like enhanced deployment does
export USERNAME="pi"  # What you should configure for Pis
echo "Test 2 - After setting USERNAME to 'pi':"
echo "USERNAME: $USERNAME"
echo "USER (still): $USER"
echo ""

# Test 3: Override USER like the scripts should do
export USER="$USERNAME"
echo "Test 3 - After overriding USER with USERNAME:"
echo "USER (now): $USER"
echo "Would try SSH to: $USER@192.168.3.201"
echo ""

echo "=== Analysis ==="
echo ""
echo "The issue is that \$USER is a system environment variable"
echo "that always contains the local username ('luser' in your case)."
echo ""
echo "The pre-deployment validation script uses \$USER@\$ip for SSH,"
echo "but if \$USER isn't properly overridden before calling the"
echo "validation function, it will try to SSH as 'luser' instead"
echo "of the Pi username you configured."
echo ""
echo "Solutions:"
echo "1. Ensure 'export USER=\"\$USERNAME\"' happens before validation"
echo "2. Or modify validation script to use a different variable"
echo "3. Or pass username as parameter to validation function"
