#!/bin/bash

# Enhanced automated deployment script with better error handling and user feedback
set -euo pipefail

echo "🚀 Enhanced Pi-Swarm Automated Deployment"
echo "=========================================="

cd /home/luser/Downloads/PI-Swarm

# Function to check if Pis are reachable
check_pi_connectivity() {
    local ips=("192.168.3.201" "192.168.3.202" "192.168.3.203")
    local reachable_count=0
    
    echo "🔍 Checking connectivity to Raspberry Pis..."
    for ip in "${ips[@]}"; do
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
        echo "   • Try: ping 192.168.3.201"
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
    
    return 0
}

# Run connectivity check
check_pi_connectivity

echo ""
echo "🚀 Starting automated deployment..."
echo "⏱️  This may take 5-10 minutes depending on network speed"
echo ""

# Create comprehensive input sequence for all deployment prompts
{
    echo "192.168.3.201,192.168.3.202,192.168.3.203"  # IP addresses
    echo "luser"                                        # Username
    echo "rpi1,rpi2,rpi3"                              # Hostnames  
    echo "raspberry"                                    # Password
    echo "y"                                           # Confirm deployment
    
    # Enterprise features configuration
    echo "n"                                           # Enable ALL enterprise features? (N)
    
    # Individual feature configuration (in case ALL is no)
    echo "n"                                           # Enable Let's Encrypt SSL automation? (N)
    echo "n"                                           # Configure Slack alerts? (N)
    echo "n"                                           # Configure email alerts? (N)
    echo "n"                                           # Configure Discord alerts? (N)
    echo "n"                                           # Setup high availability cluster? (N)
    echo "n"                                           # Enable SSL certificate monitoring? (N)
    echo "n"                                           # Initialize service template catalog? (N)
    echo "n"                                           # Enable advanced performance monitoring? (N)
    
    echo "y"                                           # Deploy services
    echo ""                                            # Extra newline for safety
    sleep 3                                            # Give time for all inputs
} | timeout 900 ./core/swarm-cluster.sh               # 15 minute timeout

deployment_status=$?

echo ""
echo "📊 Deployment Results"
echo "===================="

if [[ $deployment_status -eq 0 ]]; then
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "🌐 Access your Pi-Swarm cluster:"
    echo "   • Portainer (Container Management): http://192.168.3.201:9000"
    echo "   • Grafana (Monitoring Dashboard): http://192.168.3.201:3000"
    echo ""
    echo "🔧 Useful commands:"
    echo "   • Check cluster status: ./scripts/management/show-cluster-status.sh"
    echo "   • Run tests: ./scripts/testing/comprehensive-test.sh"
    echo ""
elif [[ $deployment_status -eq 124 ]]; then
    echo "⏰ Deployment timed out after 15 minutes"
    echo "💡 This might indicate:"
    echo "   • Slow network connection"
    echo "   • Pi hardware issues"
    echo "   • Package download problems"
    echo ""
    echo "🔄 Try running the deployment again or check the logs in data/logs/"
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
    echo "   • Try running: ./scripts/testing/comprehensive-test.sh"
fi

echo ""
echo "📚 For more help, see:"
echo "   • docs/TROUBLESHOOTING.md"
echo "   • docs/FAQ.md" 
echo "   • GitHub Issues: https://github.com/yourusername/pi-swarm/issues"

exit $deployment_status
