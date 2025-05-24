#!/bin/bash

# Validate and sanitize user input 
validate_input() {
    local input="$1"
    local type="$2"
    local allow_empty="${3:-false}"
    
    case "$type" in
        ip)
            if [[ -z "$input" ]] && [[ "$allow_empty" == "true" ]]; then
                return 0
            fi
            if ! [[ $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                return 1
            fi
            local IFS='.'
            read -ra ADDR <<< "$input"
            for i in "${ADDR[@]}"; do
                if ! [[ $i =~ ^[0-9]+$ ]] || [ $i -lt 0 ] || [ $i -gt 255 ]; then
                    return 1
                fi
            done
            ;;
        hostname)
            if [[ -z "$input" ]] && [[ "$allow_empty" == "true" ]]; then
                return 0
            fi
            if ! [[ $input =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                return 1
            fi
            if [ ${#input} -gt 63 ]; then
                return 1
            fi
            ;;
        username)
            if [[ -z "$input" ]] && [[ "$allow_empty" == "true" ]]; then
                return 0
            fi
            if ! [[ $input =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]]; then
                return 1
            fi
            ;;
        port)
            if [[ -z "$input" ]] && [[ "$allow_empty" == "true" ]]; then
                return 0
            fi
            if ! [[ $input =~ ^[0-9]+$ ]] || [ "$input" -lt 1 ] || [ "$input" -gt 65535 ]; then
                return 1
            fi
            ;;
        *)
            log ERROR "Unknown validation type: $type"
            return 1
            ;;
    esac
    return 0
}

# Secure configuration value getter with validation
get_config_value() {
    local key="$1"
    local type="$2"
    local default="$3"
    local allow_empty="${4:-false}"
    
    local value
    
    # Try to get from config file first
    if [[ -f "$CONFIG_FILE" ]]; then
        value=$(yq "$key" "$CONFIG_FILE" 2>/dev/null)
    fi
    
    # Use default if empty and default provided
    if [[ -z "$value" ]] && [[ -n "$default" ]]; then
        value="$default"
    fi
    
    # Validate value
    if ! validate_input "$value" "$type" "$allow_empty"; then
        log ERROR "Invalid configuration value for $key (type: $type): $value"
        return 1
    fi
    
    echo "$value"
}

# Security check of the environment
security_check() {
    local warnings=0
    local errors=0
    
    log INFO "Performing security checks..."
    
    # Check for sensitive files
    if [[ -f "$CONFIG_FILE" ]]; then
        if [[ "$(stat -c %a "$CONFIG_FILE")" != "600" ]]; then
            log ERROR "Configuration file has unsafe permissions: $CONFIG_FILE"
            ((errors++))
        fi
    fi
    
    # Check SSH directory permissions
    if [[ -d ~/.ssh ]]; then
        if [[ "$(stat -c %a ~/.ssh)" != "700" ]]; then
            log ERROR "SSH directory has unsafe permissions: ~/.ssh"
            ((errors++))
        fi
        
        for key_file in ~/.ssh/id_* ~/.ssh/known_hosts; do
            if [[ -f "$key_file" ]] && [[ "$(stat -c %a "$key_file")" != "600" ]]; then
                log ERROR "SSH key file has unsafe permissions: $key_file"
                ((errors++))
            fi
        done
    fi
    
    # Check for password auth
    if ssh -G localhost | grep -q "^preferredauthentications password"; then
        log WARN "SSH is configured to allow password authentication"
        ((warnings++))
    fi
    
    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        if [[ "$(stat -c %a /var/run/docker.sock)" != "660" ]]; then
            log WARN "Docker socket has potentially unsafe permissions"
            ((warnings++))
        fi
    fi
    
    # Report results
    if ((errors > 0)); then
        log ERROR "Security check found $errors error(s) and $warnings warning(s)"
        return 1
    elif ((warnings > 0)); then
        log WARN "Security check found $warnings warning(s)"
        return 0
    else
        log INFO "Security check passed"
        return 0
    fi
}
