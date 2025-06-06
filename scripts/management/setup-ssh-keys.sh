#!/bin/bash

# =============================================================================
# SSH KEY SETUP AND PASSWORDLESS SUDO CONFIGURATION
# =============================================================================
# 
# This script sets up SSH keys and configures passwordless sudo on Pi nodes
# to resolve authentication issues during deployment.
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_USER="${NODES_DEFAULT_USER:-pi}"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
DEFAULT_PI_IPS=()

# Get Pi node IPs from environment
if [[ -n "${PI_NODE_IPS:-}" ]]; then
    IFS=',' read -ra DEFAULT_PI_IPS <<< "$PI_NODE_IPS"
else
    echo -e "${RED}[ERROR] No Pi node IPs configured. Please set PI_NODE_IPS environment variable${NC}"
    echo -e "${YELLOW}Example: export PI_NODE_IPS='192.168.1.101,192.168.1.102,192.168.1.103'${NC}"
    exit 1
fi

print_header "SSH KEY SETUP AND PASSWORDLESS SUDO CONFIGURATION"

# Step 1: Generate SSH keys if they don't exist
setup_ssh_keys() {
    print_step "Setting up SSH keys..."
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log "INFO" "Generating new SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$SSH_USER@$(hostname)"
        log "INFO" "SSH key pair generated: $SSH_KEY_PATH"
    else
        log "INFO" "SSH key already exists: $SSH_KEY_PATH"
    fi
    
    # Ensure proper permissions
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "$SSH_KEY_PATH.pub"
    log "INFO" "SSH key permissions set correctly"
}

# Step 2: Discover available Pi nodes
discover_pi_nodes() {
    print_step "Discovering available Pi nodes..."
    
    local discovered_nodes=()
    for ip in "${DEFAULT_PI_IPS[@]}"; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            discovered_nodes+=("$ip")
            log "INFO" "  ✅ Node $ip: REACHABLE"
        else
            log "WARN" "  ❌ Node $ip: UNREACHABLE"
        fi
    done
    
    if [[ ${#discovered_nodes[@]} -eq 0 ]]; then
        print_error "No Pi nodes are reachable"
        exit 1
    fi
    
    export PI_NODES=("${discovered_nodes[@]}")
    log "INFO" "Discovered ${#PI_NODES[@]} Pi nodes: ${PI_NODES[*]}"
}

# Step 3: Distribute SSH keys to Pi nodes
distribute_ssh_keys() {
    print_step "Distributing SSH keys to Pi nodes..."
    
    # Get password once for all operations
    echo ""
    echo "Please enter the password for user '$SSH_USER' on the Pi nodes:"
    read -sp "Password: " PI_PASSWORD
    echo ""
    
    if [[ -z "$PI_PASSWORD" ]]; then
        print_error "Password cannot be empty"
        exit 1
    fi
    
    for pi_ip in "${PI_NODES[@]}"; do
        log "INFO" "Distributing SSH key to $pi_ip..."
        
        # Copy SSH key using sshpass
        if sshpass -p "$PI_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "$SSH_USER@$pi_ip" >/dev/null 2>&1; then
            log "INFO" "  ✅ SSH key distributed to $pi_ip"
        else
            print_warning "  ❌ Failed to distribute SSH key to $pi_ip"
            continue
        fi
        
        # Test passwordless SSH
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'SSH test'" >/dev/null 2>&1; then
            log "INFO" "  ✅ Passwordless SSH working for $pi_ip"
        else
            print_warning "  ❌ Passwordless SSH not working for $pi_ip"
        fi
    done
}

# Step 4: Configure passwordless sudo on Pi nodes
configure_passwordless_sudo() {
    print_step "Configuring passwordless sudo on Pi nodes..."
    
    for pi_ip in "${PI_NODES[@]}"; do
        log "INFO" "Configuring passwordless sudo on $pi_ip..."
        
        # Check if passwordless SSH is working
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'test'" >/dev/null 2>&1; then
            print_warning "  ❌ Cannot connect to $pi_ip without password, skipping sudo setup"
            continue
        fi
        
        # Check if passwordless sudo is already configured
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n true" >/dev/null 2>&1; then
            log "INFO" "  ✅ Passwordless sudo already configured for $pi_ip"
            continue
        fi
        
        # Configure passwordless sudo
        log "INFO" "  Setting up passwordless sudo for $SSH_USER on $pi_ip..."
        
        # Create the sudo configuration file
        if ssh "$SSH_USER@$pi_ip" "
            # Create temporary sudoers entry
            echo '$SSH_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$SSH_USER
            sudo chmod 440 /etc/sudoers.d/$SSH_USER
            
            # Test the configuration
            if sudo -n true 2>/dev/null; then
                echo 'SUCCESS: Passwordless sudo configured'
                exit 0
            else
                echo 'ERROR: Passwordless sudo configuration failed'
                sudo rm -f /etc/sudoers.d/$SSH_USER
                exit 1
            fi
        " 2>&1; then
            log "INFO" "  ✅ Passwordless sudo configured for $pi_ip"
        else
            print_warning "  ❌ Failed to configure passwordless sudo for $pi_ip"
        fi
    done
}

# Step 5: Verify setup
verify_setup() {
    print_step "Verifying SSH and sudo setup..."
    
    local all_good=true
    for pi_ip in "${PI_NODES[@]}"; do
        log "INFO" "Verifying setup for $pi_ip..."
        
        # Test SSH
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
            log "INFO" "  ✅ SSH: OK"
        else
            log "ERROR" "  ❌ SSH: FAILED"
            all_good=false
            continue
        fi
        
        # Test sudo
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$pi_ip" "sudo -n echo 'SUDO OK'" >/dev/null 2>&1; then
            log "INFO" "  ✅ SUDO: OK"
        else
            log "ERROR" "  ❌ SUDO: FAILED"
            all_good=false
        fi
    done
    
    if $all_good; then
        print_header "SETUP COMPLETED SUCCESSFULLY"
        log "INFO" "All Pi nodes are configured for passwordless SSH and sudo"
        log "INFO" "You can now run deployments without password prompts"
    else
        print_error "Some nodes have configuration issues"
        log "ERROR" "Please check the logs above and fix any failing nodes"
        exit 1
    fi
}

# Main execution
main() {
    log "INFO" "Starting SSH and sudo setup for Pi nodes..."
    
    setup_ssh_keys
    discover_pi_nodes
    distribute_ssh_keys
    configure_passwordless_sudo
    verify_setup
    
    log "INFO" "SSH and sudo setup completed successfully"
}

# Execute main function
main "$@"
