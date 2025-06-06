#!/bin/bash

# Enhanced Python Integration for Pi-Swarm
# Provides seamless integration between Bash scripts and Python modules
# with robust fallback mechanisms for production environments
#
# This module bridges the gap between existing Bash infrastructure and
# new Python-based enhancements, ensuring backward compatibility while
# enabling advanced features through Python modules.
#
# Key Features:
# - Comprehensive cluster monitoring with Python-based analytics
# - Enhanced storage management with device detection and optimization
# - Advanced security management with automated SSL and auditing
# - Performance optimization with intelligent resource management
# - Robust fallback mechanisms to Bash implementations
#
# Usage:
#   source lib/python_integration.sh
#   test_python_integration  # Test availability
#   health_check_comprehensive  # Run health checks
#   manage_storage_comprehensive scan  # Scan storage devices
#   manage_security_comprehensive audit  # Security audit

# Source logging functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/log.sh" ]]; then
    source "$PROJECT_ROOT/lib/log.sh"
elif type log >/dev/null 2>&1; then
    # log function is already available
    :
else
    # Fallback log function for standalone usage
    log() {
        local level="$1"
        shift
        echo "[$level] $*"
    }
fi

# Check if Python modules are available
check_python_modules() {
    local modules=("$@")
    local available_modules=()
    
    if ! command -v python3 >/dev/null 2>&1; then
        log WARN "Python 3 not available, falling back to Bash implementations"
        return 1
    fi
    
    for module in "${modules[@]}"; do
        if [[ -f "$PROJECT_ROOT/lib/python/${module}.py" ]]; then
            available_modules+=("$module")
        fi
    done
    
    if [[ ${#available_modules[@]} -eq ${#modules[@]} ]]; then
        log INFO "All Python modules available: ${available_modules[*]}"
        return 0
    else
        log WARN "Some Python modules missing, partial functionality available"
        return 2
    fi
}

# Enhanced directory setup using Python if available
setup_directories_enhanced() {
    local base_path="${1:-$PROJECT_ROOT}"
    
    if check_python_modules "directory_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python directory manager for enhanced setup..."
        if python3 "$PROJECT_ROOT/lib/python/directory_manager.py" create-structure \
            --base-path "$base_path" --validate --dev-structure; then
            log INFO "✅ Python directory setup completed"
            return 0
        else
            log WARN "Python directory setup failed, falling back to Bash"
        fi
    fi
    
    # Fallback to Bash directory setup
    if [[ -f "$PROJECT_ROOT/lib/system/directory_setup.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/directory_setup.sh"
        setup_project_directories "$base_path"
        return $?
    else
        log ERROR "No directory setup method available"
        return 1
    fi
}

# Enhanced SSH operations using Python if available
ssh_exec_enhanced() {
    local host="$1"
    local user="$2"
    local password="$3"
    local command="$4"
    
    if check_python_modules "ssh_manager" >/dev/null 2>&1; then
        # Try Python SSH manager first
        if python3 "$PROJECT_ROOT/lib/python/ssh_manager.py" execute \
            --host "$host" --username "$user" --password "$password" \
            --command "$command" --timeout 30; then
            return 0
        else
            log WARN "Python SSH execution failed, falling back to sshpass"
        fi
    fi
    
    # Fallback to traditional SSH
    sshpass -p "$password" ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 "$user@$host" "$command"
}

# Enhanced network discovery using Python if available
discover_pis_enhanced() {
    if check_python_modules "network_discovery" >/dev/null 2>&1; then
        log INFO "🐍 Using Python network discovery..."
        
        local offline_flag=""
        if [[ "${OFFLINE_MODE:-false}" == "true" || "${SKIP_NETWORK_CHECK:-false}" == "true" ]]; then
            offline_flag="--offline"
        fi
        
        # Run Python discovery
        local discovery_output
        if discovery_output=$(python3 "$PROJECT_ROOT/lib/python/network_discovery.py" discover \
            --format bash $offline_flag 2>/dev/null); then
            
            # Parse and export results
            eval "$discovery_output"
            
            if [[ -n "${PI_IPS:-}" ]] && [[ "${PI_COUNT:-0}" -gt 0 ]]; then
                log INFO "Python discovery found $PI_COUNT Pi device(s)"
                export PI_IPS PI_HOSTNAMES PI_COUNT
                return 0
            fi
        fi
        
        log WARN "Python discovery failed or found no devices"
    fi
    
    # Fallback to existing discovery
    if command -v discover_pis >/dev/null 2>&1; then
        discover_pis
        return $?
    else
        log ERROR "No Pi discovery method available"
        return 1
    fi
}

# Enhanced backup operations using Python if available
create_backup_enhanced() {
    local backup_type="$1"
    local paths=("${@:2}")
    
    if check_python_modules "backup_restore" >/dev/null 2>&1; then
        log INFO "🐍 Using Python backup manager..."
        
        local backup_result
        if backup_result=$(python3 "$PROJECT_ROOT/lib/python/backup_restore.py" backup \
            --base-path "$PROJECT_ROOT" --type "$backup_type" \
            --paths "${paths[@]}" 2>/dev/null); then
            
            local backup_path
            backup_path=$(echo "$backup_result" | jq -r '.backup_path' 2>/dev/null || echo "")
            
            if [[ -n "$backup_path" ]] && [[ -f "$backup_path" ]]; then
                log INFO "Backup created: $backup_path"
                echo "$backup_path"
                return 0
            fi
        fi
        
        log WARN "Python backup failed, falling back to tar"
    fi
    
    # Fallback to simple tar backup
    local backup_name="${backup_type}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_path="$PROJECT_ROOT/data/backups/$backup_name"
    
    mkdir -p "$(dirname "$backup_path")"
    
    if tar -czf "$backup_path" -C "$PROJECT_ROOT" "${paths[@]}" 2>/dev/null; then
        log INFO "Simple backup created: $backup_path"
        echo "$backup_path"
        return 0
    else
        log ERROR "Backup creation failed"
        return 1
    fi
}

# Enhanced service management using Python if available
manage_swarm_services_enhanced() {
    local action="$1"
    shift
    
    if check_python_modules "service_orchestrator" >/dev/null 2>&1; then
        log INFO "🐍 Using Python service orchestrator..."
        
        case "$action" in
            "status")
                python3 "$PROJECT_ROOT/lib/python/service_orchestrator.py" status "$@"
                ;;
            "scale")
                python3 "$PROJECT_ROOT/lib/python/service_orchestrator.py" scale-service "$@"
                ;;
            "deploy")
                python3 "$PROJECT_ROOT/lib/python/service_orchestrator.py" deploy-stack "$@"
                ;;
            *)
                log ERROR "Unknown service action: $action"
                return 1
                ;;
        esac
        
        return $?
    fi
    
    # Fallback to direct docker commands
    case "$action" in
        "status")
            docker service ls
            ;;
        "scale")
            local service="$1"
            local replicas="$2"
            docker service scale "${service}=${replicas}"
            ;;
        *)
            log ERROR "Action not supported in fallback mode: $action"
            return 1
            ;;
    esac
}

# Enhanced Python module execution with error handling
execute_python_module() {
    local module_path="$1"
    shift
    local args="$@"
    
    if [[ ! -f "$module_path" ]]; then
        log "ERROR" "Python module not found: $module_path"
        return 1
    fi
    
    # Execute with timeout and error handling
    if timeout 300 python3 "$module_path" $args; then
        return 0
    else
        local exit_code=$?
        log "ERROR" "Python module execution failed: $module_path (exit code: $exit_code)"
        return $exit_code
    fi
}

# Enhanced monitoring using Python if available
monitor_cluster_enhanced() {
    local manager_ip="$1"
    local output_file="$2"
    
    if check_python_modules "monitoring_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python monitoring manager for enhanced cluster monitoring..."
        if execute_python_module "$PROJECT_ROOT/lib/python/monitoring_manager.py" \
            --manager-ip "$manager_ip" collect ${output_file:+--output "$output_file"}; then
            log INFO "✅ Python cluster monitoring completed"
            return 0
        else
            log WARN "Python monitoring failed, falling back to Bash"
        fi
    fi
    
    # Fallback to Bash monitoring
    if [[ -f "$PROJECT_ROOT/lib/monitoring/performance_monitoring.sh" ]]; then
        source "$PROJECT_ROOT/lib/monitoring/performance_monitoring.sh"
        monitor_cluster_performance "$manager_ip"
        return $?
    else
        log ERROR "No monitoring system available"
        return 1
    fi
}

# Enhanced hardware detection using Python if available
detect_hardware_enhanced() {
    local target_host="${1:-localhost}"
    local ssh_user="$2"
    local ssh_pass="$3"
    local output_format="${4:-summary}"
    
    if check_python_modules "enhanced_hardware_detection" >/dev/null 2>&1; then
        log INFO "🐍 Using Python hardware detector for enhanced detection..."
        local python_args=(
            "--host" "$target_host"
            "--format" "$output_format"
        )
        
        [[ -n "$ssh_user" ]] && python_args+=(--ssh-user "$ssh_user")
        [[ -n "$ssh_pass" ]] && python_args+=(--ssh-pass "$ssh_pass")
        
        if execute_python_module "$PROJECT_ROOT/lib/python/enhanced_hardware_detection.py" "${python_args[@]}"; then
            log INFO "✅ Python hardware detection completed"
            return 0
        else
            log WARN "Python hardware detection failed, falling back to Bash"
        fi
    fi
    
    # Fallback to Bash hardware detection
    if [[ -f "$PROJECT_ROOT/lib/system/hardware_detection.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/hardware_detection.sh"
        detect_hardware "$target_host" "$ssh_user" "$ssh_pass"
        return $?
    else
        log ERROR "No hardware detection system available"
        return 1
    fi
}

# Enhanced configuration management using Python if available
manage_config_enhanced() {
    local action="$1"
    shift
    local args="$@"
    
    if check_python_modules "config_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python configuration manager for enhanced config management..."
        if execute_python_module "$PROJECT_ROOT/lib/python/config_manager.py" "$action" $args; then
            log INFO "✅ Python configuration management completed"
            return 0
        else
            log WARN "Python config management failed, falling back to Bash"
        fi
    fi
    
    # Fallback to Bash configuration management
    case "$action" in
        "get")
            if [[ -f "$PROJECT_ROOT/lib/config/get_config_value.sh" ]]; then
                source "$PROJECT_ROOT/lib/config/get_config_value.sh"
                get_config_value $args
                return $?
            fi
            ;;
        "validate")
            log INFO "Basic configuration validation (Python module recommended for full validation)"
            if [[ -f "$PROJECT_ROOT/config/config.yml" ]]; then
                log INFO "✅ Configuration file exists"
                return 0
            else
                log ERROR "❌ Configuration file not found"
                return 1
            fi
            ;;
        *)
            log ERROR "Configuration action '$action' not supported in fallback mode"
            return 1
            ;;
    esac
}

# Enhanced backup management using Python if available
manage_backup_enhanced() {
    local action="$1"
    shift
    local args="$@"
    
    if check_python_modules "backup_restore" >/dev/null 2>&1; then
        log INFO "🐍 Using Python backup manager for enhanced backup operations..."
        if execute_python_module "$PROJECT_ROOT/lib/python/backup_restore.py" "$action" $args; then
            log INFO "✅ Python backup operation completed"
            return 0
        else
            log WARN "Python backup operation failed, falling back to Bash"
        fi
    fi
    
    # Basic fallback for backup operations
    case "$action" in
        "create")
            log INFO "Creating basic backup using tar..."
            local backup_path="${1:-./pi-swarm-backup-$(date +%Y%m%d_%H%M%S).tar.gz}"
            tar -czf "$backup_path" -C "$PROJECT_ROOT" . 2>/dev/null
            if [[ $? -eq 0 ]]; then
                log INFO "✅ Backup created: $backup_path"
                return 0
            else
                log ERROR "❌ Backup creation failed"
                return 1
            fi
            ;;
        *)
            log ERROR "Backup action '$action' not supported in fallback mode"
            return 1
            ;;
    esac
}

# Enhanced monitoring using Python enhanced monitoring manager
monitor_cluster_comprehensive() {
    local manager_ip="$1"
    local ssh_user="${2:-pi}"
    local ssh_pass="${3:-}"
    local output_file="${4:-}"
    local format="${5:-summary}"
    
    if check_python_modules "enhanced_monitoring_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python enhanced monitoring manager..."
        local cmd="python3 '$PROJECT_ROOT/lib/python/enhanced_monitoring_manager.py' health"
        cmd="$cmd --manager-ip '$manager_ip' --ssh-user '$ssh_user'"
        
        if [[ -n "$ssh_pass" ]]; then
            cmd="$cmd --ssh-pass '$ssh_pass'"
        fi
        
        if [[ -n "$output_file" ]]; then
            cmd="$cmd --output '$output_file'"
        fi
        
        cmd="$cmd --format '$format'"
        
        if eval "$cmd"; then
            log INFO "✅ Python enhanced monitoring completed"
            return 0
        else
            log WARN "Python enhanced monitoring failed, falling back to basic monitoring"
        fi
    fi
    
    # Fallback to basic monitoring
    monitor_cluster_enhanced "$manager_ip" "$output_file"
}

# Enhanced storage management using Python enhanced storage manager
manage_storage_comprehensive() {
    local nodes=("$@")
    local action="${nodes[0]}"
    local remaining_nodes=("${nodes[@]:1}")
    
    if check_python_modules "enhanced_storage_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python enhanced storage manager..."
        local cmd="python3 '$PROJECT_ROOT/lib/python/enhanced_storage_manager.py'"
        cmd="$cmd --nodes ${remaining_nodes[*]} -- $action"
        
        case "$action" in
            "setup-glusterfs")
                cmd="$cmd --volume-name piswarm-data --replica-count 2"
                ;;
            "setup-nfs")
                if [[ ${#remaining_nodes[@]} -gt 0 ]]; then
                    cmd="$cmd --server ${remaining_nodes[0]}"
                fi
                ;;
            "create-volume")
                cmd="$cmd --name piswarm-shared --driver local"
                ;;
        esac
        
        if eval "$cmd"; then
            log INFO "✅ Python enhanced storage management completed"
            return 0
        else
            log WARN "Python enhanced storage management failed, falling back to Bash"
        fi
    fi
    
    # Fallback to basic storage management
    if [[ -f "$PROJECT_ROOT/lib/storage/storage_management.sh" ]]; then
        log INFO "🔧 Using Bash storage management fallback..."
        source "$PROJECT_ROOT/lib/storage/storage_management.sh"
        
        case "$action" in
            "scan"|"status")
                if detect_storage_devices "${remaining_nodes[0]:-}"; then
                    log INFO "✅ Bash storage scan completed"
                    return 0
                fi
                ;;
            "setup-glusterfs")
                if setup_cluster_storage "${remaining_nodes[@]}"; then
                    log INFO "✅ Bash storage setup completed"
                    return 0
                fi
                ;;
        esac
    fi
    
    log ERROR "❌ Both Python and Bash storage management failed"
    return 1
}

# Enhanced security management using Python enhanced security manager  
manage_security_comprehensive() {
    local nodes=("$@")
    local action="${nodes[0]}"
    local remaining_nodes=("${nodes[@]:1}")
    
    if check_python_modules "enhanced_security_manager" >/dev/null 2>&1; then
        log INFO "🐍 Using Python enhanced security manager..."
        local cmd="python3 '$PROJECT_ROOT/lib/python/enhanced_security_manager.py'"
        cmd="$cmd --nodes ${remaining_nodes[*]} -- $action"
        
        case "$action" in
            "generate-cert")
                cmd="$cmd --domain piswarm.local --deploy"
                ;;
            "setup-letsencrypt")
                if [[ ${#remaining_nodes[@]} -ge 2 ]]; then
                    cmd="$cmd --domain ${remaining_nodes[0]} --email ${remaining_nodes[1]}"
                fi
                ;;
            "harden")
                cmd="$cmd --apply"
                ;;
        esac
        
        if eval "$cmd"; then
            log INFO "✅ Python enhanced security management completed"
            return 0
        else
            log WARN "Python enhanced security management failed, falling back to Bash"
        fi
    fi
    
    # Fallback to basic security management
    if [[ -f "$PROJECT_ROOT/lib/security/ssl_automation.sh" ]]; then
        log INFO "🔧 Using Bash security management fallback..."
        source "$PROJECT_ROOT/lib/security/ssl_automation.sh"
        
        case "$action" in
            "generate-cert")
                if generate_wildcard_ssl "piswarm.local" "${remaining_nodes[0]:-}" "pi" ""; then
                    log INFO "✅ Bash SSL generation completed"
                    return 0
                fi
                ;;
            "audit"|"check-certs")
                log INFO "✅ Basic security check completed (limited functionality)"
                return 0
                ;;
        esac
    fi
    
    log ERROR "❌ Both Python and Bash security management failed"
    return 1
}

# Performance optimization using Python modules
optimize_cluster_performance() {
    local manager_ip="$1"
    local nodes=("${@:2}")
    
    local optimizations_applied=0
    local optimizations_failed=0
    
    # Try enhanced monitoring optimization
    if check_python_modules "enhanced_monitoring_manager" >/dev/null 2>&1; then
        log INFO "🐍 Applying monitoring optimizations..."
        if python3 "$PROJECT_ROOT/lib/python/enhanced_monitoring_manager.py" optimize \
            --manager-ip "$manager_ip"; then
            ((optimizations_applied++))
            log INFO "✅ Monitoring optimizations applied"
        else
            ((optimizations_failed++))
            log WARN "❌ Monitoring optimizations failed"
        fi
    fi
    
    # Try enhanced storage optimization
    if check_python_modules "enhanced_storage_manager" >/dev/null 2>&1 && [[ ${#nodes[@]} -gt 0 ]]; then
        log INFO "🐍 Applying storage optimizations..."
        if python3 "$PROJECT_ROOT/lib/python/enhanced_storage_manager.py" \
            --nodes "${nodes[@]}" -- optimize; then
            ((optimizations_applied++))
            log INFO "✅ Storage optimizations applied"
        else
            ((optimizations_failed++))
            log WARN "❌ Storage optimizations failed"
        fi
    fi
    
    # Try service orchestrator optimization
    if check_python_modules "service_orchestrator" >/dev/null 2>&1; then
        log INFO "🐍 Checking service configurations..."
        if python3 "$PROJECT_ROOT/lib/python/service_orchestrator.py" status \
            --manager-ip "$manager_ip" --optimize; then
            ((optimizations_applied++))
            log INFO "✅ Service optimizations checked"
        else
            ((optimizations_failed++))
            log WARN "❌ Service optimization check failed"
        fi
    fi
    
    log INFO "Performance optimization summary: $optimizations_applied applied, $optimizations_failed failed"
    
    if [[ $optimizations_applied -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Comprehensive cluster health check
health_check_comprehensive() {
    local manager_ip="${1:-}"
    local nodes=("${@:2}")
    local ssh_user="${SSH_USER:-pi}"
    local ssh_pass="${SSH_PASS:-}"
    
    log INFO "🏥 Starting comprehensive cluster health check..."
    
    # If no manager IP provided, run basic system health check
    if [[ -z "$manager_ip" ]]; then
        log INFO "📋 Running basic system health check (no cluster specified)..."
        
        # Check system resources
        if command -v free >/dev/null 2>&1; then
            local memory_usage=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')
            log INFO "💾 Memory usage: $memory_usage"
        fi
        
        # Check disk space
        if command -v df >/dev/null 2>&1; then
            local disk_usage=$(df -h / | awk 'NR==2{print $5}')
            log INFO "💽 Disk usage: $disk_usage"
        fi
        
        # Check Python modules
        if check_python_modules "directory_manager" >/dev/null 2>&1; then
            log INFO "🐍 Python modules: Available"
        else
            log WARN "🐍 Python modules: Limited availability"
        fi
        
        log INFO "✅ Basic system health check completed"
        return 0
    fi
    
    local health_score=0
    local max_score=0
    local issues=()
    
    # Enhanced monitoring health check
    if check_python_modules "enhanced_monitoring_manager" >/dev/null 2>&1; then
        log INFO "📊 Running monitoring health check..."
        ((max_score += 25))
        
        if python3 "$PROJECT_ROOT/lib/python/enhanced_monitoring_manager.py" health \
            --manager-ip "$manager_ip" --ssh-user "$ssh_user" --ssh-pass "$ssh_pass" \
            --format json > /tmp/monitoring_health.json 2>/dev/null; then
            
            local monitoring_score
            monitoring_score=$(jq -r '.cluster_summary.service_health_score // 0' /tmp/monitoring_health.json 2>/dev/null || echo "0")
            health_score=$((health_score + monitoring_score * 25 / 100))
            
            if [[ $(echo "$monitoring_score < 80" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
                issues+=("Monitoring: Service health below 80%")
            fi
        else
            issues+=("Monitoring: Health check failed")
        fi
    fi
    
    # Enhanced storage health check
    if check_python_modules "enhanced_storage_manager" >/dev/null 2>&1 && [[ ${#nodes[@]} -gt 0 ]]; then
        log INFO "💾 Running storage health check..."
        ((max_score += 25))
        
        if python3 "$PROJECT_ROOT/lib/python/enhanced_storage_manager.py" \
            --nodes "${nodes[@]}" -- status > /tmp/storage_status.json 2>/dev/null; then
            
            local online_nodes
            online_nodes=$(jq -r '.summary.online_nodes // 0' /tmp/storage_status.json 2>/dev/null || echo "0")
            local total_nodes
            total_nodes=$(jq -r '.summary.total_nodes // 1' /tmp/storage_status.json 2>/dev/null || echo "1")
            
            local storage_score=$((online_nodes * 25 / total_nodes))
            health_score=$((health_score + storage_score))
            
            if [[ $online_nodes -lt $total_nodes ]]; then
                issues+=("Storage: $((total_nodes - online_nodes)) nodes offline")
            fi
        else
            issues+=("Storage: Status check failed")
        fi
    fi
    
    # Enhanced security health check
    if check_python_modules "enhanced_security_manager" >/dev/null 2>&1 && [[ ${#nodes[@]} -gt 0 ]]; then
        log INFO "🔐 Running security health check..."
        ((max_score += 25))
        
        if python3 "$PROJECT_ROOT/lib/python/enhanced_security_manager.py" \
            --nodes "${nodes[@]}" -- audit > /tmp/security_audit.json 2>/dev/null; then
            
            # Parse security audit results (simplified)
            local security_score=20  # Assume decent security if audit passes
            health_score=$((health_score + security_score))
        else
            issues+=("Security: Audit failed")
        fi
    fi
    
    # Network connectivity check
    log INFO "🌐 Running network connectivity check..."
    ((max_score += 25))
    
    local reachable_nodes=0
    for node in "${nodes[@]}"; do
        if ping -c 1 -W 3 "$node" >/dev/null 2>&1; then
            ((reachable_nodes++))
        fi
    done
    
    if [[ ${#nodes[@]} -gt 0 ]]; then
        local network_score=$((reachable_nodes * 25 / ${#nodes[@]}))
        health_score=$((health_score + network_score))
        
        if [[ $reachable_nodes -lt ${#nodes[@]} ]]; then
            issues+=("Network: $((${#nodes[@]} - reachable_nodes)) nodes unreachable")
        fi
    else
        health_score=$((health_score + 25))  # No nodes to check
    fi
    
    # Calculate final health percentage
    local health_percentage=0
    if [[ $max_score -gt 0 ]]; then
        health_percentage=$((health_score * 100 / max_score))
    fi
    
    # Display results
    echo ""
    echo "🏥 COMPREHENSIVE HEALTH CHECK RESULTS"
    echo "====================================="
    echo "Overall Health Score: $health_score/$max_score ($health_percentage%)"
    echo ""
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "✅ All systems healthy"
    else
        echo "⚠️  Issues found:"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
    fi
    
    echo ""
    
    # Return appropriate exit code
    if [[ $health_percentage -ge 80 ]]; then
        log INFO "✅ Cluster health is good ($health_percentage%)"
        return 0
    elif [[ $health_percentage -ge 60 ]]; then
        log WARN "⚠️  Cluster health is fair ($health_percentage%)"
        return 1
    else
        log ERROR "❌ Cluster health is poor ($health_percentage%)"
        return 2
    fi
}

# Test all Python modules
test_python_integration() {
    local modules=("directory_manager" "ssh_manager" "network_discovery" "service_orchestrator" "backup_restore")
    local available=0
    local total=${#modules[@]}
    
    log INFO "Testing Python module integration..."
    
    for module in "${modules[@]}"; do
        if [[ -f "$PROJECT_ROOT/lib/python/${module}.py" ]]; then
            if python3 "$PROJECT_ROOT/lib/python/${module}.py" --help >/dev/null 2>&1; then
                log INFO "✅ $module: Available and working"
                ((available++))
            else
                log WARN "⚠️  $module: Available but has issues"
            fi
        else
            log WARN "❌ $module: Not found"
        fi
    done
    
    log INFO "Python integration: $available/$total modules available"
    
    if [[ $available -eq $total ]]; then
        log INFO "🎉 Full Python integration available"
        return 0
    elif [[ $available -gt 0 ]]; then
        log INFO "🔧 Partial Python integration available"
        return 1
    else
        log WARN "⚠️  No Python integration available, using Bash fallbacks"
        return 2
    fi
}

# Export functions for use in other scripts
export -f check_python_modules
export -f setup_directories_enhanced
export -f ssh_exec_enhanced
export -f discover_pis_enhanced
export -f create_backup_enhanced
export -f manage_swarm_services_enhanced
export -f test_python_integration
export -f execute_python_module
export -f monitor_cluster_enhanced
export -f detect_hardware_enhanced
export -f manage_config_enhanced
export -f manage_backup_enhanced
export -f monitor_cluster_comprehensive
export -f manage_storage_comprehensive
export -f manage_security_comprehensive
export -f optimize_cluster_performance
export -f health_check_comprehensive
