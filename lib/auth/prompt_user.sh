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

# validate_input: Validate user input for various types
validate_input() {
    local value="$1"
    local type="$2"
    case "$type" in
        ip)
            [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] &&
            IFS='.' read -r o1 o2 o3 o4 <<< "$value" &&
            (( o1 >= 0 && o1 <= 255 && o2 >= 0 && o2 <= 255 && o3 >= 0 && o3 <= 255 && o4 >= 0 && o4 <= 255 ))
            ;;
        username)
            [[ -n "$value" && "$value" =~ ^[a-zA-Z0-9_-]+$ ]]
            ;;
        port)
            [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 && "$value" -lt 65536 ]]
            ;;
        password)
            [[ -n "$value" && "${#value}" -ge 6 ]]
            ;;
        *)
            return 1
            ;;
    esac
}

export -f prompt_user
