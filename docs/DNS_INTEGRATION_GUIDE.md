# DNS Integration Guide for Pi-Swarm

## Overview

Pi-Swarm now includes integrated Pi-hole DNS server support, providing local DNS resolution, ad-blocking, and centralized DNS management for your Raspberry Pi cluster.

## Features

### 🌐 Pi-hole DNS Server
- **Local DNS Resolution**: Resolve cluster nodes by hostname (e.g., `pi-node-1.cluster.local`)
- **Ad Blocking**: Built-in ad-blocking for all cluster traffic
- **Web Interface**: User-friendly web dashboard for DNS management
- **Service Discovery**: Automatic DNS entries for Docker services
- **Upstream DNS**: Configurable upstream DNS servers (default: Cloudflare & Google)

### 🔧 Automatic Configuration
- **Cluster-wide DNS**: All Pis configured to use Pi-hole as primary DNS
- **Docker Integration**: Docker containers use Pi-hole for DNS resolution
- **Service URLs**: Easy access to services via friendly URLs
- **Backup DNS**: Fallback DNS servers for reliability

## Installation

### During Initial Deployment

When running `./deploy.sh`, you'll be prompted:

```bash
🌐 DNS CONFIGURATION
===================

Do you want to set up Pi-hole as a local DNS server?
Benefits of Pi-hole DNS:
• Ad-blocking for all network traffic
• Local hostname resolution (pi-node-1.cluster.local)
• Better container networking with DNS names
• Centralized DNS management for the cluster

Enable Pi-hole DNS server? (Y/n): Y
```

Select **Y** to enable Pi-hole DNS integration.

### Configuration Options

The system will automatically configure:

| Setting | Default Value | Description |
|---------|---------------|-------------|
| **Pi-hole Server** | First Pi in cluster | Which Pi hosts the DNS server |
| **Domain Name** | `cluster.local` | Local domain for the cluster |
| **Admin Password** | *set during deployment* | Web interface password |
| **Upstream DNS** | `1.1.1.1, 8.8.8.8` | External DNS servers |

## Usage

### Accessing Services

Once deployed, you can access services using friendly URLs:

| Service | URL | Description |
|---------|-----|-------------|
| **Pi-hole Admin** | `http://pihole.cluster.local/admin` | DNS management dashboard |
| **Portainer** | `http://portainer.cluster.local:9000` | Container management |
| **Grafana** | `http://grafana.cluster.local:3000` | Monitoring dashboard |
| **Prometheus** | `http://prometheus.cluster.local:9090` | Metrics collection |

### Node Access

Access individual Pis by hostname:

```bash
# SSH to nodes by hostname
ssh pi@pi-node-1.cluster.local
ssh pi@pi-node-2.cluster.local

# Ping nodes
ping pi-node-1.cluster.local
```

### Docker Service Discovery

Docker containers automatically resolve cluster hostnames:

```yaml
# docker-compose.yml example
version: '3.8'
services:
  web:
    image: nginx
    environment:
      - DATABASE_HOST=pi-node-2.cluster.local
```

## Management

### Pi-hole Web Interface

1. **Access**: Navigate to `http://pihole.cluster.local/admin`
2. **Login**: Sign in with the password you configured
3. **Features**:
   - View DNS query logs
   - Manage blocklists
   - Add custom DNS entries
   - Monitor network traffic

### Adding Custom DNS Entries

#### Via Web Interface
1. Go to Pi-hole admin → Local DNS → DNS Records
2. Add domain/IP mappings as needed

#### Via Command Line
```bash
# SSH to the Pi-hole server (usually first Pi)
ssh pi@pi-node-1.cluster.local

# Add custom DNS entry
echo "192.168.1.100 myapp.cluster.local" | sudo tee -a /etc/pihole/custom.list
sudo pihole restartdns
```

### DNS Configuration Files

Pi-hole configuration is stored in:
- **Custom DNS entries**: `/etc/pihole/custom.list`
- **Pi-hole config**: `/etc/pihole/setupVars.conf`
- **Cluster config**: `$PROJECT_ROOT/data/pihole-config.env`

## Troubleshooting

### Common Issues

#### 1. DNS Resolution Not Working

**Symptoms**: Cannot resolve `.cluster.local` hostnames

**Solutions**:
```bash
# Check Pi-hole status
ssh pi@[first-pi-ip]
sudo pihole status

# Test DNS resolution
nslookup pihole.cluster.local
nslookup google.com

# Restart Pi-hole
sudo systemctl restart pihole-FTL
```

#### 2. Web Interface Inaccessible

**Symptoms**: Cannot access `http://pihole.cluster.local/admin`

**Solutions**:
```bash
# Check Pi-hole service
sudo systemctl status pihole-FTL

# Check lighttpd (web server)
sudo systemctl status lighttpd

# Restart services
sudo systemctl restart pihole-FTL lighttpd
```

#### 3. Ad Blocking Not Working

**Symptoms**: Ads still visible on web pages

**Solutions**:
1. Check Pi-hole is being used as DNS:
   ```bash
   nslookup doubleclick.net
   # Should return Pi-hole IP (blocked)
   ```

2. Update blocklists:
   ```bash
   sudo pihole -g
   ```

3. Verify DNS settings in browser/device

### DNS Fallback

If Pi-hole fails, the system falls back to:
1. **Secondary DNS**: `1.1.1.1` (Cloudflare)
2. **Tertiary DNS**: `8.8.8.8` (Google)

### Manual DNS Reset

To reset DNS to external servers:

```bash
# On each Pi
sudo chattr -i /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

## Advanced Configuration

### Custom Upstream DNS

To change upstream DNS servers:

```bash
# SSH to Pi-hole server
ssh pi@pi-node-1.cluster.local

# Edit Pi-hole config
sudo nano /etc/pihole/setupVars.conf

# Change PIHOLE_DNS_1 and PIHOLE_DNS_2
# Then restart
sudo systemctl restart pihole-FTL
```

### DHCP Integration

Pi-hole can also serve as DHCP server:

1. Access Pi-hole admin → Settings → DHCP
2. Enable DHCP server
3. Configure IP range and gateway
4. Disable DHCP on your router

### DNS-over-HTTPS (DoH)

Enable secure DNS resolution:

```bash
# Install cloudflared
sudo wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
sudo chmod +x cloudflared-linux-arm64
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared

# Configure DoH
sudo cloudflared service install --legacy
sudo systemctl start cloudflared

# Update Pi-hole to use local DoH
# Set upstream DNS to 127.0.0.1#5053
```

## Integration with Other Services

### Docker Compose Integration

```yaml
version: '3.8'
services:
  app:
    image: my-app
    dns:
      - "${PIHOLE_SERVER_IP}"
      - "1.1.1.1"
    environment:
      - DATABASE_HOST=pi-node-2.cluster.local
```

### Monitoring Integration

Pi-hole metrics are automatically collected by Prometheus:

- DNS query rates
- Blocked query statistics
- Top domains and clients
- Pi-hole service status

View in Grafana at `http://grafana.cluster.local:3000`

## Security Considerations

### Access Control

- **Web Interface**: Protected by password
- **SSH Access**: Use key-based authentication
- **Firewall**: Consider limiting DNS access to cluster network

### DNS Security

- **DNSSEC**: Enable in Pi-hole settings for DNS validation
- **Upstream Encryption**: Use DoH/DoT for upstream queries
- **Log Privacy**: Consider log retention policies

### Network Isolation

```bash
# Limit DNS access to cluster network only
sudo iptables -A INPUT -p udp --dport 53 ! -s 192.168.1.0/24 -j DROP
sudo iptables -A INPUT -p tcp --dport 53 ! -s 192.168.1.0/24 -j DROP
```

## Performance Tuning

### Cache Configuration

Adjust DNS cache settings for better performance:

```bash
# Edit dnsmasq config
sudo nano /etc/dnsmasq.d/01-pihole.conf

# Add/modify:
cache-size=10000
local-ttl=300
```

### Log Management

Manage Pi-hole logs to prevent disk space issues:

```bash
# Configure log rotation
sudo nano /etc/logrotate.d/pihole

# Content:
/var/log/pihole.log {
    daily
    missingok
    rotate 5
    compress
    notifempty
    create 644 pihole pihole
    postrotate
        sudo systemctl reload pihole-FTL
    endscript
}
```

## Migration and Backup

### Backup Pi-hole Configuration

```bash
# Create backup script
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/pi/pihole-backups"
mkdir -p "$BACKUP_DIR"

# Backup Pi-hole settings
sudo cp /etc/pihole/setupVars.conf "$BACKUP_DIR/setupVars_$DATE.conf"
sudo cp /etc/pihole/custom.list "$BACKUP_DIR/custom_$DATE.list"
sudo cp /etc/pihole/adlists.list "$BACKUP_DIR/adlists_$DATE.list"

# Export settings via CLI
pihole -a -t "$BACKUP_DIR/teleporter_$DATE.tar.gz"
```

### Restore Configuration

```bash
# Restore from backup
sudo cp setupVars_YYYYMMDD.conf /etc/pihole/setupVars.conf
sudo cp custom_YYYYMMDD.list /etc/pihole/custom.list
sudo systemctl restart pihole-FTL
```

### Migrate to Different Pi

1. **Backup** current Pi-hole configuration
2. **Disable** Pi-hole on old Pi
3. **Update** DNS configuration to point to new Pi
4. **Install** Pi-hole on new Pi
5. **Restore** configuration from backup

## FAQ

### Q: Can I use external DNS instead of Pi-hole?
**A**: Yes, Pi-hole is optional. The deployment script allows you to skip DNS setup.

### Q: What if Pi-hole server goes down?
**A**: All Pis have fallback DNS servers configured. DNS resolution continues with `1.1.1.1` and `8.8.8.8`.

### Q: Can I run Pi-hole on a different Pi later?
**A**: Yes, but you'll need to update DNS settings on all Pis and Docker configurations.

### Q: Does Pi-hole affect internet speed?
**A**: Minimal impact. DNS caching actually improves performance for repeated queries.

### Q: Can I access Pi-hole from outside the cluster?
**A**: By default, no. You can configure port forwarding on your router if needed.

### Q: How do I update Pi-hole?
**A**: 
```bash
ssh pi@pi-node-1.cluster.local
pihole -up
```

---

## Support

For issues specific to Pi-hole integration:

1. **Check logs**: `sudo tail -f /var/log/pihole.log`
2. **Test DNS**: Use `nslookup` and `dig` commands
3. **Review setup**: Check `/etc/pihole/setupVars.conf`
4. **Community**: Visit [Pi-hole Discourse](https://discourse.pi-hole.net/)

For Pi-Swarm specific issues, check the main troubleshooting guide.
