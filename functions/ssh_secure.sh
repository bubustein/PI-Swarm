#!/bin/bash

# Global variables for SSH options
SSH_OPTIONS=(
    -o ConnectTimeout=5 
    -o BatchMode=yes
    -o ServerAliveInterval=15
)

setup_ssh_keys() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Setting up SSH keys for $host..."
    
    # Generate key if needed
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        log INFO "Generating new SSH key pair..."
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa >/dev/null || {
            log ERROR "Failed to generate SSH keys"
            return 1
        }
    fi
    
    # Ensure .ssh directory exists on remote
    if ! sshpass -p "$pass" ssh -o StrictHostKeyChecking=accept-new "$user@$host" "mkdir -p ~/.ssh"; then
        log ERROR "Could not create .ssh directory on $host"
        return 1
    fi
    
    # Copy key
    if ! sshpass -p "$pass" ssh-copy-id -o StrictHostKeyChecking=accept-new "$user@$host" >/dev/null 2>&1; then
        log ERROR "Failed to copy SSH key to $host"
        return 1
    fi
    
    # Verify key-based authentication
    if ! timeout 5 ssh "${SSH_OPTIONS[@]}" "$user@$host" "echo 'SSH key auth successful'"; then
        log ERROR "SSH key authentication verification failed for $host"
        return 1
    fi
    
    log INFO "Successfully configured SSH keys for $host"
    return 0
}

# Wrapper for secure SSH commands
ssh_exec() {
    local host="$1"
    local user="$2"
    local pass="$3"
    shift 3
    local cmd="$*"
    
    # Try key-based auth first
    if timeout 5 ssh "${SSH_OPTIONS[@]}" "$user@$host" "$cmd" 2>/dev/null; then
        return 0
    fi
    
    # Fallback to password auth with sshpass
    if ! command -v sshpass >/dev/null 2>&1; then
        log ERROR "sshpass not installed but required for password auth"
        return 1
    fi
    
    if sshpass -p "$pass" ssh -o StrictHostKeyChecking=accept-new "$user@$host" "$cmd"; then
        # If successful with password, try to setup keys for future
        setup_ssh_keys "$host" "$user" "$pass"
        return 0
    fi
    
    return 1
}

# Secure file copy
scp_file() {
    local src="$1"
    local dest="$2"
    local host="$3"
    local user="$4"
    local pass="$5"
    
    # Try key-based auth first
    if timeout 5 scp "${SSH_OPTIONS[@]}" "$src" "$user@$host:$dest" 2>/dev/null; then
        return 0
    fi
    
    # Fallback to password with sshpass
    if sshpass -p "$pass" scp -o StrictHostKeyChecking=accept-new "$src" "$user@$host:$dest"; then
        setup_ssh_keys "$host" "$user" "$pass"
        return 0
    fi
    
    return 1
}
