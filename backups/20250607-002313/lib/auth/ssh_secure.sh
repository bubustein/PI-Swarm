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
    
    # Ensure .ssh directory exists on remote using password auth
    if ! sshpass -p "$pass" ssh -o StrictHostKeyChecking=accept-new "$user@$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 2>/dev/null; then
        log WARN "Could not create .ssh directory on $host (may require manual setup)"
        return 1
    fi
    
    # Copy key using password auth
    if ! sshpass -p "$pass" ssh-copy-id -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=yes -o PubkeyAuthentication=no "$user@$host" >/dev/null 2>&1; then
        log WARN "Failed to copy SSH key to $host (will use password authentication)"
        return 1
    fi
    
    # Verify key-based authentication works
    if timeout 5 ssh "${SSH_OPTIONS[@]}" -o PasswordAuthentication=no "$user@$host" "echo 'SSH key auth successful'" >/dev/null 2>&1; then
        log INFO "Successfully configured SSH keys for $host"
        return 0
    else
        log WARN "SSH key authentication verification failed for $host (continuing with password auth)"
        return 1
    fi
}

# Wrapper for secure SSH commands
ssh_exec() {
    local host="$1"
    local user="$2"
    local pass="$3"
    shift 3
    local cmd="$*"
    
    # Try key-based auth first (only if keys should exist)
    if [[ -f ~/.ssh/id_rsa ]] && timeout 5 ssh "${SSH_OPTIONS[@]}" -o PasswordAuthentication=no "$user@$host" "$cmd" 2>/dev/null; then
        return 0
    fi
    
    # Use password auth with sshpass
    if ! command -v sshpass >/dev/null 2>&1; then
        log ERROR "sshpass not installed but required for password auth"
        return 1
    fi
    
    if sshpass -p "$pass" ssh -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=yes "$user@$host" "$cmd" 2>/dev/null; then
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
    
    # Check if source file exists
    if [[ ! -f "$src" ]]; then
        echo "ERROR: Source file '$src' does not exist" >&2
        return 1
    fi
    
    # Try key-based auth first (only if keys should exist)
    if [[ -f ~/.ssh/id_rsa ]]; then
        if timeout 5 scp "${SSH_OPTIONS[@]}" -o PasswordAuthentication=no "$src" "$user@$host:$dest" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Use password auth with sshpass, capture errors
    local scp_error
    scp_error=$(sshpass -p "$pass" scp -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=yes "$src" "$user@$host:$dest" 2>&1)
    if [[ $? -eq 0 ]]; then
        return 0
    else
        echo "ERROR: SCP failed for $src -> $user@$host:$dest - $scp_error" >&2
        return 1
    fi
}

# Secure file download (from remote to local)
scp_download() {
    local remote_src="$1"
    local local_dest="$2"
    local host="$3"
    local user="$4"
    local pass="$5"
    
    # Try key-based auth first (only if keys should exist)
    if [[ -f ~/.ssh/id_rsa ]] && timeout 5 scp "${SSH_OPTIONS[@]}" -o PasswordAuthentication=no "$user@$host:$remote_src" "$local_dest" 2>/dev/null; then
        return 0
    fi
    
    # Use password auth with sshpass
    if sshpass -p "$pass" scp -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=yes "$user@$host:$remote_src" "$local_dest" 2>/dev/null; then
        return 0
    fi
    
    return 1
}
