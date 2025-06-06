#!/bin/bash
# Pi-Swarm Environment Configuration Setup
# This script helps users configure environment variables for portable deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to validate IP address format
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to discover network information
discover_network() {
    print_step "Discovering network configuration..."
    
    # Get default gateway
    local gateway
    gateway=$(ip route | grep default | awk '{print $3}' | head -n1)
    
    # Get network interface
    local interface
    interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    # Get subnet
    local subnet
    subnet=$(ip route | grep "$interface" | grep -v default | awk '{print $1}' | head -n1)
    
    echo "  Gateway: ${gateway:-auto}"
    echo "  Interface: ${interface:-auto}"
    echo "  Subnet: ${subnet:-auto}"
    
    # Suggest IP range based on subnet
    if [[ -n "$subnet" ]]; then
        local base_ip
        base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
        echo -e "  ${YELLOW}Suggested Pi IP range: ${base_ip}.100-${base_ip}.199${NC}"
    fi
}

# Function to prompt for Pi node IPs
configure_pi_nodes() {
    print_header "Pi Node Configuration"
    
    discover_network
    
    echo ""
    echo "Please configure your Pi node IP addresses."
    echo "You can enter them as a comma-separated list."
    echo ""
    echo "Examples:"
    echo "  192.168.1.101,192.168.1.102,192.168.1.103"
    echo "  10.0.0.50,10.0.0.51,10.0.0.52,10.0.0.53"
    echo ""
    
    while true; do
        read -p "Enter Pi node IPs (comma-separated): " pi_ips
        
        if [[ -z "$pi_ips" ]]; then
            print_error "Pi node IPs are required for deployment."
            continue
        fi
        
        # Validate IPs
        IFS=',' read -ra ip_array <<< "$pi_ips"
        local valid_ips=true
        
        for ip in "${ip_array[@]}"; do
            ip=$(echo "$ip" | xargs) # trim whitespace
            if ! validate_ip "$ip"; then
                print_error "Invalid IP address: $ip"
                valid_ips=false
                break
            fi
        done
        
        if [[ "$valid_ips" == true ]]; then
            export PI_NODE_IPS="$pi_ips"
            echo "export PI_NODE_IPS=\"$pi_ips\"" >> ~/.bashrc
            print_step "Pi node IPs configured: $pi_ips"
            break
        fi
    done
}

# Function to configure default user
configure_default_user() {
    print_header "Default User Configuration"
    
    echo "Configure the default SSH user for Pi nodes."
    echo "Common defaults:"
    echo "  - Raspberry Pi OS: pi"
    echo "  - Ubuntu: ubuntu"
    echo "  - Custom installations: varies"
    echo ""
    
    read -p "Enter default SSH user [pi]: " default_user
    default_user=${default_user:-pi}
    
    export NODES_DEFAULT_USER="$default_user"
    echo "export NODES_DEFAULT_USER=\"$default_user\"" >> ~/.bashrc
    print_step "Default user configured: $default_user"
}

# Function to configure optional settings
configure_optional_settings() {
    print_header "Optional Configuration"
    
    echo "Configure optional settings (press Enter to skip):"
    echo ""
    
    # Manager IP (optional - will auto-detect if not set)
    read -p "Manager IP (leave empty for auto-detection): " manager_ip
    if [[ -n "$manager_ip" ]] && validate_ip "$manager_ip"; then
        export MANAGER_IP="$manager_ip"
        echo "export MANAGER_IP=\"$manager_ip\"" >> ~/.bashrc
        print_step "Manager IP configured: $manager_ip"
    fi
    
    # Default password (optional - will prompt if not set)
    read -s -p "Default SSH password (leave empty to use key auth): " default_pass
    echo ""
    if [[ -n "$default_pass" ]]; then
        export NODES_DEFAULT_PASS="$default_pass"
        echo "export NODES_DEFAULT_PASS=\"$default_pass\"" >> ~/.bashrc
        print_step "Default password configured"
    fi
}

# Function to validate configuration
validate_configuration() {
    print_header "Configuration Validation"
    
    print_step "Validating environment variables..."
    
    if [[ -z "${PI_NODE_IPS:-}" ]]; then
        print_error "PI_NODE_IPS not configured"
        return 1
    fi
    
    if [[ -z "${NODES_DEFAULT_USER:-}" ]]; then
        print_error "NODES_DEFAULT_USER not configured"
        return 1
    fi
    
    print_step "Testing connectivity to Pi nodes..."
    IFS=',' read -ra ip_array <<< "$PI_NODE_IPS"
    local reachable_nodes=0
    
    for ip in "${ip_array[@]}"; do
        ip=$(echo "$ip" | xargs)
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "  ✅ $ip: Reachable"
            ((reachable_nodes++))
        else
            echo "  ❌ $ip: Not reachable"
        fi
    done
    
    if [[ $reachable_nodes -eq 0 ]]; then
        print_warning "No Pi nodes are currently reachable. Check network connectivity."
        print_warning "Deployment may fail if nodes are not accessible."
    else
        print_step "$reachable_nodes out of ${#ip_array[@]} nodes are reachable"
    fi
}

# Function to show configuration summary
show_summary() {
    print_header "Configuration Summary"
    
    echo "Current environment configuration:"
    echo ""
    echo "Pi Node IPs: ${PI_NODE_IPS:-[Not configured]}"
    echo "Default User: ${NODES_DEFAULT_USER:-[Not configured]}"
    echo "Manager IP: ${MANAGER_IP:-[Auto-detect]}"
    echo "Default Password: ${NODES_DEFAULT_PASS:+[Configured]}"
    echo ""
    echo "These variables have been added to ~/.bashrc for persistence."
    echo ""
    echo -e "${GREEN}To apply configuration to current shell:${NC}"
    echo "source ~/.bashrc"
    echo ""
    echo -e "${GREEN}To start deployment:${NC}"
    echo "./deploy.sh"
}

# Main execution
main() {
    print_header "Pi-Swarm Environment Configuration"
    
    echo "This script will help you configure environment variables for portable Pi-Swarm deployment."
    echo "It will guide you through setting up Pi node IPs, SSH users, and other configuration."
    echo ""
    
    read -p "Continue with configuration? [Y/n]: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Configuration cancelled."
        exit 0
    fi
    
    configure_pi_nodes
    configure_default_user
    configure_optional_settings
    validate_configuration
    show_summary
    
    echo ""
    print_step "Configuration complete! 🎉"
}

# Run main function
main "$@"
