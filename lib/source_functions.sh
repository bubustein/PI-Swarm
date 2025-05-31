source_functions() {
    # Prevent recursive loading
    if [[ "${FUNCTIONS_LOADED:-}" == "true" ]]; then
        return 0
    fi
    export FUNCTIONS_LOADED="true"
    
    # Load log.sh first since it's needed by this function
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    source "$script_dir/log.sh" || echo "Warning: Could not load log.sh"
    
    log INFO "Loading function files..."
    local loaded=0

    # Auto-detect lib directory if not set
    if [[ -z "${FUNCTIONS_DIR:-}" ]]; then
        if [[ -d "$(dirname "${BASH_SOURCE[0]}")" ]]; then
            FUNCTIONS_DIR="$(dirname "${BASH_SOURCE[0]}")"
        elif [[ -d "./lib" ]]; then
            FUNCTIONS_DIR="./lib"
        else
            log ERROR "Cannot find lib directory"
            return 1
        fi
    fi

    set +e  # Disable exit on error during sourcing
    declare -a essential_functions=(
        "config/validate_environment.sh"
        "auth/prompt_user.sh"  # Ensure validate_input is always loaded
        "acquire_lock.sh"
        "release_lock.sh"
        "networking/network_utilities.sh"
        "networking/discover_pis.sh"
        "networking/validate_network_config.sh"
        "deployment/setup_pis.sh"
        "deployment/init_swarm.sh"
        "deployment/deploy_services.sh"
        "deployment/deployment_summary.sh"
        "security/ssl_automation.sh"
        "config/get_config_value.sh" # Add get_config_value to essential functions
        "auth/ssh_secure.sh" # Add ssh_exec and setup_ssh_keys to essential functions
        "monitoring/service_status.sh" # Add service_status.sh to essential functions for deploy_services
        "deployment/configure_pi_headless.sh"
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

# Automatically call the function when this file is sourced
source_functions
