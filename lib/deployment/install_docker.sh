#!/bin/bash

# Enhanced Docker installation with prerequisite checking and clean installation
install_docker() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local force_clean="${4:-false}"  # Optional parameter to force clean installation
    
    log INFO "Checking Docker prerequisites on $host..."
    
    # Check if Docker is already installed
    local docker_installed=false
    local docker_working=false
    
    if ssh_exec "$host" "$user" "$pass" "command -v docker" >/dev/null 2>&1; then
        docker_installed=true
        log INFO "Docker binary found on $host"
        
        # Test if Docker is actually working
        if ssh_exec "$host" "$user" "$pass" "docker --version" >/dev/null 2>&1; then
            docker_working=true
            log INFO "Docker is responding on $host"
        else
            log WARN "Docker binary exists but not working properly on $host"
        fi
    else
        log INFO "Docker not found on $host"
    fi
    
    # Force clean installation if requested
    if [[ "$force_clean" == "true" ]] && [[ "$docker_installed" == "true" ]]; then
        log INFO "Force clean installation requested - removing existing Docker on $host"
        clean_docker_installation "$host" "$user" "$pass"
        docker_installed=false
        docker_working=false
    fi
    
    # If Docker is installed and working, just verify configuration
    if [[ "$docker_installed" == "true" ]] && [[ "$docker_working" == "true" ]]; then
        log INFO "Docker is already installed and working on $host"
        verify_docker_configuration "$host" "$user" "$pass"
        return $?
    fi
    
    # Clean up broken Docker installation if needed
    if [[ "$docker_installed" == "true" ]] && [[ "$docker_working" == "false" ]]; then
        log INFO "Cleaning up broken Docker installation on $host"
        clean_docker_installation "$host" "$user" "$pass"
    fi
    
    # Fresh Docker installation
    install_fresh_docker "$host" "$user" "$pass"
    
    # Configure Docker after installation
    configure_docker "$host" "$user" "$pass"
    
    # Verify final configuration
    verify_docker_configuration "$host" "$user" "$pass"
}

# Clean up existing Docker installation
clean_docker_installation() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Cleaning existing Docker installation on $host..."
    
    # Stop Docker services
    ssh_exec "$host" "$user" "$pass" "sudo systemctl stop docker docker.socket containerd" 2>/dev/null || true
    
    # Remove Docker packages
    ssh_exec "$host" "$user" "$pass" "sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" 2>/dev/null || true
    
    # Clean up Docker directories and files
    ssh_exec "$host" "$user" "$pass" "
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -rf /etc/docker
        sudo rm -f /etc/systemd/system/docker.service
        sudo rm -f /etc/systemd/system/docker.socket
        sudo rm -f /usr/local/bin/docker-compose
    " 2>/dev/null || true
    
    # Remove user from docker group
    ssh_exec "$host" "$user" "$pass" "sudo deluser $user docker" 2>/dev/null || true
    
    # Reload systemd
    ssh_exec "$host" "$user" "$pass" "sudo systemctl daemon-reload" || true
    
    log INFO "Docker cleanup completed on $host"
}

# Install fresh Docker
install_fresh_docker() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Installing fresh Docker on $host..."
    
    # Update package index
    if ! ssh_exec "$host" "$user" "$pass" "sudo apt-get update -qq"; then
        log ERROR "Failed to update package index on $host"
        return 1
    fi
    
    # Install prerequisites
    local prereq_packages="ca-certificates curl gnupg lsb-release"
    if ! ssh_exec "$host" "$user" "$pass" "sudo apt-get install -y -qq $prereq_packages"; then
        log ERROR "Failed to install Docker prerequisites on $host"
        return 1
    fi
    
    # Download and run Docker installation script
    if ! ssh_exec "$host" "$user" "$pass" "curl -fsSL https://get.docker.com -o get-docker.sh"; then
        log ERROR "Failed to download Docker installation script on $host"
        return 1
    fi
    
    # Run Docker installation script
    log INFO "Running Docker installation script on $host..."
    if ! ssh_exec "$host" "$user" "$pass" "sudo sh get-docker.sh"; then
        log ERROR "Failed to install Docker on $host"
        return 1
    fi
    
    # Clean up installation script
    ssh_exec "$host" "$user" "$pass" "rm -f get-docker.sh" || true
    
    # Configure Docker
    configure_docker "$host" "$user" "$pass"
}

# Configure Docker after installation
configure_docker() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Configuring Docker on $host..."
    
    # Add user to docker group
    if ! ssh_exec "$host" "$user" "$pass" "sudo usermod -aG docker $user"; then
        log ERROR "Failed to add $user to docker group on $host"
        return 1
    fi
    
    # Create Docker daemon configuration
    ssh_exec "$host" "$user" "$pass" "sudo mkdir -p /etc/docker"
    ssh_exec "$host" "$user" "$pass" "sudo tee /etc/docker/daemon.json >/dev/null" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false
}
EOF
    
    # Start and enable Docker services
    if ! ssh_exec "$host" "$user" "$pass" "sudo systemctl start docker && sudo systemctl enable docker"; then
        log ERROR "Failed to start Docker daemon on $host"
        return 1
    fi
    
    # Wait for Docker to be ready
    log INFO "Waiting for Docker to be ready on $host..."
    local max_attempts=10
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh_exec "$host" "$user" "$pass" "sudo docker info" >/dev/null 2>&1; then
            break
        fi
        ((attempt++))
        sleep 2
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log ERROR "Docker failed to start properly on $host"
        return 1
    fi
    
    log INFO "Docker configuration completed on $host"
}

# Verify Docker configuration
verify_docker_configuration() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Verifying Docker configuration on $host..."
    
    # Check Docker version
    if ! ssh_exec "$host" "$user" "$pass" "docker --version"; then
        log ERROR "Docker version check failed on $host"
        return 1
    fi
    
    # Check if user is in docker group
    if ! ssh_exec "$host" "$user" "$pass" "groups | grep -q docker"; then
        log INFO "Adding $user to docker group on $host..."
        if ! ssh_exec "$host" "$user" "$pass" "sudo usermod -aG docker $user"; then
            log ERROR "Failed to add $user to docker group on $host"
            return 1
        fi
        log INFO "User $user added to docker group on $host (logout/login required)"
    fi
    
    # Verify Docker daemon is running
    if ! ssh_exec "$host" "$user" "$pass" "sudo systemctl is-active docker" >/dev/null; then
        log INFO "Starting Docker daemon on $host..."
        if ! ssh_exec "$host" "$user" "$pass" "sudo systemctl start docker && sudo systemctl enable docker"; then
            log ERROR "Failed to start Docker daemon on $host"
            return 1
        fi
    fi
    
    # Test Docker with a simple container (using sudo since user needs to log out/in for group membership)
    log INFO "Testing Docker installation on $host..."
    if ssh_exec "$host" "$user" "$pass" "sudo docker run --rm hello-world" >/dev/null 2>&1; then
        log INFO "✅ Docker test successful on $host"
    else
        log WARN "Docker test container failed on $host, but installation appears successful"
    fi
    
    # Install Docker Compose if not present
    if ! ssh_exec "$host" "$user" "$pass" "docker-compose --version" 2>/dev/null; then
        install_docker_compose "$host" "$user" "$pass"
    fi
    
    log INFO "Docker verification completed on $host"
    return 0
}

# Install Docker Compose
install_docker_compose() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Installing Docker Compose on $host..."
    
    # Get latest Docker Compose version for ARM
    local compose_version="2.24.1"  # Use a known working version
    local compose_url="https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-linux-aarch64"
    
    # Download and install Docker Compose
    if ssh_exec "$host" "$user" "$pass" "sudo curl -L \"$compose_url\" -o /usr/local/bin/docker-compose"; then
        if ssh_exec "$host" "$user" "$pass" "sudo chmod +x /usr/local/bin/docker-compose"; then
            log INFO "Docker Compose installed successfully on $host"
        else
            log WARN "Failed to make Docker Compose executable on $host"
        fi
    else
        log WARN "Failed to download Docker Compose on $host"
    fi
}
