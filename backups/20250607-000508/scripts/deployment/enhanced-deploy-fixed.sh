#!/bin/bash

# Enhanced interactive deployment script with proper user input handling
set -euo pipefail

echo "🚀 Enhanced Pi-Swarm Interactive Deployment"
echo "============================================"

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Function to check if Pis are reachable
check_pi_connectivity() {
    echo ""
    echo "🔍 Please enter your Raspberry Pi IP addresses..."
    echo "💡 Enter IP addresses separated by commas (e.g., 192.168.1.100,192.168.1.101)"
    read -p "Pi IP addresses: " pi_ips_input
    
    # Convert comma-separated string to array
    IFS=',' read -ra ips <<< "$pi_ips_input"
    local reachable_count=0
    
    echo ""
    echo "🔍 Checking connectivity to Raspberry Pis..."
    for ip in "${ips[@]}"; do
        # Trim whitespace
        ip=$(echo "$ip" | xargs)
        if timeout 2 ping -c 1 "$ip" >/dev/null 2>&1; then
            echo "  ✅ $ip - Reachable"
            ((reachable_count++))
        else
            echo "  ❌ $ip - Not reachable"
        fi
    done
    
    if [[ $reachable_count -eq 0 ]]; then
        echo ""
        echo "❌ No Raspberry Pis are reachable!"
        echo "💡 Troubleshooting tips:"
        echo "   • Ensure Pis are powered on"
        echo "   • Check network connectivity"
        echo "   • Verify IP addresses are correct"
        echo ""
        echo "🔄 Would you like to:"
        echo "   1. Continue anyway (deployment will likely fail)"
        echo "   2. Exit and fix connectivity issues"
        read -p "Enter your choice (1/2): " choice
        
        case $choice in
            1) echo "⚠️ Continuing with deployment despite connectivity issues..." ;;
            2) echo "🛑 Exiting. Please fix connectivity and try again."; exit 0 ;;
            *) echo "🛑 Invalid choice. Exiting."; exit 1 ;;
        esac
    else
        echo "✅ Found $reachable_count reachable Pi(s). Proceeding with deployment."
    fi
    
    # Store the IPs for later use
    export PI_IPS="$pi_ips_input"
}

# Get user credentials
get_user_credentials() {
    echo ""
    echo "🔐 SSH Authentication Setup"
    echo ""
    read -p "Enter SSH username for your Pis (default: pi): " username
    username=${username:-pi}
    
    echo "💡 Enter hostnames for your Pis separated by commas"
    echo "   Example: rpi1,rpi2,rpi3"
    read -p "Pi hostnames: " hostnames
    
    echo "💡 Enter the SSH password for your Raspberry Pis"
    read -s -p "SSH Password: " password
    echo ""
    
    export NODES_DEFAULT_USER="$username"
    export NODES_DEFAULT_PASS="$password"
    export PI_HOSTNAMES="$hostnames"
}

# Function to configure enterprise features
configure_enterprise_features() {
    echo ""
    echo "🏢 Enterprise Features Configuration"
    echo "===================================="
    echo ""
    echo "Would you like to enable enterprise features?"
    echo "1. Enable ALL enterprise features (SSL, alerts, HA, monitoring)"
    echo "2. Configure features individually"
    echo "3. Skip enterprise features (basic deployment only)"
    echo ""
    read -p "Enter your choice (1-3): " enterprise_choice
    
    case $enterprise_choice in
        1)
            echo "🔧 Enabling ALL enterprise features..."
            export ENABLE_ALL_ENTERPRISE="y"
            export ENABLE_LETSENCRYPT="y"
            export ENABLE_SLACK_ALERTS="y"
            export ENABLE_EMAIL_ALERTS="y"
            export ENABLE_DISCORD_ALERTS="y"
            export ENABLE_HIGH_AVAILABILITY="y"
            export ENABLE_SSL_MONITORING="y"
            export ENABLE_SERVICE_TEMPLATES="y"
            export ENABLE_PERFORMANCE_MONITORING="y"
            ;;
        2)
            echo "🎛️ Configuring features individually..."
            export ENABLE_ALL_ENTERPRISE="n"
            
            read -p "Enable Let's Encrypt SSL automation? (y/N): " ssl_choice
            export ENABLE_LETSENCRYPT="${ssl_choice:-n}"
            
            read -p "Configure Slack alerts? (y/N): " slack_choice
            export ENABLE_SLACK_ALERTS="${slack_choice:-n}"
            
            read -p "Configure email alerts? (y/N): " email_choice
            export ENABLE_EMAIL_ALERTS="${email_choice:-n}"
            
            read -p "Configure Discord alerts? (y/N): " discord_choice
            export ENABLE_DISCORD_ALERTS="${discord_choice:-n}"
            
            read -p "Setup high availability cluster? (y/N): " ha_choice
            export ENABLE_HIGH_AVAILABILITY="${ha_choice:-n}"
            
            read -p "Enable SSL certificate monitoring? (y/N): " ssl_mon_choice
            export ENABLE_SSL_MONITORING="${ssl_mon_choice:-n}"
            
            read -p "Initialize service template catalog? (y/N): " templates_choice
            export ENABLE_SERVICE_TEMPLATES="${templates_choice:-n}"
            
            read -p "Enable advanced performance monitoring? (y/N): " perf_choice
            export ENABLE_PERFORMANCE_MONITORING="${perf_choice:-n}"
            ;;
        3)
            echo "⚡ Basic deployment mode selected"
            export ENABLE_ALL_ENTERPRISE="n"
            export ENABLE_LETSENCRYPT="n"
            export ENABLE_SLACK_ALERTS="n"
            export ENABLE_EMAIL_ALERTS="n"
            export ENABLE_DISCORD_ALERTS="n"
            export ENABLE_HIGH_AVAILABILITY="n"
            export ENABLE_SSL_MONITORING="n"
            export ENABLE_SERVICE_TEMPLATES="n"
            export ENABLE_PERFORMANCE_MONITORING="n"
            ;;
        *)
            echo "🛑 Invalid choice. Defaulting to basic deployment."
            export ENABLE_ALL_ENTERPRISE="n"
            ;;
    esac
}

# Main deployment function
run_deployment() {
    echo ""
    echo "🚀 Starting Pi-Swarm deployment..."
    echo "⏱️  This may take 5-10 minutes depending on network speed"
    echo ""
    
    # Show deployment summary
    echo "📋 Deployment Summary:"
    echo "   • Target IPs: $PI_IPS"
    echo "   • SSH User: $NODES_DEFAULT_USER" 
    echo "   • Hostnames: $PI_HOSTNAMES"
    echo "   • Enterprise Features: ${ENABLE_ALL_ENTERPRISE:-n}"
    echo ""
    
    read -p "Proceed with deployment? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "🛑 Deployment cancelled by user."
        exit 0
    fi
    
    # Run the main deployment script
    echo "🏃 Executing deployment..."
    
    # Override the discovery function since we already have the IPs
    export SKIP_DISCOVERY="true"
    
    # Run the core deployment script
    "$PROJECT_ROOT/core/swarm-cluster.sh"
    
    deployment_status=$?
    
    echo ""
    echo "📊 Deployment Results"
    echo "===================="
    
    if [[ $deployment_status -eq 0 ]]; then
        echo "🎉 Deployment completed successfully!"
        echo ""
        # Get the first IP as manager IP
        first_ip=$(echo "$PI_IPS" | cut -d',' -f1 | xargs)
        echo "🌐 Access your Pi-Swarm cluster:"
        echo "   • Portainer (Container Management): http://$first_ip:9000"
        echo "   • Grafana (Monitoring Dashboard): http://$first_ip:3000"
        echo "   • Prometheus (Metrics): http://$first_ip:9090"
        echo ""
        echo "🔧 Useful commands:"
        echo "   • Check cluster status: ./scripts/management/show-cluster-status.sh"
        echo "   • Run tests: ./scripts/testing/comprehensive-test.sh"
        echo ""
    else
        echo "❌ Deployment failed with exit code: $deployment_status"
        echo ""
        echo "🔍 Check the latest log file for details:"
        echo "   tail -50 data/logs/piswarm-$(date +%Y%m%d).log"
        echo ""
        echo "🛠️ Common solutions:"
        echo "   • Verify Pi credentials (username/password)"
        echo "   • Check network connectivity"
        echo "   • Ensure Pis have internet access"
    fi
    
    return $deployment_status
}

# Main execution flow
echo "This script will guide you through an interactive Pi-Swarm deployment."
echo "You'll be prompted for your Pi IP addresses, credentials, and configuration."
echo ""

# Step 1: Check Pi connectivity
check_pi_connectivity

# Step 2: Get user credentials
get_user_credentials

# Step 3: Configure enterprise features
configure_enterprise_features

# Step 4: Run deployment
run_deployment

echo ""
echo "📚 For more help, see:"
echo "   • docs/TROUBLESHOOTING.md"
echo "   • docs/FAQ.md" 
echo "   • GitHub repository for issues and updates"
