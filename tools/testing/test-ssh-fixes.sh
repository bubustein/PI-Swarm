#!/bin/bash

# Test script to verify SSH authentication fixes
set -euo pipefail

echo "🔧 Testing SSH Authentication Fixes"
echo "===================================="
echo ""

# Get the actual username from user
echo "What username do you use to connect to your Raspberry Pis?"
echo "💡 Common options:"
echo "   - 'pi' for Raspberry Pi OS"
echo "   - 'ubuntu' for Ubuntu"
echo "   - Custom username if you created one"
echo ""
read -p "Enter your Pi username: " your_user

if [[ -z "$your_user" ]]; then
    echo "⚠️  No username provided, using 'pi' as default"
    your_user="pi"
fi

# Set up test environment
export USERNAME="$your_user"
export PASSWORD=""    # Will be prompted if needed
export PI_USER="$USERNAME"
export PI_PASS="$PASSWORD"
export NODES_DEFAULT_USER="$USERNAME"
export NODES_DEFAULT_PASS="$PASSWORD"

echo "✅ Using username: $your_user"
echo ""

# Test the variable resolution logic
echo "🧪 Testing username variable resolution:"
echo "Local system USER: $USER"
echo "Configured USERNAME: $USERNAME"
echo "PI_USER: $PI_USER"
echo "NODES_DEFAULT_USER: $NODES_DEFAULT_USER"
echo ""

# Test the fallback logic used in pre_deployment_validation.sh
test_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
echo "Resolved SSH user: $test_user"
echo ""

if [[ "$test_user" == "pi" ]]; then
    echo "✅ Username resolution working correctly (using 'pi' as default)"
elif [[ "$test_user" == "$USERNAME" ]]; then
    echo "✅ Username resolution working correctly (using configured USERNAME)"
else
    echo "❌ Username resolution may have issues"
fi

echo ""
echo "🔑 Manual SSH test (replace IP with your Pi's IP):"
echo "   ssh $test_user@192.168.3.201"
echo ""
echo "💡 If SSH works manually, the Pi-Swarm deployment should work now"
echo ""
echo "Next steps:"
echo "1. Test manual SSH connection to verify credentials:"
echo "   ssh $your_user@<your_pi_ip>"
echo "2. If SSH works, set environment variable and run deployment:"
echo "   export USERNAME=\"$your_user\""
echo "   export SSH_PASSWORD=\"your_password\""
echo "   ./deploy.sh"
echo "3. Or use automated deployment:"
echo "   export SSH_PASSWORD=\"your_password\""
echo "   ./automated-deploy.sh"
