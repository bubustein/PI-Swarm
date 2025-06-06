configure_static_ip() {
    local host="$1"
    local new_ip="$2"
    local gateway="$3"
    local dns="$4"

    log INFO "Configuring static IP $new_ip on $host..."
    log DEBUG "Using SSH username: '${NODES_DEFAULT_USER}'"

    # Check for valid username
    if [[ -z "${NODES_DEFAULT_USER}" || ! "${NODES_DEFAULT_USER}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log ERROR "Invalid or empty SSH username: '${NODES_DEFAULT_USER}'"
        return 1
    fi

    # Use the global credentials first
    local user="$NODES_DEFAULT_USER"
    local pass="$NODES_DEFAULT_PASS"

    # Check if the current IP is already set to the desired static IP
    local current_ip
    log DEBUG "Trying SSH: sshpass -p '$pass' ssh -o StrictHostKeyChecking=no $user@$host 'hostname -I'"
    current_ip=$(sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "hostname -I | awk '{print \\$1}'" 2>&1)
    local ssh_status=$?
    if [[ $ssh_status -ne 0 ]]; then
        log WARN "SSH authentication failed for $host. Output: $current_ip"
        read -r -p "Enter SSH username for $host: " user
        read -r -s -p "Enter SSH password for $user: " pass
        echo
        log DEBUG "Retrying SSH: sshpass -p '$pass' ssh -o StrictHostKeyChecking=no $user@$host 'hostname -I'"
        current_ip=$(sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "hostname -I | awk '{print \\$1}'" 2>&1)
        ssh_status=$?
        if [[ $ssh_status -ne 0 ]]; then
            log ERROR "SSH authentication failed again for $host. Output: $current_ip. Skipping."
            return 1
        fi
    fi
    if [[ "$current_ip" == "$new_ip" ]]; then
        log INFO "$host already has IP $new_ip, skipping reconfiguration."
        return 0
    fi

    # Prepare netplan YAML
    local netplan_yaml="network:\n  version: 2\n  renderer: networkd\n  ethernets:\n    eth0:\n      dhcp4: false\n      addresses:\n        - $new_ip/24\n      routes:\n        - to: 0.0.0.0/0\n          via: $gateway\n      nameservers:\n        addresses:\n          - 1.1.1.1\n          - 8.8.8.8"

    # Set hostname based on last octet
    local last_octet
    last_octet=$(echo "$new_ip" | awk -F. '{print $4}')
    local new_hostname="raspberrypi0$last_octet"

    # Apply netplan config and set hostname remotely
    log DEBUG "Applying netplan and hostname via SSH for $host"
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" bash -c "'
        echo \"$netplan_yaml\" | sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null
        sudo hostnamectl set-hostname $new_hostname
        sudo netplan apply
    '"
    if [[ $? -ne 0 ]]; then
        log ERROR "Failed to configure static IP and hostname on $host"
        return 1
    fi
    log INFO "Static IP $new_ip and hostname $new_hostname set on $host."
    sleep 5
    return 0
}
