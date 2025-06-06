assign_pi_network_conf() {
    PI_STATIC_IPS=()
    local base_subnet="192.168.3"
    local start_ip=191

    PI_GATEWAY="${NETWORK_GATEWAY:-$(default_gateway)}"
    PI_DNS="${NETWORK_DNS:-$(default_dns)}"

    log INFO "Assigning static IPs starting at $base_subnet.$start_ip..."

    for idx in "${!PI_IPS[@]}"; do
        local old_ip="${PI_IPS[$idx]}"
        local new_ip="$base_subnet.$((start_ip+idx))"

        # Only configure if not already set (handled in configure_static_ip)
        if configure_static_ip "$old_ip" "$new_ip" "$PI_GATEWAY" "$PI_DNS"; then
            # Get the actual IP after configuration
            local actual_ip
            actual_ip=$(sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$old_ip" "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$new_ip")
            PI_STATIC_IPS+=("$actual_ip")
            log INFO "Successfully set $old_ip -> $actual_ip"
        else
            log ERROR "Failed to configure $old_ip"
        fi
    done
}
