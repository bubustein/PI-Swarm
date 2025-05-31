#!/bin/bash

# Automated deployment script for Pi-Swarm
set -euo pipefail

echo "🚀 Starting automated Pi-Swarm deployment..."

cd /home/luser/Downloads/PI-Swarm

# Create an expect-like script using bash
{
    echo "192.168.3.201,192.168.3.202,192.168.3.203"  # IP addresses
    echo "luser"                                        # Username
    echo "rpi1,rpi2,rpi3"                              # Hostnames
    echo "raspberry"                                    # Password (assuming default)
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
