validate_environment() {
    log INFO "Validating environment..."

    for cmd in sshpass ssh docker nmap; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "Missing required command: $cmd"
            exit 1
        fi
    done

    # Only prompt for credentials if not set
    if [[ -z "${NODES_DEFAULT_USER:-}" ]]; then
        read -r -p "Enter SSH username for Pis: " NODES_DEFAULT_USER
        export NODES_DEFAULT_USER
    fi
    if [[ -z "${NODES_DEFAULT_PASS:-}" ]]; then
        read -r -s -p "Enter SSH password for $NODES_DEFAULT_USER: " NODES_DEFAULT_PASS
        echo
        export NODES_DEFAULT_PASS
    fi

    log INFO "Environment OK"
}
