# 🚨 Quick Fix Guide for SSH Authentication and Docker Installation Issues

## Issue Summary
- **SSH Authentication**: System was using local username 'luser' instead of Pi username
- **Password Validation**: Portainer password validation was causing infinite loops
- **Docker Installation**: Failing due to SSH authentication issues

## ✅ Fixes Applied

### 1. SSH Authentication Fixed
**Problem**: Pre-deployment validation was using `$USER` (local system username) instead of configured Pi username.

**Solution**: Updated variable fallback logic in `/lib/deployment/pre_deployment_validation.sh`:
```bash
# Before (incorrect):
local ssh_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-$USER}}}"

# After (fixed):
local ssh_user="${USERNAME:-${PI_USER:-${NODES_DEFAULT_USER:-pi}}}"
```

### 2. Password Validation Fixed
**Problem**: Portainer password prompt was in infinite loop when reading from non-interactive input.

**Solution**: Updated `/lib/deployment/deploy_services.sh`:
- Added attempt counter with fallback to default password
- Improved input handling with `/dev/tty`
- Added environment variable support

### 3. Environment Variable Support Added
**Problem**: No way to set credentials for automated deployment.

**Solution**: Added support for environment variables:
```bash
export SSH_USER="pi"           # SSH username for Pis
export SSH_PASSWORD="your_pwd" # SSH password
export USERNAME="pi"           # Alternative username variable
```

## 🚀 Quick Deployment Guide

### Option 1: Manual Testing First
```bash
# 1. Test SSH manually
ssh pi@192.168.3.201  # Replace with your Pi's IP

# 2. If SSH works, set environment variables
export USERNAME="pi"
export SSH_PASSWORD="your_password"

# 3. Run deployment
./deploy.sh
```

### Option 2: Automated Deployment
```bash
# 1. Set password
export SSH_PASSWORD="your_password"

# 2. Run automated deployment
./automated-deploy.sh
```

### Option 3: Enhanced Interactive Deployment
```bash
# Run the enhanced deployment script (recommended)
./scripts/deployment/enhanced-deploy.sh
```

## 🔧 Troubleshooting

### Run the troubleshooting script:
```bash
./troubleshoot.sh
```

### Common Issues:

1. **"Cannot SSH to 192.168.x.x as luser"**
   - **Fixed**: Update applied to use correct username
   - Set `export USERNAME="pi"` if still occurs

2. **"Password must be at least 8 characters"** (infinite loop)
   - **Fixed**: Improved password validation with fallback
   - Set `export PORTAINER_PASSWORD="your_8char_password"` for automation

3. **"Docker installation failed"**
   - Usually caused by SSH authentication issues (now fixed)
   - Check SSH access manually first
   - Ensure Pi has internet connectivity

### Environment Variables Reference:
```bash
# SSH Authentication
export USERNAME="pi"                    # Pi username (pi/ubuntu/etc)
export SSH_PASSWORD="your_password"     # Pi password
export SSH_USER="pi"                   # Alternative username
export PASSWORD="your_password"        # Alternative password

# Service Passwords
export PORTAINER_PASSWORD="secure123"  # Portainer admin password (8+ chars)
export GRAFANA_PASSWORD="admin"       # Grafana password

# Legacy variables (still supported)
export PI_USER="pi"
export PI_PASS="your_password"
export NODES_DEFAULT_USER="pi"
export NODES_DEFAULT_PASS="your_password"
```

## 🧪 Test Your Fixes

1. **Test username resolution**:
   ```bash
   ./test-ssh-fixes.sh
   ```

2. **Full troubleshooting**:
   ```bash
   ./troubleshoot.sh
   ```

3. **Manual SSH test**:
   ```bash
   ssh pi@192.168.3.201  # Replace with your Pi IP
   ```

## 📝 Files Modified

- `lib/deployment/pre_deployment_validation.sh` - Fixed username fallback logic
- `lib/deployment/deploy_services.sh` - Fixed password validation loop
- `core/swarm-cluster.sh` - Added environment variable support
- `automated-deploy.sh` - Added SSH credential handling

## 🎯 Expected Results

After applying these fixes:
- ✅ SSH authentication should work with correct username
- ✅ Password prompts should not loop infinitely
- ✅ Docker installation should succeed
- ✅ Automated deployment should work with environment variables
- ✅ Pre-deployment validation should pass

## 🆘 If Issues Persist

1. Check your Pi's SSH configuration:
   ```bash
   # On your Pi:
   sudo systemctl status ssh
   sudo systemctl enable ssh
   sudo systemctl start ssh
   ```

2. Verify network connectivity:
   ```bash
   ping 192.168.3.201  # Your Pi's IP
   nc -z 192.168.3.201 22  # Check SSH port
   ```

3. Test Docker installation manually:
   ```bash
   ssh pi@192.168.3.201 "curl -fsSL https://get.docker.com | sudo sh"
   ```

4. Check firewall on Pi:
   ```bash
   ssh pi@192.168.3.201 "sudo ufw status"
   ```

## 📞 Support

- Run `./troubleshoot.sh` for detailed diagnostics
- Check log files in `data/logs/`
- Review `docs/TROUBLESHOOTING.md` for more details

---
*Last updated: June 2, 2025*
