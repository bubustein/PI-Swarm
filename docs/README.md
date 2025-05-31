[![CI](https://github.com/<your-org>/pi-swarm/actions/workflows/test.yml/badge.svg)](https://github.com/<your-org>/pi-swarm/actions/workflows/test.yml)

> **Tip:** For best code quality, run `shellcheck` on all scripts before pushing.

# Pi-Swarm 🐳⚡

**Transform your Raspberry Pi cluster into an enterprise-grade Docker Swarm platform in minutes**

[![Docker](https://img.shields.io/badge/Docker-Swarm-blue?logo=docker)](https://docs.docker.com/engine/swarm/)
[![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-Supported-red?logo=raspberry-pi)](https://www.raspberrypi.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Pi-Swarm is a production-ready, enterprise-grade solution that automatically deploys and manages Docker Swarm clusters on Raspberry Pi hardware. With just one command, you get a fully configured cluster with professional monitoring, security, and management tools.

---

## 🚀 Quick Start

**Get your enterprise Pi cluster running in 5 minutes:**

```bash
# 1. Clone the repository
git clone <repository-url> pi-swarm && cd pi-swarm

# 2. Run the deployment script
./swarm-cluster.sh

# 3. Enter your Pi IP addresses when prompted
# Example: 192.168.1.10,192.168.1.11,192.168.1.12

# 4. Enable enterprise features when asked: y

# 🎉 Your cluster is ready!
```

**Access your cluster:**
- **Portainer** (Web UI): `https://[manager-ip]:9443`
- **Grafana** (Monitoring): `http://[manager-ip]:3000`
- **CLI Management**: `./pi-swarm status`

---

## ✨ Features

### 🏗️ **Core Platform**
- **One-Command Deployment** - Complete cluster setup with enterprise features
- **Docker Swarm Orchestration** - Multi-node container management
- **Dynamic IP Discovery** - No hardcoded addresses, works with any network
- **Professional Web UI** - Portainer for visual container management
- **Real-time Monitoring** - Grafana dashboards with live metrics

### 🔒 **Enterprise Security**
- **Automated SSL/TLS** - Let's Encrypt certificates with auto-renewal
- **Advanced Security Hardening** - Firewall, fail2ban, SSH keys
- **Access Control** - Role-based permissions and secure authentication
- **Security Auditing** - Automated vulnerability scanning

### 📊 **Monitoring & Alerts**
- **Multi-Channel Alerts** - Slack, email, Discord notifications
- **Performance Monitoring** - CPU, memory, disk, temperature tracking
- **Custom Dashboards** - Pi-optimized Grafana visualizations
- **Health Checks** - Automated service monitoring and recovery

### 🏗️ **High Availability**
- **Multi-Manager Clustering** - Automatic failover with 3+ managers
- **Load Balancing** - Traffic distribution across healthy nodes
- **Shared Storage** - NFS integration for persistent data
- **Network Redundancy** - Overlay network resilience

### 🎛️ **Management Tools**
- **Professional CLI** - 25+ commands for complete cluster control
- **Service Templates** - Pre-configured stacks (WordPress, databases, monitoring)
- **Backup & Recovery** - Automated configuration backups
- **Performance Optimization** - Pi-specific system tuning  
---

## 🎯 What You Get

### 🐳 **Complete Container Platform**
**Portainer CE** - Professional web-based container management
- Docker Swarm visualization and control
- Service deployment and scaling
- Real-time monitoring and log viewing
- User management and access control
- SSL-secured interfaces

**Full Monitoring Stack** - Enterprise-grade observability
- Grafana dashboards with Pi-optimized visualizations
- Prometheus metrics collection from all nodes
- Node Exporter for system metrics
- Alertmanager for notification routing
- 30-day data retention with historical analysis

### 🔧 **Management Interfaces**

**Professional CLI Tool** (`./pi-swarm`)
```bash
# Cluster operations
./pi-swarm status              # Live cluster health
./pi-swarm services            # Running services overview
./pi-swarm nodes               # Node status and roles

# Enterprise features
./pi-swarm ssl-setup           # Configure SSL certificates
./pi-swarm setup-alerts        # Configure notifications
./pi-swarm ha-setup            # High availability setup

# Service management
./pi-swarm templates           # Available service templates
./pi-swarm deploy-template     # Deploy pre-configured stacks
./pi-swarm scale <service> <n> # Scale services
```

**Web Dashboard Access**
- **Portainer**: `https://[manager-ip]:9443` - Container management
- **Grafana**: `http://[manager-ip]:3000` - Monitoring dashboards
- **Prometheus**: `http://[manager-ip]:9090` - Metrics collection

---

## 📋 Prerequisites

**Hardware Requirements:**
- 2+ Raspberry Pi devices (3B+, 4, or 5 recommended)
- MicroSD cards (32GB+ recommended)
- Network connectivity between Pis

**Software Setup:**
- Raspberry Pi OS (64-bit recommended)
- SSH enabled on all Pis (`sudo raspi-config`)
- **Regular user account with sudo privileges** (e.g., 'pi', 'ubuntu', etc.)
  - Do not use root user - most Pi setups disable root login for security
  - Your user account should have sudo access for system administration
- **Static IP addresses configured** (DHCP reservations or manual configuration)
  - Pi-Swarm assumes static IPs are already configured
  - Each Pi should have a fixed, reachable IP address

**Control Node Packages:**
```bash
sudo apt update
sudo apt install -y sshpass nmap docker.io yq
```

---

## 🚀 Installation Guide

### Step 1: Download Pi-Swarm
```bash
git clone <repository-url> pi-swarm
cd pi-swarm
chmod +x pi-swarm swarm-cluster.sh *.sh
```

### Step 2: Configure Your Environment (Optional)
```bash
# Copy example configuration
cp config.yml.example config.yml

# Edit configuration (optional - script can auto-configure)
nano config.yml
```

### Step 3: Deploy Your Cluster
```bash
./swarm-cluster.sh
```

**Prerequisites:** Ensure your Pis have static IP addresses configured before running the script.

**You'll be prompted for:**
1. **Pi IP addresses** (comma-separated): `192.168.1.10,192.168.1.11,192.168.1.12`
   - Use the existing static IPs of your Raspberry Pis
2. **SSH credentials** for your Pi user account
   - **Username**: Your regular Pi user (e.g., 'pi', 'ubuntu', etc.) - **NOT root**
   - **Password**: The password for your user account
   - The script will automatically set up SSH keys for secure access
3. **Enterprise features** (recommended: select `y` for "Enable ALL enterprise features")

**If enabling enterprise features, you'll configure:**
- Domain name for SSL certificates (optional)
- Email for Let's Encrypt registration
- Slack webhook URL for alerts (optional)
- Email SMTP settings for notifications (optional)

### Step 4: Access Your Cluster
```bash
# Check cluster status
./show-cluster-status.sh

# Use management CLI
./pi-swarm help
```

---

## 🛠️ Management Commands

### Core Operations
```bash
./pi-swarm status              # Cluster health overview
./pi-swarm nodes               # List all cluster nodes
./pi-swarm services            # Show running services
./pi-swarm logs <service>      # View service logs
./pi-swarm backup              # Create cluster backup
```

### Service Management
```bash
./pi-swarm templates           # List available service templates
./pi-swarm deploy-template <name>  # Deploy a service stack
./pi-swarm scale <service> <n>     # Scale service replicas
./pi-swarm restart <service>       # Restart a service
```

### Enterprise Features
```bash
# SSL Management
./pi-swarm ssl-setup           # Configure SSL certificates
./pi-swarm ssl-status          # Check certificate status
./pi-swarm ssl-renew           # Manually renew certificates

# High Availability
./pi-swarm ha-setup            # Configure multi-manager HA
./pi-swarm ha-status           # Check HA cluster health

# Monitoring & Alerts
./pi-swarm setup-alerts        # Configure alert channels
./pi-swarm test-alerts         # Test alert delivery
./pi-swarm monitor             # Live monitoring dashboard
```

---

## 📦 Service Templates

Deploy production-ready applications with one command:

### Web Applications
```bash
./pi-swarm deploy-template wordpress      # WordPress with MySQL
./pi-swarm deploy-template nextcloud      # NextCloud file sharing
./pi-swarm deploy-template nginx-lb       # Load-balanced NGINX
```

### Databases
```bash
./pi-swarm deploy-template postgresql-ha  # High-availability PostgreSQL
./pi-swarm deploy-template mysql-cluster  # MySQL cluster
./pi-swarm deploy-template redis-cluster  # Redis cluster
```

### Monitoring & Security
```bash
./pi-swarm deploy-template elk-stack      # Elasticsearch, Logstash, Kibana
./pi-swarm deploy-template vault-cluster  # HashiCorp Vault
./pi-swarm deploy-template wireguard-vpn  # WireGuard VPN server
```

**View all templates:** `./pi-swarm templates`

---

## 🔧 Configuration

### Basic Configuration (config.yml)
```yaml
# Network settings
network:
  interface: auto              # Auto-detect network interface
  dns: auto                   # Auto-detect DNS servers
  gateway: auto               # Auto-detect gateway

# Swarm settings
swarm:
  manager_port: 2377          # Swarm manager port
  portainer:
    enabled: true
    port: 9443               # Portainer HTTPS port
    ssl: true               # Enable SSL
    
# Default credentials (will prompt if empty)
nodes:
  default_user: ""           # SSH username for Pis
  default_pass: ""           # SSH password (or use keys)
```

### Enterprise Features Configuration

When you enable enterprise features, the system automatically configures:

**SSL Automation**
- Let's Encrypt certificates for your domain
- Self-signed certificates for IP-only access
- Automatic renewal with expiry monitoring

**Multi-Channel Alerts**
- Slack notifications for cluster events
- Email alerts for critical issues
- Discord integration for team communication

**High Availability**
- Multi-manager cluster (3+ nodes)
- Automatic failover and recovery
- Shared storage for persistent data

---

## 🐛 Troubleshooting

### Check Cluster Health
```bash
# Live cluster status with actual IPs
./show-cluster-status.sh

# Comprehensive health check
./pi-swarm status

# View detailed logs
tail -f logs/piswarm-$(date +%Y%m%d).log
```

### Common Issues

**SSH Connection Problems**
```bash
# Verify SSH access to each Pi
ssh pi@192.168.1.10

# Check SSH key setup
./pi-swarm verify-ssh
```

**Service Not Starting**
```bash
# Check service logs
./pi-swarm logs <service-name>

# Restart service
./pi-swarm restart <service-name>

# Check Docker Swarm status
docker service ls
```

**Network Issues**
```bash
# Test connectivity between nodes
./pi-swarm network-test

# Check overlay networks
docker network ls
```

### Enterprise Feature Validation
```bash
# Test all enterprise features
./test-enterprise-complete.sh

# Validate specific features
./validate-enterprise.sh
```

---

## 🏗️ Architecture

Pi-Swarm uses a modular architecture with enterprise-grade components:

```
📁 pi-swarm/
├── swarm-cluster.sh           # Main deployment script
├── pi-swarm                   # Enterprise CLI management tool
├── config.yml                 # Configuration file
├── show-cluster-status.sh     # Live cluster status
├── 📁 functions/              # Modular function files
│   ├── discover_pis.sh        # Pi discovery and validation
│   ├── setup_pis.sh           # Pi configuration
│   ├── init_swarm.sh          # Swarm initialization
│   ├── deploy_services.sh     # Service deployment
│   ├── ssl_automation.sh      # SSL certificate management
│   ├── alert_integration.sh   # Multi-channel alerts
│   ├── high_availability.sh   # HA cluster setup
│   ├── service_templates.sh   # Pre-configured services
│   ├── performance_monitoring.sh  # System optimization
│   └── security_advanced.sh   # Security hardening
├── 📁 grafana/                # Grafana dashboards
├── 📁 logs/                   # System logs
└── 📁 backups/                # Configuration backups
```

---

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1. **Report Issues** - Found a bug? [Open an issue](../../issues)
2. **Feature Requests** - Have an idea? [Start a discussion](../../discussions)
3. **Code Contributions** - Fork, branch, and submit a pull request
4. **Documentation** - Help improve our docs and examples

### Development Setup
```bash
# Clone for development
git clone <repository-url> pi-swarm-dev
cd pi-swarm-dev

# Test your changes
./test-enterprise-complete.sh
```

---

## 📚 Documentation

- **[User Authentication Guide](USER_AUTHENTICATION.md)** - SSH setup and security requirements
- **[Enterprise Features Guide](ENTERPRISE_FEATURES.md)** - Detailed feature documentation
- **[Deployment Guide](DEPLOYMENT_READY_FINAL.md)** - Production deployment instructions
- **[Implementation Summary](IMPLEMENTATION_SUMMARY.md)** - Technical implementation details
- **[Portainer Integration](PORTAINER_INTEGRATION.md)** - Container management guide

---

## 🏆 Why Pi-Swarm?

### vs. Manual Docker Setup
- **1 command** vs. hours of manual configuration
- **Enterprise features** built-in vs. DIY security and monitoring
- **Professional tools** vs. basic Docker commands

### vs. Kubernetes on Pi
- **Lightweight** - Optimized for Pi hardware constraints
- **Simple** - Docker Swarm is easier to learn and maintain
- **Production-ready** - Enterprise features without complexity

### vs. Commercial Solutions
- **Open Source** - No licensing costs or vendor lock-in
- **Pi-Optimized** - Specifically designed for Raspberry Pi hardware
- **Complete Stack** - Monitoring, security, and management included

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Docker team for Docker Swarm
- Portainer team for the excellent container management UI
- Grafana Labs for monitoring solutions
- Raspberry Pi Foundation for affordable computing hardware

---

**Ready to transform your Pi cluster?** 

```bash
git clone <repository-url> pi-swarm && cd pi-swarm && ./swarm-cluster.sh
```

[⭐ Star this repo](../../stargazers) if Pi-Swarm helps you build amazing things!
