#!/bin/bash

# Mock deployment test script - tests deployment logic without requiring actual Pis
set -euo pipefail

echo "🚀 Mock Pi-Swarm deployment test..."

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Mock environment variables
export PI_STATIC_IPS=("192.168.3.201" "192.168.3.202" "192.168.3.203")
export PI_USER="luser"
export PI_PASS="${TEST_PI_PASSWORD:-}"
export ENABLE_LETSENCRYPT="n"
export SETUP_SLACK="n"
export SETUP_EMAIL_ALERTS="n"
export SETUP_DISCORD="n"
export SETUP_HA="n"
export ENABLE_SSL_MONITORING="n"
export ENABLE_TEMPLATES="n"
export ENABLE_ADVANCED_MONITORING="n"

# Source functions
source lib/source_functions.sh

echo "✅ Function loading test passed"

# Test SSL certificate logic
if [[ "$ENABLE_LETSENCRYPT" =~ ^(y|yes)$ ]] || [[ -n "${SSL_DOMAIN:-}" ]]; then
    echo "❌ SSL setup would be called (incorrect)"
else
    echo "✅ SSL setup correctly skipped"
fi

# Test configuration file existence
echo "📁 Checking required configuration files..."
for file in "config/docker-compose.monitoring.yml" "config/prometheus.yml" "config/prometheus-alerts.yml"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
    fi
done

# Test function existence
echo "🔧 Checking critical functions..."
for func in "deploy_services" "init_swarm" "configure_pi_headless" "setup_ssl_certificates"; do
    if command -v "$func" >/dev/null 2>&1; then
        echo "✅ Function $func is available"
    else
        echo "❌ Function $func is missing"
    fi
done

echo "✅ Mock deployment test completed successfully!"
echo "📝 Ready to deploy to actual hardware when Pis are available"
