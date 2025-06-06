#!/bin/bash

sanitize_complete() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    echo "Testing function"
    read -p "Are you absolutely sure you want to proceed? (type YES to confirm): " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    echo "Continuing..."
}

echo "Test script works"
