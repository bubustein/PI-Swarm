#!/bin/bash

# Comprehensive troubleshooting script for Pi-Swarm deployment issues
set -euo pipefail

echo "🔧 Pi-Swarm Deployment Troubleshooting"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "OK") echo -e "${GREEN}✅ $message${NC}" ;;
        "WARN") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

# Get basic info
echo "1. 📋 System Information"
echo "========================"
echo "Date: $(date)"
echo "User: $USER"
echo "PWD: $PWD"
echo "Shell: $SHELL"
echo ""

# Check if we're in the right directory
if [[ ! -f "core/swarm-cluster.sh" ]]; then
    print_status "ERROR" "Not in Pi-Swarm directory. Please cd to Pi-Swarm directory first."
    exit 1
fi
print_status "OK" "In Pi-Swarm directory"

# Check basic dependencies
echo "2. 🔧 Dependency Check"
echo "======================"
dependencies=("ssh" "sshpass" "curl" "docker" "grep" "awk" "sed")
missing_deps=()

for dep in "${dependencies[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        print_status "OK" "$dep is installed"
    else
        print_status "ERROR" "$dep is missing"
        missing_deps+=("$dep")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo ""
    print_status "WARN" "Missing dependencies: ${missing_deps[*]}"
    echo "Install with: sudo apt-get install ${missing_deps[*]}"
fi

# Check SSH configuration
echo ""
echo "3. 🔑 SSH Configuration"
echo "======================="

if [[ -f ~/.ssh/id_rsa ]]; then
    print_status "OK" "SSH private key exists"
else
    print_status "WARN" "No SSH private key found. You may need password authentication."
fi

if [[ -f ~/.ssh/id_rsa.pub ]]; then
    print_status "OK" "SSH public key exists"
else
    print_status "WARN" "No SSH public key found."
fi

# Test environment variables
echo ""
echo "4. 🌍 Environment Variables"
echo "==========================="

echo "Current environment variables:"
echo "USER: $USER"
echo "USERNAME: ${USERNAME:-not set}"
echo "SSH_USER: ${SSH_USER:-not set}"
echo "SSH_PASSWORD: ${SSH_PASSWORD:-not set (hidden)}"
echo "PI_USER: ${PI_USER:-not set}"
echo "PI_PASS: ${PI_PASS:-not set (hidden)}"
echo "NODES_DEFAULT_USER: ${NODES_DEFAULT_USER:-not set}"
echo "NODES_DEFAULT_PASS: ${NODES_DEFAULT_PASS:-not set (hidden)}"
echo "PORTAINER_PASSWORD: ${PORTAINER_PASSWORD:-not set (hidden)}"

# Test variable resolution
test_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
echo ""
echo "Resolved SSH username: $test_user"

if [[ "$test_user" == "luser" ]]; then
    print_status "ERROR" "Username resolution is using local system user 'luser' instead of Pi username"
    echo "Set USERNAME environment variable: export USERNAME=pi"
elif [[ "$test_user" == "pi" ]]; then
    print_status "OK" "Username resolution using 'pi' (default for Raspberry Pi OS)"
elif [[ "$test_user" == "ubuntu" ]]; then
    print_status "OK" "Username resolution using 'ubuntu' (default for Ubuntu)"
else
    print_status "INFO" "Username resolution using '$test_user'"
fi

# Test password validation function
echo ""
echo "5. 🔒 Password Validation Test"
echo "=============================="

validate_portainer_password() {
    local test_password="$1"
    if [[ -n "$test_password" && ${#test_password} -ge 8 ]]; then
        return 0
    else
        return 1
    fi
}

test_passwords=("short" "password123" "pi" "raspberry")
for pwd in "${test_passwords[@]}"; do
    if validate_portainer_password "$pwd"; then
        print_status "OK" "Password '$pwd' is valid (≥8 chars)"
    else
        print_status "WARN" "Password '$pwd' is too short (<8 chars)"
    fi
done

# Network connectivity test
echo ""
echo "6. 🌐 Network Connectivity"
echo "=========================="

if ping -c1 8.8.8.8 >/dev/null 2>&1; then
    print_status "OK" "Internet connectivity (DNS: 8.8.8.8)"
else
    print_status "ERROR" "No internet connectivity"
fi

if ping -c1 1.1.1.1 >/dev/null 2>&1; then
    print_status "OK" "Internet connectivity (DNS: 1.1.1.1)"
else
    print_status "ERROR" "No internet connectivity"
fi

# Pi discovery test
echo ""
echo "7. 🔍 Pi Discovery"
echo "=================="

local_ip=$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)
network_base=$(echo "$local_ip" | cut -d'.' -f1-3)

print_status "INFO" "Local IP: $local_ip"
print_status "INFO" "Scanning network: ${network_base}.0/24"

# Quick Pi discovery
pi_ips=()
for i in {1..254}; do
    ip="${network_base}.$i"
    if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
        if nc -z -w1 "$ip" 22 2>/dev/null; then
            pi_ips+=("$ip")
            print_status "OK" "Found Pi candidate: $ip (SSH port open)"
        fi
    fi
done

if [[ ${#pi_ips[@]} -eq 0 ]]; then
    print_status "WARN" "No Pi devices found on network"
else
    print_status "OK" "Found ${#pi_ips[@]} Pi candidate(s): ${pi_ips[*]}"
fi

# Manual SSH test suggestions
echo ""
echo "8. 🧪 Manual Testing Suggestions"
echo "==============================="

if [[ ${#pi_ips[@]} -gt 0 ]]; then
    test_ip="${pi_ips[0]}"
    echo "Test SSH manually with these commands:"
    echo ""
    echo "# Test with pi user (default for Raspberry Pi OS):"
    echo "ssh pi@$test_ip"
    echo ""
    echo "# Test with ubuntu user (default for Ubuntu):"
    echo "ssh ubuntu@$test_ip"
    echo ""
    echo "# If successful, set environment variables:"
    echo "export USERNAME=pi  # or ubuntu"
    echo "export SSH_PASSWORD='your_password'"
    echo ""
fi

echo "# Run deployment:"
echo "./deploy.sh"
echo ""
echo "# Or run automated deployment:"
echo "export SSH_PASSWORD='your_password'"
echo "./automated-deploy.sh"

echo ""
echo "9. 📝 Log Files"
echo "==============="

if [[ -d "data/logs" ]]; then
    latest_log=$(ls -t data/logs/*.log 2>/dev/null | head -1 || echo "")
    if [[ -n "$latest_log" ]]; then
        print_status "INFO" "Latest log file: $latest_log"
        echo "Check recent errors with: tail -50 '$latest_log'"
    else
        print_status "WARN" "No log files found"
    fi
else
    print_status "WARN" "No logs directory found"
fi

echo ""
echo "🔧 Troubleshooting Complete!"
echo "=============================="
echo ""
print_status "INFO" "Next steps based on findings above:"
echo "1. Fix any missing dependencies"
echo "2. Set correct USERNAME and SSH_PASSWORD environment variables"
echo "3. Test manual SSH connection to verify credentials"
echo "4. Run deployment script"
echo ""
print_status "INFO" "If issues persist, check the log files and GitHub issues"
