# discover_pis: Prompt user for Pi IPs and validate reachability

discover_pis() {
    log INFO "Manual Pi Discovery Mode"
    echo "Please provide the IP addresses of your Raspberry Pi devices."
    read -rp "Enter comma-separated IP addresses (e.g., 192.168.1.10,192.168.1.11): " ip_list
    IFS=',' read -ra IPS <<< "$ip_list"
    echo "\nTesting connectivity to ${#IPS[@]} IP addresses..."
    
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
}
