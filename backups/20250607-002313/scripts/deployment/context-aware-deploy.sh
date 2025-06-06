#!/bin/bash
# Context-Aware Deployment Script
# Integrates hardware detection, sanitization, and adaptive deployment

set -euo pipefail

echo "🎯 Pi-Swarm Context-Aware Deployment"
echo "====================================="
echo ""

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source functions
source lib/source_functions.sh
source_functions

# Source hardware detection and sanitization modules
source lib/system/hardware_detection.sh
source lib/system/sanitization.sh

echo "This deployment method provides intelligent, context-aware deployment by:"
echo "  🔍 Detecting hardware specifications and OS capabilities"
echo "  🧹 Optionally sanitizing systems for optimal performance"
echo "  🎯 Adapting deployment strategies based on detected capabilities"
echo "  🚀 Deploying with optimized configurations for each system"
echo ""

# Step 1: Get Pi credentials and connectivity
echo "🔐 Step 1: SSH Configuration"
echo "============================="
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

# Validate connectivity
echo "🔍 Testing connectivity to Pis..."
reachable_pis=()
for ip in "${pi_ips[@]}"; do
    if ping -c1 -W2 "$ip" >/dev/null 2>&1; then
        if ssh_exec "$ip" "$username" "$password" "echo 'SSH OK'" >/dev/null 2>&1; then
            echo "  ✅ $ip - reachable and SSH working"
            reachable_pis+=("$ip")
        else
            echo "  ⚠️  $ip - reachable but SSH failed"
        fi
    else
        echo "  ❌ $ip - unreachable"
    fi
done

if [[ ${#reachable_pis[@]} -eq 0 ]]; then
    echo ""
    echo "❌ No Pis are accessible. Please check:"
    echo "   • IP addresses are correct"
    echo "   • Pis are powered on and connected"
    echo "   • SSH credentials are correct"
    exit 1
fi

echo ""
echo "✅ Found ${#reachable_pis[@]} accessible Pi(s): ${reachable_pis[*]}"

# Step 2: Hardware and OS Detection
echo ""
echo "🔍 Step 2: Hardware & OS Detection"
echo "==================================="
echo "Analyzing hardware specifications and OS capabilities..."
echo ""

detection_success=()
for ip in "${reachable_pis[@]}"; do
    echo "🔍 Analyzing $ip..."
    
    # Detect hardware
    if detect_hardware "$ip" "$username" "$password"; then
        log INFO "Hardware detection completed for $ip"
    else
        log WARN "Hardware detection failed for $ip"
        continue
    fi
    
    # Detect OS
    if detect_os "$ip" "$username" "$password"; then
        log INFO "OS detection completed for $ip"
    else
        log WARN "OS detection failed for $ip"
        continue
    fi
    
    # Determine deployment strategy
    if determine_deployment_strategy "$ip"; then
        log INFO "Deployment strategy determined for $ip"
        detection_success+=("$ip")
    else
        log WARN "Strategy determination failed for $ip"
    fi
done

if [[ ${#detection_success[@]} -eq 0 ]]; then
    echo "❌ Hardware detection failed for all Pis. Falling back to standard deployment."
    read -p "Continue with standard deployment? (y/N): " fallback
    if [[ ! "${fallback,,}" =~ ^(y|yes)$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
    # Fall back to standard deployment
    export PI_IPS="${reachable_pis[*]// /,}"
    export USERNAME="$username"
    export PASSWORD="$password"
    exec ./scripts/deployment/enhanced-deploy.sh
fi

echo ""
echo "✅ Hardware detection completed for ${#detection_success[@]} Pi(s)"

# Display detected configurations
echo ""
echo "📋 Detected System Configurations:"
echo "==================================="
for ip in "${detection_success[@]}"; do
    generate_system_profile "$ip"
done

# Step 3: Optional Sanitization
echo ""
echo "🧹 Step 3: System Sanitization (Optional)"
echo "=========================================="
echo "Would you like to sanitize/clean the systems before deployment?"
echo "This can improve performance and ensure optimal deployment conditions."
echo ""
echo "Sanitization options:"
echo "  1. Skip sanitization (faster deployment)"
echo "  2. Minimal cleaning (package caches, temp files)"
echo "  3. Standard cleaning (recommended)"
echo "  4. Thorough cleaning (aggressive cleanup)"
echo ""

while true; do
    read -p "Choose option (1-4): " sanitize_choice
    case $sanitize_choice in
        1) sanitization_level=""; break ;;
        2) sanitization_level="minimal"; break ;;
        3) sanitization_level="standard"; break ;;
        4) sanitization_level="thorough"; break ;;
        *) echo "❌ Invalid choice. Please enter 1-4."; continue ;;
    esac
done

if [[ -n "$sanitization_level" ]]; then
    echo ""
    echo "🧹 Performing $sanitization_level sanitization..."
    
    sanitized_pis=()
    for ip in "${detection_success[@]}"; do
        echo "🧼 Sanitizing $ip..."
        if sanitize_system "$ip" "$username" "$password" "$sanitization_level"; then
            echo "✅ Sanitization completed for $ip"
            sanitized_pis+=("$ip")
        else
            echo "❌ Sanitization failed for $ip (continuing anyway)"
        fi
    done
    
    echo ""
    echo "✅ Sanitization completed for ${#sanitized_pis[@]}/${#detection_success[@]} Pi(s)"
fi

# Step 4: Context-Aware Deployment Configuration
echo ""
echo "🎯 Step 4: Context-Aware Deployment Configuration"
echo "=================================================="
echo "Configuring deployment based on detected capabilities..."
echo ""

# Determine overall cluster strategy based on detected hardware
min_memory=999999
total_cores=0
has_ssd=false
all_raspberry_pi=true

for ip in "${detection_success[@]}"; do
    hw_array="HW_${ip//./_}"
    local -n hw_ref=$hw_array 2>/dev/null || continue
    
    memory_mb=${hw_ref[MEMORY_TOTAL_MB]:-0}
    if (( memory_mb > 0 && memory_mb < min_memory )); then
        min_memory=$memory_mb
    fi
    
    cores=${hw_ref[CPU_CORES]:-1}
    total_cores=$((total_cores + cores))
    
    if [[ "${hw_ref[STORAGE_TYPE]:-}" == "SSD" ]]; then
        has_ssd=true
    fi
    
    if [[ "${hw_ref[IS_RASPBERRY_PI]:-}" != "true" ]]; then
        all_raspberry_pi=false
    fi
done

# Determine cluster-wide settings
echo "📊 Cluster Analysis:"
echo "   Minimum Memory: ${min_memory}MB"
echo "   Total CPU Cores: $total_cores"
echo "   SSD Storage: $has_ssd"
echo "   All Raspberry Pi: $all_raspberry_pi"
echo ""

# Configure deployment based on cluster capabilities
if (( min_memory >= 4096 && total_cores >= 8 )); then
    cluster_profile="high_performance"
    echo "🚀 High Performance cluster detected"
    enable_advanced_monitoring="true"
    enable_ssl="true"
    enable_ha="true"
elif (( min_memory >= 2048 && total_cores >= 4 )); then
    cluster_profile="standard"
    echo "⚡ Standard cluster detected"
    enable_advanced_monitoring="true"
    enable_ssl="true"
    enable_ha="false"
else
    cluster_profile="lightweight"
    echo "🪶 Lightweight cluster detected"
    enable_advanced_monitoring="false"
    enable_ssl="false"
    enable_ha="false"
fi

echo ""
echo "🎯 Recommended Configuration:"
echo "   Cluster Profile: $cluster_profile"
echo "   Advanced Monitoring: $enable_advanced_monitoring"
echo "   SSL/TLS: $enable_ssl"
echo "   High Availability: $enable_ha"

# Allow user to override recommendations
echo ""
read -p "Use recommended configuration? (Y/n): " use_recommended
use_recommended=${use_recommended:-Y}

if [[ ! "${use_recommended,,}" =~ ^(y|yes)$ ]]; then
    echo ""
    echo "🔧 Custom Configuration:"
    read -p "Enable SSL/TLS? (y/N): " enable_ssl
    enable_ssl=${enable_ssl:-n}
    
    read -p "Enable advanced monitoring? (y/N): " enable_advanced_monitoring  
    enable_advanced_monitoring=${enable_advanced_monitoring:-n}
    
    if [[ ${#detection_success[@]} -ge 3 ]]; then
        read -p "Enable high availability? (y/N): " enable_ha
        enable_ha=${enable_ha:-n}
    fi
fi

# Step 5: Deploy with Context-Aware Configuration
echo ""
echo "🚀 Step 5: Context-Aware Deployment"
echo "===================================="
echo "Starting deployment with optimized configuration..."
echo ""

# Export configuration for the main deployment script
export PI_IPS="${detection_success[*]// /,}"
export USERNAME="$username"
export PASSWORD="$password"
export CLUSTER_NAME="piswarm-${cluster_profile}"

# Configure enterprise features based on analysis
if [[ "${enable_ssl,,}" =~ ^(y|yes|true)$ ]]; then
    export ENABLE_LETSENCRYPT="y"
    echo "✅ SSL/TLS will be configured"
else
    export ENABLE_LETSENCRYPT="n"
fi

if [[ "${enable_advanced_monitoring,,}" =~ ^(y|yes|true)$ ]]; then
    export ENABLE_ADVANCED_MONITORING="y"
    echo "✅ Advanced monitoring will be enabled"
else
    export ENABLE_ADVANCED_MONITORING="n"
fi

if [[ "${enable_ha,,}" =~ ^(y|yes|true)$ ]]; then
    export SETUP_HA="y"
    echo "✅ High availability will be configured"
else
    export SETUP_HA="n"
fi

# Apply per-node optimizations during deployment
echo ""
echo "📋 Per-Node Optimizations:"
for ip in "${detection_success[@]}"; do
    strategy_array="STRATEGY_${ip//./_}"
    local -n strategy_ref=$strategy_array 2>/dev/null || continue
    
    echo "   $ip: ${strategy_ref[DEPLOYMENT_TYPE]} (${strategy_ref[DOCKER_MEMORY_LIMIT]} memory, ${strategy_ref[DOCKER_CPU_LIMIT]} CPU)"
done

echo ""
echo "🎯 Starting context-aware deployment..."

# Run the enhanced deployment with our optimized configuration
if bash "$PROJECT_ROOT/core/swarm-cluster.sh"; then
    echo ""
    echo "🎉 Context-Aware Deployment Completed Successfully!"
    echo "=================================================="
    echo ""
    echo "✅ Your Pi-Swarm cluster has been deployed with optimizations based on:"
    echo "   • Hardware specifications detected for each Pi"
    echo "   • Operating system capabilities"
    echo "   • Cluster-wide performance profile ($cluster_profile)"
    echo "   • Context-specific resource limits and configurations"
    echo ""
    
    if [[ -n "$sanitization_level" ]]; then
        echo "🧹 Systems were sanitized ($sanitization_level level) before deployment"
    fi
    
    echo ""
    echo "🌐 Access your optimized cluster at:"
    first_ip=$(echo "${detection_success[0]}")
    echo "   • Portainer: http://$first_ip:9000"
    echo "   • Grafana: http://$first_ip:3000"
    echo "   • Prometheus: http://$first_ip:9090"
    
else
    echo ""
    echo "❌ Context-aware deployment failed!"
    echo "==================================="
    echo ""
    echo "The deployment encountered errors despite hardware detection and optimization."
    echo "Check the logs for details: data/logs/piswarm-$(date +%Y%m%d).log"
    exit 1
fi
