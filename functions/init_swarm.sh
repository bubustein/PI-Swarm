init_swarm() {
    log INFO "Initializing Docker Swarm..."

    local manager_ip="${PI_STATIC_IPS[0]}"

    sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$manager_ip" 'docker swarm init --advertise-addr '$manager_ip
    local join_token
    join_token=$(sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$manager_ip" "docker swarm join-token -q worker")

    for ip in "${PI_STATIC_IPS[@]:1}"; do
        sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$ip" "docker swarm join --token $join_token $manager_ip:2377"
        log INFO "$ip joined the Swarm."
    done
}
