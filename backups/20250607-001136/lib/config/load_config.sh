#!/bin/bash

load_config() {
    log INFO "Loading configuration from $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Use Python yq syntax (key paths as arguments, not with -e)
    NETWORK_INTERFACE=$(yq .network.interface "$CONFIG_FILE" | sed 's/^"//;s/"$//')
    NETWORK_STATIC_IPS_START_IP=$(yq .network.static_ips.start_ip "$CONFIG_FILE" | sed 's/^"//;s/"$//')
    NETWORK_SUBNET=$(yq .network.subnet "$CONFIG_FILE" | sed 's/^"//;s/"$//')
    NETWORK_GATEWAY=$(yq .network.gateway "$CONFIG_FILE" | sed 's/^"//;s/"$//')
    NETWORK_DNS=$(yq .network.dns "$CONFIG_FILE" | sed 's/^"//;s/"$//')

    NODES_DEFAULT_USER=$(yq .nodes.default_user "$CONFIG_FILE" | sed 's/^"//;s/"$//')
    NODES_DEFAULT_PASS=$(yq .nodes.default_pass "$CONFIG_FILE" | sed 's/^"//;s/"$//')

    export NETWORK_INTERFACE NETWORK_STATIC_IPS_START_IP NETWORK_SUBNET NETWORK_GATEWAY NETWORK_DNS
    export NODES_DEFAULT_USER NODES_DEFAULT_PASS
}

export -f load_config