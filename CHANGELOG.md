# Changelog

## [v2.0.1] - 2025-05-31

### Fixed
- **Improved Error Messages**: SSH key setup failures now show warnings instead of errors and continue deployment
- **SSL Configuration Logic**: Fixed SSL certificate setup to only run when explicitly enabled
- **Enhanced User Feedback**: Added deployment summary with cluster status, service health, and next steps
- **Better Connectivity Handling**: Improved Pi discovery with unreachable device warnings and helpful tips
- **Automated Deployment**: Enhanced automated deployment script with connectivity checks and better error handling

### Added
- **Deployment Summary Function**: Provides comprehensive post-deployment status and guidance
- **Enhanced Connectivity Validation**: Better error messages and troubleshooting tips for network issues
- **Improved SSH Key Setup**: More graceful handling of SSH authentication failures
- **Mock Deployment Testing**: Added testing scripts for validation without requiring hardware

### Changed
- **Error Severity**: SSH key setup failures are now warnings rather than fatal errors
- **SSL Setup Logic**: Only runs SSL certificate generation when explicitly enabled
- **Function Loading**: Added deployment_summary to essential functions

---

## [v2.0.0] - 2025-05-31

### Major Changes
- Complete project restructuring for open-source/public deployment
- All scripts and functions reorganized into scope-based directories
- Documentation, CONTRIBUTING, SECURITY, FAQ, TROUBLESHOOTING, and LICENSE updated
- CI/CD: Added GitHub Actions workflow for tests; CI badge in docs
- All test scripts restored and made executable; comprehensive test script validates project integrity

### Deployment & Functionality
- Modernized Docker and Docker Compose installation (V2 plugin, fallback to manual)
- Improved SSH enablement and password handling for non-interactive automation
- Enhanced error handling and diagnostics for all remote operations
- File copy logic fixed: all required config files and Grafana templates now copy correctly
- Service stack deployment now supports both Docker Compose V1 and V2
- All essential functions loaded and exported; function loader improved
- Removed duplicate/conflicting Docker installation logic
- Made undefined/optional functions (security hardening, validation) safe to skip

### Testing & Validation
- Comprehensive test script passes: function loading, lock, network, syntax
- Automated deployment test script added for CI and local validation

### Other Improvements
- Enhanced error diagnostics in scp_file and remote operations
- Project is now robust, reproducible, and ready for GitHub open-source release

---

See `RELEASE_NOTES_v2.0.0.md` for a detailed migration and upgrade guide.

## [v1.0.0] - 2025-05-25
### Added
- Secure and robust cluster setup
- SSH key auth + password fallback
- Config backup, rollback, and validation
- Service deployment + health checks
- Logging, dry-run mode, and status report
