# Pi-Swarm Portable Configuration Guide

## Overview

Pi-Swarm v2.0.0 has been designed to be completely portable and environment-agnostic. All hardcoded IP addresses, usernames, paths, and other environment-specific values have been removed and replaced with configurable environment variables.

## Required Environment Variables

### Core Configuration

- **`PI_NODE_IPS`** - Comma-separated list of Pi node IP addresses
  - Example: `export PI_NODE_IPS="192.168.1.101,192.168.1.102,192.168.1.103"`
  - Required for all deployment and management operations

- **`NODES_DEFAULT_USER`** - Default SSH username for Pi nodes
  - Example: `export NODES_DEFAULT_USER="pi"`
  - Default: `pi` (used if not set)
  - Common values: `pi` (Raspberry Pi OS), `ubuntu` (Ubuntu)

### Optional Configuration

- **`MANAGER_IP`** - Specific manager node IP address
  - Example: `export MANAGER_IP="192.168.1.101"`
  - If not set, the first IP from `PI_NODE_IPS` is used as manager

- **`NODES_DEFAULT_PASS`** - Default SSH password for Pi nodes
  - Example: `export NODES_DEFAULT_PASS="your_password"`
  - If not set, the script will prompt for passwords or use SSH key authentication

- **`PI_STATIC_IPS`** - Space-separated list for legacy compatibility
  - Example: `export PI_STATIC_IPS="192.168.1.101 192.168.1.102 192.168.1.103"`
  - Used by some scripts as an alternative to `PI_NODE_IPS`

## Quick Setup

### Method 1: Automated Setup (Recommended)

Run the interactive environment configuration script:

```bash
./scripts/setup-environment.sh
```

This script will:
- Guide you through network discovery
- Validate IP addresses
- Configure SSH users
- Test connectivity to Pi nodes
- Save configuration to `~/.bashrc` for persistence

### Method 2: Manual Configuration

Set environment variables manually:

```bash
# Configure Pi node IPs (required)
export PI_NODE_IPS="192.168.1.101,192.168.1.102,192.168.1.103"

# Configure SSH user (optional, defaults to 'pi')
export NODES_DEFAULT_USER="pi"

# Configure manager IP (optional, auto-detected if not set)
export MANAGER_IP="192.168.1.101"

# Configure SSH password (optional, will prompt if not set)
export NODES_DEFAULT_PASS="your_password"

# Make configuration persistent
echo 'export PI_NODE_IPS="192.168.1.101,192.168.1.102,192.168.1.103"' >> ~/.bashrc
echo 'export NODES_DEFAULT_USER="pi"' >> ~/.bashrc
```

### Method 3: Environment File

Create a `.env` file in the project root (a sample `.env.example` is provided):

```bash
# .env file
PI_NODE_IPS=192.168.1.101,192.168.1.102,192.168.1.103
NODES_DEFAULT_USER=pi
MANAGER_IP=192.168.1.101
```

Then source it before running scripts:
```bash
source .env
./deploy.sh
```

## Network Discovery

The environment setup script includes automatic network discovery to help you configure the correct IP addresses for your environment:

- Detects your current gateway and subnet
- Suggests appropriate IP ranges based on your network
- Validates IP address formats
- Tests connectivity to configured nodes

## Deployment Scripts

### Initial Setup and Deployment

```bash
# Clone the repository
git clone https://github.com/bubustein/PI-Swarm.git
cd PI-Swarm

# Make scripts executable
chmod +x deploy.sh
chmod +x scripts/setup-environment.sh

# Configure environment (recommended)
./scripts/setup-environment.sh

# Deploy your cluster
./deploy.sh
```

### Alternative Manual Configuration

```bash
# Clone and setup
git clone https://github.com/bubustein/PI-Swarm.git
cd PI-Swarm
chmod +x deploy.sh

# Configure environment variables manually
export PI_NODE_IPS="192.168.1.101,192.168.1.102,192.168.1.103"
export NODES_DEFAULT_USER="pi"

# Deploy
./deploy.sh
```

### Individual Script Usage

#### Main Deployment
```bash
# After configuring environment variables
./deploy.sh
```

#### Comprehensive System Repair
```bash
./scripts/management/comprehensive-system-repair.sh
```

#### Automated Comprehensive Deployment
```bash
./scripts/deployment/automated-comprehensive-deploy.sh
```

#### SSH Setup
```bash
./scripts/management/setup-ssh-keys.sh
./scripts/management/fix-ssh-sudo.sh
```

## Validation

All major scripts now include environment validation that will:
- Check for required environment variables
- Provide helpful error messages with setup instructions
- Test connectivity to configured Pi nodes
- Use sensible defaults where appropriate

## Migration from Hardcoded Configuration

If you're migrating from an older version with hardcoded values:

1. Remove any old hardcoded IP addresses from custom scripts
2. Run the environment setup script: `./scripts/setup-environment.sh`
3. Verify configuration with: `echo $PI_NODE_IPS`
4. Test deployment with: `./deploy.sh`

## Common Network Configurations

### Home Network (192.168.1.x)
```bash
export PI_NODE_IPS="192.168.1.101,192.168.1.102,192.168.1.103"
```

### Home Network (192.168.0.x)
```bash
export PI_NODE_IPS="192.168.0.101,192.168.0.102,192.168.0.103"
```

### Office Network (10.0.x.x)
```bash
export PI_NODE_IPS="10.0.1.101,10.0.1.102,10.0.1.103"
```

### Custom Network
```bash
export PI_NODE_IPS="172.16.1.101,172.16.1.102,172.16.1.103"
```

## Testing Configuration

To test your configuration without running a full deployment:

```bash
# Test environment variables
echo "Pi Nodes: $PI_NODE_IPS"
echo "Default User: $NODES_DEFAULT_USER"

# Test connectivity
for ip in $(echo $PI_NODE_IPS | tr ',' ' '); do
    echo "Testing $ip..."
    ping -c 1 -W 2 "$ip" && echo "✅ Reachable" || echo "❌ Not reachable"
done

# Test SSH connectivity
for ip in $(echo $PI_NODE_IPS | tr ',' ' '); do
    echo "Testing SSH to $NODES_DEFAULT_USER@$ip..."
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$NODES_DEFAULT_USER@$ip" "echo 'SSH OK'" || echo "SSH failed"
done
```

## Troubleshooting

### Environment Variables Not Set
```
❌ ERROR: PI_NODE_IPS environment variable is not set!
```
**Solution**: Run `./scripts/setup-environment.sh` or set manually

### SSH Connection Issues
```
SSH failed to pi@192.168.1.101
```
**Solutions**:
- Check if Pi is powered on and network-accessible
- Verify SSH is enabled on the Pi
- Check username (`NODES_DEFAULT_USER`)
- Set up SSH keys with `./scripts/management/setup-ssh-keys.sh`

### Network Discovery Issues
**Solutions**:
- Manually specify IP addresses if auto-discovery fails
- Check network connectivity between deployment machine and Pi nodes
- Ensure Pi nodes are on the same network or have proper routing

## Security Considerations

- **SSH Keys**: Use SSH key authentication instead of passwords when possible
- **Firewall**: Configure firewalls appropriately for your network
- **Network Isolation**: Consider network segmentation for production deployments
- **Credential Management**: Avoid storing passwords in scripts or environment files

## Integration with CI/CD

For automated deployments in CI/CD pipelines:

```bash
# In CI/CD configuration
export PI_NODE_IPS="$CI_PI_NODE_IPS"
export NODES_DEFAULT_USER="$CI_SSH_USER"
export NODES_DEFAULT_PASS="$CI_SSH_PASS"

# Run deployment
./deploy.sh --offline
```

This portable configuration system ensures that Pi-Swarm can be deployed in any network environment without requiring code modifications.
