#!/bin/bash

# Automated deployment script for Pi-Swarm
set -euo pipefail

echo "🚀 Starting automated Pi-Swarm deployment..."

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Run pre-deployment validation
echo "🔍 Running pre-deployment validation..."
if ! bash lib/deployment/pre_deployment_validation.sh; then
    echo "❌ Pre-deployment validation failed. Aborting deployment."
    exit 1
fi
echo "✅ Pre-deployment validation passed. Continuing with deployment..."

# Create an expect-like script using bash
{
    echo "192.168.3.201,192.168.3.202,192.168.3.203"  # IP addresses
    echo "luser"                                        # Username
    echo "rpi1,rpi2,rpi3"                              # Hostnames
    echo ""                                             # Password (will be prompted if not set)
    echo "y"                                           # Confirm deployment
    
    # Enterprise features configuration
    echo "n"                                           # Enable ALL enterprise features? (N)
    
    # Individual feature configuration (since we said no to all)
    echo "n"                                           # Enable Let's Encrypt SSL automation? (N)
    echo "n"                                           # Configure Slack alerts? (N)
    echo "n"                                           # Configure email alerts? (N)
    echo "n"                                           # Configure Discord alerts? (N)
    echo "n"                                           # Setup high availability cluster? (N)
    echo "n"                                           # Enable SSL certificate monitoring? (N)
    echo "n"                                           # Initialize service template catalog? (N)
    echo "n"                                           # Enable advanced performance monitoring? (N)
    
    echo "y"                                           # Deploy services
    echo ""                                            # Extra newline
    sleep 2
} | timeout 600 ./core/swarm-cluster.sh

echo "✅ Deployment completed!"
