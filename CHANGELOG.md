# Changelog

## [v2.0.0] - 2025-05-31
### Major Deployment Fixes & Open Source Ready
This version represents a complete deployment overhaul making Pi-Swarm production-ready and open-source deployment-ready.

#### 🚀 **Critical Deployment Fixes**
- **Fixed configuration file path resolution** - Updated from `SCRIPT_DIR` to `PROJECT_ROOT` for reliable file access
- **Modernized Docker Compose installation** - Switched to Docker Compose V2 plugin method with V1 fallback compatibility
- **Enhanced Docker group management** - Added existence checks and non-fatal group addition with proper verification
- **Eliminated duplicate Docker installations** - Removed conflicting installation calls and streamlined deployment flow
- **Enhanced service deployment** - Added dual compatibility for both V1 (`docker-compose`) and V2 (`docker compose`) commands
- **Improved error diagnostics** - Enhanced `scp_file` function with comprehensive error reporting and source file validation
- **Fixed template path resolution** - Corrected Grafana templates directory path resolution
- **Made security functions optional** - Added existence checks for undefined security functions

#### 🔧 **Core Infrastructure Improvements**
- **Robust function loading** - `lib/source_functions.sh` now loads all 15 essential functions reliably
- **Enhanced error handling** - Comprehensive error reporting and graceful failure handling throughout deployment
- **Path resolution fixes** - All file operations now use consistent `PROJECT_ROOT` base paths
- **Service stack reliability** - Docker Compose services deploy successfully with proper dependency management

#### 📁 **Project Structure & Organization**
- **Scope-based directory organization** - All files reorganized into logical functional directories
- **Comprehensive documentation** - Added CONTRIBUTING, SECURITY, FAQ, TROUBLESHOOTING guides
- **Automated testing** - Complete test suite with `comprehensive-test.sh` validation
- **CI/CD integration** - GitHub Actions workflow for automated testing

#### 🛠 **New Features & Tools**
- **Automated deployment testing** - `validate-deployment-fixes.sh` for end-to-end deployment validation
- **Enhanced configuration management** - Restored and improved `get_config_value` function
- **SSL automation** - Complete SSL certificate automation with Let's Encrypt integration
- **Prometheus alerting** - Added comprehensive alerting rules configuration
- **Service monitoring** - Enhanced service status monitoring and health checks

#### 🧪 **Testing & Validation**
- **All test scripts restored** - Complete test suite with executable permissions
- **Deployment flow validation** - Successfully tested through all configuration phases
- **Function loading verification** - Confirmed all essential functions load correctly
- **CI badge integration** - GitHub Actions CI status in documentation

#### 📖 **Documentation Updates**
- **Complete project documentation** - Comprehensive docs in `docs/` directory
- **Enterprise transformation guide** - Complete enterprise deployment documentation
- **Security guidelines** - Detailed security configuration and best practices
- **Contributing guidelines** - Clear contribution process and coding standards

#### 🔐 **Security Enhancements**
- **SSH key management** - Enhanced SSH secure configuration
- **SSL certificate automation** - Automated wildcard SSL and Let's Encrypt integration
- **Security function checks** - Optional security function loading with graceful degradation

### Technical Details
- **Essential Functions Loaded**: 15 core functions including configure_pi_headless, Docker management, and service deployment
- **Docker Compose Compatibility**: Supports both V1 (docker-compose) and V2 (docker compose) commands
- **Error Recovery**: Non-fatal failures with comprehensive error reporting
- **Path Resolution**: Consistent PROJECT_ROOT-based file operations
- **Service Stack**: Prometheus, Grafana, Node Exporter with proper template deployment

### Breaking Changes
- Configuration file paths now resolve from PROJECT_ROOT instead of SCRIPT_DIR
- Docker installation method changed from pip to native Docker Compose V2 plugin
- Some security functions are now optional and won't halt deployment if missing

### Migration Guide
- Existing deployments should work without changes
- New deployments benefit from improved reliability and error handling
- All file paths are now relative to project root for consistency

## [v1.0.0] - 2025-05-25
### Added
- Secure and robust cluster setup
- SSH key auth + password fallback
- Config backup, rollback, and validation
- Service deployment + health checks
- Logging, dry-run mode, and status report
