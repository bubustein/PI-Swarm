# 🚀 Pi-Swarm v2.0.0

[![Tests](https://github.com/bubustein/PI-Swarm/workflows/Tests/badge.svg)](https://github.com/bubustein/PI-Swarm/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Raspberry Pi](https://img.shields.io/badge/-RaspberryPi-C51A4A?style=flat&logo=Raspberry-Pi)](https://www.raspberrypi.org/)

> **Enterprise-grade Docker Swarm orchestration platform for Raspberry Pi clusters**

Pi-Swarm transforms your Raspberry Pi devices into a powerful, production-ready Docker Swarm cluster with monitoring, security, and automated deployment capabilities.

## ✨ Features

- 🐳 **Automated Docker Swarm Setup** - One-command cluster initialization
- 📊 **Built-in Monitoring** - Prometheus, Grafana, and custom dashboards
- 🔒 **Security Hardening** - SSH keys, firewall, SSL certificates
- 🌐 **Service Management** - Portainer integration for easy container management
- 🚨 **Alert Integration** - Slack, email, and Discord notifications
- 🔄 **High Availability** - Multi-node failover and load balancing
- 📱 **Web Dashboard** - Real-time cluster monitoring and control

## 🚀 Quick Start

### 1. Clone and Setup
```bash
git clone https://github.com/bubustein/PI-Swarm.git
cd PI-Swarm
chmod +x deploy.sh
```

### 2. Deploy Your Cluster
```bash
# Interactive deployment menu (Recommended)
./deploy.sh

# Or use direct deployment methods:
./scripts/deployment/automated-deploy.sh    # Fully automated
./scripts/deployment/enhanced-deploy.sh     # Interactive with guidance
./core/swarm-cluster.sh                     # Traditional method
```

### 3. Access Your Services
- **Portainer (Container Management)**: `http://YOUR_PI_IP:9000`
- **Grafana (Monitoring)**: `http://YOUR_PI_IP:3000`
- **Prometheus (Metrics)**: `http://YOUR_PI_IP:9090`

## 📋 Prerequisites

- 2+ Raspberry Pi devices (Pi 3B+ or newer recommended)
- Raspberry Pi OS (64-bit recommended)
- Network connectivity between Pis
- SSH access to all devices

## 🎯 Deployment Options

| Method | Use Case | Interaction | Features |
|--------|----------|-------------|----------|
| `./deploy.sh` | **Recommended** | Menu-driven | All options available |
| `automated-deploy.sh` | CI/CD, Testing | None required | Sensible defaults |
| `enhanced-deploy.sh` | First-time users | Interactive guidance | Error handling |
| `swarm-cluster.sh` | Advanced users | Full manual control | All enterprise features |

## 🔍 Validation and Testing

```bash
# Validate project integrity
./scripts/testing/comprehensive-test.sh

# Test deployment logic without hardware
./scripts/testing/mock-deployment-test.sh

# Check production readiness
./scripts/testing/final-validation-test.sh
```
