#!/bin/bash

# Enhanced Directory Structure Setup for Pi-Swarm
# Ensures all required directories exist before deployment with advanced features

# Source logging functions if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../log.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../log.sh"
else
    # Fallback logging
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1: $2"; }
fi

setup_project_directories() {
    local project_root="${1:-$(pwd)}"
    local create_gitkeep="${2:-true}"
    local set_permissions="${3:-true}"
    local verbose="${4:-false}"
    
    log "INFO" "Setting up enhanced directory structure for Pi-Swarm..."
    
    # Core directories for Pi-Swarm operation
    local directories=(
        "data"
        "data/logs"
        "data/backups" 
        "data/configs"
        "data/ssl"
        "data/monitoring"
        "data/storage"
        "data/cache"
        "data/cluster"
        "data/cluster/nodes"
        "data/cluster/services"
        "data/cluster/volumes"
        "temp"
        "temp/downloads"
        "temp/extraction"
        "temp/scripts"
        "temp/logs"
    )
    
    # Additional directories for enhanced features
    local enhanced_directories=(
        "data/dns"
        "data/dns/pihole"
        "data/dns/configs"
        "data/storage/glusterfs"
        "data/storage/nfs"
        "data/storage/local"
        "data/monitoring/prometheus"
        "data/monitoring/grafana"
        "data/monitoring/logs"
        "data/ssl/certs"
        "data/ssl/keys"
        "data/ssl/ca"
        "data/backups/configs"
        "data/backups/storage"
        "data/backups/ssl"
        "data/python"
        "data/python/cache"
        "data/python/logs"
        "temp/python"
        "temp/testing"
        "temp/mock"
    )
    
    # Combine all directories
    local all_directories=("${directories[@]}" "${enhanced_directories[@]}")
    
    local created_count=0
    local skipped_count=0
    local failed_count=0
    
    [[ "$verbose" == "true" ]] && log "INFO" "Creating $(echo "${all_directories[@]}" | wc -w) directories..."
    
    for dir in "${all_directories[@]}"; do
        local full_path="$project_root/$dir"
        if [[ ! -d "$full_path" ]]; then
            if mkdir -p "$full_path" 2>/dev/null; then
                [[ "$verbose" == "true" ]] && echo "  ✅ Created: $dir"
                ((created_count++))
            else
                echo "  ❌ Failed to create: $dir"
                ((failed_count++))
            fi
        else
            [[ "$verbose" == "true" ]] && echo "  ✓ Exists: $dir"
            ((skipped_count++))
        fi
    done
    
    # Set proper permissions if requested
    if [[ "$set_permissions" == "true" ]]; then
        setup_directory_permissions "$project_root" "$verbose"
    fi
    
    # Create .gitkeep files for empty directories if requested
    if [[ "$create_gitkeep" == "true" ]]; then
        create_gitkeep_files "$project_root" "${all_directories[@]}"
    fi
    
    # Generate directory validation script
    generate_directory_validation_script "$project_root"
    
    # Summary
    log "INFO" "Directory setup complete:"
    log "INFO" "  ✅ Created: $created_count directories"
    log "INFO" "  ✓ Existing: $skipped_count directories" 
    log "INFO" "  ❌ Failed: $failed_count directories"
    
    if [[ $failed_count -gt 0 ]]; then
        log "WARN" "Some directories could not be created. Check permissions."
        return 1
    fi
    
    return 0
}

setup_directory_permissions() {
    local project_root="$1"
    local verbose="${2:-false}"
    
    [[ "$verbose" == "true" ]] && log "INFO" "Setting up directory permissions..."
    
    # Core directory permissions
    chmod 755 "$project_root/data" 2>/dev/null || true
    chmod 755 "$project_root/temp" 2>/dev/null || true
    
    # Secure permissions for sensitive directories
    chmod 700 "$project_root/data/ssl" 2>/dev/null || true
    chmod 700 "$project_root/data/ssl/keys" 2>/dev/null || true
    chmod 755 "$project_root/data/ssl/certs" 2>/dev/null || true
    chmod 700 "$project_root/data/ssl/ca" 2>/dev/null || true
    
    # Backup directories
    chmod 750 "$project_root/data/backups" 2>/dev/null || true
    
    # Log directories - writable but not executable
    find "$project_root/data" -name "*logs*" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Temporary directories - fully accessible
    find "$project_root/temp" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    [[ "$verbose" == "true" ]] && log "INFO" "Directory permissions configured"
}

create_gitkeep_files() {
    local project_root="$1"
    shift
    local directories=("$@")
    
    for dir in "${directories[@]}"; do
        local full_path="$project_root/$dir"
        if [[ -d "$full_path" ]] && [[ ! -f "$full_path/.gitkeep" ]]; then
            # Only create .gitkeep if directory is empty
            if [[ -z "$(ls -A "$full_path" 2>/dev/null)" ]]; then
                echo "# This file keeps the directory in git even when empty" > "$full_path/.gitkeep"
                echo "# Generated by Pi-Swarm directory setup on $(date)" >> "$full_path/.gitkeep"
            fi
        fi
    done
}

generate_directory_validation_script() {
    local project_root="$1"
    local validation_script="$project_root/scripts/testing/validate-directory-structure.sh"
    
    mkdir -p "$(dirname "$validation_script")"
    
    cat > "$validation_script" << 'EOF'
#!/bin/bash

# Auto-generated directory structure validation script
# Generated by Pi-Swarm enhanced directory setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Expected directories (auto-generated list)
EXPECTED_DIRS=(
    "data"
    "data/logs"
    "data/backups"
    "data/configs"
    "data/ssl"
    "data/monitoring"
    "data/storage"
    "data/cache"
    "data/cluster"
    "data/cluster/nodes"
    "data/cluster/services"
    "data/cluster/volumes"
    "data/dns"
    "data/dns/pihole"
    "data/dns/configs"
    "data/storage/glusterfs"
    "data/storage/nfs"
    "data/storage/local"
    "data/monitoring/prometheus"
    "data/monitoring/grafana"
    "data/monitoring/logs"
    "data/ssl/certs"
    "data/ssl/keys"
    "data/ssl/ca"
    "data/backups/configs"
    "data/backups/storage"
    "data/backups/ssl"
    "data/python"
    "data/python/cache"
    "data/python/logs"
    "temp"
    "temp/downloads"
    "temp/extraction"
    "temp/scripts"
    "temp/logs"
    "temp/python"
    "temp/testing"
    "temp/mock"
)

validate_directory_structure() {
    local missing_dirs=()
    local total_dirs=${#EXPECTED_DIRS[@]}
    local existing_dirs=0
    
    echo "🔍 Validating Pi-Swarm directory structure..."
    echo "Expected directories: $total_dirs"
    echo ""
    
    for dir in "${EXPECTED_DIRS[@]}"; do
        local full_path="$PROJECT_ROOT/$dir"
        if [[ -d "$full_path" ]]; then
            echo "  ✅ $dir"
            ((existing_dirs++))
        else
            echo "  ❌ Missing: $dir"
            missing_dirs+=("$dir")
        fi
    done
    
    echo ""
    echo "📊 Summary:"
    echo "  Total expected: $total_dirs"
    echo "  Existing: $existing_dirs"
    echo "  Missing: ${#missing_dirs[@]}"
    
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        echo "  ✅ All directories exist!"
        return 0
    else
        echo "  ❌ Missing directories found"
        echo ""
        echo "To create missing directories, run:"
        echo "  cd '$PROJECT_ROOT' && source lib/system/directory_setup.sh && setup_project_directories"
        return 1
    fi
}

create_missing_directories() {
    echo "🔧 Creating missing directories..."
    if [[ -f "$PROJECT_ROOT/lib/system/directory_setup.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/directory_setup.sh"
        setup_project_directories "$PROJECT_ROOT" true true true
    else
        echo "❌ Directory setup script not found!"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-validate}" in
        validate)
            validate_directory_structure
            ;;
        create)
            create_missing_directories
            ;;
        both)
            validate_directory_structure || create_missing_directories
            ;;
        help)
            echo "Usage: $0 [validate|create|both]"
            echo ""
            echo "Commands:"
            echo "  validate  - Check if all expected directories exist (default)"
            echo "  create    - Create any missing directories"
            echo "  both      - Validate and create missing directories if needed"
            echo "  help      - Show this help message"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use 'help' for usage information"
            exit 1
            ;;
    esac
fi
EOF
    
    chmod +x "$validation_script"
    log "INFO" "Directory validation script created: $validation_script"
}

setup_enhanced_project_structure() {
    local project_root="${1:-$(pwd)}"
    local options="${2:-default}"
    
    log "INFO" "Setting up enhanced Pi-Swarm project structure..."
    
    case "$options" in
        minimal)
            setup_project_directories "$project_root" false false false
            ;;
        standard)
            setup_project_directories "$project_root" true true false
            ;;
        full|enhanced)
            setup_project_directories "$project_root" true true true
            create_development_structure "$project_root"
            ;;
        *)
            setup_project_directories "$project_root" true true true
            ;;
    esac
}

create_development_structure() {
    local project_root="$1"
    
    log "INFO" "Creating development-specific structure..."
    
    # Development directories
    local dev_dirs=(
        "dev"
        "dev/testing"
        "dev/mock-data"
        "dev/experiments"
        "dev/python-migration"
        "dev/benchmarks"
    )
    
    for dir in "${dev_dirs[@]}"; do
        local full_path="$project_root/$dir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            echo "  ✅ Created dev directory: $dir"
        fi
    done
    
    # Create development configuration files
    cat > "$project_root/dev/testing/pytest.ini" << 'EOF'
[tool:pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short
EOF
    
    cat > "$project_root/dev/python-migration/migration-plan.md" << 'EOF'
# Python Migration Plan

## Priority Modules for Migration

1. **SSH Management** ✅
   - Complex authentication logic
   - Connection pooling needs
   - Better error handling

2. **Service Orchestration** ✅
   - Docker service management
   - Template generation
   - Health monitoring

3. **Configuration Management** ✅
   - YAML parsing and validation
   - Environment integration
   - Schema validation

4. **Hardware Detection** ✅
   - System information gathering
   - Device enumeration
   - Performance metrics

## Next Targets

- Network discovery and scanning
- Backup and restore operations
- Monitoring data collection
- Log aggregation and analysis

## Integration Strategy

- Gradual replacement of Bash functions
- Maintain backward compatibility
- Add Python CLI interfaces
- Enhanced error handling and logging
EOF
    
    log "INFO" "Development structure created successfully"
}

validate_directory_permissions() {
    local project_root="${1:-$(pwd)}"
    
    log "INFO" "Validating directory permissions..."
    
    local issues=0
    
    # Check critical directory permissions
    if [[ -d "$project_root/data/ssl" ]]; then
        local ssl_perms=$(stat -c "%a" "$project_root/data/ssl" 2>/dev/null || echo "000")
        if [[ "$ssl_perms" != "700" ]]; then
            log "WARN" "SSL directory permissions ($ssl_perms) should be 700"
            ((issues++))
        fi
    fi
    
    if [[ -d "$project_root/data/backups" ]]; then
        local backup_perms=$(stat -c "%a" "$project_root/data/backups" 2>/dev/null || echo "000")
        if [[ "$backup_perms" != "750" ]] && [[ "$backup_perms" != "755" ]]; then
            log "WARN" "Backup directory permissions ($backup_perms) should be 750 or 755"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "INFO" "✅ Directory permissions look good"
        return 0
    else
        log "WARN" "❌ Found $issues permission issues"
        return 1
    fi
}

# Cleanup old or temporary directories
cleanup_old_directories() {
    local project_root="${1:-$(pwd)}"
    local dry_run="${2:-true}"
    
    log "INFO" "Scanning for old/temporary directories to cleanup..."
    
    # Directories that can be safely cleaned
    local cleanup_candidates=(
        "temp/downloads/*"
        "temp/extraction/*"
        "temp/scripts/*"
        "temp/logs/*"
        "temp/testing/*"
        "temp/mock/*"
        "data/cache/*"
    )
    
    local cleaned_count=0
    
    for pattern in "${cleanup_candidates[@]}"; do
        local full_pattern="$project_root/$pattern"
        
        # Find files older than 7 days
        if find "$project_root/$(dirname "$pattern")" -name "$(basename "$pattern")" -type f -mtime +7 2>/dev/null | grep -q .; then
            if [[ "$dry_run" == "true" ]]; then
                echo "  [DRY RUN] Would clean: $pattern (files older than 7 days)"
                ((cleaned_count++))
            else
                find "$project_root/$(dirname "$pattern")" -name "$(basename "$pattern")" -type f -mtime +7 -delete 2>/dev/null
                echo "  ✅ Cleaned: $pattern (files older than 7 days)"
                ((cleaned_count++))
            fi
        fi
    done
    
    if [[ $cleaned_count -eq 0 ]]; then
        log "INFO" "No old files found for cleanup"
    else
        if [[ "$dry_run" == "true" ]]; then
            log "INFO" "Would clean $cleaned_count locations (run with dry_run=false to execute)"
        else
            log "INFO" "Cleaned $cleaned_count locations"
        fi
    fi
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    case "${1:-setup}" in
        setup)
            setup_project_directories "${2:-$(pwd)}" true true true
            ;;
        enhanced)
            setup_enhanced_project_structure "${2:-$(pwd)}" "full"
            ;;
        validate)
            validate_directory_permissions "${2:-$(pwd)}"
            ;;
        cleanup)
            cleanup_old_directories "${2:-$(pwd)}" "${3:-true}"
            ;;
        help)
            echo "Enhanced Directory Setup for Pi-Swarm"
            echo ""
            echo "Usage: $0 [COMMAND] [PROJECT_ROOT] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  setup     - Setup standard directory structure (default)"
            echo "  enhanced  - Setup enhanced directory structure with dev features"
            echo "  validate  - Validate directory permissions"
            echo "  cleanup   - Cleanup old temporary files (dry run by default)"
            echo "  help      - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 setup /path/to/project"
            echo "  $0 enhanced"
            echo "  $0 cleanup . false"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use 'help' for usage information"
            exit 1
            ;;
    esac
fi

# Cleanup temporary directories (for testing/maintenance)
cleanup_temp_directories() {
    local project_root="${1:-$(pwd)}"
    
    echo "🧹 Cleaning temporary directories..."
    
    # Remove temp directory contents but keep the directory
    if [[ -d "$project_root/temp" ]]; then
        find "$project_root/temp" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        echo "  ✅ Cleared temp directory"
    fi
    
    # Clean old log files (older than 30 days)
    if [[ -d "$project_root/data/logs" ]]; then
        find "$project_root/data/logs" -name "*.log" -mtime +30 -delete 2>/dev/null || true
        echo "  ✅ Cleaned old log files"
    fi
    
    # Clean cache directory
    if [[ -d "$project_root/data/cache" ]]; then
        find "$project_root/data/cache" -type f -mtime +7 -delete 2>/dev/null || true
        echo "  ✅ Cleaned cache files"
    fi
    
    echo "🧹 Cleanup complete"
}

# Validate directory structure
validate_directory_structure() {
    local project_root="${1:-$(pwd)}"
    
    local required_dirs=(
        "data/logs"
        "data/backups"
        "temp"
    )
    
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$project_root/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if (( ${#missing_dirs[@]} > 0 )); then
        echo "❌ Missing required directories: ${missing_dirs[*]}"
        return 1
    fi
    
    echo "✅ Directory structure validation passed"
    return 0
}

# Main function when script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    
    case "${1:-setup}" in
        setup)
            setup_project_directories "$PROJECT_ROOT"
            ;;
        validate)
            validate_directory_structure "$PROJECT_ROOT"
            ;;
        cleanup)
            cleanup_temp_directories "$PROJECT_ROOT"
            ;;
        *)
            echo "Usage: $0 {setup|validate|cleanup}"
            echo ""
            echo "Commands:"
            echo "  setup     - Create all required directories"
            echo "  validate  - Check if required directories exist"
            echo "  cleanup   - Clean temporary and old files"
            exit 1
            ;;
    esac
fi
