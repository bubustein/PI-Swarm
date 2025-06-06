# functions/high_availability.sh
# High Availability setup for multi-manager Docker Swarm configuration

# Setup multi-manager high availability cluster
setup_high_availability() {
    local manager_ips="$1"  # Comma-separated list of manager IPs
    local worker_ips="$2"   # Comma-separated list of worker IPs
    local primary_manager="$3"
    
    log "INFO" "Setting up high availability cluster with multiple managers"
    
    # Convert comma-separated IPs to arrays
    IFS=',' read -ra MANAGER_IPS <<< "$manager_ips"
    IFS=',' read -ra WORKER_IPS <<< "$worker_ips"
    
    local total_managers=${#MANAGER_IPS[@]}
    
    # Validate odd number of managers for proper quorum
    if (( total_managers % 2 == 0 )); then
        log "WARN" "Even number of managers ($total_managers) detected. Recommend odd number for proper quorum."
        log "INFO" "Continuing with $total_managers managers..."
    fi
    
    log "INFO" "Configuring $total_managers manager nodes for HA"
    
    # Initialize swarm on primary manager
    log "INFO" "Initializing swarm on primary manager: $primary_manager"
    ssh "$USER@$primary_manager" "docker swarm init --advertise-addr $primary_manager" || {
        log "ERROR" "Failed to initialize swarm on primary manager"
        return 1
    }
    
    # Get manager and worker join tokens
    local manager_token=$(ssh "$USER@$primary_manager" "docker swarm join-token manager -q")
    local worker_token=$(ssh "$USER@$primary_manager" "docker swarm join-token worker -q")
    
    log "INFO" "Manager join token obtained"
    log "INFO" "Worker join token obtained"
    
    # Join additional managers
    for manager_ip in "${MANAGER_IPS[@]}"; do
        if [[ "$manager_ip" != "$primary_manager" ]]; then
            log "INFO" "Adding manager node: $manager_ip"
            ssh "$USER@$manager_ip" "docker swarm join --token $manager_token $primary_manager:2377" || {
                log "WARN" "Failed to join manager node: $manager_ip"
            }
        fi
    done
    
    # Join worker nodes
    for worker_ip in "${WORKER_IPS[@]}"; do
        log "INFO" "Adding worker node: $worker_ip"
        ssh "$USER@$worker_ip" "docker swarm join --token $worker_token $primary_manager:2377" || {
            log "WARN" "Failed to join worker node: $worker_ip"
        }
    done
    
    # Wait for cluster to stabilize
    sleep 10
    
    # Verify cluster health
    verify_ha_cluster "$primary_manager"
    
    # Setup HA-specific configurations
    setup_ha_networking "${MANAGER_IPS[@]}"
    setup_ha_storage "${MANAGER_IPS[@]}"
    setup_ha_monitoring "${MANAGER_IPS[@]}"
    
    log "INFO" "✅ High availability cluster setup complete"
}

# Verify HA cluster health
verify_ha_cluster() {
    local primary_manager="$1"
    
    log "INFO" "Verifying HA cluster health..."
    
    # Check node status
    local node_output=$(ssh "$USER@$primary_manager" "docker node ls")
    log "INFO" "Cluster nodes:"
    echo "$node_output" | while read line; do
        log "INFO" "  $line"
    done
    
    # Check manager count
    local manager_count=$(ssh "$USER@$primary_manager" "docker node ls --filter role=manager -q | wc -l")
    local worker_count=$(ssh "$USER@$primary_manager" "docker node ls --filter role=worker -q | wc -l")
    
    log "INFO" "Cluster composition: $manager_count managers, $worker_count workers"
    
    # Verify quorum
    if (( manager_count >= 3 )); then
        log "INFO" "✅ Sufficient managers for HA quorum ($manager_count)"
    else
        log "WARN" "⚠️  Low manager count ($manager_count) - consider adding more for better HA"
    fi
    
    # Check cluster status
    local swarm_status=$(ssh "$USER@$primary_manager" "docker info --format '{{.Swarm.LocalNodeState}}'")
    if [[ "$swarm_status" == "active" ]]; then
        log "INFO" "✅ Swarm cluster is active and healthy"
    else
        log "ERROR" "❌ Swarm cluster status: $swarm_status"
        return 1
    fi
}

# Setup HA networking with overlay networks
setup_ha_networking() {
    local manager_ips=("$@")
    local primary_manager="${manager_ips[0]}"
    
    log "INFO" "Setting up HA networking..."
    
    # Create overlay networks for different service tiers
    ssh "$USER@$primary_manager" << 'EOF'
# Create production overlay network
docker network create --driver overlay --attachable production-net

# Create management overlay network
docker network create --driver overlay --attachable management-net

# Create monitoring overlay network (if not exists)
if ! docker network ls | grep -q monitoring; then
    docker network create --driver overlay --attachable monitoring
fi

# Create backup overlay network
docker network create --driver overlay --attachable backup-net
EOF
    
    # Configure network policies and security
    setup_network_security "$primary_manager"
    
    log "INFO" "✅ HA networking setup complete"
}

# Setup network security for HA
setup_network_security() {
    local manager_ip="$1"
    
    log "INFO" "Configuring network security for HA cluster..."
    
    # Create network security script
    cat > "/tmp/network-security.sh" << 'EOF'
#!/bin/bash
# Network security configuration for HA cluster

# Enable IP forwarding for container networking
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.conf
sysctl -p

# Configure UFW rules for Docker Swarm
ufw allow 2376/tcp  # Docker daemon TLS
ufw allow 2377/tcp  # Swarm management
ufw allow 7946/tcp  # Container network discovery
ufw allow 7946/udp  # Container network discovery
ufw allow 4789/udp  # Overlay network traffic

# Allow inter-manager communication
ufw allow from 192.168.0.0/16 to any port 2377
ufw allow from 10.0.0.0/8 to any port 2377

# Enable UFW if not already enabled
ufw --force enable

echo "Network security configured for HA cluster"
EOF
    
    # Deploy network security configuration
    scp "/tmp/network-security.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo bash /tmp/network-security.sh"
    
    log "INFO" "✅ Network security configured"
}

# Setup HA shared storage
setup_ha_storage() {
    local manager_ips=("$@")
    local primary_manager="${manager_ips[0]}"
    
    log "INFO" "Setting up HA shared storage..."
    
    # Create distributed storage volumes
    ssh "$USER@$primary_manager" << 'EOF'
# Create shared volumes for HA services
docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=1G ha-shared-config
docker volume create --driver local ha-prometheus-data
docker volume create --driver local ha-grafana-data
docker volume create --driver local ha-portainer-data

# Create backup volumes
docker volume create --driver local ha-backup-data
EOF
    
    # Setup NFS for shared storage (optional enhancement)
    setup_nfs_storage "${manager_ips[@]}"
    
    log "INFO" "✅ HA storage setup complete"
}

# Setup NFS shared storage for true HA
setup_nfs_storage() {
    local manager_ips=("$@")
    local nfs_server="${manager_ips[0]}"
    
    log "INFO" "Setting up NFS shared storage..."
    
    # Install and configure NFS server on primary manager
    ssh "$USER@$nfs_server" << 'EOF'
sudo apt update
sudo apt install -y nfs-kernel-server

# Create shared directories
sudo mkdir -p /srv/nfs/piswarm/{config,data,backups}
sudo chown -R nobody:nogroup /srv/nfs/piswarm
sudo chmod -R 755 /srv/nfs/piswarm

# Configure NFS exports
echo "/srv/nfs/piswarm *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# Start NFS services
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server
EOF
    
    # Configure NFS clients on other managers
    for manager_ip in "${manager_ips[@]}"; do
        if [[ "$manager_ip" != "$nfs_server" ]]; then
            log "INFO" "Configuring NFS client on $manager_ip"
            ssh "$USER@$manager_ip" << EOF
sudo apt update
sudo apt install -y nfs-common

# Create mount points
sudo mkdir -p /mnt/piswarm/{config,data,backups}

# Add to fstab for automatic mounting
echo "$nfs_server:/srv/nfs/piswarm/config /mnt/piswarm/config nfs defaults 0 0" | sudo tee -a /etc/fstab
echo "$nfs_server:/srv/nfs/piswarm/data /mnt/piswarm/data nfs defaults 0 0" | sudo tee -a /etc/fstab
echo "$nfs_server:/srv/nfs/piswarm/backups /mnt/piswarm/backups nfs defaults 0 0" | sudo tee -a /etc/fstab

# Mount NFS shares
sudo mount -a
EOF
        fi
    done
    
    log "INFO" "✅ NFS shared storage configured"
}

# Setup HA monitoring and health checks
setup_ha_monitoring() {
    local manager_ips=("$@")
    local primary_manager="${manager_ips[0]}"
    
    log "INFO" "Setting up HA monitoring..."
    
    # Create HA health check script
    cat > "/tmp/ha-health-check.sh" << 'EOF'
#!/bin/bash
# HA Cluster Health Check Script

MANAGER_IPS=()
HEALTH_LOG="/var/log/ha-health.log"
ALERT_THRESHOLD=2  # Number of failed checks before alerting

check_manager_health() {
    local manager_ip="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check Docker daemon
    if ssh -o ConnectTimeout=5 pi@"$manager_ip" "docker info >/dev/null 2>&1"; then
        echo "[$timestamp] Manager $manager_ip: Docker daemon OK" >> "$HEALTH_LOG"
        return 0
    else
        echo "[$timestamp] Manager $manager_ip: Docker daemon FAILED" >> "$HEALTH_LOG"
        return 1
    fi
}

check_swarm_quorum() {
    local check_manager="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get active manager count
    local active_managers=$(ssh pi@"$check_manager" "docker node ls --filter role=manager --filter membership=accepted --format '{{.Status}}' | grep -c Ready" 2>/dev/null || echo "0")
    
    if [[ "$active_managers" -ge 2 ]]; then
        echo "[$timestamp] Swarm quorum OK: $active_managers active managers" >> "$HEALTH_LOG"
        return 0
    else
        echo "[$timestamp] Swarm quorum CRITICAL: Only $active_managers active managers" >> "$HEALTH_LOG"
        # Send critical alert
        if command -v slack-notify >/dev/null 2>&1; then
            slack-notify service-down "Swarm quorum critical: $active_managers managers"
        fi
        return 1
    fi
}

promote_worker_to_manager() {
    local worker_ip="$1"
    local primary_manager="$2"
    
    echo "Attempting to promote worker $worker_ip to manager..."
    ssh pi@"$primary_manager" "docker node promote $worker_ip" && {
        echo "Successfully promoted $worker_ip to manager"
        if command -v slack-notify >/dev/null 2>&1; then
            slack-notify deployment "Promoted worker $worker_ip to manager for HA"
        fi
    }
}

# Main health check loop
main() {
    local failed_checks=0
    
    # Check each manager
    for manager_ip in "${MANAGER_IPS[@]}"; do
        if ! check_manager_health "$manager_ip"; then
            ((failed_checks++))
        fi
    done
    
    # Check overall swarm health
    if [[ ${#MANAGER_IPS[@]} -gt 0 ]]; then
        check_swarm_quorum "${MANAGER_IPS[0]}"
    fi
    
    # Cleanup old logs (keep last 7 days)
    find /var/log -name "ha-health.log.*" -mtime +7 -delete 2>/dev/null
}

# Load manager IPs from config
if [[ -f /etc/piswarm/managers.conf ]]; then
    mapfile -t MANAGER_IPS < /etc/piswarm/managers.conf
fi

main "$@"
EOF
    
    # Deploy health check script
    scp "/tmp/ha-health-check.sh" "$USER@$primary_manager:/tmp/"
    ssh "$USER@$primary_manager" << 'EOF'
sudo mkdir -p /etc/piswarm
sudo mv /tmp/ha-health-check.sh /usr/local/bin/ha-health-check
sudo chmod +x /usr/local/bin/ha-health-check

# Create cron job for health checks
echo "*/5 * * * * root /usr/local/bin/ha-health-check" | sudo tee -a /etc/crontab
EOF
    
    # Deploy to all managers
    for manager_ip in "${manager_ips[@]}"; do
        echo "$manager_ip" | ssh "$USER@$primary_manager" "sudo tee -a /etc/piswarm/managers.conf"
    done
    
    log "INFO" "✅ HA monitoring setup complete"
}

# Failover procedures
setup_failover_procedures() {
    local manager_ips=("$@")
    local primary_manager="${manager_ips[0]}"
    
    log "INFO" "Setting up automated failover procedures..."
    
    cat > "/tmp/failover.sh" << 'EOF'
#!/bin/bash
# Automated failover script for HA cluster

MANAGER_IPS=()
FAILOVER_LOG="/var/log/failover.log"

detect_failed_manager() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    for manager_ip in "${MANAGER_IPS[@]}"; do
        if ! ssh -o ConnectTimeout=5 pi@"$manager_ip" "docker info >/dev/null 2>&1"; then
            echo "[$timestamp] Detected failed manager: $manager_ip" >> "$FAILOVER_LOG"
            
            # Attempt automated recovery
            initiate_failover "$manager_ip"
        fi
    done
}

initiate_failover() {
    local failed_manager="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] Initiating failover for $failed_manager" >> "$FAILOVER_LOG"
    
    # Find a healthy manager to execute commands
    local healthy_manager=""
    for manager_ip in "${MANAGER_IPS[@]}"; do
        if [[ "$manager_ip" != "$failed_manager" ]]; then
            if ssh -o ConnectTimeout=5 pi@"$manager_ip" "docker info >/dev/null 2>&1"; then
                healthy_manager="$manager_ip"
                break
            fi
        fi
    done
    
    if [[ -n "$healthy_manager" ]]; then
        # Demote failed manager if still reachable
        ssh pi@"$healthy_manager" "docker node demote $failed_manager" 2>/dev/null
        
        # Update node availability
        ssh pi@"$healthy_manager" "docker node update --availability drain $failed_manager" 2>/dev/null
        
        echo "[$timestamp] Failover completed for $failed_manager" >> "$FAILOVER_LOG"
        
        # Send alert
        if command -v slack-notify >/dev/null 2>&1; then
            slack-notify node-down "$failed_manager (failover initiated)"
        fi
    else
        echo "[$timestamp] CRITICAL: No healthy managers available for failover!" >> "$FAILOVER_LOG"
    fi
}

# Load configuration and run
if [[ -f /etc/piswarm/managers.conf ]]; then
    mapfile -t MANAGER_IPS < /etc/piswarm/managers.conf
    detect_failed_manager
fi
EOF
    
    # Deploy failover script
    scp "/tmp/failover.sh" "$USER@$primary_manager:/tmp/"
    ssh "$USER@$primary_manager" << 'EOF'
sudo mv /tmp/failover.sh /usr/local/bin/failover
sudo chmod +x /usr/local/bin/failover

# Create cron job for failover detection
echo "*/10 * * * * root /usr/local/bin/failover" | sudo tee -a /etc/crontab
EOF
    
    log "INFO" "✅ Failover procedures setup complete"
}
