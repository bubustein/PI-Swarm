#!/bin/bash

# Global backup directory
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"

# Create backup of critical files
backup_device_config() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local backup_path="$BACKUP_DIR/$host"
    
    log INFO "Creating configuration backup for $host..."
    
    # Ensure backup dir exists
    mkdir -p "$backup_path"
    
    # List of critical files to backup
    local files_to_backup=(
        "/etc/netplan/50-cloud-init.yaml"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/docker/daemon.json"
    )
    
    local success=true
    
    for file in "${files_to_backup[@]}"; do
        if ssh_exec "$host" "$user" "$pass" "test -f $file"; then
            local backup_file="$backup_path/$(basename "$file")"
            if ! scp_file "$user@$host:$file" "$backup_file" "$host" "$user" "$pass"; then
                log ERROR "Failed to backup $file from $host"
                success=false
            fi
        fi
    done
    
    if [[ "$success" == true ]]; then
        log INFO "Configuration backup completed for $host"
        return 0
    else
        log ERROR "Configuration backup failed for $host"
        return 1
    fi
}

# Restore configuration from backup
restore_device_config() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local backup_path="$BACKUP_DIR/$host"
    
    if [[ ! -d "$backup_path" ]]; then
        log ERROR "No backup found for $host at $backup_path"
        return 1
    fi
    
    log INFO "Restoring configuration for $host..."
    
    local success=true
    
    for backup_file in "$backup_path"/*; do
        local remote_path="/etc/$(basename "$backup_file")"
        if ! scp_file "$backup_file" "$remote_path" "$host" "$user" "$pass"; then
            log ERROR "Failed to restore $(basename "$backup_file") to $host"
            success=false
        fi
    done
    
    if [[ "$success" == true ]]; then
        # Apply netplan if it was restored
        if [[ -f "$backup_path/50-cloud-init.yaml" ]]; then
            if ! ssh_exec "$host" "$user" "$pass" "sudo netplan apply"; then
                log ERROR "Failed to apply restored netplan config on $host"
                success=false
            fi
        fi
        
        # Apply hostname if it was restored
        if [[ -f "$backup_path/hostname" ]]; then
            local hostname
            hostname=$(cat "$backup_path/hostname")
            if ! ssh_exec "$host" "$user" "$pass" "sudo hostnamectl set-hostname $hostname"; then
                log ERROR "Failed to restore hostname on $host"
                success=false
            fi
        fi
    fi
    
    if [[ "$success" == true ]]; then
        log INFO "Configuration successfully restored for $host"
        return 0
    else
        log ERROR "Configuration restore failed for $host"
        return 1
    fi
}

# Validate device configuration 
validate_device_config() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "Validating configuration on $host..."
    
    # Check network connectivity
    if ! ping -c 1 -W 2 "$host" >/dev/null; then
        log ERROR "Host $host is not responding to ping"
        return 1
    fi
    
    # Check SSH connectivity
    if ! ssh_exec "$host" "$user" "$pass" "exit" 2>/dev/null; then
        log ERROR "SSH connection failed to $host"
        return 1
    fi
    
    # Check critical services
    local services=("docker" "ssh")
    for svc in "${services[@]}"; do
        if ! ssh_exec "$host" "$user" "$pass" "systemctl is-active $svc" >/dev/null; then
            log ERROR "Service $svc is not running on $host"
            return 1
        fi
    done
    
    # Check Docker Swarm status if applicable
    if ssh_exec "$host" "$user" "$pass" "docker info --format '{{.Swarm.LocalNodeState}}'" | grep -q "active"; then
        if ! ssh_exec "$host" "$user" "$pass" "docker node ls >/dev/null 2>&1"; then
            log ERROR "Docker Swarm appears to be in an inconsistent state on $host"
            return 1
        fi
    fi
    
    log INFO "Configuration validation successful for $host"
    return 0
}
