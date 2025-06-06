#!/bin/bash

# =============================================================================
# AUTOMATED COMPREHENSIVE PI-SWARM DEPLOYMENT SCRIPT
# =============================================================================
# 
# This script runs the comprehensive repair and then deploys the cluster
# in a fully automated fashion, addressing all known issues.
#
# Author: DevOps Team
# Version: 2.0.0
# Date: June 7, 2025
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

print_header() {
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "$1"
    echo "============================================================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

print_header "AUTOMATED COMPREHENSIVE PI-SWARM DEPLOYMENT"

log "INFO" "Starting automated deployment process..."

# Step 1: Run comprehensive system repair
print_step "Running comprehensive system repair..."
if "$PROJECT_ROOT/scripts/management/comprehensive-system-repair.sh"; then
    log "INFO" "System repair completed successfully"
else
    log "ERROR" "System repair failed"
    exit 1
fi

# Step 2: Set up discovered Pi IPs
print_step "Setting up environment variables..."
if [[ -z "${PI_STATIC_IPS:-}" ]]; then
    # Discover Pi nodes
    log "INFO" "Discovering Pi nodes..."
    discovered_nodes=()
    default_ips=("192.168.3.201" "192.168.3.202" "192.168.3.203" "192.168.3.204")
    
    for ip in "${default_ips[@]}"; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            if ssh -o ConnectTimeout=5 -o BatchMode=yes "luser@$ip" "echo 'test'" >/dev/null 2>&1; then
                discovered_nodes+=("$ip")
                log "INFO" "  ✅ Node $ip: ONLINE"
            fi
        fi
    done
    
    if [[ ${#discovered_nodes[@]} -gt 0 ]]; then
        export PI_STATIC_IPS="${discovered_nodes[*]}"
        log "INFO" "Set PI_STATIC_IPS to: $PI_STATIC_IPS"
    else
        log "ERROR" "No Pi nodes discovered"
        exit 1
    fi
else
    log "INFO" "Using provided PI_STATIC_IPS: $PI_STATIC_IPS"
fi

# Step 3: Run main deployment script
print_step "Running main deployment with automated answers..."

# Create automated input for deploy.sh
{
    echo "y"    # Enable shared storage
    echo "y"    # Enable Pi-hole DNS
    echo "1"    # Automated deployment
} | "$PROJECT_ROOT/deploy.sh"

deployment_result=$?

if [[ $deployment_result -eq 0 ]]; then
    print_header "DEPLOYMENT SUCCESSFUL"
    log "INFO" "Pi-Swarm cluster deployed successfully!"
    
    print_step "Deployment Summary:"
    echo "  • Cluster nodes: $PI_STATIC_IPS"
    echo "  • Storage: GlusterFS enabled"
    echo "  • DNS: Pi-hole configured"
    echo "  • Monitoring: Grafana + Prometheus"
    echo "  • Management: Portainer web interface"
    
    print_step "Access your cluster:"
    pi_array=($PI_STATIC_IPS)
    manager_ip="${pi_array[0]}"
    echo "  • Portainer: http://$manager_ip:9000"
    echo "  • Grafana: http://$manager_ip:3000"
    echo "  • Pi-hole: http://$manager_ip/admin (password: piswarm123)"
    
else
    print_error "Deployment failed with exit code: $deployment_result"
    
    print_step "Troubleshooting information:"
    echo "  • Check logs: $PROJECT_ROOT/data/logs/"
    echo "  • Verify Pi connectivity: ping <pi-ip>"
    echo "  • Check SSH access: ssh luser@<pi-ip>"
    echo "  • Review troubleshooting guide: docs/TROUBLESHOOTING.md"
    
    exit $deployment_result
fi

log "INFO" "Automated deployment completed successfully"
