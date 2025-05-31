#!/bin/bash

# Debug deployment script to test service deployment independently
set -euo pipefail

echo "🔍 Debug: Testing service deployment..."

cd /home/luser/Downloads/PI-Swarm

# Load functions
source lib/source_functions.sh

# Test variables
MANAGER_IP="192.168.3.201"
USER="luser"
PASS="raspberry"

echo "🔍 Testing SSH connection to manager..."
if ssh_exec "$MANAGER_IP" "$USER" "$PASS" "echo 'SSH works'"; then
    echo "✅ SSH connection successful"
else
    echo "❌ SSH connection failed"
    exit 1
fi

echo "🔍 Testing Docker Swarm status..."
swarm_status=$(ssh_exec "$MANAGER_IP" "$USER" "$PASS" "docker info --format '{{.Swarm.LocalNodeState}}'")
echo "Swarm status: $swarm_status"

echo "🔍 Testing file availability..."
ssh_exec "$MANAGER_IP" "$USER" "$PASS" "cd ~/PISworm && ls -la docker-compose.monitoring.yml" || echo "❌ Compose file not found"

echo "🔍 Testing Docker Compose availability..."
ssh_exec "$MANAGER_IP" "$USER" "$PASS" "
    if docker compose version >/dev/null 2>&1; then
        echo 'Docker Compose V2 available'
        docker compose version
    elif docker-compose --version >/dev/null 2>&1; then
        echo 'Docker Compose V1 available'
        docker-compose --version
    else
        echo 'No Docker Compose found'
    fi
"

echo "✅ Debug complete"
