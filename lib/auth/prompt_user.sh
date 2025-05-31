#!/bin/bash

prompt_user() {
    # Only prompt if not already set
    if [[ -z "$NODES_DEFAULT_USER" ]]; then
        echo ""
        echo "🔐 SSH Authentication Setup"
        echo "Enter the username for your Raspberry Pi accounts."
        echo "⚠️  Note: Do not use 'root' - use your regular Pi user account (e.g., 'pi', 'ubuntu', etc.)"
        echo ""
        read -r -p "Enter SSH username for Pis: " NODES_DEFAULT_USER
        
        # Validate and warn about root usage
        if [[ "$NODES_DEFAULT_USER" == "root" ]]; then
            echo ""
            echo "⚠️  WARNING: Using 'root' is not recommended and may fail!"
            echo "   Most Pi setups disable root login for security."
            echo "   Consider using your regular user account instead."
            echo ""
            read -r -p "Continue with root anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Please enter your regular Pi username:"
                read -r -p "Enter SSH username for Pis: " NODES_DEFAULT_USER
            fi
        fi
        
        export NODES_DEFAULT_USER
    fi
    if [[ -z "$NODES_DEFAULT_PASS" ]]; then
        read -r -s -p "Enter SSH password for $NODES_DEFAULT_USER: " NODES_DEFAULT_PASS
        echo
        export NODES_DEFAULT_PASS
    fi
}

export -f prompt_user
