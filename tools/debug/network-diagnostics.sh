#!/bin/bash

# Network Diagnostics for Pi-Swarm
set -euo pipefail

echo "🔍 Pi-Swarm Network Diagnostics"
echo "================================"
echo ""

# Default IPs from the error message
PIES=(192.168.3.201 192.168.3.202 192.168.3.203)

echo "📡 Checking network interface and local IP..."
ip addr show | grep -E "inet.*192\.168\." || echo "No 192.168.x.x IP found"
echo ""

echo "🔍 Scanning for active devices on your network..."
# Get your network subnet
LOCAL_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
SUBNET=$(echo $LOCAL_IP | cut -d. -f1-3)
echo "Local IP: $LOCAL_IP"
echo "Scanning subnet: $SUBNET.0/24"
echo ""

# Quick ping scan
echo "🏓 Quick ping test for Pi IPs..."
for pi in "${PIES[@]}"; do
    echo -n "  $pi: "
    if ping -c 1 -W 1 "$pi" >/dev/null 2>&1; then
        echo "✅ REACHABLE"
    else
        echo "❌ NOT REACHABLE"
    fi
done
echo ""

# Scan for SSH services
echo "🔐 Checking for SSH services..."
for pi in "${PIES[@]}"; do
    echo -n "  $pi:22: "
    if timeout 3 bash -c "echo >/dev/tcp/$pi/22" 2>/dev/null; then
        echo "✅ SSH PORT OPEN"
    else
        echo "❌ SSH PORT CLOSED/FILTERED"
    fi
done
echo ""

# Network discovery
echo "🌐 Discovering active devices (this may take a moment)..."
nmap -sn "$SUBNET.0/24" 2>/dev/null | grep -E "Nmap scan report|MAC Address" | head -20 || echo "nmap not available"
echo ""

# Alternative discovery using arp
echo "📋 ARP table (recently contacted devices):"
arp -a | grep "$SUBNET" || echo "No devices in ARP table for this subnet"
echo ""

echo "💡 Recommendations:"
echo "1. If no Pis are reachable, check if they're powered on"
echo "2. Verify the IP addresses are correct (check your router's DHCP table)"
echo "3. If IPs are wrong, you can edit config/config.yml to update them"
echo "4. Ensure SSH is enabled on your Pis"
echo ""
echo "🔧 To update Pi IPs, edit: config/config.yml"
echo "📝 Then re-run the deployment with: ./deploy.sh"
