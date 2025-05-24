#!/bin/bash

prompt_user() {
    # Only prompt if not already set
    if [[ -z "$NODES_DEFAULT_USER" ]]; then
        read -r -p "Enter SSH username for Pis: " NODES_DEFAULT_USER
        export NODES_DEFAULT_USER
    fi
    if [[ -z "$NODES_DEFAULT_PASS" ]]; then
        read -r -s -p "Enter SSH password for $NODES_DEFAULT_USER: " NODES_DEFAULT_PASS
        echo
        export NODES_DEFAULT_PASS
    fi
}

export -f prompt_user
