deploy_services() {
    log INFO "Deploying monitoring stack..."
    local manager_ip="${PI_STATIC_IPS[0]}"
    sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$manager_ip" '
        cd ~/PISworm || exit 1
        docker compose -f docker-compose.monitoring.yml up -d
    '
    log INFO "Monitoring stack deployed."
}
