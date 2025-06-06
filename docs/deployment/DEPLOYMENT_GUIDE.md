# Pi-Swarm Deployment Guide

## Quick Start Options

Pi-Swarm offers multiple deployment methods to suit different needs:

### 1. Enhanced Automated Deployment (Recommended)
For the best user experience with connectivity checks and helpful feedback:
```bash
./enhanced-deploy.sh
```

**Features:**
- ✅ Pre-deployment connectivity checks
- ✅ Helpful troubleshooting tips
- ✅ Comprehensive deployment summary
- ✅ Clear next steps and access URLs

### 2. Basic Automated Deployment
For simple automated deployment without user interaction:
```bash
./automated-deploy.sh
```

**Features:**
- ✅ Fully automated (no user input required)
- ✅ Handles all interactive prompts
- ✅ Suitable for CI/CD pipelines

### 3. Interactive Deployment
For full control over all configuration options:
```bash
./core/swarm-cluster.sh
```

**Features:**
- ✅ Configure enterprise features (SSL, alerts, HA)
- ✅ Custom domain and email setup
- ✅ Advanced monitoring options

## Pre-Deployment Checklist

Before running any deployment:

1. **Hardware Ready**
   - [ ] Raspberry Pis powered on and connected to network
   - [ ] All Pis have fresh Raspberry Pi OS installed
   - [ ] SSH enabled on all Pis

2. **Network Configuration**
   - [ ] Pis have static IP addresses or DHCP reservations
   - [ ] You know the IP addresses of your Pis
   - [ ] All Pis can reach the internet for package downloads

3. **Credentials**
   - [ ] You know the username and password for your Pis
   - [ ] **Set unique credentials for each Pi; do not rely on defaults**

4. **Local Machine**
   - [ ] SSH client available
   - [ ] Network connectivity to Pi network

## Post-Deployment Access

After successful deployment, you can access:

### Management Interfaces
- **Portainer**: http://YOUR_PI_IP:9000
  - Username: admin
  - Password: *your chosen password*
  - Manage containers, services, and swarm

- **Grafana**: http://YOUR_PI_IP:3000
  - Username: admin
  - Password: admin (change on first login)
  - Monitor cluster performance and health

### Useful Commands
```bash
# Check cluster status
./scripts/management/show-cluster-status.sh

# Run comprehensive tests
./scripts/testing/comprehensive-test.sh

# View logs
tail -f data/logs/piswarm-$(date +%Y%m%d).log
```

## Troubleshooting

### Common Issues

1. **"No Pis are reachable"**
   - Check Pi power and network connections
   - Verify IP addresses are correct
   - Test with: `ping YOUR_PI_IP`

2. **"SSH connection failed"**
   - Verify username and password
   - Ensure SSH is enabled on Pis
   - Try manual SSH: `ssh luser@YOUR_PI_IP`

3. **"Service deployment failed"**
   - Check internet connectivity on Pis
   - Verify Docker installation completed
   - Check available disk space

4. **"Docker Swarm not active"**
   - Ensure all Pis are reachable
   - Check for port conflicts (2377, 7946, 4789)
   - Verify Docker service is running

### Getting Help

- **Documentation**: See `docs/TROUBLESHOOTING.md` and `docs/FAQ.md`
- **Logs**: Check `data/logs/` for detailed error information
- **Community**: GitHub Issues for bug reports and questions

## Advanced Configuration

### Enterprise Features
For production deployments, consider enabling:

- **SSL/TLS Encryption**: Secure web interfaces
- **Slack/Discord Alerts**: Real-time notifications
- **Email Alerts**: SMTP-based alerting
- **High Availability**: Multi-manager setup
- **Advanced Monitoring**: Enhanced metrics collection

Run interactive deployment to configure these features:
```bash
./core/swarm-cluster.sh
```

### Custom Configuration
Edit configuration files before deployment:

- `config/docker-compose.monitoring.yml` - Service definitions
- `config/prometheus.yml` - Monitoring configuration
- `config/prometheus-alerts.yml` - Alert rules

## Security Considerations

- Change default passwords after deployment
- Configure firewall rules as needed
- Enable SSH key authentication
- Consider VPN access for remote management
- Regular security updates on all Pis

## Next Steps

1. **Explore Portainer**: Learn container management
2. **Set Up Monitoring**: Configure Grafana dashboards
3. **Deploy Applications**: Use the swarm for your projects
4. **Backup Configuration**: Regular backups of important data
5. **Community**: Share your experience and contribute back

---

**Need help?** Check our documentation or open an issue on GitHub!
