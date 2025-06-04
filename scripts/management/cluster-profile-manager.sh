#!/bin/bash
# PI-Swarm Cluster Profile Management Script
# Allows users to switch between cluster profiles and monitor resource usage

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required functions
source "$PROJECT_ROOT/lib/log.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set default values for configuration variables
export CLUSTER_PROFILE="${CLUSTER_PROFILE:-unknown}"
export CONTEXT_AWARE_DEPLOYMENT="${CONTEXT_AWARE_DEPLOYMENT:-false}"
export NODES_DEFAULT_USER="${NODES_DEFAULT_USER:-pi}"
export NODES_DEFAULT_PASS="${NODES_DEFAULT_PASS:-}"

# Handle PI_STATIC_IPS array properly
if [[ -z "${PI_STATIC_IPS:-}" ]]; then
    PI_STATIC_IPS=()
fi

# Try to load configuration if available
if [[ -f "$PROJECT_ROOT/config/config.yml" ]]; then
    # Simple config loading - extract key values
    if grep -q "CLUSTER_PROFILE" "$PROJECT_ROOT/config/config.yml" 2>/dev/null; then
        CLUSTER_PROFILE=$(grep "CLUSTER_PROFILE" "$PROJECT_ROOT/config/config.yml" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    fi
    if grep -q "CONTEXT_AWARE_DEPLOYMENT" "$PROJECT_ROOT/config/config.yml" 2>/dev/null; then
        CONTEXT_AWARE_DEPLOYMENT=$(grep "CONTEXT_AWARE_DEPLOYMENT" "$PROJECT_ROOT/config/config.yml" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    echo "PI-Swarm Cluster Profile Manager"
    echo "==============================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status                     - Show current cluster profile and resource usage"
    echo "  list                      - List available cluster profiles"
    echo "  switch <profile>          - Switch to a different cluster profile"
    echo "  monitor                   - Continuous monitoring of cluster resources"
    echo "  optimize                  - Get optimization recommendations"
    echo "  backup-config             - Backup current cluster configuration"
    echo "  restore-config <backup>   - Restore cluster configuration from backup"
    echo ""
    echo "Available Profiles:"
    echo "  basic          - Minimal resources, essential services only"
    echo "  lightweight    - Optimized for Pi Zero/1, reduced memory usage"
    echo "  standard       - Balanced configuration for Pi 3/4"
    echo "  high-performance - Full features for Pi 4/5 with 4GB+ RAM"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 switch high-performance"
    echo "  $0 monitor"
}

show_cluster_status() {
    echo -e "${BLUE}PI-Swarm Cluster Status${NC}"
    echo "======================="
    echo ""
    
    # Check if configuration is loaded
    if [[ -z "${PI_STATIC_IPS:-}" ]] || [[ "${#PI_STATIC_IPS[@]}" -eq 0 ]]; then
        echo -e "${RED}Error: Cluster configuration not found or not loaded${NC}"
        echo "Please ensure:"
        echo "1. You have deployed a cluster first"
        echo "2. Configuration file exists: $PROJECT_ROOT/config/config.yml"
        echo "3. PI_STATIC_IPS is properly configured"
        echo ""
        echo "To deploy a cluster, run: ./deploy.sh"
        return 1
    fi
    
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    # Get cluster information
    echo -e "${GREEN}Cluster Information:${NC}"
    echo "  Manager IP: $manager_ip"
    echo "  Current Profile: ${CLUSTER_PROFILE:-unknown}"
    echo "  Context-Aware Deployment: ${CONTEXT_AWARE_DEPLOYMENT:-false}"
    echo ""
    
    # Get node count and status
    local node_count
    node_count=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker node ls --format '{{.Hostname}}' | wc -l" 2>/dev/null || echo "Unknown")
    
    echo -e "${GREEN}Cluster Nodes ($node_count total):${NC}"
    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        docker node ls --format 'table {{.Hostname}}\t{{.Status}}\t{{.Availability}}\t{{.ManagerStatus}}'
    " 2>/dev/null || echo "  Unable to retrieve node information"
    echo ""
    
    # Get service status
    echo -e "${GREEN}Active Services:${NC}"
    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}\t{{.Ports}}'
    " 2>/dev/null || echo "  Unable to retrieve service information"
    echo ""
    
    # Show resource usage
    show_resource_usage
}

show_resource_usage() {
    echo -e "${GREEN}Resource Usage:${NC}"
    
    # Check if we have valid IPs
    if [[ -z "${PI_STATIC_IPS:-}" ]] || [[ "${#PI_STATIC_IPS[@]}" -eq 0 ]]; then
        echo "  No cluster nodes configured"
        return 1
    fi
    
    local total_memory_usage=0
    local total_cpu_usage=0
    local node_count=0
    
    for ip in "${PI_STATIC_IPS[@]}"; do
        echo "  Node $ip:"
        
        local memory_info
        memory_info=$(ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            free -h | awk '/^Mem:/ {printf \"  Memory: %s used / %s total (%.0f%%)\", \$3, \$2, \$3/\$2 * 100}'
        " 2>/dev/null || echo "    Memory: Unable to retrieve")
        echo "$memory_info"
        
        local cpu_usage
        cpu_usage=$(ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            top -bn1 | grep \"Cpu(s)\" | sed \"s/.*, *\\([0-9.]*\\)%* id.*/\\1/\" | awk '{printf \"  CPU: %.1f%% used\", 100 - \$1}'
        " 2>/dev/null || echo "    CPU: Unable to retrieve")
        echo "$cpu_usage"
        
        local temperature
        temperature=$(ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 || echo 'N/A'
        " 2>/dev/null || echo "N/A")
        echo "    Temperature: $temperature"
        echo ""
        
        node_count=$((node_count + 1))
    done
}

list_profiles() {
    echo -e "${BLUE}Available Cluster Profiles${NC}"
    echo "=========================="
    echo ""
    
    echo -e "${GREEN}basic${NC} - Minimal Resources"
    echo "  • Memory: 256MB Prometheus, 256MB Grafana, 128MB Portainer"
    echo "  • Retention: 3 days"
    echo "  • Features: Essential monitoring only"
    echo "  • Disabled: Traefik, cAdvisor"
    echo "  • Best for: Pi Zero, Pi 1, or testing environments"
    echo ""
    
    echo -e "${GREEN}lightweight${NC} - Pi Zero/1 Optimized"
    echo "  • Memory: 512MB Prometheus, 512MB Grafana, 256MB Portainer"
    echo "  • Retention: 7 days"
    echo "  • Features: Core monitoring with reduced frequency"
    echo "  • Optimizations: Reduced collection intervals, memory tuning"
    echo "  • Best for: Pi Zero 2W, Pi 1 Model B+"
    echo ""
    
    echo -e "${GREEN}standard${NC} - Balanced Configuration"
    echo "  • Memory: 2GB Prometheus, 1GB Grafana, 512MB Portainer"
    echo "  • Retention: 15 days"
    echo "  • Features: Full monitoring stack with Traefik"
    echo "  • Best for: Pi 3, Pi 4 with 2-4GB RAM"
    echo ""
    
    echo -e "${GREEN}high-performance${NC} - Full Features"
    echo "  • Memory: 3GB Prometheus, 2GB Grafana, 512MB Portainer"
    echo "  • Retention: 30 days"
    echo "  • Features: Extended monitoring, Jaeger tracing, more plugins"
    echo "  • Optimizations: Higher collection frequency, more concurrent queries"
    echo "  • Best for: Pi 4/5 with 4GB+ RAM, Pi Compute Module 4"
    echo ""
    
    local current_profile="${CLUSTER_PROFILE:-unknown}"
    echo -e "Current profile: ${GREEN}$current_profile${NC}"
}

switch_profile() {
    local new_profile="$1"
    
    # Validate profile
    case "$new_profile" in
        "basic"|"lightweight"|"standard"|"high-performance")
            ;;
        *)
            echo -e "${RED}Error: Invalid profile '$new_profile'${NC}"
            echo "Valid profiles: basic, lightweight, standard, high-performance"
            return 1
            ;;
    esac
    
    echo -e "${BLUE}Switching Cluster Profile${NC}"
    echo "========================"
    echo ""
    echo "Current profile: ${CLUSTER_PROFILE:-unknown}"
    echo "New profile: $new_profile"
    echo ""
    
    # Ask for confirmation
    read -p "Are you sure you want to switch profiles? This will restart all services. (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Profile switch cancelled."
        return 0
    fi
    
    # Update profile in configuration
    export CLUSTER_PROFILE="$new_profile"
    export CONTEXT_AWARE_DEPLOYMENT="true"
    
    # Update config file
    sed -i "s/CLUSTER_PROFILE=.*/CLUSTER_PROFILE=$new_profile/" "$PROJECT_ROOT/config/config.yml" 2>/dev/null || true
    sed -i "s/CONTEXT_AWARE_DEPLOYMENT=.*/CONTEXT_AWARE_DEPLOYMENT=true/" "$PROJECT_ROOT/config/config.yml" 2>/dev/null || true
    
    echo "Reconfiguring services for $new_profile profile..."
    
    # Use the switch_cluster_profile function from deploy_services.sh
    if switch_cluster_profile "$new_profile"; then
        echo -e "${GREEN}✅ Successfully switched to $new_profile profile${NC}"
        echo ""
        echo "Run '$0 status' to verify the new configuration."
    else
        echo -e "${RED}❌ Failed to switch cluster profile${NC}"
        return 1
    fi
}

monitor_cluster() {
    echo -e "${BLUE}PI-Swarm Cluster Monitor${NC}"
    echo "======================="
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}PI-Swarm Cluster Monitor - $(date)${NC}"
        echo "================================================"
        echo ""
        
        show_resource_usage
        
        echo "Press Ctrl+C to stop monitoring..."
        sleep 10
    done
}

get_optimization_recommendations() {
    echo -e "${BLUE}Cluster Optimization Analysis${NC}"
    echo "============================="
    echo ""
    
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    # Load current cluster variables
    export CLUSTER_PROFILE="${CLUSTER_PROFILE:-standard}"
    export CONTEXT_AWARE_DEPLOYMENT="${CONTEXT_AWARE_DEPLOYMENT:-false}"
    
    # Call the monitoring function from deploy_services.sh
    monitor_cluster_resources "$manager_ip"
}

backup_cluster_config() {
    local backup_name="cluster-config-$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$PROJECT_ROOT/data/backups/$backup_name"
    
    echo -e "${BLUE}Backing up Cluster Configuration${NC}"
    echo "================================"
    echo ""
    
    mkdir -p "$backup_dir"
    
    # Backup local configuration
    cp "$PROJECT_ROOT/config/config.yml" "$backup_dir/"
    cp "$PROJECT_ROOT/config/docker-compose.monitoring.yml" "$backup_dir/"
    
    # Backup adaptive configuration if it exists
    if [[ -f "$PROJECT_ROOT/config/docker-compose.adaptive.yml" ]]; then
        cp "$PROJECT_ROOT/config/docker-compose.adaptive.yml" "$backup_dir/"
    fi
    
    # Backup remote configuration from manager
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    echo "Backing up remote configuration from $manager_ip..."
    scp_download "~/PISworm/docker-compose.*.yml" "$backup_dir/" "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" 2>/dev/null || true
    scp_download "~/PISworm/.env" "$backup_dir/" "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" 2>/dev/null || true
    
    # Create backup info file
    cat > "$backup_dir/backup_info.txt" << EOF
PI-Swarm Cluster Configuration Backup
=====================================
Backup Date: $(date)
Cluster Profile: ${CLUSTER_PROFILE:-unknown}
Context-Aware Deployment: ${CONTEXT_AWARE_DEPLOYMENT:-false}
Manager IP: $manager_ip
Total Nodes: ${#PI_STATIC_IPS[@]}

Files Included:
- config.yml (local configuration)
- docker-compose.monitoring.yml (base service configuration)
- docker-compose.adaptive.yml (adaptive configuration, if exists)
- Remote docker-compose files
- Remote .env file
EOF
    
    echo -e "${GREEN}✅ Backup created: $backup_dir${NC}"
    echo "Backup info saved in: $backup_dir/backup_info.txt"
}

# Main script logic
case "${1:-}" in
    "status")
        show_cluster_status
        ;;
    "list")
        list_profiles
        ;;
    "switch")
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error: Profile name required${NC}"
            echo "Usage: $0 switch <profile>"
            list_profiles
            exit 1
        fi
        switch_profile "$2"
        ;;
    "monitor")
        monitor_cluster
        ;;
    "optimize")
        get_optimization_recommendations
        ;;
    "backup-config")
        backup_cluster_config
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
