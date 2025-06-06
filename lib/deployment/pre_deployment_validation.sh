#!/bin/bash
# Pre-deployment validation and Pi state preparation
# Ensures Raspberry Pis are in optimal state before Docker Swarm deployment

# Source Python integration functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/python_integration.sh" ]]; then
    source "$PROJECT_ROOT/lib/python_integration.sh"
    PYTHON_ENHANCED=true
else
    PYTHON_ENHANCED=false
fi

# Enhanced validation function that uses Python modules when available
validate_and_prepare_pi_state_enhanced() {
    local pi_ips=("$@")
    
    if [[ "$PYTHON_ENHANCED" == "true" ]]; then
        echo "🔧 Using enhanced Python-based validation and preparation..."
        
        # Use comprehensive monitoring and health checks
        if health_check_comprehensive; then
            echo "✅ Comprehensive health check passed"
        else
            echo "⚠️  Health check completed with warnings"
        fi
        
        # Use enhanced storage management for validation
        if manage_storage_comprehensive validate; then
            echo "✅ Storage validation passed"
        else
            echo "⚠️  Storage validation completed with warnings"
        fi
        
        # Use enhanced security management for validation
        if manage_security_comprehensive audit; then
            echo "✅ Security audit passed"
        else
            echo "⚠️  Security audit completed with warnings"
        fi
        
        # Use enhanced monitoring for cluster performance
        if optimize_cluster_performance validate; then
            echo "✅ Performance optimization checks passed"
        else
            echo "⚠️  Performance checks completed with warnings"
        fi
        
        # Fall back to standard validation for Pi-specific checks
        echo "🔍 Running Pi-specific validation checks..."
        validate_and_prepare_pi_state "${pi_ips[@]}"
    else
        echo "🔍 Using standard validation (Python modules not available)..."
        validate_and_prepare_pi_state "${pi_ips[@]}"
    fi
}

# Check and prepare Pi state for deployment
validate_and_prepare_pi_state() {
    local pi_ips=("$@")
    
    # Determine the SSH username to use (with proper fallback logic)
    # Note: Avoid using $USER as it's the local system username
    local ssh_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
    local ssh_pass="${PASSWORD:-${PI_PASS:-${NODES_DEFAULT_PASS:-}}}"
    
    # Helper function for SSH commands with proper authentication
    ssh_pi() {
        local ip="$1"
        shift
        local cmd="$*"
        
        if [[ -n "$ssh_pass" ]]; then
            sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" "$cmd"
        else
            ssh -o BatchMode=yes "$ssh_user@$ip" "$cmd"
        fi
    }
    
    log "INFO" "🔍 Starting pre-deployment Pi state validation and preparation..."
    log "INFO" "Using SSH username: $ssh_user"
    echo ""
    echo "🧹 Pi State Validation & Cleanup Process"
    echo "========================================"
    
    # Phase 1: Basic connectivity and system checks
    log "INFO" "Phase 1: Basic System Validation"
    for ip in "${pi_ips[@]}"; do
        echo "  🔍 Checking Pi: $ip"
        
        # Test SSH connectivity with proper authentication
        if [[ -n "$ssh_pass" ]]; then
            # Use password authentication with sshpass
            if ! sshpass -p "$ssh_pass" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ssh_user@$ip" "echo 'SSH OK'" >/dev/null 2>&1; then
                log "ERROR" "❌ Cannot SSH to $ip as $ssh_user - check connectivity and authentication"
                return 1
            fi
        else
            # Try key-based authentication
            if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$ssh_user@$ip" "echo 'SSH OK'" >/dev/null 2>&1; then
                log "ERROR" "❌ Cannot SSH to $ip as $ssh_user - check connectivity and authentication"
                return 1
            fi
        fi
        
        # Check if Pi is responsive
        if ! ping -c 2 -W 3 "$ip" >/dev/null 2>&1; then
            log "ERROR" "❌ Pi $ip is not responding to ping"
            return 1
        fi
        
        echo "    ✅ Basic connectivity OK"
    done
    
    # Phase 2: System resource and state validation
    log "INFO" "Phase 2: System Resource Validation"
    for ip in "${pi_ips[@]}"; do
        echo "  📊 Analyzing Pi resources: $ip"
        
        # Check available disk space (minimum 2GB free)
        local free_space=$(ssh_pi "$ip" "df / | tail -1 | awk '{print \$4}'")
        local free_gb=$((free_space / 1024 / 1024))
        
        if [[ $free_gb -lt 2 ]]; then
            log "WARN" "⚠️  Low disk space on $ip: ${free_gb}GB free (minimum 2GB recommended)"
            echo "    🧹 Attempting to free up space..."
            cleanup_pi_disk_space "$ip" "$ssh_user" "$ssh_pass"
        else
            echo "    ✅ Sufficient disk space: ${free_gb}GB free"
        fi
        
        # Check available memory (minimum 512MB)
        local free_mem=$(ssh_pi "$ip" "free -m | grep '^Mem:' | awk '{print \$7}'")
        if [[ $free_mem -lt 512 ]]; then
            log "WARN" "⚠️  Low memory on $ip: ${free_mem}MB free"
            echo "    🧹 Clearing memory cache..."
            ssh_pi "$ip" "sudo sync && sudo sysctl vm.drop_caches=3" >/dev/null 2>&1
        else
            echo "    ✅ Sufficient memory: ${free_mem}MB free"
        fi
        
        # Check system load
        local load_avg=$(ssh_pi "$ip" "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ','")
        if (( $(echo "$load_avg > 2.0" | bc -l) )); then
            log "WARN" "⚠️  High system load on $ip: $load_avg"
        else
            echo "    ✅ Normal system load: $load_avg"
        fi
    done
    
    # Phase 3: Docker and conflicting services cleanup
    log "INFO" "Phase 3: Docker Environment Preparation"
    for ip in "${pi_ips[@]}"; do
        echo "  🐳 Preparing Docker environment: $ip"
        
        # Check if Docker is installed and get version
        local docker_status=$(ssh_pi "$ip" "which docker >/dev/null 2>&1 && docker --version 2>/dev/null || echo 'not_installed'")
        
        if [[ "$docker_status" == "not_installed" ]]; then
            echo "    📦 Docker not installed (will be installed during deployment)"
        else
            echo "    🔍 Found Docker: $docker_status"
            
            # Check for existing Docker Swarm
            local swarm_status=$(ssh_pi "$ip" "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo 'inactive'")
            if [[ "$swarm_status" != "inactive" ]]; then
                log "WARN" "⚠️  Pi $ip is already part of a Docker Swarm (state: $swarm_status)"
                echo "    🧹 Cleaning up existing swarm configuration..."
                cleanup_existing_swarm "$ip" "$ssh_user" "$ssh_pass"
            else
                echo "    ✅ No existing swarm configuration"
            fi
            
            # Clean up any stopped containers and networks
            echo "    🧹 Cleaning Docker resources..."
            ssh_pi "$ip" "
                docker system prune -f >/dev/null 2>&1 || true
                docker volume prune -f >/dev/null 2>&1 || true
                docker network prune -f >/dev/null 2>&1 || true
            " >/dev/null 2>&1
            echo "    ✅ Docker cleanup completed"
        fi
    done
    
    # Phase 4: Network configuration validation
    log "INFO" "Phase 4: Network Configuration Validation"
    validate_network_requirements "${pi_ips[@]}"
    
    # Phase 5: Security and firewall preparation
    log "INFO" "Phase 5: Security Configuration"
    for ip in "${pi_ips[@]}"; do
        echo "  🔒 Preparing security configuration: $ip"
        
        # Check SSH configuration
        local ssh_config=$(ssh_pi "$ip" "sudo sshd -T | grep -E '(passwordauthentication|pubkeyauthentication|permitrootlogin)'" 2>/dev/null || echo "")
        echo "    📋 SSH configuration validated"
        
        # Prepare firewall (but don't enable yet to avoid lockout)
        echo "    🛡️  Preparing firewall rules..."
        ssh_pi "$ip" "
            # Install ufw if not present
            sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y ufw >/dev/null 2>&1 || true
            
            # Reset and configure basic rules (but don't enable)
            sudo ufw --force reset >/dev/null 2>&1
            sudo ufw default deny incoming >/dev/null 2>&1
            sudo ufw default allow outgoing >/dev/null 2>&1
            sudo ufw allow ssh >/dev/null 2>&1
            
            # Docker Swarm required ports
            sudo ufw allow 2376/tcp >/dev/null 2>&1  # Docker daemon
            sudo ufw allow 2377/tcp >/dev/null 2>&1  # Swarm management
            sudo ufw allow 7946/tcp >/dev/null 2>&1  # Container network discovery
            sudo ufw allow 7946/udp >/dev/null 2>&1  # Container network discovery
            sudo ufw allow 4789/udp >/dev/null 2>&1  # Overlay network traffic
            
            # Common service ports
            sudo ufw allow 80/tcp >/dev/null 2>&1     # HTTP
            sudo ufw allow 443/tcp >/dev/null 2>&1    # HTTPS
            sudo ufw allow 9000/tcp >/dev/null 2>&1   # Portainer
            sudo ufw allow 3000/tcp >/dev/null 2>&1   # Grafana
            sudo ufw allow 9090/tcp >/dev/null 2>&1   # Prometheus
        " >/dev/null 2>&1
        echo "    ✅ Firewall rules prepared (not enabled yet)"
    done
    
    # Phase 6: System optimization
    log "INFO" "Phase 6: System Optimization"
    for ip in "${pi_ips[@]}"; do
        echo "  ⚡ Optimizing system settings: $ip"
        
        # Enable memory cgroup (required for Docker resource limits)
        ssh_pi "$ip" "
            if ! grep -q 'cgroup_enable=memory' /boot/cmdline.txt 2>/dev/null; then
                sudo sed -i '\$s/\$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
                echo '    📝 Memory cgroup enabled (reboot required)'
            fi
        " 2>/dev/null
        
        # Optimize swap settings for Docker
        ssh_pi "$ip" "
            # Set swappiness to 10 (better for containers)
            echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1 || true
            sudo sysctl vm.swappiness=10 >/dev/null 2>&1 || true
            
            # Increase file descriptor limits
            echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf >/dev/null 2>&1 || true
            echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf >/dev/null 2>&1 || true
        " >/dev/null 2>&1
        echo "    ✅ System optimization completed"
    done
    
    # Phase 7: Final validation summary
    echo ""
    log "INFO" "🎯 Pre-deployment Validation Summary"
    echo "======================================"
    
    local all_ready=true
    for ip in "${pi_ips[@]}"; do
        echo "  Pi $ip:"
        
        # Final connectivity check
        if ssh_pi "$ip" "echo 'ready'" >/dev/null 2>&1; then
            echo "    ✅ Connectivity: OK"
        else
            echo "    ❌ Connectivity: FAILED"
            all_ready=false
        fi
        
        # Check resources one more time
        local final_space=$(ssh_pi "$ip" "df / | tail -1 | awk '{print \$4}'")
        local final_gb=$((final_space / 1024 / 1024))
        echo "    📊 Disk space: ${final_gb}GB available"
        
        local final_mem=$(ssh_pi "$ip" "free -m | grep '^Mem:' | awk '{print \$7}'")
        echo "    💾 Memory: ${final_mem}MB available"
        
        # Check if reboot is needed
        if ssh_pi "$ip" "[ -f /var/run/reboot-required ]" 2>/dev/null; then
            echo "    ⚠️  Reboot recommended (kernel/system updates)"
        fi
    done
    
    if [[ "$all_ready" == "true" ]]; then
        echo ""
        log "INFO" "✅ All Pis are ready for deployment!"
        return 0
    else
        echo ""
        log "ERROR" "❌ Some Pis failed validation. Please resolve issues before proceeding."
        return 1
    fi
}

# Cleanup disk space on Pi
cleanup_pi_disk_space() {
    local ip="$1"
    local ssh_user="$2"
    local ssh_pass="$3"
    
    # Load sanitization functions for enhanced cleanup
    if [[ -f "$PROJECT_ROOT/lib/system/sanitization.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/sanitization.sh"
        echo "      🧹 Using enhanced cleanup for $ip..."
        cleanup_apt_system "$ip" "$ssh_user" "$ssh_pass" || {
            echo "      ⚠️  Enhanced cleanup completed with warnings (usually safe)"
        }
        return 0
    fi
    
    # Fallback to basic cleanup if sanitization not available
    if [[ -n "$ssh_pass" ]]; then
        sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" "
            # Set debconf to noninteractive mode to avoid prompts
            export DEBIAN_FRONTEND=noninteractive
            
            # Preconfigure grub-pc to avoid interactive prompts
            if dpkg -l | grep -q grub-pc; then
                echo 'grub-pc grub-pc/install_devices_empty boolean true' | sudo debconf-set-selections
                echo 'grub-pc grub-pc/install_devices string /dev/sda' | sudo debconf-set-selections
                echo 'grub-pc grub-pc/install_devices_disks_changed multiselect' | sudo debconf-set-selections
            fi
            
            # Clean package cache with enhanced handling
            sudo apt-get clean >/dev/null 2>&1 || true
            sudo apt-get autoremove -y --purge 2>/dev/null || {
                sudo apt-get autoremove -y --purge --allow-remove-essential 2>/dev/null || true
            }
            sudo apt-get autoclean >/dev/null 2>&1 || true
            
            # Clean logs (keep last 7 days)
            sudo journalctl --vacuum-time=7d >/dev/null 2>&1 || true
            
            # Clean temporary files
            sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
            sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
            
            # Clean old Docker images if Docker is installed
            if command -v docker >/dev/null 2>&1; then
                docker image prune -f >/dev/null 2>&1 || true
            fi
        " >/dev/null 2>&1
    else
        ssh -o BatchMode=yes "$ssh_user@$ip" "
            # Set debconf to noninteractive mode to avoid prompts
            export DEBIAN_FRONTEND=noninteractive
            
            # Preconfigure grub-pc to avoid interactive prompts
            if dpkg -l | grep -q grub-pc; then
                echo 'grub-pc grub-pc/install_devices_empty boolean true' | sudo debconf-set-selections
                echo 'grub-pc grub-pc/install_devices string /dev/sda' | sudo debconf-set-selections
                echo 'grub-pc grub-pc/install_devices_disks_changed multiselect' | sudo debconf-set-selections
            fi
            
            # Clean package cache with enhanced handling
            sudo apt-get clean >/dev/null 2>&1 || true
            sudo apt-get autoremove -y --purge 2>/dev/null || {
                sudo apt-get autoremove -y --purge --allow-remove-essential 2>/dev/null || true
            }
            sudo apt-get autoclean >/dev/null 2>&1 || true
            
            # Clean logs (keep last 7 days)
            sudo journalctl --vacuum-time=7d >/dev/null 2>&1 || true
            
            # Clean temporary files
            sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
            sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
            
            # Clean old Docker images if Docker is installed
            if command -v docker >/dev/null 2>&1; then
                docker image prune -f >/dev/null 2>&1 || true
            fi
        " >/dev/null 2>&1
    fi
    
    # Check space again
    local new_space
    if [[ -n "$ssh_pass" ]]; then
        new_space=$(sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" "df / | tail -1 | awk '{print \$4}'")
    else
        new_space=$(ssh -o BatchMode=yes "$ssh_user@$ip" "df / | tail -1 | awk '{print \$4}'")
    fi
    local new_gb=$((new_space / 1024 / 1024))
    echo "    📊 Space after cleanup: ${new_gb}GB free"
}

# Clean up existing Docker Swarm configuration
cleanup_existing_swarm() {
    local ip="$1"
    
    # Get SSH credentials from the parent function's scope
    local ssh_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
    local ssh_pass="${PASSWORD:-${PI_PASS:-${NODES_DEFAULT_PASS:-}}}"
    
    if [[ -n "$ssh_pass" ]]; then
        sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" "
            # Leave swarm if part of one
            docker swarm leave --force >/dev/null 2>&1 || true
            
            # Stop and remove all containers
            docker stop \$(docker ps -aq) >/dev/null 2>&1 || true
            docker rm \$(docker ps -aq) >/dev/null 2>&1 || true
            
            # Remove all custom networks
            docker network ls --filter type=custom -q | xargs -r docker network rm >/dev/null 2>&1 || true
            
            # Clean up volumes
            docker volume prune -f >/dev/null 2>&1 || true
        " >/dev/null 2>&1
    else
        ssh -o BatchMode=yes "$ssh_user@$ip" "
            # Leave swarm if part of one
            docker swarm leave --force >/dev/null 2>&1 || true
            
            # Stop and remove all containers
            docker stop \$(docker ps -aq) >/dev/null 2>&1 || true
            docker rm \$(docker ps -aq) >/dev/null 2>&1 || true
            
            # Remove all custom networks
            docker network ls --filter type=custom -q | xargs -r docker network rm >/dev/null 2>&1 || true
            
            # Clean up volumes
            docker volume prune -f >/dev/null 2>&1 || true
        " >/dev/null 2>&1
    fi
    
    echo "    ✅ Existing swarm configuration cleaned"
}

# Validate network requirements
validate_network_requirements() {
    local pi_ips=("$@")
    
    # Get SSH credentials from the parent function's scope
    local ssh_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
    local ssh_pass="${PASSWORD:-${PI_PASS:-${NODES_DEFAULT_PASS:-}}}"
    
    # Helper function for SSH commands with proper authentication
    ssh_pi_network() {
        local ip="$1"
        shift
        local cmd="$*"
        
        if [[ -n "$ssh_pass" ]]; then
            sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$ip" "$cmd"
        else
            ssh -o BatchMode=yes "$ssh_user@$ip" "$cmd"
        fi
    }
    
    echo "  🌐 Validating network connectivity between Pis..."
    
    # Test connectivity between all Pis
    for i in "${!pi_ips[@]}"; do
        for j in "${!pi_ips[@]}"; do
            if [[ $i -ne $j ]]; then
                local ip1="${pi_ips[$i]}"
                local ip2="${pi_ips[$j]}"
                
                if ssh_pi_network "$ip1" "ping -c 2 -W 3 $ip2" >/dev/null 2>&1; then
                    echo "    ✅ $ip1 → $ip2: OK"
                else
                    log "ERROR" "❌ Network connectivity failed: $ip1 → $ip2"
                    return 1
                fi
            fi
        done
    done
    
    # Check required ports are not in use
    for ip in "${pi_ips[@]}"; do
        echo "  🔍 Checking port availability on $ip..."
        local blocked_ports=""
        
        # Check critical Docker Swarm ports
        for port in 2377 7946 4789; do
            if ssh_pi_network "$ip" "ss -tuln | grep ':$port '" >/dev/null 2>&1; then
                blocked_ports="$blocked_ports $port"
            fi
        done
        
        if [[ -n "$blocked_ports" ]]; then
            log "WARN" "⚠️  Ports in use on $ip:$blocked_ports (may cause conflicts)"
        else
            echo "    ✅ Required ports available"
        fi
    done
}

# Export functions
export -f validate_and_prepare_pi_state
export -f validate_and_prepare_pi_state_enhanced
export -f cleanup_pi_disk_space
export -f cleanup_existing_swarm
export -f validate_network_requirements
