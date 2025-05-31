deploy_services() {
    local manager_ip="${PI_STATIC_IPS[0]}"
    
    log INFO "Deploying complete service stack (Monitoring + Portainer)..."
    
    # Load service status functions
    source "$FUNCTIONS_DIR/monitoring/service_status.sh"
    
    # Set environment variables for the deployment
    local portainer_password="${PORTAINER_PASSWORD:-piswarm123}"
    local grafana_password="${GRAFANA_PASSWORD:-admin}"
    
    # Create Portainer admin password file and deploy services, capturing output
    # Use ssh_exec for stack deployment, capturing and printing output
    stack_output=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "
        cd ~/PISworm || exit 1
        echo '[REMOTE] Creating Portainer admin password hash...'
        echo '$portainer_password' | docker run --rm -i portainer/helper-reset-password > admin_password 2>&1
        echo '[REMOTE] Running docker compose up (trying V2 first, fallback to V1)...'
        if docker compose version >/dev/null 2>&1; then
            docker compose -f docker-compose.monitoring.yml up -d 2>&1
        elif docker-compose --version >/dev/null 2>&1; then
            docker-compose -f docker-compose.monitoring.yml up -d 2>&1
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
    echo ""
    
    echo "🌐 WEB INTERFACES & ACCESS DETAILS:"
    echo ""
    echo "┌─ 🐳 PORTAINER (Container Management)"
    echo "│  ├─ HTTPS: https://$manager_ip:9443"
    echo "│  ├─ HTTP:  http://$manager_ip:9000"  
    echo "│  ├─ Username: admin"
    echo "│  └─ Password: ${PORTAINER_PASSWORD:-piswarm123}"
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
    echo "   2. Login with admin/piswarm123 and set a new password"
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
    sed -i "s/{{PORTAINER_PASSWORD}}/${PORTAINER_PASSWORD:-piswarm123}/g" "$dashboard_file"
    sed -i "s/{{GRAFANA_PASSWORD}}/${GRAFANA_PASSWORD:-admin}/g" "$dashboard_file"
    sed -i "s/{{SSH_USER}}/${NODES_DEFAULT_USER}/g" "$dashboard_file"
    
    log INFO "Web dashboard generated: $dashboard_file"
}
