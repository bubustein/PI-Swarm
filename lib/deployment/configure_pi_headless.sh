#!/bin/bash

# Configure Pi headless setup including hostname, static IP, and basic system settings
configure_pi_headless() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Configuring headless setup for $host..."
    
    # Enable SSH if not already enabled
    if ! ssh_exec "$host" "$user" "$pass" "systemctl is-enabled ssh"; then
        log INFO "Enabling SSH service on $host..."
        if ! ssh_exec "$host" "$user" "$pass" "sudo systemctl enable ssh && sudo systemctl start ssh"; then
            log ERROR "Failed to enable SSH on $host"
            return 1
        fi
    fi
    
    # Update package lists and install essential packages
    log INFO "Updating package lists on $host..."
    if ! ssh_exec "$host" "$user" "$pass" "sudo apt-get update -qq"; then
        log ERROR "Failed to update package lists on $host"
        return 1
    fi
    
    # Install essential packages
    local packages="curl wget git ca-certificates gnupg lsb-release"
    log INFO "Installing essential packages on $host: $packages"
    if ! ssh_exec "$host" "$user" "$pass" "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $packages"; then
        log ERROR "Failed to install essential packages on $host"
        return 1
    fi
    
    # Configure timezone (optional)
    if ! ssh_exec "$host" "$user" "$pass" "sudo timedatectl set-timezone UTC"; then
        log WARN "Failed to set timezone on $host"
    fi
    
    # Enable memory cgroup (required for Docker)
    log INFO "Enabling cgroup memory on $host..."
    if ! ssh_exec "$host" "$user" "$pass" "grep -q 'cgroup_enable=memory' /boot/firmware/cmdline.txt"; then
        if ! ssh_exec "$host" "$user" "$pass" "sudo sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt"; then
            log WARN "Failed to enable cgroup memory on $host (may affect Docker)"
        else
            log INFO "Cgroup memory enabled on $host (reboot required to take effect)"
        fi
    fi
    
    # Create PISworm directory for later use
    log INFO "Creating PISworm directory on $host..."
    if ! ssh_exec "$host" "$user" "$pass" "mkdir -p ~/PISworm"; then
        log ERROR "Failed to create PISworm directory on $host"
        return 1
    fi
    
    # Copy monitoring configuration files
    log INFO "Copying monitoring configuration to $host..."
    
    # Use scp to copy files
    if ! scp_file "$SCRIPT_DIR/docker-compose.monitoring.yml" "~/PISworm/" "$host" "$user" "$pass"; then
        log WARN "Failed to copy docker-compose.monitoring.yml to $host"
    fi
    
    if ! scp_file "$SCRIPT_DIR/prometheus.yml" "~/PISworm/" "$host" "$user" "$pass"; then
        log WARN "Failed to copy prometheus.yml to $host"
    fi
    
    # Create environment file for service passwords
    ssh_exec "$host" "$user" "$pass" "cat > ~/PISworm/.env << 'EOF'
# Service Configuration
PORTAINER_PASSWORD=piswarm123
GRAFANA_PASSWORD=admin
PORTAINER_PORT=9443
PORTAINER_HTTP_PORT=9000
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=15d
EOF"
    
    # Copy grafana directory if it exists
    if [[ -d "$SCRIPT_DIR/grafana" ]]; then
        if ! ssh_exec "$host" "$user" "$pass" "mkdir -p ~/PISworm/grafana"; then
            log WARN "Failed to create grafana directory on $host"
        fi
        # Note: This is a simplified copy - in production you'd want to recursively copy the grafana directory
    fi
    
    log INFO "Headless configuration completed for $host"
    return 0
}

export -f configure_pi_headless
