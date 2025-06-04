# Pi-Swarm Security Improvements - Password Management

## 🔐 Overview

Pi-Swarm has been updated to eliminate hardcoded password assumptions and improve security practices. This document outlines the changes made and best practices for secure deployment.

## ❌ What Was Removed

### Hardcoded Password Assumptions
- **SSH Password**: Removed default "raspberry" password assumption
- **Portainer Password**: Removed default "piswarm123" password assumption  
- **Test Scripts**: Removed hardcoded passwords from debug/testing scripts

### Specific Changes Made
1. **Core deployment script** (`core/swarm-cluster.sh`):
   - Removed automatic fallback to "raspberry" password
   - Now requires explicit password entry if not configured

2. **Service deployment** (`lib/deployment/deploy_services.sh`):
   - Removed hardcoded "piswarm123" for Portainer
   - Now prompts for secure password during deployment
   - Enforces minimum 8-character password length

3. **Automated deployment scripts**:
   - Removed hardcoded "raspberry" password
   - Now requires explicit configuration or prompting

4. **Debug/Testing scripts**:
   - Removed hardcoded passwords
   - Now use environment variables or prompt for passwords

## ✅ Current Security Practices

### SSH Authentication
- **No Default Passwords**: System will prompt for passwords if not configured
- **Configuration-Based**: Passwords can be set in configuration files
- **Environment Variables**: Support for `TEST_PASSWORD` in testing scenarios
- **SSH Keys Preferred**: Enhanced deployment script promotes SSH key usage

### Service Passwords
- **Portainer**: Requires secure password (minimum 8 characters) set during deployment
- **Grafana**: Uses configurable password (defaults to "admin" but changeable)
- **No Hardcoded Defaults**: All service passwords must be explicitly set

### Testing & Development
- **Environment Variables**: Test scripts use `TEST_PASSWORD` and `TEST_PI_PASSWORD`
- **Explicit Configuration**: No assumptions about default passwords
- **Documentation**: Clear guidance on security best practices

## 🛡️ Best Practices

### For Production Deployments
1. **Use SSH Keys**: Set up SSH key authentication instead of passwords
2. **Strong Passwords**: Use passwords with at least 12 characters
3. **Unique Passwords**: Never reuse passwords between services
4. **Configuration Files**: Store passwords in secure configuration files
5. **Environment Variables**: Use environment variables for sensitive data

### For Development/Testing
1. **Environment Variables**: Set `TEST_PASSWORD` for testing scripts
2. **Temporary Passwords**: Use temporary passwords for test environments
3. **Document Assumptions**: Clearly document any test credentials
4. **Separate Environments**: Keep test and production credentials separate

## 🔧 Migration Guide

### If You Were Using Default Passwords

#### Previous Behavior (❌ Insecure)
```bash
# System automatically assumed "raspberry" password
./deploy.sh
```

#### New Behavior (✅ Secure)
```bash
# System prompts for password if not configured
./deploy.sh
# Will prompt: "Please enter the SSH password for user 'pi':"
```

### Configuration File Setup
```yaml
# config/config.yml
nodes:
  default_user: "pi"
  default_pass: "your-secure-password"  # Optional, will prompt if not set
```

### Environment Variable Setup
```bash
# For testing
export TEST_PASSWORD="your-test-password"
export TEST_PI_PASSWORD="your-pi-password"
```

## 📋 Security Checklist

Before deploying Pi-Swarm:

- [ ] SSH keys are set up (recommended)
- [ ] Unique, strong passwords are prepared
- [ ] No default passwords are being used
- [ ] Configuration files are properly secured
- [ ] Test credentials are separate from production
- [ ] Password requirements are understood (8+ characters for services)

## 🚨 Important Notes

### Breaking Changes
- **Automated Scripts**: May now prompt for passwords where they previously assumed defaults
- **Test Scripts**: Require environment variables or manual password entry
- **Service Setup**: Portainer now requires secure password during deployment

### Compatibility
- **Configuration Files**: Existing config files with passwords will continue to work
- **Environment Variables**: New environment variable support maintains automation capability
- **Prompting**: Interactive prompting ensures no deployment fails due to missing passwords

## 🔗 Related Documentation

- [User Authentication Guide](USER_AUTHENTICATION.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Enterprise Security Features](ENTERPRISE_FEATURES.md)
- [Troubleshooting](TROUBLESHOOTING.md)

---

**Note**: These security improvements ensure Pi-Swarm follows industry best practices and eliminates common security vulnerabilities associated with default passwords.
