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
