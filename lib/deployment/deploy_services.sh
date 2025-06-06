deploy_services() {
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    # Set default values for required variables
    export NODES_DEFAULT_USER="${NODES_DEFAULT_USER:-luser}"
    export NODES_DEFAULT_PASS="${NODES_DEFAULT_PASS:-}"
    export PI_SWARM_CONFIG_DIR="${PI_SWARM_CONFIG_DIR:-/home/luser/PI-Swarm/config}"

    # If no password is set in environment, prompt for it
    if [[ -z "${PORTAINER_PASSWORD:-}" ]]; then
        echo ""
        echo "🔐 Portainer Admin Password Setup"
        echo "================================="
        echo "Please set a secure password for the Portainer admin account:"
        echo "(This will be the login password for the web interface)"
        echo "(Minimum 8 characters required)"
        
        local attempts=0
        local max_attempts=3
        while [[ $attempts -lt $max_attempts ]]; do
            read -sp "Enter Portainer admin password: " portainer_password < /dev/tty
            echo ""
            if [[ -n "$portainer_password" && ${#portainer_password} -ge 8 ]]; then
                break
            else
                ((attempts++))
                if [[ $attempts -eq $max_attempts ]]; then
                    log ERROR "Failed to set valid password after $max_attempts attempts"
                    log ERROR "Using default password 'piswarm123' - PLEASE CHANGE IMMEDIATELY"
                    portainer_password="piswarm123"
                    break
                else
                    echo "❌ Password must be at least 8 characters long. Please try again. (Attempt $attempts/$max_attempts)"
                fi
            fi
        done
    else
        portainer_password="$PORTAINER_PASSWORD"
        # Validate that environment password meets requirements
        if [[ ${#portainer_password} -lt 8 ]]; then
            log WARN "Environment PORTAINER_PASSWORD is less than 8 characters, using default"
            portainer_password="piswarm123"
        fi
    fi

    log INFO "Deploying complete service stack (Monitoring + Portainer)..."
    
    # Configure adaptive services based on detected hardware
    if [[ "${CONTEXT_AWARE_DEPLOYMENT:-false}" == "true" ]]; then
        log INFO "Context-aware deployment enabled - configuring adaptive services"
        configure_adaptive_services
        local compose_file_name="docker-compose.adaptive.yml"
    else
        log INFO "Using standard service configuration"
        local compose_file_name="docker-compose.monitoring.yml"
    fi
    
    # Load service status functions
    source "$FUNCTIONS_DIR/monitoring/service_status.sh"

    local grafana_password="${GRAFANA_PASSWORD:-admin}"

    # Export cluster information for service deployment
    export_cluster_variables_for_deployment
    
    # Copy adaptive configuration to manager node if context-aware deployment is enabled
    if [[ "${CONTEXT_AWARE_DEPLOYMENT:-false}" == "true" ]]; then
        log INFO "Copying adaptive docker-compose configuration to manager node"
        if ! scp_file "$PI_SWARM_CONFIG_DIR/docker-compose.adaptive.yml" "~/piswarm/docker-compose.adaptive.yml" "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS"; then
            log WARN "Failed to copy adaptive configuration, falling back to standard configuration"
            local compose_file_name="docker-compose.monitoring.yml"
        fi
    fi
    
    # Create Portainer admin password file and deploy services, capturing output
    # Use ssh_exec for stack deployment, capturing and printing output
    stack_output=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        cd ~/piswarm || exit 1
        echo '[REMOTE] Creating Portainer admin password hash...'
        echo '$portainer_password' | docker run --rm -i portainer/helper-reset-password > admin_password 2>&1
        echo '[REMOTE] Running docker compose up with $compose_file_name (trying V2 first, fallback to V1)...'
        if docker compose version >/dev/null 2>&1; then
            docker compose -f $compose_file_name up -d 2>&1
        elif docker-compose --version >/dev/null 2>&1; then
            docker-compose -f $compose_file_name up -d 2>&1
        else
            echo '[REMOTE ERROR] Neither docker compose nor docker-compose command found'
            exit 1
        fi
    ")
    status=$?
    echo "$stack_output"
    if [[ $status -ne 0 ]]; then
        log ERROR "Service stack deployment failed. See above for remote error output."
        return 1
    fi
    
    if [[ $status -eq 0 ]]; then
        log INFO "Service stack deployed successfully!"
        
        # Wait for services to start
        log INFO "Waiting for services to initialize..."
        sleep 15
        
        # Initialize Portainer with the swarm endpoint
        initialize_portainer "$manager_ip" "$portainer_password"
        
        # Check service health
        check_service_health "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS"
        
        # Test endpoints
        test_service_endpoints "$manager_ip"
        
        # Display comprehensive service overview
        display_service_overview "$manager_ip"
        
        # Monitor cluster resources and provide recommendations
        monitor_cluster_resources "$manager_ip"
        
        # Generate quick access info
        generate_access_info "$manager_ip"
    else
        log ERROR "Failed to deploy service stack"
        return 1
    fi
}

initialize_portainer() {
    local manager_ip="$1"
    local admin_password="$2"
    
    log INFO "Initializing Portainer and connecting to Docker Swarm..."
    
    # Wait for Portainer to be ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "curl -k -s https://localhost:9443/api/status" >/dev/null 2>&1; then
            log INFO "Portainer is ready!"
            break
        fi
        ((attempt++))
        log INFO "Waiting for Portainer to start... ($attempt/$max_attempts)"
        sleep 5
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log WARN "Portainer may not be fully ready yet, but continuing..."
    fi
    
    # The swarm endpoint is automatically detected by Portainer when running in swarm mode
    log INFO "Portainer will automatically detect the Docker Swarm cluster"
}

display_service_overview() {
    local manager_ip="$1"
    
    log INFO "=== 🎉 DEPLOYMENT COMPLETE ==="
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 PI-SWARM CLUSTER READY 🚀                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Get cluster information
    local node_count
    node_count=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker node ls --format '{{.Hostname}}' | wc -l" 2>/dev/null || echo "Unknown")
    
    local service_count
    service_count=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker service ls --format '{{.Name}}' | wc -l" 2>/dev/null || echo "Unknown")
    
    echo "📊 CLUSTER INFORMATION:"
    echo "   • Manager Node: $manager_ip"
    echo "   • Total Nodes: $node_count"
    echo "   • Active Services: $service_count"
    echo "   • Cluster Name: pi-swarm"
    
    # Display cluster profile information if context-aware deployment was used
    if [[ "${CONTEXT_AWARE_DEPLOYMENT:-false}" == "true" ]]; then
        echo "   • Cluster Profile: ${CLUSTER_PROFILE:-standard}"
        echo "   • Total Memory: ${CLUSTER_TOTAL_MEMORY:-unknown}MB"
        echo "   • Min CPU Cores: ${CLUSTER_MIN_CPU_CORES:-unknown}"
        echo "   • Deployment Mode: Context-Aware (Hardware-Optimized)"
    else
        echo "   • Deployment Mode: Standard Configuration"
    fi
    echo ""
    
    echo "🌐 WEB INTERFACES & ACCESS DETAILS:"
    echo ""
    echo "┌─ 🐳 PORTAINER (Container Management)"
    echo "│  ├─ HTTPS: https://$manager_ip:9443"
    echo "│  ├─ HTTP:  http://$manager_ip:9000"  
    echo "│  ├─ Username: admin"
    echo "│  └─ Password: [Password you set during deployment]"
    echo ""
    echo "┌─ 📊 GRAFANA (Monitoring Dashboard)"
    echo "│  ├─ URL: http://$manager_ip:3000"
    echo "│  ├─ Username: admin"
    echo "│  └─ Password: ${GRAFANA_PASSWORD:-admin}"
    echo ""
    echo "┌─ 🔍 PROMETHEUS (Metrics Collection)"
    echo "│  ├─ URL: http://$manager_ip:9090"
    echo "│  └─ No authentication required"
    echo ""
    echo "┌─ 📈 NODE EXPORTER (System Metrics)"
    echo "│  └─ Available on all nodes: http://[node-ip]:9100"
    echo ""
    
    echo "🔧 MANAGEMENT COMMANDS:"
    echo "   • View cluster: ssh $NODES_DEFAULT_USER@$manager_ip 'docker node ls'"
    echo "   • View services: ssh $NODES_DEFAULT_USER@$manager_ip 'docker service ls'"
    echo "   • Service logs: ssh $NODES_DEFAULT_USER@$manager_ip 'docker service logs [service-name]'"
    echo ""
    
    echo "📋 DEPLOYED SERVICES STATUS:"
    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        echo '   Service Name          | Replicas | Image                     | Ports'
        echo '   ---------------------|----------|---------------------------|------------------'
        docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}\t{{.Ports}}' | tail -n +2 | while read line; do
            echo \"   \$line\"
        done
    " 2>/dev/null || echo "   Unable to retrieve service status"
    
    # Generate web dashboard
    generate_web_dashboard "$manager_ip"
    
    echo ""
    echo "🎯 NEXT STEPS:"
    echo "   1. Open Portainer: https://$manager_ip:9443 (accept SSL warning)"
    echo "   2. Login with admin/[your-password] and optionally change password in settings"
    echo "   3. Open Grafana: http://$manager_ip:3000 for monitoring dashboards"
    echo "   4. Open Web Dashboard: file://$(pwd)/pi-swarm-dashboard.html"
    echo "   5. Use Portainer to deploy additional applications to your swarm"
    echo ""
    echo "✅ Your Pi Swarm cluster is ready for production use!"
    echo "🌐 Web Dashboard: file://$(pwd)/pi-swarm-dashboard.html"
    echo ""
}

generate_web_dashboard() {
    local manager_ip="$1"
    local dashboard_file="$(pwd)/pi-swarm-dashboard.html"
    
    log INFO "Generating web dashboard..."
    
    # Copy template and replace placeholders
    cp "$(pwd)/web-dashboard.html" "$dashboard_file"
    
    # Replace placeholders with actual values
    sed -i "s/{{MANAGER_IP}}/$manager_ip/g" "$dashboard_file"
    sed -i "s/{{PORTAINER_PASSWORD}}/$portainer_password/g" "$dashboard_file"
    sed -i "s/{{GRAFANA_PASSWORD}}/${GRAFANA_PASSWORD:-admin}/g" "$dashboard_file"
    sed -i "s/{{SSH_USER}}/${NODES_DEFAULT_USER}/g" "$dashboard_file"
    
    log INFO "Web dashboard generated: $dashboard_file"
}

# Context-aware deployment configuration based on hardware detection
configure_adaptive_services() {
    local cluster_profile="${CLUSTER_PROFILE:-standard}"
    local min_memory="${CLUSTER_MIN_MEMORY:-1024}"
    local min_cpu_cores="${CLUSTER_MIN_CPU_CORES:-4}"
    local total_nodes="${CLUSTER_TOTAL_NODES:-1}"
    
    log INFO "Configuring services for cluster profile: $cluster_profile"
    log INFO "Cluster specs - Min Memory: ${min_memory}MB, Min CPU: ${min_cpu_cores} cores, Nodes: $total_nodes"
    
    # Create adaptive docker-compose configuration
    local compose_file="$PI_SWARM_CONFIG_DIR/docker-compose.monitoring.yml"
    local adaptive_compose_file="$PI_SWARM_CONFIG_DIR/docker-compose.adaptive.yml"
    
    # Copy base configuration
    cp "$compose_file" "$adaptive_compose_file"
    
    # Apply cluster-specific optimizations
    case "$cluster_profile" in
        "basic")
            log INFO "Applying basic profile optimizations (minimal resources)"
            apply_basic_profile_config "$adaptive_compose_file"
            ;;
        "lightweight")
            log INFO "Applying lightweight profile optimizations (optimized for Pi Zero/1)"
            apply_lightweight_profile_config "$adaptive_compose_file"
            ;;
        "standard")
            log INFO "Applying standard profile optimizations (balanced for Pi 3/4)"
            apply_standard_profile_config "$adaptive_compose_file"
            ;;
        "high-performance")
            log INFO "Applying high-performance profile optimizations (Pi 4/5 with 4GB+ RAM)"
            apply_high_performance_profile_config "$adaptive_compose_file"
            ;;
        *)
            log WARN "Unknown cluster profile '$cluster_profile', using standard configuration"
            apply_standard_profile_config "$adaptive_compose_file"
            ;;
    esac
    
    # Apply node count optimizations
    apply_node_count_optimizations "$adaptive_compose_file" "$total_nodes"
    
    log INFO "Adaptive service configuration complete: $adaptive_compose_file"
}

apply_basic_profile_config() {
    local compose_file="$1"
    log INFO "Configuring services for basic profile (very limited resources)"
    
    # Prometheus - minimal configuration
    sed -i 's/memory: 2G/memory: 256M/g' "$compose_file"
    sed -i 's/memory: 1G/memory: 128M/g' "$compose_file"
    sed -i 's/--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}/--storage.tsdb.retention.time=3d/g' "$compose_file"
    
    # Grafana - reduce memory footprint
    sed -i '/grafana:/,/healthcheck:/ s/memory: 1G/memory: 256M/' "$compose_file"
    sed -i '/grafana:/,/healthcheck:/ s/memory: 512M/memory: 128M/' "$compose_file"
    
    # Portainer - minimal resources
    sed -i '/portainer:/,/healthcheck:/ s/memory: 512M/memory: 128M/' "$compose_file"
    sed -i '/portainer:/,/healthcheck:/ s/memory: 256M/memory: 64M/' "$compose_file"
    
    # Disable resource-intensive services
    add_service_condition "$compose_file" "traefik" "false"  # Disable Traefik in basic mode
    add_service_condition "$compose_file" "cadvisor" "false"  # Disable cAdvisor in basic mode
}

apply_lightweight_profile_config() {
    local compose_file="$1"
    log INFO "Configuring services for lightweight profile (Pi Zero/1 optimized)"
    
    # Prometheus - reduced retention and memory
    sed -i 's/memory: 2G/memory: 512M/g' "$compose_file"
    sed -i 's/memory: 1G/memory: 256M/g' "$compose_file"
    sed -i 's/--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}/--storage.tsdb.retention.time=7d/g' "$compose_file"
    
    # Grafana - optimized for low memory
    sed -i '/grafana:/,/healthcheck:/ s/memory: 1G/memory: 512M/' "$compose_file"
    sed -i '/grafana:/,/healthcheck:/ s/memory: 512M/memory: 256M/' "$compose_file"
    
    # Add Grafana memory optimization environment variables
    add_grafana_optimizations "$compose_file"
    
    # cAdvisor - reduced collection frequency
    sed -i 's/--housekeeping_interval=30s/--housekeeping_interval=60s/g' "$compose_file"
    sed -i '/cadvisor:/,/command:/ s/memory: 256M/memory: 128M/' "$compose_file"
    sed -i '/cadvisor:/,/command:/ s/memory: 128M/memory: 64M/' "$compose_file"
}

apply_standard_profile_config() {
    local compose_file="$1"
    log INFO "Configuring services for standard profile (balanced configuration)"
    
    # Keep existing resource limits but optimize for Pi 3/4
    # Prometheus - standard retention
    sed -i 's/--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}/--storage.tsdb.retention.time=15d/g' "$compose_file"
    
    # Add performance optimizations
    add_performance_optimizations "$compose_file"
}

apply_high_performance_profile_config() {
    local compose_file="$1"
    log INFO "Configuring services for high-performance profile (Pi 4/5 with 4GB+ RAM)"
    
    # Prometheus - increased resources and retention
    sed -i 's/memory: 2G/memory: 3G/g' "$compose_file"
    sed -i 's/memory: 1G/memory: 1.5G/g' "$compose_file"
    sed -i 's/--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}/--storage.tsdb.retention.time=30d/g' "$compose_file"
    
    # Grafana - increased memory and enable more plugins
    sed -i '/grafana:/,/healthcheck:/ s/memory: 1G/memory: 2G/' "$compose_file"
    sed -i '/grafana:/,/healthcheck:/ s/memory: 512M/memory: 1G/' "$compose_file"
    
    # Add high-performance Grafana plugins
    add_high_performance_grafana_config "$compose_file"
    
    # cAdvisor - more frequent collection
    sed -i 's/--housekeeping_interval=30s/--housekeeping_interval=15s/g' "$compose_file"
    
    # Enable additional monitoring services
    add_additional_monitoring_services "$compose_file"
}

apply_node_count_optimizations() {
    local compose_file="$1"
    local node_count="$2"
    
    log INFO "Applying optimizations for $node_count node(s)"
    
    if [[ $node_count -gt 3 ]]; then
        # For larger clusters, enable distributed monitoring
        log INFO "Enabling distributed monitoring for cluster with $node_count nodes"
        add_distributed_monitoring_config "$compose_file"
        
        # Increase Prometheus query concurrency for larger clusters
        add_prometheus_scaling_config "$compose_file" "$node_count"
    elif [[ $node_count -eq 1 ]]; then
        # Single node optimizations
        log INFO "Applying single-node optimizations"
        add_single_node_optimizations "$compose_file"
    fi
}

add_service_condition() {
    local compose_file="$1"
    local service_name="$2"
    local condition="$3"
    
    # Comment out service if condition is false
    if [[ "$condition" == "false" ]]; then
        sed -i "/^  $service_name:/,/^  [a-zA-Z]/ s/^/#/" "$compose_file"
        log INFO "Disabled service: $service_name"
    fi
}

add_grafana_optimizations() {
    local compose_file="$1"
    
    # Add memory optimization environment variables
    sed -i '/GF_INSTALL_PLUGINS=/a \
      - GF_DATABASE_MAX_IDLE_CONNECTIONS=2\
      - GF_DATABASE_MAX_OPEN_CONNECTIONS=5\
      - GF_RENDERING_SERVER_URL=\
      - GF_RENDERING_CALLBACK_URL=' "$compose_file"
}

add_performance_optimizations() {
    local compose_file="$1"
    
    # Add general performance optimizations
    sed -i '/prometheus:/a \
    environment:\
      - GOMAXPROCS=2' "$compose_file"
}

add_high_performance_grafana_config() {
    local compose_file="$1"
    
    # Add more plugins and increase database connections for high-performance
    sed -i 's/GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource/GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource,grafana-piechart-panel,grafana-worldmap-panel,grafana-polystat-panel/' "$compose_file"
    sed -i '/GF_INSTALL_PLUGINS=/a \
      - GF_DATABASE_MAX_IDLE_CONNECTIONS=10\
      - GF_DATABASE_MAX_OPEN_CONNECTIONS=20\
      - GF_EXPLORE_ENABLED=true\
      - GF_ALERTING_ENABLED=true' "$compose_file"
}

add_additional_monitoring_services() {
    local compose_file="$1"
    
    # Add Jaeger tracing service for high-performance clusters
    cat >> "$compose_file" << 'EOF'

  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"
      - "14268:14268"
    environment:
      - COLLECTOR_ZIPKIN_HTTP_PORT=9411
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

EOF
}

add_distributed_monitoring_config() {
    local compose_file="$1"
    
    # Add configurations for distributed monitoring
    sed -i '/prometheus:/a \
    environment:\
      - PROMETHEUS_REMOTE_WRITE_ENABLED=true' "$compose_file"
}

add_prometheus_scaling_config() {
    local compose_file="$1"
    local node_count="$2"
    
    # Calculate query concurrency based on node count
    local query_concurrency=$((node_count * 2))
    
    sed -i "/--alertmanager.notification-queue-capacity=10000/a \
      - '--query.max-concurrency=$query_concurrency'" "$compose_file"
}

add_single_node_optimizations() {
    local compose_file="$1"
    
    # Optimize for single node deployment
    sed -i '/node.role == manager/c \
          - node.role == manager' "$compose_file"
    
    # Reduce resource reservations for single node
    sed -i 's/reservations:/reservations:\
          cpus: "0.1"/' "$compose_file"
}

export_cluster_variables_for_deployment() {
    log INFO "Exporting cluster variables for adaptive deployment"
    
    # Export hardware-specific environment variables for docker-compose
    export CLUSTER_PROFILE="${CLUSTER_PROFILE:-standard}"
    export CLUSTER_MIN_MEMORY="${CLUSTER_MIN_MEMORY:-1024}"
    export CLUSTER_MIN_CPU_CORES="${CLUSTER_MIN_CPU_CORES:-4}"
    export CLUSTER_TOTAL_NODES="${CLUSTER_TOTAL_NODES:-1}"
    export CLUSTER_AVG_MEMORY="${CLUSTER_AVG_MEMORY:-${CLUSTER_MIN_MEMORY}}"
    export CLUSTER_TOTAL_MEMORY="${CLUSTER_TOTAL_MEMORY:-${CLUSTER_MIN_MEMORY}}"
    
    # Set resource limits based on cluster profile
    case "$CLUSTER_PROFILE" in
        "basic")
            export PROMETHEUS_RETENTION="3d"
            export PROMETHEUS_PORT="9090"
            export GRAFANA_PORT="3000"
            export PORTAINER_PORT="9443"
            export PORTAINER_HTTP_PORT="9000"
            ;;
        "lightweight")
            export PROMETHEUS_RETENTION="7d"
            export PROMETHEUS_PORT="9090"
            export GRAFANA_PORT="3000"
            export PORTAINER_PORT="9443"
            export PORTAINER_HTTP_PORT="9000"
            ;;
        "standard")
            export PROMETHEUS_RETENTION="15d"
            export PROMETHEUS_PORT="9090"
            export GRAFANA_PORT="3000"
            export PORTAINER_PORT="9443"
            export PORTAINER_HTTP_PORT="9000"
            ;;
        "high-performance")
            export PROMETHEUS_RETENTION="30d"
            export PROMETHEUS_PORT="9090"
            export GRAFANA_PORT="3000"
            export PORTAINER_PORT="9443"
            export PORTAINER_HTTP_PORT="9000"
            ;;
    esac
    
    log INFO "Cluster profile: $CLUSTER_PROFILE"
    log INFO "Prometheus retention: $PROMETHEUS_RETENTION"
    log INFO "Total cluster memory: ${CLUSTER_TOTAL_MEMORY}MB across $CLUSTER_TOTAL_NODES node(s)"
}

# Monitor cluster resource usage and provide optimization recommendations
monitor_cluster_resources() {
    local manager_ip="$1"
    
    if [[ "${CONTEXT_AWARE_DEPLOYMENT:-false}" != "true" ]]; then
        return 0  # Skip monitoring if context-aware deployment is not enabled
    fi
    
    log INFO "Monitoring cluster resource usage for optimization recommendations..."
    
    # Get current resource usage from all nodes
    local total_memory_usage=0
    local total_cpu_usage=0
    local node_count=0
    
    # Collect resource usage from all nodes
    for ip in "${PI_STATIC_IPS[@]}"; do
        local memory_usage
        local cpu_usage
        
        memory_usage=$(ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            free -m | awk '/^Mem:/ {printf \"%.0f\", \$3/\$2 * 100}'
        " 2>/dev/null || echo "0")
        
        cpu_usage=$(ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
            top -bn1 | grep \"Cpu(s)\" | sed \"s/.*, *\\([0-9.]*\\)%* id.*/\\1/\" | awk '{print 100 - \$1}'
        " 2>/dev/null || echo "0")
        
        total_memory_usage=$((total_memory_usage + memory_usage))
        total_cpu_usage=$((total_cpu_usage + cpu_usage))
        node_count=$((node_count + 1))
    done
    
    # Calculate averages
    local avg_memory_usage=$((total_memory_usage / node_count))
    local avg_cpu_usage=$((total_cpu_usage / node_count))
    
    log INFO "Cluster resource usage - Memory: ${avg_memory_usage}%, CPU: ${avg_cpu_usage}%"
    
    # Provide optimization recommendations
    provide_optimization_recommendations "$avg_memory_usage" "$avg_cpu_usage"
}

provide_optimization_recommendations() {
    local memory_usage="$1"
    local cpu_usage="$2"
    
    echo ""
    echo "🔍 RESOURCE USAGE ANALYSIS:"
    echo "   • Average Memory Usage: ${memory_usage}%"
    echo "   • Average CPU Usage: ${cpu_usage}%"
    echo "   • Current Profile: ${CLUSTER_PROFILE:-standard}"
    echo ""
    
    # Memory-based recommendations
    if [[ $memory_usage -gt 85 ]]; then
        echo "⚠️  HIGH MEMORY USAGE DETECTED:"
        echo "   • Consider upgrading to Raspberry Pi models with more RAM"
        echo "   • Switch to 'lightweight' profile to reduce memory footprint"
        echo "   • Disable non-essential services (Traefik, cAdvisor)"
        echo ""
    elif [[ $memory_usage -lt 30 && "$CLUSTER_PROFILE" == "basic" ]]; then
        echo "✅ LOW MEMORY USAGE DETECTED:"
        echo "   • Consider upgrading to 'standard' profile for more features"
        echo "   • You can enable additional monitoring services"
        echo ""
    fi
    
    # CPU-based recommendations
    if [[ $cpu_usage -gt 80 ]]; then
        echo "⚠️  HIGH CPU USAGE DETECTED:"
        echo "   • Consider distributing load across more Pi nodes"
        echo "   • Reduce monitoring collection frequency"
        echo "   • Switch to 'lightweight' profile"
        echo ""
    elif [[ $cpu_usage -lt 20 && "$CLUSTER_PROFILE" != "high-performance" ]]; then
        echo "✅ LOW CPU USAGE DETECTED:"
        echo "   • Consider upgrading to 'high-performance' profile"
        echo "   • You can enable more frequent monitoring collection"
        echo "   • Additional services like Jaeger tracing can be added"
        echo ""
    fi
    
    # Profile-specific recommendations
    case "$CLUSTER_PROFILE" in
        "basic")
            if [[ $memory_usage -lt 50 && $cpu_usage -lt 50 ]]; then
                echo "💡 OPTIMIZATION SUGGESTION:"
                echo "   • Your cluster can handle the 'lightweight' profile"
                echo "   • Run: ./deploy.sh and enable context-aware deployment with 'lightweight' profile"
                echo ""
            fi
            ;;
        "lightweight")
            if [[ $memory_usage -lt 40 && $cpu_usage -lt 40 ]]; then
                echo "💡 OPTIMIZATION SUGGESTION:"
                echo "   • Your cluster can handle the 'standard' profile"
                echo "   • This would enable Traefik and full cAdvisor monitoring"
                echo ""
            fi
            ;;
        "standard")
            if [[ $memory_usage -lt 35 && $cpu_usage -lt 35 ]]; then
                echo "💡 OPTIMIZATION SUGGESTION:"
                echo "   • Your cluster can handle the 'high-performance' profile"
                echo "   • This would enable extended retention, Jaeger tracing, and more plugins"
                echo ""
            fi
            ;;
    esac
}

# Function to help users switch cluster profiles
switch_cluster_profile() {
    local new_profile="$1"
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    if [[ -z "$new_profile" ]]; then
        echo "❌ Please specify a profile: basic, lightweight, standard, or high-performance"
        return 1
    fi
    
    log INFO "Switching cluster profile to: $new_profile"
    
    # Update cluster profile variable
    export CLUSTER_PROFILE="$new_profile"
    
    # Reconfigure and redeploy services
    configure_adaptive_services
    
    # Redeploy with new configuration
    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        cd ~/piswarm
        if docker compose version >/dev/null 2>&1; then
            docker compose -f docker-compose.adaptive.yml down
            docker compose -f docker-compose.adaptive.yml up -d
        elif docker-compose --version >/dev/null 2>&1; then
            docker-compose -f docker-compose.adaptive.yml down
            docker-compose -f docker-compose.adaptive.yml up -d
        fi
    "
    
    log INFO "Cluster profile switched to: $new_profile"
    echo "✅ Services redeployed with $new_profile profile configuration"
}
