#!/bin/bash

# Configure Pi headless setup including hostname, static IP, and basic system settings
configure_pi_headless() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    # Use PROJECT_ROOT if available, otherwise derive from SCRIPT_DIR
    local project_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    
    log INFO "Configuring headless setup for $host..."
    
    # Enable SSH if not already enabled
    ssh_status=$(ssh_exec "$host" "$user" "$pass" "systemctl is-enabled ssh" 2>&1 || true)
    if [[ "$ssh_status" == *"enabled"* ]]; then
        log INFO "SSH is already enabled on $host."
    else
        log INFO "Enabling SSH service on $host..."
        if ! ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S systemctl enable ssh && echo '$pass' | sudo -S systemctl start ssh"; then
            log WARN "Failed to enable SSH on $host (continuing with configuration)"
        fi
    fi

    # Check Docker before proceeding
    if ! ssh_exec "$host" "$user" "$pass" "docker --version"; then
        log INFO "Docker not found on $host. Installing Docker automatically..."
        
        # Download and install Docker using get.docker.com script with non-interactive sudo
        docker_install_output=$(ssh_exec "$host" "$user" "$pass" "curl -fsSL https://get.docker.com -o get-docker.sh && echo '$pass' | sudo -S sh get-docker.sh && rm get-docker.sh" 2>&1)
        install_exit_code=$?
        
        if [[ $install_exit_code -ne 0 ]]; then
            log ERROR "Failed to install Docker on $host. Exit code: $install_exit_code. Output:\n$docker_install_output"
            return 1
        fi
        
        # Verify Docker installation
        if ! ssh_exec "$host" "$user" "$pass" "docker --version"; then
            log ERROR "Docker installation completed but docker command not available on $host. Output:\n$docker_install_output"
            return 1
        fi
        
        log INFO "Docker installed successfully on $host"
        
        # Add user to docker group (non-fatal if it fails)
        log INFO "Adding $user to docker group on $host..."
        
        # First ensure docker group exists
        group_create_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S groupadd -f docker" 2>&1)
        if [[ $? -ne 0 ]]; then
            log WARN "Failed to ensure docker group exists on $host. Output:\n$group_create_output"
        fi
        
        # Check if user is already in docker group
        group_check=$(ssh_exec "$host" "$user" "$pass" "groups $user" 2>&1)
        if [[ "$group_check" == *"docker"* ]]; then
            log INFO "$user is already in docker group on $host"
        else
            # Add user to docker group
            addgroup_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S usermod -aG docker $user" 2>&1)
            addgroup_exit_code=$?
            
            if [[ $addgroup_exit_code -ne 0 ]]; then
                log WARN "Failed to add $user to docker group on $host. Output:\n$addgroup_output"
                log WARN "Docker commands may require sudo. This is not critical for deployment."
                # Don't return 1 here - just warn and continue
            else
                log INFO "Added $user to docker group on $host (logout/login required for group changes to take effect)"
                
                # Verify the addition worked
                verify_group=$(ssh_exec "$host" "$user" "$pass" "groups $user" 2>&1)
                if [[ "$verify_group" == *"docker"* ]]; then
                    log INFO "Docker group addition verified on $host"
                else
                    log WARN "Docker group addition verification failed on $host"
                fi
            fi
        fi
        
        # Enable Docker to start on boot
        enable_docker_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S systemctl enable docker" 2>&1)
        if [[ $? -ne 0 ]]; then
            log WARN "Failed to enable Docker service on $host. Output:\n$enable_docker_output"
        else
            log INFO "Enabled Docker service on $host"
        fi
        
        # Install Docker Compose V2 (plugin-based approach)
        log INFO "Installing Docker Compose V2 on $host..."
        
        # Check if Docker Compose plugin already exists
        compose_check=$(ssh_exec "$host" "$user" "$pass" "docker compose version" 2>&1 || true)
        if [[ "$compose_check" == *"version"* ]]; then
            log INFO "Docker Compose V2 already installed on $host"
        else
            # Install Docker Compose V2 plugin
            compose_install_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S apt-get update && echo '$pass' | sudo -S apt-get install -y docker-compose-plugin" 2>&1)
            compose_exit_code=$?
            
            if [[ $compose_exit_code -ne 0 ]]; then
                log WARN "Failed to install Docker Compose plugin via apt on $host. Trying manual installation... Output:\n$compose_install_output"
                
                # Fallback: manual installation of Docker Compose V2
                manual_install_output=$(ssh_exec "$host" "$user" "$pass" "
                    COMPOSE_VERSION=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'\"' -f4) &&
                    echo '$pass' | sudo -S curl -L \"https://github.com/docker/compose/releases/download/\${COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose &&
                    echo '$pass' | sudo -S chmod +x /usr/local/bin/docker-compose &&
                    echo '$pass' | sudo -S ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
                " 2>&1)
                
                if [[ $? -ne 0 ]]; then
                    log ERROR "Failed to install Docker Compose manually on $host. Output:\n$manual_install_output"
                    return 1
                fi
                log INFO "Docker Compose installed manually on $host"
            else
                log INFO "Docker Compose plugin installed successfully on $host"
            fi
        fi
        
        # Test installations
        docker_test_output=$(ssh_exec "$host" "$user" "$pass" "docker version" 2>&1)
        log INFO "Docker version on $host:\n$docker_test_output"
        
        # Test Docker Compose - try both V2 (compose) and V1 (docker-compose) commands
        compose_test_output=$(ssh_exec "$host" "$user" "$pass" "docker compose version || docker-compose --version" 2>&1)
        log INFO "Docker Compose version on $host:\n$compose_test_output"
        
        log INFO "Docker and Docker Compose installed successfully on $host"
    else
        log INFO "Docker is already installed on $host"
    fi

    # Ensure Docker service is running
    docker_status=$(ssh_exec "$host" "$user" "$pass" "systemctl is-active docker" 2>&1 || true)
    if [[ "$docker_status" != "active" ]]; then
        log INFO "Starting Docker service on $host..."
        if ! ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S systemctl start docker"; then
            log WARN "Failed to start Docker service on $host. Swarm/services may fail."
        else
            log INFO "Docker service started on $host."
        fi
    else
        log INFO "Docker service is already running on $host."
    fi
    
    # Update package lists and install essential packages
    log INFO "Updating package lists on $host..."
    update_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S apt-get update -qq" 2>&1)
    if [[ $? -ne 0 ]]; then
        log ERROR "Failed to update package lists on $host. Output:\n$update_output"
        return 1
    fi
    
    # Install essential packages
    local packages="curl wget git ca-certificates gnupg lsb-release"
    log INFO "Installing essential packages on $host: $packages"
    install_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $packages" 2>&1)
    if [[ $? -ne 0 ]]; then
        log ERROR "Failed to install essential packages on $host. Output:\n$install_output"
        return 1
    fi
    log INFO "Essential packages installed successfully on $host"
    
    # Configure timezone (optional)
    timezone_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S timedatectl set-timezone UTC" 2>&1)
    if [[ $? -ne 0 ]]; then
        log WARN "Failed to set timezone on $host. Output:\n$timezone_output"
    else
        log INFO "Timezone set to UTC on $host"
    fi
    
    # Enable memory cgroup (required for Docker)
    log INFO "Enabling cgroup memory on $host..."
    cgroup_check=$(ssh_exec "$host" "$user" "$pass" "grep -q 'cgroup_enable=memory' /boot/firmware/cmdline.txt && echo 'found' || echo 'not found'" 2>&1)
    if [[ "$cgroup_check" == *"not found"* ]]; then
        cgroup_output=$(ssh_exec "$host" "$user" "$pass" "echo '$pass' | sudo -S sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt" 2>&1)
        if [[ $? -ne 0 ]]; then
            log WARN "Failed to enable cgroup memory on $host (may affect Docker). Output:\n$cgroup_output"
        else
            log INFO "Cgroup memory enabled on $host (reboot required to take effect)"
        fi
    else
        log INFO "Cgroup memory already enabled on $host"
    fi
    
    # Create piswarm directory for later use
    log INFO "Creating piswarm directory on $host..."
    if ! ssh_exec "$host" "$user" "$pass" "mkdir -p ~/piswarm"; then
        log ERROR "Failed to create piswarm directory on $host"
        return 1
    fi
    
    # Copy monitoring configuration files
    log INFO "Copying monitoring configuration to $host..."
    
    # Use scp to copy files - fix paths to use config directory
    if ! scp_file "$project_root/config/docker-compose.monitoring.yml" "~/piswarm/" "$host" "$user" "$pass"; then
        log WARN "Failed to copy docker-compose.monitoring.yml to $host"
    fi
    
    if ! scp_file "$project_root/config/prometheus.yml" "~/piswarm/" "$host" "$user" "$pass"; then
        log WARN "Failed to copy prometheus.yml to $host"
    fi
    
    if ! scp_file "$project_root/config/prometheus-alerts.yml" "~/piswarm/" "$host" "$user" "$pass"; then
        log WARN "Failed to copy prometheus-alerts.yml to $host"
    fi
    
    # Create environment file for service passwords
    ssh_exec "$host" "$user" "$pass" "cat > ~/piswarm/.env << 'EOF'
# Service Configuration
PORTAINER_PASSWORD=\${PORTAINER_PASSWORD:-admin}
GRAFANA_PASSWORD=admin
PORTAINER_PORT=9443
PORTAINER_HTTP_PORT=9000
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=15d
EOF"
    
    # Copy grafana templates directory if it exists
    if [[ -d "$project_root/templates/grafana" ]]; then
        if ! ssh_exec "$host" "$user" "$pass" "mkdir -p ~/piswarm/grafana"; then
            log WARN "Failed to create grafana directory on $host"
        else
            # Recursively copy all files and subdirectories in grafana templates
            find "$project_root/templates/grafana" -type f | while read -r file; do
                rel_path="${file#$project_root/templates/grafana/}"
                remote_dir="~/piswarm/grafana/$(dirname "$rel_path")"
                ssh_exec "$host" "$user" "$pass" "mkdir -p $remote_dir"
                scp_file "$file" "$remote_dir/" "$host" "$user" "$pass"
            done
            log INFO "Grafana templates copied to $host"
        fi
    else
        log WARN "Grafana templates directory not found at $project_root/templates/grafana"
    fi
    
    log INFO "Headless configuration completed for $host"
    return 0
}

export -f configure_pi_headless
