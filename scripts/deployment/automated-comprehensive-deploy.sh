#!/bin/bash

# =============================================================================
# AUTOMATED COMPREHENSIVE PI-SWARM DEPLOYMENT SCRIPT
# =============================================================================
# 
# This script runs the comprehensive repair and then deploys the cluster
# in a fully automated fashion, addressing all known issues.
#
# ENVIRONMENT CONFIGURATION:
# Before running this script, configure the required environment variables:
#
#   PI_NODE_IPS       - Comma-separated list of Pi node IP addresses
#                       Example: "192.168.1.101,192.168.1.102,192.168.1.103"
#
#   NODES_DEFAULT_USER - Default SSH username for Pi nodes (default: pi)
#                       Example: "pi" or "ubuntu"
#
# Quick setup: Run ../../scripts/setup-environment.sh to configure these variables
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

# Environment validation
validate_environment() {
    log "INFO" "Validating environment configuration..."
    
    if [[ -z "${PI_NODE_IPS:-}" ]]; then
        print_error "PI_NODE_IPS environment variable is not set!"
        print_error "Please run ../../scripts/setup-environment.sh or set manually."
        exit 1
    fi
    
    if [[ -z "${NODES_DEFAULT_USER:-}" ]]; then
        print_warning "NODES_DEFAULT_USER not set, using default: pi"
        export NODES_DEFAULT_USER="pi"
    fi
    
    log "INFO" "Environment validation complete - Pi Nodes: $PI_NODE_IPS, User: $NODES_DEFAULT_USER"
}

print_header "AUTOMATED COMPREHENSIVE PI-SWARM DEPLOYMENT"

# Validate environment first
validate_environment

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
    default_ips=()
    
    # Get Pi node IPs from environment
    if [[ -n "${PI_NODE_IPS:-}" ]]; then
        IFS=',' read -ra default_ips <<< "$PI_NODE_IPS"
    else
        print_warning "No Pi node IPs configured. Please set PI_NODE_IPS environment variable"
        print_warning "Example: export PI_NODE_IPS='192.168.1.101,192.168.1.102,192.168.1.103'"
        exit 1
    fi
    
    for ip in "${default_ips[@]}"; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            if ssh -o ConnectTimeout=5 -o BatchMode=yes "${NODES_DEFAULT_USER:-pi}@$ip" "echo 'test'" >/dev/null 2>&1; then
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

# Step 2.5: Perform pre-deployment cleanup
print_step "Performing comprehensive system cleanup..."

# Load sanitization functions if available
if [[ -f "$PROJECT_ROOT/lib/system/sanitization.sh" ]]; then
    source "$PROJECT_ROOT/lib/system/sanitization.sh"
    
    # Set debconf to noninteractive mode to avoid prompts
    export DEBIAN_FRONTEND=noninteractive
    
    # Preconfigure grub-pc to avoid interactive prompts
    if dpkg -l | grep -q grub-pc; then
        echo 'grub-pc grub-pc/install_devices_empty boolean true' | sudo debconf-set-selections
        echo 'grub-pc grub-pc/install_devices string /dev/sda' | sudo debconf-set-selections
        echo 'grub-pc grub-pc/install_devices_disks_changed multiselect' | sudo debconf-set-selections
    fi
    
    # Perform comprehensive cleanup
    log "INFO" "Cleaning package system..."
    sudo apt-get autoremove -y --purge 2>/dev/null || {
        log "WARN" "Standard autoremove failed, trying with force options..."
        sudo apt-get autoremove -y --purge --allow-remove-essential 2>/dev/null || true
    }
    
    sudo apt-get clean || true
    sudo apt-get autoclean || true
    
    # Clean up Pi nodes if available
    if [[ -n "${PI_STATIC_IPS:-}" ]]; then
        for pi_ip in $PI_STATIC_IPS; do
            log "INFO" "Cleaning up Pi node: $pi_ip"
            cleanup_apt_system "$pi_ip" "luser" "" || {
                log "WARN" "Cleanup on $pi_ip completed with warnings (this is usually safe)"
            }
        done
    fi
    
    log "INFO" "System cleanup completed successfully"
else
    log "WARN" "Sanitization script not found, performing basic cleanup..."
    sudo apt-get autoremove -y --purge 2>/dev/null || true
    sudo apt-get clean || true
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
