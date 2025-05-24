source_functions() {
    log INFO "Loading function files..."
    local loaded=0

    set +e  # Disable exit on error during sourcing
    declare -a essential_functions=(
        "validate_environment.sh"
        "acquire_lock.sh"
        "release_lock.sh"
        "network_utilities.sh"
        "discover_pis.sh"
        "validate_network_config.sh"
        "configure_static_ip.sh"
        "assign_pi_network_conf.sh"
        "setup_pis.sh"
        "init_swarm.sh"
        "deploy_services.sh"
        "log.sh"
    )

    for func in "${essential_functions[@]}"; do
        func_path="$FUNCTIONS_DIR/$func"
        log DEBUG "Checking for: $func_path"
        if [[ -f "$func_path" ]]; then
            log DEBUG "Sourcing: $func_path"
            source "$func_path"
            log DEBUG "Loaded: $func"
            ((loaded++))
        else
            log ERROR "Missing essential function file: $func_path"
            set -e
            exit 1
        fi
    done
    set -e  # Restore exit on error

    for func_file in "$FUNCTIONS_DIR"/*.sh; do
        if [[ -f "$func_file" ]] && [[ ! " ${essential_functions[*]} " =~ $(basename "$func_file") ]]; then
            source "$func_file"
            log DEBUG "Loaded extra: $(basename "$func_file")"
        fi
    done
    log INFO "Loaded $loaded essential functions."
}
