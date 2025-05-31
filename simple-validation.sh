#!/bin/bash

# Simple final validation test
set -euo pipefail

echo "🧪 Simple Pi-Swarm Validation"
echo "============================="

cd /home/luser/Downloads/PI-Swarm

# Test function loading
echo "🔧 Testing function loading..."
source lib/source_functions.sh
echo "✅ Functions loaded: ${FUNCTIONS_LOADED:-false}"

# Test configuration files
echo "📁 Testing configuration files..."
for file in config/docker-compose.monitoring.yml config/prometheus.yml config/prometheus-alerts.yml; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
    fi
done

# Test critical functions
echo "⚙️ Testing critical functions..."
for func in deployment_summary setup_ssl_certificates deploy_services; do
    if command -v "$func" >/dev/null 2>&1; then
        echo "✅ $func available"
    else
        echo "❌ $func missing"
    fi
done

echo "✅ Basic validation complete!"
