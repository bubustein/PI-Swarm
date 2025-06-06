validate_connections() {
    log INFO "Validating SSH connections to Pis..."
    for IP in "${PI_IPS[@]}"; do
        if ! sshpass -p "$NODES_DEFAULT_PASS" ssh \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  -o StrictHostKeyChecking=no \
  "$NODES_DEFAULT_USER@$IP"
 "exit" &>/dev/null; then
            log ERROR "Cannot connect to $IP via SSH"
            exit 1
        fi
    done
    log INFO "All Pis are reachable via SSH."
}
export -f validate_connections
