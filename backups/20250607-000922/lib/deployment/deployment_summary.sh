# deployment_summary.sh - Provides deployment completion summary

deployment_summary() {
    local success_count=0
    local failed_count=0
    local warnings=()
    
    echo ""
    echo "🏁 Pi-Swarm Deployment Summary"
    echo "================================"
    
    # Check if we have deployment status info
    if [[ -n "${PI_STATIC_IPS:-}" ]]; then
        echo "📊 Cluster Status:"
        for ip in ${PI_STATIC_IPS}; do
            if ssh_exec "$ip" "$PI_USER" "$PI_PASS" "docker info --format '{{.Swarm.LocalNodeState}}'" 2>/dev/null | grep -q "active"; then
                echo "  ✅ $ip - Docker Swarm Active"
                ((success_count++))
            else
                echo "  ❌ $ip - Docker Swarm Inactive or Unreachable"
                ((failed_count++))
            fi
        done
    fi
    
    # Service status
    if [[ $success_count -gt 0 ]]; then
        echo ""
        echo "🐳 Service Status:"
        manager_ip="${PI_STATIC_IPS%% *}"  # First IP
        if command -v check_service_health >/dev/null 2>&1; then
            check_service_health "$manager_ip" "$PI_USER" "$PI_PASS" 2>/dev/null || echo "  ⚠️  Service health check unavailable"
        else
            echo "  ℹ️  Service health check function not available"
        fi
    fi
    
    # SSL status
    echo ""
    echo "🔒 Security Status:"
    if [[ "$ENABLE_LETSENCRYPT" =~ ^(y|yes)$ ]] && [[ -n "${SSL_DOMAIN:-}" ]]; then
        echo "  ✅ Let's Encrypt SSL enabled for $SSL_DOMAIN"
    elif [[ -n "${SSL_DOMAIN:-}" ]]; then
        echo "  🔑 Self-signed SSL certificates generated"
    else
        echo "  ℹ️  SSL setup was skipped"
    fi
    
    # Overall status
    echo ""
    echo "📈 Overall Result:"
    if [[ $failed_count -eq 0 ]] && [[ $success_count -gt 0 ]]; then
        echo "  🎉 Deployment completed successfully!"
        echo "  🌐 Access your cluster at: http://${PI_STATIC_IPS%% *}:9000 (Portainer)"
        echo "  📊 Monitoring available at: http://${PI_STATIC_IPS%% *}:3000 (Grafana)"
    elif [[ $success_count -gt 0 ]]; then
        echo "  ⚠️  Deployment completed with warnings"
        echo "  🔧 Some components may need manual configuration"
    else
        echo "  ❌ Deployment failed"
        echo "  💡 Check the logs for detailed error information"
    fi
    
    # Next steps
    echo ""
    echo "🚀 Next Steps:"
    if [[ $success_count -gt 0 ]]; then
        echo "  1. Access Portainer: http://${PI_STATIC_IPS%% *}:9000"
        echo "  2. Access Grafana: http://${PI_STATIC_IPS%% *}:3000"
        echo "  3. Check cluster status: ./scripts/management/show-cluster-status.sh"
    else
        echo "  1. Check connectivity to your Raspberry Pis"
        echo "  2. Verify credentials and SSH access"
        echo "  3. Review deployment logs in data/logs/"
        echo "  4. Run comprehensive test: ./scripts/testing/comprehensive-test.sh"
    fi
}

export -f deployment_summary
