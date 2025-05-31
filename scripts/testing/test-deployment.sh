#!/bin/bash

# Automated deployment script for testing
set -euo pipefail

echo "=== Pi-Swarm Automated Deployment Test ==="
echo "This script will automatically provide inputs for the deployment"
echo ""

# Change to project directory
cd "$(dirname "$0")"

# Set up environment
export PROJECT_ROOT="$(pwd)"
export FUNCTIONS_DIR="$PROJECT_ROOT/lib"

# Define the expected inputs
PI_IPS="192.168.3.201,192.168.3.202,192.168.3.203"
USERNAME="luser"
PASSWORD="password"

echo "Deployment configuration:"
echo "  Pi IPs: $PI_IPS"
echo "  Username: $USERNAME"
echo "  Password: [hidden]"
echo ""

# Create the input script with all required inputs
cat << 'EOF' > /tmp/deployment_inputs.txt
192.168.3.201,192.168.3.202,192.168.3.203
luser
password
y
piswarm.local
admin@piswarm.local


localhost
testuser
testpass
admin@piswarm.local

EOF

echo "Starting deployment with automated inputs..."
echo ""

# Run the deployment with inputs
timeout 300 bash -c "
    exec < /tmp/deployment_inputs.txt
    ./core/swarm-cluster.sh
" || {
    exit_code=$?
    echo ""
    echo "Deployment completed with exit code: $exit_code"
    if [[ $exit_code -eq 124 ]]; then
        echo "Deployment timed out after 5 minutes"
    fi
}

# Clean up
rm -f /tmp/deployment_inputs.txt

echo ""
echo "=== Deployment Test Complete ==="
