#!/bin/bash

# Test script to validate fixes
PROJECT_ROOT="/home/luser/Downloads/PI-Swarm"
FUNCTIONS_DIR="$PROJECT_ROOT/lib"
source "$PROJECT_ROOT/lib/source_functions.sh"

echo "Testing file path resolution..."
echo "PROJECT_ROOT is: $PROJECT_ROOT"
echo "Current directory: $(pwd)"
echo "Configuration files:"
echo "Checking: $PROJECT_ROOT/config/docker-compose.monitoring.yml"
if [[ -f "$PROJECT_ROOT/config/docker-compose.monitoring.yml" ]]; then
    echo "✅ docker-compose.monitoring.yml found"
else
    echo "❌ docker-compose.monitoring.yml NOT found"
fi
if [[ -f "$PROJECT_ROOT/config/prometheus.yml" ]]; then
    echo "✅ prometheus.yml found"
else
    echo "❌ prometheus.yml NOT found"
fi
if [[ -f "$PROJECT_ROOT/config/prometheus-alerts.yml" ]]; then
    echo "✅ prometheus-alerts.yml found"
else
    echo "❌ prometheus-alerts.yml NOT found"
fi

echo ""
echo "Testing Grafana templates:"
if [[ -d "$PROJECT_ROOT/templates/grafana" ]]; then
    echo "✅ Grafana templates directory found"
    find "$PROJECT_ROOT/templates/grafana" -type f | head -5
else
    echo "❌ Grafana templates directory NOT found"
fi

echo ""
echo "Testing scp_file function with invalid file..."
if scp_file "/nonexistent/file" "/tmp/" "127.0.0.1" "test" "test" 2>&1; then
    echo "ERROR: scp_file should have failed"
else
    echo "SUCCESS: scp_file properly failed for nonexistent file"
fi

echo ""
echo "All tests completed."
