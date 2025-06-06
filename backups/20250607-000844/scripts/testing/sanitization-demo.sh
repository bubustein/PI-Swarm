#!/bin/bash
# System Sanitization Demo Script
# Demonstrates system cleaning and sanitization capabilities

set -euo pipefail

echo "🧼 Pi-Swarm System Sanitization & Cleaning"
echo "==========================================="
echo ""

# Get script directory and change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source functions
source lib/source_functions.sh
source_functions

# Source sanitization module
source lib/system/sanitization.sh

echo "This tool will clean and sanitize your Raspberry Pis to optimize them"
echo "for Pi-Swarm deployment."
echo ""

# Show sanitization levels
echo "🧹 Available Sanitization Levels:"
echo "=================================="
echo ""
echo "1. 📦 Minimal (Safe)"
echo "   • Clean package caches"
echo "   • Remove old temporary files"
echo "   • Basic log cleanup (keep 3 days)"
echo "   • Quick and safe for production systems"
echo ""
echo "2. 🔧 Standard (Recommended)"
echo "   • Everything from Minimal"
echo "   • Clean user caches and thumbnails"
echo "   • Docker cleanup (if installed)"
echo "   • Remove orphaned packages"
echo "   • Clear swap and memory caches"
echo ""
echo "3. 🔥 Thorough (Aggressive)"
echo "   • Everything from Standard"
echo "   • Remove old kernels"
echo "   • Deep log cleanup and truncation"
echo "   • Clear all browser and Python caches"
echo "   • Remove crash dumps"
echo ""
echo "4. 💀 Complete (DANGEROUS)"
echo "   • Everything from Thorough"
echo "   • Remove ALL user data (except current user essentials)"
echo "   • Remove ALL logs completely"
echo "   • Nuclear cleanup - USE WITH EXTREME CAUTION"
echo ""

# Get user choice
while true; do
    read -p "Choose sanitization level (1-4): " level_choice
    case $level_choice in
        1) sanitization_level="minimal"; break ;;
        2) sanitization_level="standard"; break ;;
        3) sanitization_level="thorough"; break ;;
        4) 
            echo ""
            echo "⚠️  DANGER: Complete sanitization will remove ALL user data!"
            read -p "Are you absolutely sure? (type 'YES' to confirm): " confirm
            if [[ "$confirm" == "YES" ]]; then
                sanitization_level="complete"
                break
            else
                echo "Complete sanitization cancelled. Please choose a different level."
                continue
            fi
            ;;
        *) echo "❌ Invalid choice. Please enter 1-4."; continue ;;
    esac
done

echo ""
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
echo "✅ Found ${#reachable_pis[@]} reachable Pi(s)."
echo ""

# Final confirmation
echo "📋 Sanitization Summary:"
echo "========================"
echo "   Level: $sanitization_level"
echo "   Target Pis: ${reachable_pis[*]}"
echo "   SSH User: $username"
echo ""

if [[ "$sanitization_level" == "complete" ]]; then
    echo "💀 WARNING: Complete sanitization is DESTRUCTIVE and IRREVERSIBLE!"
    echo "   This will remove ALL user data and logs from the target systems."
    echo ""
fi

read -p "Proceed with sanitization? (y/N): " proceed
if [[ ! "${proceed,,}" =~ ^(y|yes)$ ]]; then
    echo "Sanitization cancelled by user."
    exit 0
fi

echo ""
echo "🧹 Starting System Sanitization..."
echo "=================================="

# Sanitize each Pi
success_count=0
for ip in "${reachable_pis[@]}"; do
    echo ""
    echo "🧼 Sanitizing $ip ($sanitization_level level)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Test SSH connectivity
    if ! ssh_exec "$ip" "$username" "$password" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "❌ SSH failed for $ip. Skipping..."
        continue
    fi
    
    # Generate pre-sanitization report
    echo "📊 Pre-sanitization system status:"
    generate_sanitization_report "$ip" "$username" "$password"
    
    echo ""
    echo "🧹 Running sanitization..."
    
    # Perform sanitization
    if sanitize_system "$ip" "$username" "$password" "$sanitization_level"; then
        echo "✅ Sanitization completed successfully"
        ((success_count++))
        
        echo ""
        echo "📊 Post-sanitization system status:"
        generate_sanitization_report "$ip" "$username" "$password"
    else
        echo "❌ Sanitization failed for $ip"
    fi
    
    echo ""
done

echo ""
echo "🎉 Sanitization Complete!"
echo "========================="
echo ""
echo "📊 Summary:"
echo "   • Successfully sanitized: $success_count/${#reachable_pis[@]} Pi(s)"
echo "   • Sanitization level: $sanitization_level"
echo "   • Systems are now optimized for deployment"
echo ""

if [[ $success_count -gt 0 ]]; then
    echo "🚀 Next Steps:"
    echo "   • Your Pis are now clean and optimized"
    echo "   • Run a deployment script to set up Pi-Swarm"
    echo "   • Use option 1 (Automated Deployment) from main menu"
    echo "   • Or run: ./scripts/deployment/automated-deploy.sh"
    echo ""
    echo "💡 The cleaned systems will provide optimal performance for Docker Swarm."
else
    echo "❌ No systems were successfully sanitized."
    echo "   Please check connectivity and credentials, then try again."
fi
