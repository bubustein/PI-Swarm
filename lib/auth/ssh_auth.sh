# functions/ssh_auth.sh

# pi_ssh_check <host> <user> <pass>
# Returns 0 on success, 1 on auth failure, 2 on connection failure
pi_ssh_check() {
    local host="$1"
    local user="$2"
    local pass="$3"

    sshpass -p "$pass" ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$user@$host" "exit" >/dev/null 2>&1
    local status=$?
    if [[ $status -eq 0 ]]; then
        return 0  # Success
    elif [[ $status -eq 5 || $status -eq 255 ]]; then
        return 1  # Auth failure
    else
        return 2  # Other failure
    fi
}

# Enhanced SSH check with user guidance
pi_ssh_check_with_guidance() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    local result
    result=$(pi_ssh_check "$host" "$user" "$pass")
    local status=$?
    
    if [[ $status -eq 1 ]]; then
        # Authentication failure - provide specific guidance
        if [[ "$user" == "root" ]]; then
            log WARN "SSH authentication failed for root@$host"
            log INFO "Root login is often disabled on Pi systems for security."
            log INFO "Try using your regular Pi user account (e.g., 'pi', 'ubuntu', etc.)"
            log INFO "If root has no password, consider enabling SSH keys or using a regular user."
        else
            log WARN "SSH authentication failed for $user@$host"
            log INFO "Please check your username and password."
            log INFO "Ensure SSH is enabled and the user account exists on the Pi."
        fi
    elif [[ $status -eq 2 ]]; then
        log WARN "SSH connection failed to $host"
        log INFO "Please check network connectivity and ensure SSH is running on the Pi."
    fi
    
    return $status
}
