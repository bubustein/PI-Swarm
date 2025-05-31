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
    echo "y"                                           # Deploy services
    sleep 2
} | timeout 300 ./core/swarm-cluster.sh

echo "✅ Deployment completed!"
