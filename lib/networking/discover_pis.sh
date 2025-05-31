# discover_pis: Prompt user for Pi IPs and validate reachability

discover_pis() {
    log INFO "Manual Pi Discovery Mode"
    echo "Please provide the IP addresses of your Raspberry Pi devices."
    read -rp "Enter comma-separated IP addresses (e.g., 192.168.1.10,192.168.1.11): " ip_list
    IFS=',' read -ra IPS <<< "$ip_list"
    echo "\nTesting connectivity to ${#IPS[@]} IP addresses..."
    for ip in "${IPS[@]}"; do
        ip_trimmed=$(echo "$ip" | xargs)
        if ping -c 1 -W 1 "$ip_trimmed" >/dev/null 2>&1; then
            echo "Testing $ip_trimmed... ✅ Reachable"
        else
            echo "Testing $ip_trimmed... ❌ Not reachable"
        fi
    done
    # Export the list for use by the main script (space-separated)
    export PI_IPS="${IPS[*]}"
}
