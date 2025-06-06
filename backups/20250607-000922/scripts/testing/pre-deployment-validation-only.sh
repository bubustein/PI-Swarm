#!/bin/bash

# Pre-deployment Validation Only Script
# Runs validation and cleanup without actual deployment
set -euo pipefail

echo "🧹 Pi-Swarm Pre-deployment Validation Only"
echo "=========================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

# Source functions
source lib/source_functions.sh
source_functions

echo "🎯 This validation process will:"
echo "   • Discover and validate Raspberry Pi connectivity"
echo "   • Check system resources and requirements"
echo "   • Clean up old Docker containers and images"
echo "   • Optimize network and performance settings"
echo "   • Prepare Pis for optimal deployment"
echo ""

# Step 1: Pi Discovery
echo "🔍 Step 1: Discovering Raspberry Pi devices"
echo "============================================="

if ! discover_pis; then
    log ERROR "Pi discovery failed. Please check your network setup and try again."
    exit 1
fi

echo ""
echo "✅ Pi discovery completed successfully!"
echo "   Found Pi IPs: $PI_IPS"
echo ""

# Step 2: Get authentication details
echo "🔑 Step 2: Authentication Setup"
echo "==============================="

# Get username
while true; do
    read -p "Username for Pi access (default: pi): " USERNAME
    USERNAME=${USERNAME:-pi}
    if [[ -n "$USERNAME" ]]; then
        break
    fi
done

# Get password
echo ""
echo "Please enter the password for user '$USERNAME':"
while true; do
    read -sp "Password: " PASSWORD
    echo ""
    if [[ -n "$PASSWORD" ]]; then
        break
    else
        echo "❌ Password cannot be empty."
    fi
done

# Step 3: Run Pre-deployment Validation
echo ""
echo "🧹 Step 3: Running Pre-deployment Validation"
echo "============================================="

# Source the pre-deployment validation functions
if [[ -f "$SCRIPT_DIR/lib/deployment/pre_deployment_validation.sh" ]]; then
    source "$SCRIPT_DIR/lib/deployment/pre_deployment_validation.sh"
    
    # Convert PI_IPS string to array
    IFS=' ' read -ra pi_array <<< "$PI_IPS"
    
    # Run validation
    export USER="$USERNAME"
    if validate_and_prepare_pi_state "${pi_array[@]}"; then
        echo ""
        echo "🎉 Pre-deployment Validation Completed Successfully!"
        echo "=================================================="
        echo ""
        echo "✅ All Pis are validated and optimized!"
        echo ""
        echo "📋 Summary:"
        echo "   • Connectivity: All Pis accessible"
        echo "   • Resources: Sufficient disk space and memory"
        echo "   • Docker: Clean environment ready"
        echo "   • Network: Connectivity validated"
        echo "   • Security: SSH access confirmed"
        echo "   • Performance: System optimized"
        echo ""
        echo "🚀 Your Pis are now ready for deployment!"
        echo ""
        echo "💡 Next steps:"
        echo "   1. Run: ./deploy.sh"
        echo "   2. Choose deployment method (1 or 2 recommended)"
        echo "   3. Your Pis will deploy faster with pre-validated state"
        echo ""
    else
        echo ""
        echo "❌ Pre-deployment Validation Failed!"
        echo "==================================="
        echo ""
        echo "Some issues were found with your Pi setup."
        echo "Please review the errors above and address them before deployment."
        echo ""
        echo "📋 Common solutions:"
        echo "   • Check network connectivity to all Pis"
        echo "   • Verify SSH authentication (user/password)"
        echo "   • Ensure sufficient disk space (minimum 2GB free)"
        echo "   • Check that Docker service is not running in conflict"
        echo ""
        echo "💬 For help, see: docs/TROUBLESHOOTING.md"
        exit 1
    fi
else
    echo "❌ Pre-deployment validation script not found!"
    echo "   Expected: $SCRIPT_DIR/lib/deployment/pre_deployment_validation.sh"
    exit 1
fi
