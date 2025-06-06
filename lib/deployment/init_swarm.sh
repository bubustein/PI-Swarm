init_swarm() {
    log INFO "Initializing Docker Swarm..."

    local manager_ip="${PI_STATIC_IPS[0]}"

    # Try using Python service orchestrator first, fall back to direct commands
    if [[ -f "$PROJECT_ROOT/lib/python/service_orchestrator.py" ]] && command -v python3 >/dev/null 2>&1; then
        log INFO "Using Python service orchestrator for enhanced swarm management..."
        
        # Initialize swarm using Python orchestrator
        if python3 "$PROJECT_ROOT/lib/python/service_orchestrator.py" init-swarm \
            --manager-ip "$manager_ip" \
            --ssh-user "$NODES_DEFAULT_USER" \
            --ssh-password "$NODES_DEFAULT_PASS" \
            --worker-ips "${PI_STATIC_IPS[@]:1}"; then
            log INFO "Swarm initialized successfully using Python orchestrator"
            return 0
        else
            log WARN "Python orchestrator failed, falling back to direct commands"
        fi
    fi

    # Fallback to direct SSH commands
    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm init --advertise-addr $manager_ip"
    local join_token
    join_token=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm join-token -q worker")

    for ip in "${PI_STATIC_IPS[@]:1}"; do
        ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm join --token $join_token $manager_ip:2377"
        log INFO "$ip joined the Swarm."
    done
}
