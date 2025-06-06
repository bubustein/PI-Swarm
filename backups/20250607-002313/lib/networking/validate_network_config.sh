validate_network_config() {
    local ip=$1
    local mask=$2
    local gateway=$3
    local dns=${4:-$(default_dns)}
    local interface=${5:-$NETWORK_INTERFACE}
    
    # Validate IP format
    if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log ERROR "Invalid IP format: $ip"
        return 1
    fi
    
    # Validate each octet is in range
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ "$octet" -lt 0 ]] || [[ "$octet" -gt 255 ]]; then
            log ERROR "IP octet out of range (0-255): $octet"
            return 1
        fi
    done
    
    # Validate subnet mask if provided
    if [[ -n "$mask" ]]; then
        if ! [[ $mask =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && ! [[ $mask =~ ^[0-9]{1,2}$ ]]; then
            log ERROR "Invalid subnet mask: $mask"
            return 1
        fi
    fi
    
    # Validate gateway format and reachability
    if [[ -n "$gateway" ]]; then
        if ! [[ $gateway =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            log ERROR "Invalid gateway format: $gateway"
            return 1
        fi
        
        if ! ping -c 1 -W 2 -I "$interface" "$gateway" >/dev/null 2>&1; then
            log WARN "Gateway $gateway is not reachable on interface $interface"
        fi
    fi
    
    # Validate DNS server
    if [[ -n "$dns" ]]; then
        if ! [[ $dns =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            log ERROR "Invalid DNS format: $dns"
            return 1
        fi
        
        if ! ping -c 1 -W 2 "$dns" >/dev/null 2>&1; then
            log WARN "DNS server $dns is not responding"
        fi
        
        if ! nslookup google.com "$dns" >/dev/null 2>&1; then
            log WARN "DNS resolution test failed with server $dns"
        fi
    fi
    
    # Check for IP conflicts
    if arping -D -I "$interface" -c 2 "$ip" >/dev/null 2>&1; then
        log ERROR "IP address $ip is already in use on the network"
        return 1
    fi
    
    return 0
}