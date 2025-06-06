#!/bin/bash
# Hardware Detection Demo Script
# Demonstrates hardware and OS detection capabilities

set -euo pipefail

echo "🔍 Pi-Swarm Hardware Detection & System Analysis"
echo "================================================="
echo ""

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source functions
source lib/source_functions.sh
source_functions

# Source hardware detection module
source lib/system/hardware_detection.sh

echo "This tool will detect hardware and OS specifications of your Raspberry Pis"
echo "and generate detailed system profiles for optimization."
echo ""

# Get Pi credentials
echo "🔐 SSH Configuration"
echo "===================="
read -p "Enter SSH username for your Pis (default: pi): " username
username=${username:-pi}

echo ""
echo "💡 Enter IP addresses of your Raspberry Pis separated by spaces"
echo "   Example: 192.168.1.100 192.168.1.101 192.168.1.102"
read -p "Pi IP addresses: " pi_ips_input

# Convert to array
read -ra pi_ips <<< "$pi_ips_input"

echo ""
read -sp "Enter SSH password: " password
echo ""
echo ""

# Validate connectivity first
echo "🔍 Testing connectivity to Pis..."
reachable_pis=()
for ip in "${pi_ips[@]}"; do
    if ping -c1 -W2 "$ip" >/dev/null 2>&1; then
        echo "  ✅ $ip - reachable"
        reachable_pis+=("$ip")
    else
        echo "  ❌ $ip - unreachable"
    fi
done

if [[ ${#reachable_pis[@]} -eq 0 ]]; then
    echo ""
    echo "❌ No Pis are reachable. Please check:"
    echo "   • IP addresses are correct"
    echo "   • Pis are powered on and connected"
    echo "   • Network connectivity"
    exit 1
fi

echo ""
echo "✅ Found ${#reachable_pis[@]} reachable Pi(s). Starting hardware detection..."
echo ""

# Detect hardware and OS for each Pi
for ip in "${reachable_pis[@]}"; do
    echo "🔍 Analyzing $ip..."
    echo "=================="
    
    # Test SSH connectivity
    if ! ssh_exec "$ip" "$username" "$password" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "❌ SSH failed for $ip. Skipping..."
        continue
    fi
    
    # Detect hardware
    if detect_hardware "$ip" "$username" "$password"; then
        echo "✅ Hardware detection completed"
    else
        echo "❌ Hardware detection failed"
        continue
    fi
    
    # Detect OS
    if detect_os "$ip" "$username" "$password"; then
        echo "✅ OS detection completed"
    else
        echo "❌ OS detection failed"
        continue
    fi
    
    # Generate system profile
    echo ""
    generate_system_profile "$ip"
    
    # Determine deployment strategy
    if determine_deployment_strategy "$ip"; then
        echo ""
        echo "🎯 Recommended Deployment Strategy:"
        local strategy_array="STRATEGY_${ip//./_}"
        local -n strategy_ref=$strategy_array
        echo "   Deployment Type: ${strategy_ref[DEPLOYMENT_TYPE]}"
        echo "   Docker Memory Limit: ${strategy_ref[DOCKER_MEMORY_LIMIT]}"
        echo "   Docker CPU Limit: ${strategy_ref[DOCKER_CPU_LIMIT]}"
        echo "   Advanced Monitoring: ${strategy_ref[ENABLE_ADVANCED_MONITORING]}"
        echo "   Log Retention: ${strategy_ref[ENABLE_LOG_RETENTION]} (${strategy_ref[LOG_RETENTION_DAYS]} days)"
        
        if [[ "${strategy_ref[OPTIMIZE_FOR_SD_CARD]:-}" == "true" ]]; then
            echo "   SD Card Optimization: Enabled"
        fi
        
        if [[ "${strategy_ref[ENABLE_THERMAL_THROTTLING]:-}" == "true" ]]; then
            echo "   ⚠️  Thermal Protection: Enabled (high temperature detected)"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
done

echo ""
echo "🎉 Hardware Detection Complete!"
echo "==============================="
echo ""
echo "📊 Summary:"
echo "   • Analyzed ${#reachable_pis[@]} Pi(s)"
echo "   • Generated system profiles and deployment strategies"
echo "   • Ready for context-aware deployment"
echo ""
echo "🚀 Next Steps:"
echo "   • Use option 8 (Context-Aware Deployment) from main menu"
echo "   • Or run: ./scripts/deployment/context-aware-deploy.sh"
echo ""
echo "💾 Hardware data has been stored in memory for this session."
echo "   Run context-aware deployment immediately to use this data."
