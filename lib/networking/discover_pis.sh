# discover_pis: Enhanced Pi discovery with network scanning and manual input

# Source the enhanced Pi discovery functionality
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "${SCRIPT_DIR}/lib/networking/pi_discovery.sh" 2>/dev/null || {
    log WARN "Enhanced Pi discovery not available, using basic discovery"
}

discover_pis() {
    # Try Python network discovery first if available
    if [[ -f "$SCRIPT_DIR/lib/python/network_discovery.py" ]] && command -v python3 >/dev/null 2>&1; then
        log INFO "🐍 Using Python network discovery for enhanced Pi detection..."
        
        local offline_flag=""
        if [[ "${OFFLINE_MODE:-false}" == "true" || "${SKIP_NETWORK_CHECK:-false}" == "true" ]]; then
            offline_flag="--offline"
        fi
        
        # Run Python discovery and capture output
        local discovery_output
        if discovery_output=$(python3 "$SCRIPT_DIR/lib/python/network_discovery.py" discover --format bash $offline_flag 2>/dev/null); then
            # Parse Python discovery output
            eval "$discovery_output"
            
            if [[ -n "${PI_IPS:-}" ]] && [[ "${PI_COUNT:-0}" -gt 0 ]]; then
                log INFO "Python discovery found $PI_COUNT Pi device(s): $PI_IPS"
                export PI_IPS
                export PI_HOSTNAMES
                export PI_COUNT
                return 0
            else
                log WARN "Python discovery found no Pi devices, falling back to enhanced discovery"
            fi
        else
            log WARN "Python discovery failed, falling back to enhanced discovery"
        fi
    fi
    
    # Try enhanced discovery next, fall back to basic if not available
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
