#!/bin/bash
set -euo pipefail

# ---- Global Configuration ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_DIR="$SCRIPT_DIR/functions"
CONFIG_FILE="$SCRIPT_DIR/config.yml"
LOG_FILE="$SCRIPT_DIR/logs/piswarm-$(date +%Y%m%d).log"
BACKUP_DIR="$SCRIPT_DIR/backups"

# ---- Dependency and Environment Checks ----

REQUIRED_TOOLS=(sshpass ssh nmap awk sed grep tee curl docker docker-compose lsb_release ip sudo python3)
PYTHON_MIN_VERSION=3

missing_tools=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done

# Python check
if ! command -v python3 >/dev/null 2>&1; then
    missing_tools+=("python3")
elif ! python3 -c 'import sys; assert sys.version_info.major >= 3' 2>/dev/null; then
    echo "Python 3 is required."
    exit 1
fi

# Network check
if ! ping -c1 8.8.8.8 >/dev/null 2>&1 && ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
    echo "No internet/network connectivity detected. Please check your network."
    exit 1
fi

# Check sudo/root access
if [[ $EUID -ne 0 ]]; then
    if ! sudo -v >/dev/null 2>&1; then
        echo "This script requires sudo/root privileges to install dependencies."
        exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

if (( ${#missing_tools[@]} > 0 )); then
    echo "The following required tools are missing: ${missing_tools[*]}"
    echo "Attempting to install missing packages..."

    # Group tools by apt and special-case
    APT_TOOLS=()
    for t in "${missing_tools[@]}"; do
        case "$t" in
            docker)
                echo "Installing Docker using official script..."
                curl -fsSL https://get.docker.com | $SUDO sh
                ;;
            docker-compose)
                echo "Installing docker-compose (via apt)..."
                $SUDO apt-get update
                $SUDO apt-get install -y docker-compose
                ;;
            python3)
                echo "Installing python3..."
                $SUDO apt-get update
                $SUDO apt-get install -y python3
                ;;
            *)
                APT_TOOLS+=("$t")
                ;;
        esac
    done

    if (( ${#APT_TOOLS[@]} > 0 )); then
        echo "Installing via apt: ${APT_TOOLS[*]}"
        $SUDO apt-get update
        $SUDO apt-get install -y "${APT_TOOLS[@]}"
    fi

    # Final check
    still_missing=()
    for t in "${missing_tools[@]}"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            still_missing+=("$t")
        fi
    done
    if (( ${#still_missing[@]} > 0 )); then
        echo "ERROR: These tools could not be installed: ${still_missing[*]}"
        exit 1
    fi
fi

# Confirm that docker is running
if ! systemctl is-active --quiet docker; then
    echo "Docker is installed but not running. Attempting to start docker..."
    $SUDO systemctl start docker
    sleep 2
    if ! systemctl is-active --quiet docker; then
        echo "Docker could not be started. Please check your Docker installation."
        exit 1
    fi
fi

echo "All dependencies and environment checks passed."

### ---- Main Script Logic ----

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_DIR="$SCRIPT_DIR/functions"
LOG_FILE="$SCRIPT_DIR/logs/piswarm-$(date +%Y%m%d).log"

# Source core functions
source "$FUNCTIONS_DIR/log.sh"
source "$FUNCTIONS_DIR/ssh_secure.sh"
source "$FUNCTIONS_DIR/config_management.sh"
source "$FUNCTIONS_DIR/security.sh"

# Load all other functions
source "$FUNCTIONS_DIR/source_functions.sh"
source_functions

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Trap for cleanup and error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Script failed with exit code $exit_code"
        if [ -n "${LAST_BACKUP_DIR:-}" ]; then
            log INFO "Attempting to restore from backup: $LAST_BACKUP_DIR"
            for host in "${PI_IPS[@]:-}"; do
                if [ -d "$LAST_BACKUP_DIR/$host" ]; then
                    restore_device_config "$host" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS"
                fi
            done
        fi
    fi
    # Release any held locks
    release_lock || true
}
trap cleanup EXIT
trap 'log ERROR "Error on line $LINENO: $BASH_COMMAND"' ERR

# Discover Pis on the network (no credentials needed, runs locally)
discover_pis

# Perform security checks
if ! security_check; then
    log ERROR "Security checks failed. Please fix the issues before continuing."
    exit 1
fi

# After discovery, validate and log selected Pis
for ip in "${PI_IPS[@]}"; do
    if ! validate_input "$ip" "ip"; then
        log ERROR "Invalid IP address detected: $ip"
        exit 1
    fi
done

log INFO "Selected Pis: ${PI_IPS[*]}"
log INFO "Selected Hostnames: ${PI_HOSTNAMES[*]}"

# Get credentials from config or prompt
PI_USER=$(get_config_value ".nodes.default_user" "username" "" "true")
if [[ -z "$PI_USER" ]]; then
    while true; do
        read -rp "Enter SSH username for Pis: " PI_USER
        if validate_input "$PI_USER" "username"; then
            break
        fi
        log ERROR "Invalid username format. Use only alphanumeric characters, underscore, and hyphen."
    done
fi

PI_PASS=$(get_config_value ".nodes.default_pass" "password" "" "true")
if [[ -z "$PI_PASS" ]]; then
    while true; do
        read -srp "Enter SSH password for $PI_USER: " PI_PASS
        echo
        if [[ -n "$PI_PASS" ]]; then
            break
        fi
        log ERROR "Password cannot be empty."
    done
fi

# Export for function compatibility
export NODES_DEFAULT_USER="$PI_USER"
export NODES_DEFAULT_PASS="$PI_PASS"

declare -A PI_PER_HOST_USER
declare -A PI_PER_HOST_PASS

# Create backup directory for this run
LAST_BACKUP_DIR="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LAST_BACKUP_DIR"

# Configure each Pi
for PI_IP in "${PI_STATIC_IPS[@]}"; do
    SSH_USER="${PI_PER_HOST_USER[$PI_IP]:-$PI_USER}"
    SSH_PASS="${PI_PER_HOST_PASS[$PI_IP]:-$PI_PASS}"

    # Try to establish secure SSH connection
    if ! ssh_exec "$PI_IP" "$SSH_USER" "$SSH_PASS" "echo 'Testing connection'"; then
        log WARN "Initial connection failed for $PI_IP. Attempting key-based setup..."
        if ! setup_ssh_keys "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
            log ERROR "Failed to setup SSH keys for $PI_IP. Skipping this host."
            continue
        fi
    fi

    # Backup existing configuration
    if ! backup_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
        log ERROR "Failed to backup configuration for $PI_IP. Skipping this host."
        continue
    fi

    # Configure the Pi
    if ! configure_pi_headless "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
        log ERROR "Failed to configure $PI_IP. Attempting to restore from backup..."
        restore_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS"
        continue
    fi

    # Install and configure Docker
    if ! install_docker "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
        log ERROR "Failed to install Docker on $PI_IP. Attempting to restore from backup..."
        restore_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS"
        continue
    fi

    # Validate final configuration
    if ! validate_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
        log ERROR "Post-configuration validation failed for $PI_IP. Attempting to restore from backup..."
        restore_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS"
        continue
    fi

    log INFO "Successfully configured $PI_IP"
done

# Initialize swarm if configuration was successful for at least one Pi
if [[ ${#PI_STATIC_IPS[@]} -gt 0 ]]; then
    if ! init_swarm; then
        log ERROR "Failed to initialize Docker Swarm. Check the logs for details."
        exit 1
    fi

    # Deploy monitoring stack only if swarm initialization was successful
    if ! deploy_services; then
        log ERROR "Failed to deploy monitoring services. The swarm is running but monitoring is not configured."
        exit 1
    fi
else
    log ERROR "No Pis were successfully configured. Cannot initialize swarm."
    exit 1
fi

# Final validation of the entire cluster
log INFO "Validating cluster configuration..."
manager_ip="${PI_STATIC_IPS[0]}"
if ! ssh_exec "$manager_ip" "$PI_USER" "$PI_PASS" "docker node ls --format '{{.Hostname}} {{.Status}}' | grep -v 'Down'"; then
    log ERROR "Some nodes appear to be down or not properly joined to the swarm."
    exit 1
fi

log INFO "PISworm orchestration complete. Cluster is operational."
log INFO "Manager node: $manager_ip"
log INFO "Access Grafana at: http://$manager_ip:3000"
log INFO "Access Prometheus at: http://$manager_ip:9090"
