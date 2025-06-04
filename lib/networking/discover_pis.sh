# discover_pis: Enhanced Pi discovery with network scanning and manual input

# Source the enhanced Pi discovery functionality
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "${SCRIPT_DIR}/lib/networking/pi_discovery.sh" 2>/dev/null || {
    log WARN "Enhanced Pi discovery not available, using basic discovery"
}

discover_pis() {
    # Try enhanced discovery first, fall back to basic if not available
    if command -v discover_and_scan_pis >/dev/null 2>&1; then
        log INFO "🔍 Starting enhanced Pi discovery with network scanning..."
        discover_and_scan_pis
    else
        log INFO "🔍 Using manual Pi discovery mode..."
        echo "Please provide the IP addresses of your Raspberry Pi devices."
        read -rp "Enter comma-separated IP addresses (e.g., 192.168.1.10,192.168.1.11): " ip_list
        IFS=',' read -ra IPS <<< "$ip_list"
        echo -e "\nTesting connectivity to ${#IPS[@]} IP addresses..."
        
        local reachable_count=0
        local unreachable_ips=()
        
        for ip in "${IPS[@]}"; do
            ip_trimmed=$(echo "$ip" | xargs)
            if ping -c 1 -W 1 "$ip_trimmed" >/dev/null 2>&1; then
                echo "Testing $ip_trimmed... ✅ Reachable"
                ((reachable_count++))
            else
                echo "Testing $ip_trimmed... ❌ Not reachable"
                unreachable_ips+=("$ip_trimmed")
            fi
        done
        
        # Warn about unreachable Pis but don't fail
        if [[ ${#unreachable_ips[@]} -gt 0 ]]; then
            log WARN "Some Pis are not reachable: ${unreachable_ips[*]}"
            log WARN "Deployment will continue but may fail for unreachable devices"
            echo "💡 Tip: Ensure Pis are powered on and connected to the network"
        fi
        
        if [[ $reachable_count -eq 0 ]]; then
            log ERROR "No Pis are reachable. Please check network connectivity and try again."
            return 1
        fi
        
        log INFO "Found $reachable_count reachable Pi(s) out of ${#IPS[@]} total"
        
        # Export the list for use by the main script (space-separated)
        export PI_IPS="${IPS[*]}"
    fi
}
