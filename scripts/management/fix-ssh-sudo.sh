#!/bin/bash

# =============================================================================
# FIX SSH AND SUDO ISSUES
# =============================================================================
# 
# This script fixes SSH and sudo configuration issues on Pi nodes
# Handles passwordless sudo setup with interactive password prompts
#
# Author: DevOps Team
# Version: 1.0.0
# Date: June 7, 2025
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSH_USER="${NODES_DEFAULT_USER:-pi}"
PI_NODES=()

# Get Pi node IPs from environment
if [[ -n "${PI_NODE_IPS:-}" ]]; then
    IFS=',' read -ra PI_NODES <<< "$PI_NODE_IPS"
else
    echo -e "${RED}[ERROR] No Pi node IPs configured. Please set PI_NODE_IPS environment variable${NC}"
    echo -e "${YELLOW}Example: export PI_NODE_IPS='192.168.1.101,192.168.1.102,192.168.1.103'${NC}"
    exit 1
fi

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

print_step() {
    echo -e "${GREEN}[STEP] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check which nodes are reachable
check_connectivity() {
    print_step "Checking connectivity to Pi nodes..."
    
    local reachable_nodes=()
    for ip in "${PI_NODES[@]}"; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            reachable_nodes+=("$ip")
            log "INFO" "  ✅ Node $ip: REACHABLE"
        else
            log "WARN" "  ❌ Node $ip: UNREACHABLE"
        fi
    done
    
    if [[ ${#reachable_nodes[@]} -eq 0 ]]; then
        print_error "No Pi nodes are reachable"
        exit 1
    fi
    
    PI_NODES=("${reachable_nodes[@]}")
}

# Check SSH connectivity
check_ssh() {
    print_step "Checking SSH connectivity..."
    
    for pi_ip in "${PI_NODES[@]}"; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
            log "INFO" "  ✅ SSH to $pi_ip: OK"
        else
            print_warning "  ❌ SSH to $pi_ip: FAILED (password required)"
        fi
    done
}

# Check sudo configuration
check_sudo() {
    print_step "Checking sudo configuration..."
    
    for pi_ip in "${PI_NODES[@]}"; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n echo 'SUDO OK'" >/dev/null 2>&1; then
            log "INFO" "  ✅ Passwordless sudo on $pi_ip: OK"
        else
            print_warning "  ❌ Passwordless sudo on $pi_ip: FAILED"
        fi
    done
}

# Fix passwordless sudo for a single node
fix_sudo_for_node() {
    local pi_ip="$1"
    
    log "INFO" "Fixing passwordless sudo for $pi_ip..."
    
    # Check if SSH works without password
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'test'" >/dev/null 2>&1; then
        print_warning "Cannot connect to $pi_ip without password, skipping sudo setup"
        return 1
    fi
    
    # Check if passwordless sudo already works
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n true" >/dev/null 2>&1; then
        log "INFO" "Passwordless sudo already configured for $pi_ip"
        return 0
    fi
    
    # Get password for sudo operations
    echo ""
    echo "Enter the sudo password for user '$SSH_USER' on $pi_ip:"
    read -sp "Password: " SUDO_PASSWORD
    echo ""
    
    if [[ -z "$SUDO_PASSWORD" ]]; then
        print_error "Password cannot be empty"
        return 1
    fi
    
    # Configure passwordless sudo
    local ssh_command="
        # Create sudoers entry
        echo '$SUDO_PASSWORD' | sudo -S bash -c 'echo \"$SSH_USER ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/$SSH_USER'
        
        # Set proper permissions
        echo '$SUDO_PASSWORD' | sudo -S chmod 440 /etc/sudoers.d/$SSH_USER
        
        # Test the configuration
        if sudo -n true 2>/dev/null; then
            echo 'SUCCESS'
        else
            echo 'FAILED'
            exit 1
        fi
    "
    
    if ssh "$SSH_USER@$pi_ip" "$ssh_command" 2>/dev/null | grep -q "SUCCESS"; then
        log "INFO" "  ✅ Passwordless sudo configured for $pi_ip"
        return 0
    else
        print_error "  ❌ Failed to configure passwordless sudo for $pi_ip"
        return 1
    fi
}

# Interactive sudo fix
interactive_sudo_fix() {
    print_step "Interactive passwordless sudo setup..."
    
    local nodes_needing_sudo=()
    
    # Identify nodes that need sudo configuration
    for pi_ip in "${PI_NODES[@]}"; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'test'" >/dev/null 2>&1; then
            if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n true" >/dev/null 2>&1; then
                nodes_needing_sudo+=("$pi_ip")
            fi
        fi
    done
    
    if [[ ${#nodes_needing_sudo[@]} -eq 0 ]]; then
        log "INFO" "All reachable nodes already have passwordless sudo configured"
        return 0
    fi
    
    echo ""
    echo "The following nodes need passwordless sudo configuration:"
    for ip in "${nodes_needing_sudo[@]}"; do
        echo "  - $ip"
    done
    echo ""
    
    # Fix each node
    for pi_ip in "${nodes_needing_sudo[@]}"; do
        echo "=== Configuring passwordless sudo for $pi_ip ==="
        if fix_sudo_for_node "$pi_ip"; then
            log "INFO" "Successfully configured $pi_ip"
        else
            print_error "Failed to configure $pi_ip"
        fi
        echo ""
    done
}

# Verify final setup
verify_setup() {
    print_step "Verifying final setup..."
    
    local all_good=true
    for pi_ip in "${PI_NODES[@]}"; do
        echo "Testing $pi_ip:"
        
        # Test SSH
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
            echo "  ✅ SSH: OK"
        else
            echo "  ❌ SSH: FAILED"
            all_good=false
            continue
        fi
        
        # Test sudo
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n echo 'SUDO OK'" >/dev/null 2>&1; then
            echo "  ✅ SUDO: OK"
        else
            echo "  ❌ SUDO: FAILED"
            all_good=false
        fi
    done
    
    echo ""
    if $all_good; then
        echo -e "${GREEN}✅ ALL NODES CONFIGURED SUCCESSFULLY${NC}"
        echo "You can now run deployments without password prompts"
    else
        echo -e "${RED}❌ SOME NODES HAVE ISSUES${NC}"
        echo "Please check the output above and fix any failing nodes manually"
        exit 1
    fi
}

# Main execution
main() {
    echo "=============================================="
    echo "      SSH AND SUDO CONFIGURATION FIX"
    echo "=============================================="
    echo ""
    
    check_connectivity
    check_ssh
    check_sudo
    interactive_sudo_fix
    verify_setup
    
    echo ""
    echo "Setup completed successfully!"
}

# Execute main function
main "$@"
