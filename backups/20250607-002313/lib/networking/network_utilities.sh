# Network utility functions for Pi-Swarm

# Get default gateway
default_gateway() {
    ip route | awk '/default/ {print $3}' | head -n1
}
export -f default_gateway

# Get default DNS server
default_dns() {
    awk '/nameserver/ {print $2; exit}' /etc/resolv.conf
}
export -f default_dns

# Get default network interface
default_iface() {
    ip route | awk '/default/ {print $5}' | head -n1
}
export -f default_iface

# Get network subnet from default route
default_subnet() {
    ip route | awk '/default/ {print $1}' | head -n1
}

# Get current IP address of default interface
current_ip() {
    local iface=$(default_iface)
    ip addr show "$iface" | awk '/inet / {print $2}' | cut -d'/' -f1 | head -n1
}

# Test network connectivity
test_connectivity() {
    local host="${1:-8.8.8.8}"
    ping -c 1 -W 2 "$host" >/dev/null 2>&1
}

# Get network information summary
network_info() {
    echo "Gateway: $(default_gateway)"
    echo "DNS: $(default_dns)"
    echo "Interface: $(default_iface)"
    echo "Current IP: $(current_ip)"
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Check if IP is reachable
ping_host() {
    local ip="$1"
    local timeout="${2:-2}"
    ping -c 1 -W "$timeout" "$ip" >/dev/null 2>&1
}

# Export functions
export -f default_gateway default_dns default_iface default_subnet current_ip
export -f test_connectivity network_info validate_ip ping_host