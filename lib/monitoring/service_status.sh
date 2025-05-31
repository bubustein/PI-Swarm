#!/bin/bash

# Check health status of all deployed services
check_service_health() {
    local manager_ip="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Checking service health status..."
    
    # Check if all services are running
    local services_status
    services_status=$(ssh_exec "$manager_ip" "$user" "$pass" "docker service ls --format '{{.Name}} {{.Replicas}}'" 2>/dev/null)
    
    echo ""
    echo "🔍 SERVICE HEALTH CHECK:"
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local service_name=$(echo "$line" | awk '{print $1}')
            local replicas=$(echo "$line" | awk '{print $2}')
            
            if [[ "$replicas" =~ ^[0-9]+/[0-9]+$ ]]; then
                local running=$(echo "$replicas" | cut -d'/' -f1)
                local desired=$(echo "$replicas" | cut -d'/' -f2)
                
                if [[ "$running" == "$desired" ]]; then
                    echo "   ✅ $service_name: $replicas (Healthy)"
                else
                    echo "   ⚠️  $service_name: $replicas (Scaling/Starting)"
                fi
            else
                echo "   ❓ $service_name: $replicas (Unknown)"
            fi
        fi
    done <<< "$services_status"
}

# Test connectivity to all service endpoints
test_service_endpoints() {
    local manager_ip="$1"
    
    echo ""
    echo "🌐 ENDPOINT CONNECTIVITY TEST:"
    
    # Test Portainer HTTPS
    if timeout 5 curl -k -s "https://$manager_ip:9443/api/status" >/dev/null 2>&1; then
        echo "   ✅ Portainer HTTPS (9443): Accessible"
    else
        echo "   ❌ Portainer HTTPS (9443): Not accessible"
    fi
    
    # Test Portainer HTTP
    if timeout 5 curl -s "http://$manager_ip:9000" >/dev/null 2>&1; then
        echo "   ✅ Portainer HTTP (9000): Accessible"
    else
        echo "   ❌ Portainer HTTP (9000): Not accessible"
    fi
    
    # Test Grafana
    if timeout 5 curl -s "http://$manager_ip:3000/api/health" >/dev/null 2>&1; then
        echo "   ✅ Grafana (3000): Accessible"
    else
        echo "   ❌ Grafana (3000): Not accessible"
    fi
    
    # Test Prometheus
    if timeout 5 curl -s "http://$manager_ip:9090/-/healthy" >/dev/null 2>&1; then
        echo "   ✅ Prometheus (9090): Accessible"
    else
        echo "   ❌ Prometheus (9090): Not accessible"
    fi
    
    # Test Node Exporter on manager
    if timeout 5 curl -s "http://$manager_ip:9100/metrics" >/dev/null 2>&1; then
        echo "   ✅ Node Exporter (9100): Accessible"
    else
        echo "   ❌ Node Exporter (9100): Not accessible"
    fi
}

# Generate service access URLs and credentials
generate_access_info() {
    local manager_ip="$1"
    
    echo ""
    echo "📋 QUICK ACCESS REFERENCE:"
    echo ""
    echo "Copy and save these URLs for easy access:"
    echo ""
    echo "# Portainer (Container Management)"
    echo "https://$manager_ip:9443"
    echo "Username: admin"
    echo "Password: ${PORTAINER_PASSWORD:-piswarm123}"
    echo ""
    echo "# Grafana (Monitoring Dashboard)"  
    echo "http://$manager_ip:3000"
    echo "Username: admin"
    echo "Password: ${GRAFANA_PASSWORD:-admin}"
    echo ""
    echo "# Prometheus (Raw Metrics)"
    echo "http://$manager_ip:9090"
    echo ""
    echo "# Node Exporter (System Metrics)"
    echo "http://$manager_ip:9100/metrics"
    echo ""
}

export -f check_service_health test_service_endpoints generate_access_info
