# Pi-Swarm Directory Structure

This document describes the organized directory structure of the Pi-Swarm project after restructuring for better maintainability and scope-based organization.

## Overview

The project has been reorganized from a flat structure into logical scope-based directories to improve maintainability, reduce complexity, and make it easier for developers to find and modify relevant components.

## Directory Structure

```
PI-Swarm/
├── config/                     # Configuration files
│   ├── config.yml              # Main cluster configuration
│   ├── docker-compose.monitoring.yml  # Monitoring stack configuration
│   └── prometheus.yml          # Prometheus configuration
│
├── core/                       # Main deployment scripts
│   ├── swarm-cluster.sh        # Primary deployment script
│   └── pi-swarm               # CLI management tool
│
├── lib/                        # Function libraries organized by scope
│   ├── source_functions.sh     # Main function loader
│   ├── log.sh                  # Logging utilities
│   ├── acquire_lock.sh         # Process locking
│   ├── release_lock.sh         # Process unlocking
│   ├── high_availability.sh    # HA features
│   │
│   ├── auth/                   # Authentication and SSH functions
│   │   ├── prompt_user.sh      # User input prompts and validation
│   │   ├── ssh_auth.sh         # SSH authentication helpers
│   │   ├── ssh_secure.sh       # Secure SSH operations
│   │   └── validate_connections.sh  # Connection validation
│   │
│   ├── config/                 # Configuration management
│   │   ├── config_management.sh    # Configuration utilities
│   │   ├── environment.sh      # Environment setup
│   │   ├── load_config.sh      # Configuration loading
│   │   └── validate_environment.sh  # Environment validation
│   │
│   ├── deployment/             # Deployment and setup functions
│   │   ├── configure_pi_headless.sh    # Headless Pi configuration
│   │   ├── deploy_services.sh  # Service deployment
│   │   ├── init_swarm.sh       # Swarm initialization
│   │   ├── install_docker.sh   # Docker installation
│   │   ├── service_templates.sh # Service templates
│   │   └── setup_pis.sh        # Pi node setup
│   │
│   ├── monitoring/             # Monitoring and alerting
│   │   ├── alert_integration.sh    # Alert integration
│   │   ├── performance_monitoring.sh  # Performance monitoring
│   │   └── service_status.sh   # Service status checking
│   │
│   ├── networking/             # Network configuration
│   │   ├── assign_pi_network_conf.sh   # Network assignment
│   │   ├── configure_static_ip.sh      # Static IP configuration
│   │   ├── discover_pis.sh     # Pi discovery
│   │   ├── network_utilities.sh    # Network utilities
│   │   └── validate_network_config.sh  # Network validation
│   │
│   └── security/               # Security functions
│       ├── security.sh         # Basic security functions
│       ├── security_advanced.sh    # Advanced security features
│       └── ssl_automation.sh   # SSL certificate automation
│
├── data/                       # Runtime data
│   ├── logs/                   # Log files
│   │   └── piswarm-YYYYMMDD.log
│   └── backups/                # Configuration backups
│       └── YYYYMMDD_HHMMSS/
│
├── docs/                       # Documentation
│   ├── README.md               # Main documentation
│   ├── USER_AUTHENTICATION.md  # SSH setup guide
│   ├── NON_ROOT_IMPLEMENTATION.md  # Non-root implementation
│   ├── DIRECTORY_STRUCTURE.md  # This file
│   └── *.md                    # Other documentation files
│
├── scripts/                    # Utility scripts
│   ├── management/             # Management scripts
│   │   ├── release.sh          # Release management
│   │   └── show-cluster-status.sh  # Status display
│   │
│   ├── testing/                # Testing scripts
│   │   ├── test-non-root-implementation.sh  # Non-root validation
│   │   ├── comprehensive-test.sh    # Comprehensive testing
│   │   ├── simple-test.sh      # Simple functionality test
│   │   └── *.sh                # Other test scripts
│   │
│   └── utilities/              # Utility scripts
│
├── templates/                  # Service templates and configs
│   └── grafana/                # Grafana templates
│       └── provisioning/
│
└── web/                        # Web interfaces
    └── web-dashboard.html      # Web dashboard
```

## Migration from Old Structure

### What Changed

1. **Functions moved to lib/**: All function files moved from `functions/` to `lib/` with sub-directories by scope
2. **Configuration centralized**: All config files moved to `config/`
3. **Main scripts in core/**: Primary deployment scripts moved to `core/`
4. **Documentation consolidated**: All docs moved to `docs/`
5. **Runtime data separated**: Logs and backups moved to `data/`
6. **Scripts organized**: Management, testing, and utility scripts organized in `scripts/`

### Updated Path References

Scripts that previously referenced the old structure have been updated:

- `FUNCTIONS_DIR="$SCRIPT_DIR/functions"` → `FUNCTIONS_DIR="$PROJECT_ROOT/lib"`
- `CONFIG_FILE="$SCRIPT_DIR/config.yml"` → `CONFIG_FILE="$PROJECT_ROOT/config/config.yml"`
- `LOG_FILE="$SCRIPT_DIR/logs/..."` → `LOG_FILE="$PROJECT_ROOT/data/logs/..."`

## Function Loading

The `lib/source_functions.sh` script has been updated to work with the new directory structure. It automatically loads functions from the appropriate subdirectories based on their scope.

### Essential Functions Loading Order

1. **Config**: Environment validation and configuration loading
2. **Networking**: Pi discovery and network utilities
3. **Auth**: SSH authentication and user prompts
4. **Deployment**: Docker installation and swarm initialization
5. **Monitoring**: Performance monitoring and alerting
6. **Security**: Security functions and SSL automation

## Benefits of New Structure

1. **Better Organization**: Functions are grouped by logical scope
2. **Easier Maintenance**: Related functionality is co-located
3. **Clearer Dependencies**: Function relationships are more apparent
4. **Improved Testing**: Test scripts can target specific functional areas
5. **Enhanced Documentation**: Each scope can have focused documentation
6. **Scalability**: New features can be added to appropriate scopes

## Usage Guidelines

### For Developers

1. **Adding new functions**: Place in the appropriate `lib/` subdirectory
2. **Configuration changes**: Update files in `config/`
3. **Documentation updates**: Add/modify files in `docs/`
4. **Testing**: Use existing test framework in `scripts/testing/`

### For Users

1. **Main deployment**: Use `core/swarm-cluster.sh`
2. **Management**: Use `core/pi-swarm` CLI tool
3. **Configuration**: Edit files in `config/`
4. **Logs**: Check `data/logs/` for runtime logs
5. **Backups**: Find configuration backups in `data/backups/`

## Backward Compatibility

While the internal structure has changed significantly, the user-facing interface remains the same:

- Main deployment script: `core/swarm-cluster.sh`
- CLI management tool: `core/pi-swarm`
- Configuration file: `config/config.yml`

All old functionality is preserved and enhanced with the new structure.
