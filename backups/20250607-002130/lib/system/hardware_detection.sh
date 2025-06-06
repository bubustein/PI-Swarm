#!/bin/bash
# Hardware and OS Detection Module
# Detects system specifications and capabilities for context-aware deployment

# Detect hardware specifications of a target system
detect_hardware() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "🔍 Detecting hardware specifications for $host..."
    
    local hw_info=""
    
    # Gather comprehensive hardware information
    hw_info=$(ssh_exec "$host" "$user" "$pass" "
        echo '=== HARDWARE DETECTION ==='
        
        # CPU Information
        echo 'CPU_MODEL='\"$(grep '^model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)\"
        echo 'CPU_CORES='$(nproc)
        echo 'CPU_ARCH='$(uname -m)
        echo 'CPU_FREQ_MAX='$(lscpu | grep 'CPU max MHz' | awk '{print \$4}' | cut -d'.' -f1 || echo 'unknown')
        
        # Memory Information
        echo 'MEMORY_TOTAL_KB='$(grep '^MemTotal:' /proc/meminfo | awk '{print \$2}')
        echo 'MEMORY_TOTAL_MB='$(($(grep '^MemTotal:' /proc/meminfo | awk '{print \$2}') / 1024))
        echo 'MEMORY_AVAILABLE_MB='$(free -m | grep '^Mem:' | awk '{print \$7}')
        
        # Storage Information
        echo 'STORAGE_ROOT_TOTAL_GB='$(df -BG / | tail -1 | awk '{print \$2}' | tr -d 'G')
        echo 'STORAGE_ROOT_AVAILABLE_GB='$(df -BG / | tail -1 | awk '{print \$4}' | tr -d 'G')
        echo 'STORAGE_TYPE='$(lsblk -d -o name,rota | grep -v NAME | awk '{if(\$2==0) print \"SSD\"; else print \"HDD\"}' | head -1)
        
        # Network Information
        echo 'NETWORK_INTERFACES='\"$(ip -o link show | grep -v 'lo:' | awk -F': ' '{print \$2}' | tr '\n' ',' | sed 's/,\$//')\"
        echo 'NETWORK_SPEED='$(ethtool eth0 2>/dev/null | grep Speed | awk '{print \$2}' || echo 'unknown')
        
        # Hardware Platform Detection
        if [ -f /proc/device-tree/model ]; then
            echo 'HARDWARE_MODEL='\"$(cat /proc/device-tree/model | tr -d '\0')\"
        elif [ -f /sys/devices/virtual/dmi/id/product_name ]; then
            echo 'HARDWARE_MODEL='\"$(cat /sys/devices/virtual/dmi/id/product_name)\"
        else
            echo 'HARDWARE_MODEL=unknown'
        fi
        
        # Raspberry Pi specific detection
        if grep -q 'Raspberry Pi' /proc/device-tree/model 2>/dev/null; then
            echo 'IS_RASPBERRY_PI=true'
            echo 'PI_REVISION='$(cat /proc/cpuinfo | grep 'Revision' | awk '{print \$3}')
            echo 'PI_SERIAL='$(cat /proc/cpuinfo | grep 'Serial' | awk '{print \$3}')
        else
            echo 'IS_RASPBERRY_PI=false'
        fi
        
        # GPU Information (if available)
        if command -v vcgencmd >/dev/null 2>&1; then
            echo 'GPU_MEMORY_MB='$(vcgencmd get_mem gpu | cut -d'=' -f2 | tr -d 'M')
        fi
        
        # Temperature monitoring capability
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            echo 'TEMP_MONITORING=true'
            echo 'CURRENT_TEMP_C='$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
        else
            echo 'TEMP_MONITORING=false'
        fi
        
        # Power management
        if command -v vcgencmd >/dev/null 2>&1; then
            echo 'POWER_THROTTLING='$(vcgencmd get_throttled | cut -d'=' -f2)
        fi
        
        echo '=== END HARDWARE DETECTION ==='
    " 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$hw_info" ]]; then
        # Parse hardware information into associative array
        declare -gA "HW_${host//./_}"
        local array_name="HW_${host//./_}"
        
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                value="${value//\"/}"  # Remove quotes
                declare -g "${array_name}[$key]=$value"
            fi
        done <<< "$(echo "$hw_info" | grep '=')"
        
        log INFO "✅ Hardware detection completed for $host"
        return 0
    else
        log WARN "❌ Hardware detection failed for $host"
        return 1
    fi
}

# Detect operating system details
detect_os() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    log INFO "🔍 Detecting OS details for $host..."
    
    local os_info=""
    
    os_info=$(ssh_exec "$host" "$user" "$pass" "
        echo '=== OS DETECTION ==='
        
        # Basic OS Information
        echo 'OS_NAME='\"$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\"
        echo 'OS_VERSION='\"$(grep '^VERSION=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\"
        echo 'OS_ID='$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')
        echo 'OS_VERSION_ID='$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')
        echo 'OS_PRETTY_NAME='\"$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\"
        
        # Kernel Information
        echo 'KERNEL_VERSION='$(uname -r)
        echo 'KERNEL_ARCH='$(uname -m)
        
        # Package Manager Detection
        if command -v apt >/dev/null 2>&1; then
            echo 'PACKAGE_MANAGER=apt'
        elif command -v yum >/dev/null 2>&1; then
            echo 'PACKAGE_MANAGER=yum'
        elif command -v dnf >/dev/null 2>&1; then
            echo 'PACKAGE_MANAGER=dnf'
        elif command -v pacman >/dev/null 2>&1; then
            echo 'PACKAGE_MANAGER=pacman'
        else
            echo 'PACKAGE_MANAGER=unknown'
        fi
        
        # Init System Detection
        if pidof systemd >/dev/null; then
            echo 'INIT_SYSTEM=systemd'
        elif [ -f /sbin/openrc ]; then
            echo 'INIT_SYSTEM=openrc'
        else
            echo 'INIT_SYSTEM=sysv'
        fi
        
        # Container Runtime Detection
        if command -v docker >/dev/null 2>&1; then
            echo 'DOCKER_INSTALLED=true'
            echo 'DOCKER_VERSION='$(docker --version | awk '{print \$3}' | tr -d ',')
        else
            echo 'DOCKER_INSTALLED=false'
        fi
        
        if command -v podman >/dev/null 2>&1; then
            echo 'PODMAN_INSTALLED=true'
        else
            echo 'PODMAN_INSTALLED=false'
        fi
        
        # Python availability
        if command -v python3 >/dev/null 2>&1; then
            echo 'PYTHON3_VERSION='$(python3 --version | awk '{print \$2}')
        fi
        
        # Last boot time (uptime)
        echo 'UPTIME_DAYS='$(uptime | awk '{print \$3}' | tr -d ',')
        echo 'LOAD_AVERAGE='$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ',')
        
        echo '=== END OS DETECTION ==='
    " 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$os_info" ]]; then
        # Parse OS information into associative array
        declare -gA "OS_${host//./_}"
        local array_name="OS_${host//./_}"
        
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                value="${value//\"/}"  # Remove quotes
                declare -g "${array_name}[$key]=$value"
            fi
        done <<< "$(echo "$os_info" | grep '=')"
        
        log INFO "✅ OS detection completed for $host"
        return 0
    else
        log WARN "❌ OS detection failed for $host"
        return 1
    fi
}

# Generate system capabilities summary
generate_system_profile() {
    local host="$1"
    local hw_array="HW_${host//./_}"
    local os_array="OS_${host//./_}"
    
    # Use nameref to access associative arrays dynamically
    local -n hw_ref=$hw_array 2>/dev/null || { log WARN "No hardware data for $host"; return 1; }
    local -n os_ref=$os_array 2>/dev/null || { log WARN "No OS data for $host"; return 1; }
    
    echo ""
    echo "📋 System Profile: $host"
    echo "========================="
    echo "🖥️  Hardware:"
    echo "   Model: ${hw_ref[HARDWARE_MODEL]:-unknown}"
    echo "   CPU: ${hw_ref[CPU_MODEL]:-unknown} (${hw_ref[CPU_CORES]:-?} cores, ${hw_ref[CPU_ARCH]:-?})"
    echo "   Memory: ${hw_ref[MEMORY_TOTAL_MB]:-?}MB total, ${hw_ref[MEMORY_AVAILABLE_MB]:-?}MB available"
    echo "   Storage: ${hw_ref[STORAGE_ROOT_TOTAL_GB]:-?}GB total, ${hw_ref[STORAGE_ROOT_AVAILABLE_GB]:-?}GB free (${hw_ref[STORAGE_TYPE]:-unknown})"
    
    if [[ "${hw_ref[IS_RASPBERRY_PI]}" == "true" ]]; then
        echo "   🥧 Raspberry Pi detected (Revision: ${hw_ref[PI_REVISION]:-unknown})"
        if [[ -n "${hw_ref[CURRENT_TEMP_C]}" ]]; then
            echo "   🌡️  Temperature: ${hw_ref[CURRENT_TEMP_C]}°C"
        fi
    fi
    
    echo ""
    echo "💿 Operating System:"
    echo "   OS: ${os_ref[OS_PRETTY_NAME]:-unknown}"
    echo "   Kernel: ${os_ref[KERNEL_VERSION]:-unknown} (${os_ref[KERNEL_ARCH]:-?})"
    echo "   Package Manager: ${os_ref[PACKAGE_MANAGER]:-unknown}"
    echo "   Init System: ${os_ref[INIT_SYSTEM]:-unknown}"
    echo "   Docker: ${os_ref[DOCKER_INSTALLED]:-false} ${os_ref[DOCKER_VERSION]:+(${os_ref[DOCKER_VERSION]})}"
    echo "   Uptime: ${os_ref[UPTIME_DAYS]:-?} days, Load: ${os_ref[LOAD_AVERAGE]:-?}"
}

# Determine deployment strategy based on detected hardware/OS
determine_deployment_strategy() {
    local host="$1"
    local hw_array="HW_${host//./_}"
    local os_array="OS_${host//./_}"
    
    local -n hw_ref=$hw_array 2>/dev/null || return 1
    local -n os_ref=$os_array 2>/dev/null || return 1
    
    # Initialize strategy variables
    declare -gA "STRATEGY_${host//./_}"
    local strategy_array="STRATEGY_${host//./_}"
    local -n strategy_ref=$strategy_array
    
    # Memory-based optimizations
    local memory_mb=${hw_ref[MEMORY_TOTAL_MB]:-0}
    if (( memory_mb >= 8192 )); then
        strategy_ref[DEPLOYMENT_TYPE]="high_performance"
        strategy_ref[DOCKER_MEMORY_LIMIT]="2G"
        strategy_ref[ENABLE_ADVANCED_MONITORING]="true"
    elif (( memory_mb >= 4096 )); then
        strategy_ref[DEPLOYMENT_TYPE]="standard"
        strategy_ref[DOCKER_MEMORY_LIMIT]="1G"
        strategy_ref[ENABLE_ADVANCED_MONITORING]="true"
    elif (( memory_mb >= 2048 )); then
        strategy_ref[DEPLOYMENT_TYPE]="lightweight"
        strategy_ref[DOCKER_MEMORY_LIMIT]="512M"
        strategy_ref[ENABLE_ADVANCED_MONITORING]="false"
    else
        strategy_ref[DEPLOYMENT_TYPE]="minimal"
        strategy_ref[DOCKER_MEMORY_LIMIT]="256M"
        strategy_ref[ENABLE_ADVANCED_MONITORING]="false"
    fi
    
    # Storage-based optimizations
    local storage_gb=${hw_ref[STORAGE_ROOT_AVAILABLE_GB]:-0}
    if (( storage_gb >= 50 )); then
        strategy_ref[ENABLE_LOG_RETENTION]="true"
        strategy_ref[LOG_RETENTION_DAYS]="30"
    elif (( storage_gb >= 20 )); then
        strategy_ref[ENABLE_LOG_RETENTION]="true"
        strategy_ref[LOG_RETENTION_DAYS]="7"
    else
        strategy_ref[ENABLE_LOG_RETENTION]="false"
        strategy_ref[LOG_RETENTION_DAYS]="1"
    fi
    
    # CPU-based optimizations
    local cpu_cores=${hw_ref[CPU_CORES]:-1}
    if (( cpu_cores >= 4 )); then
        strategy_ref[DOCKER_CPU_LIMIT]="2"
        strategy_ref[PARALLEL_BUILDS]="true"
    elif (( cpu_cores >= 2 )); then
        strategy_ref[DOCKER_CPU_LIMIT]="1"
        strategy_ref[PARALLEL_BUILDS]="false"
    else
        strategy_ref[DOCKER_CPU_LIMIT]="0.5"
        strategy_ref[PARALLEL_BUILDS]="false"
    fi
    
    # OS-specific optimizations
    case "${os_ref[OS_ID]}" in
        "ubuntu")
            strategy_ref[PACKAGE_UPDATE_CMD]="apt-get update && apt-get upgrade -y"
            strategy_ref[PACKAGE_INSTALL_CMD]="apt-get install -y"
            strategy_ref[SERVICE_MANAGER]="systemctl"
            ;;
        "debian")
            strategy_ref[PACKAGE_UPDATE_CMD]="apt-get update && apt-get upgrade -y"
            strategy_ref[PACKAGE_INSTALL_CMD]="apt-get install -y"
            strategy_ref[SERVICE_MANAGER]="systemctl"
            ;;
        "centos"|"rhel")
            strategy_ref[PACKAGE_UPDATE_CMD]="yum update -y"
            strategy_ref[PACKAGE_INSTALL_CMD]="yum install -y"
            strategy_ref[SERVICE_MANAGER]="systemctl"
            ;;
        *)
            strategy_ref[PACKAGE_UPDATE_CMD]="echo 'Unknown package manager'"
            strategy_ref[PACKAGE_INSTALL_CMD]="echo 'Unknown package manager'"
            strategy_ref[SERVICE_MANAGER]="systemctl"
            ;;
    esac
    
    # Raspberry Pi specific optimizations
    if [[ "${hw_ref[IS_RASPBERRY_PI]}" == "true" ]]; then
        strategy_ref[ENABLE_GPU_MEMORY_SPLIT]="true"
        strategy_ref[ENABLE_HARDWARE_WATCHDOG]="true"
        strategy_ref[OPTIMIZE_FOR_SD_CARD]="true"
        
        # Temperature-based throttling
        if [[ -n "${hw_ref[CURRENT_TEMP_C]}" ]] && (( ${hw_ref[CURRENT_TEMP_C]} > 70 )); then
            strategy_ref[ENABLE_THERMAL_THROTTLING]="true"
            log WARN "High temperature detected on $host (${hw_ref[CURRENT_TEMP_C]}°C). Enabling thermal protection."
        fi
    fi
    
    log INFO "✅ Deployment strategy determined for $host: ${strategy_ref[DEPLOYMENT_TYPE]}"
}

# Export functions
export -f detect_hardware detect_os generate_system_profile determine_deployment_strategy
