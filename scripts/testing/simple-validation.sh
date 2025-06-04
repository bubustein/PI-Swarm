#!/bin/bash

# Simple validation test
set -euo pipefail

echo "🧪 Simple Pi-Swarm Validation"
echo "============================="

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

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
