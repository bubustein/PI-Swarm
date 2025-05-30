init_swarm() {
    log INFO "Initializing Docker Swarm..."

    local manager_ip="${PI_STATIC_IPS[0]}"

    ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm init --advertise-addr $manager_ip"
    local join_token
    join_token=$(ssh_exec "$manager_ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm join-token -q worker")

    for ip in "${PI_STATIC_IPS[@]:1}"; do
        ssh_exec "$ip" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS" "docker swarm join --token $join_token $manager_ip:2377"
        log INFO "$ip joined the Swarm."
    done
}
