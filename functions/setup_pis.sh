setup_pis() {
    log INFO "Setting up Pis..."

    for ip in "${PI_STATIC_IPS[@]}"; do
        log INFO "Setting up $ip..."
        sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$ip" '
            curl -fsSL https://get.docker.com | sh &&
            sudo usermod -aG docker $USER
        ' 2>/dev/null || {
            log WARN "SSH authentication failed for $ip. Prompting for new credentials."
            read -r -p "Enter SSH username for $ip: " NODES_DEFAULT_USER
            read -r -s -p "Enter SSH password for $NODES_DEFAULT_USER: " NODES_DEFAULT_PASS
            echo
            export NODES_DEFAULT_USER NODES_DEFAULT_PASS
            sshpass -p "$NODES_DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$NODES_DEFAULT_USER@$ip" '
                curl -fsSL https://get.docker.com | sh &&
                sudo usermod -aG docker $USER
            ' || {
                log ERROR "SSH authentication failed again for $ip. Skipping."
                continue
            }
        }
    done
}
