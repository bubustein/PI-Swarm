# 🚀 Pi-Swarm v2.0.0

> **Enterprise-grade Docker Swarm orchestration platform for Raspberry Pi clusters**

Pi-Swarm transforms your Raspberry Pi devices into a powerful, production-ready Docker Swarm cluster with monitoring, security, and automated deployment capabilities.

## 📄 Main Script

- **`deploy.sh`** (in project root): The single entry point for all deployment and management operations. It provides an interactive menu to:
  - Launch automated or interactive deployments
  - Run validation and troubleshooting
  - Access advanced and demo features

## ✨ Features

- 🐳 **Automated Docker Swarm Setup**
- � **Shared Storage Integration** (GlusterFS with SSD support)
- 🌐 **DNS Server** (Pi-hole with ad-blocking and local resolution)
- �📊 **Built-in Monitoring** (Prometheus, Grafana)
- 🔒 **Security Hardening** (SSH, firewall, SSL)
- 🌐 **Service Management** (Portainer)
- 🚨 **Alert Integration** (Slack, Email, Discord, WhatsApp)
- 🤖 **LLM-Powered Alerts**
- 🔄 **High Availability**
- 📱 **Web Dashboard**

## 🚀 Quick Start

```bash
git clone <your-repo-url>
cd PI-Swarm
chmod +x deploy.sh
./deploy.sh
```

## 📚 Documentation

- [Deployment Guide](docs/deployment/DEPLOYMENT_GUIDE.md)
- [Storage Integration Guide](docs/STORAGE_INTEGRATION_GUIDE.md)
- [DNS Integration Guide](docs/DNS_INTEGRATION_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [FAQ](docs/FAQ.md)
- [Security](docs/SECURITY.md)
- [Portainer Integration](docs/PORTAINER_INTEGRATION.md)
- [Context-Aware Deployment](docs/deployment/CONTEXT_AWARE_DEPLOYMENT_COMPLETE.md)
- [Enterprise Features](docs/enterprise/ENTERPRISE_FEATURES.md)
- [Directory Structure](docs/DIRECTORY_STRUCTURE.md)

For more, see the [docs/](docs/) folder.

## 🤝 Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md)

## 🛡️ License
See [LICENSE](LICENSE)

---

> For advanced usage, see the interactive menu in `deploy.sh` or explore the [docs/](docs/) directory for detailed guides.
