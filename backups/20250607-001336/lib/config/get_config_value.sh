#!/bin/bash
# get_config_value: Retrieve a value from the YAML config file or prompt if required
# Usage: get_config_value <yaml_path> <type> <default> <prompt_if_empty>
get_config_value() {
    local yaml_path="$1"
    local type="${2:-string}"
    local default_value="${3:-}"
    local prompt_if_empty="${4:-false}"
    local value

    # Use yq to extract the value
    value=$(yq "$yaml_path" "$CONFIG_FILE" 2>/dev/null | sed 's/^"//;s/"$//')
    if [[ -z "$value" || "$value" == "null" ]]; then
        value="$default_value"
    fi

    # Prompt if still empty and prompt_if_empty is true
    if [[ -z "$value" && "$prompt_if_empty" == "true" ]]; then
        case "$type" in
            username)
                while true; do
                    read -rp "Enter SSH username: " value
                    validate_input "$value" "username" && break || echo "Invalid username."
                done
                ;;
            password)
                while true; do
                    read -srp "Enter SSH password: " value; echo
                    [[ -n "$value" ]] && break || echo "Password cannot be empty."
                done
                ;;
            *)
                while true; do
                    read -rp "Enter value for $yaml_path: " value
                    [[ -n "$value" ]] && break || echo "Value cannot be empty."
                done
                ;;
        esac
    fi
    echo "$value"
}

export -f get_config_value
