# Pi-Swarm Storage Integration - Complete Guide

## Overview

Your Pi-Swarm deployment now includes integrated shared storage support using GlusterFS and your 250GB SSDs. This provides high-availability, distributed storage across all Raspberry Pis in your cluster.

## Storage Architecture

### GlusterFS Distributed Storage
- **Replication**: Data is replicated across multiple Pis for high availability
- **Auto-detection**: Automatically finds and uses your 250GB SSDs
- **Performance**: Distributed reads and writes for better performance
- **Scalability**: Easy to add more storage nodes to the cluster

### Storage Layout
```
/mnt/shared-storage/
├── docker-volumes/          # Docker persistent volumes
├── portainer-data/          # Portainer configuration and data
├── grafana-data/            # Grafana dashboards and metrics
├── prometheus-data/         # Prometheus metrics storage
└── app-data/               # Custom application data
```

## Deployment Process

### 1. Start Deployment
```bash
./deploy.sh
```

### 2. Choose Storage Configuration
When prompted:
- Select **Y** for "Enable shared storage?"
- This configures GlusterFS using your 250GB SSDs

### 3. Select Deployment Option
- **Option 1**: Automated (uses storage defaults)
- **Option 2**: Enhanced Interactive (recommended)
- **Option 3**: Traditional (manual configuration)

## Storage Setup Process

The deployment automatically:

1. **Detection**: Auto-detects 250GB SSDs on each Pi
2. **Installation**: Installs GlusterFS server and client on all nodes
3. **Formatting**: Creates ext4 filesystem on SSDs
4. **Mounting**: Mounts SSDs at `/mnt/gluster-storage`
5. **Clustering**: Creates GlusterFS peer cluster
6. **Volume Creation**: Creates distributed/replicated volume
7. **Client Mount**: Mounts shared storage at `/mnt/shared-storage`
8. **Docker Integration**: Configures Docker to use shared storage

## Docker Integration

### Automatic Configuration
Docker is automatically configured to:
- Use shared storage for persistent volumes
- Store container data on distributed filesystem
- Enable cross-node data access

### Manual Volume Creation
Create Docker volumes using shared storage:

```bash
# Standard volume on shared storage
docker volume create --driver local \
  --opt type=none \
  --opt device=/mnt/shared-storage/docker-volumes/myapp \
  --opt o=bind myapp-data

# Use in docker-compose.yml
services:
  myapp:
    volumes:
      - myapp-data:/app/data
volumes:
  myapp-data:
    external: true
```

### Service Templates with Storage
Deploy services that automatically use shared storage:

```bash
# Deploy Portainer with shared storage
./pi-swarm deploy-template portainer

# Deploy Grafana with persistent data
./pi-swarm deploy-template grafana

# Deploy custom apps with data persistence
./pi-swarm deploy-template webapp
```

## Storage Management Commands

### Check Storage Status
```bash
# GlusterFS cluster status
sudo gluster peer status

# Volume information
sudo gluster volume info

# Volume status and health
sudo gluster volume status

# Storage usage
df -h /mnt/shared-storage
```

### Monitor Storage Health
```bash
# Check mount points
mount | grep gluster

# Monitor I/O performance
iostat -x 1

# Check filesystem health
sudo fsck.ext4 -n /dev/sda1  # Non-destructive check
```

## Benefits

### High Availability
- **Data Replication**: Files stored on multiple Pis
- **Automatic Failover**: Access continues if a Pi goes down
- **Self-Healing**: Automatic recovery when nodes return

### Performance
- **Distributed I/O**: Read/write operations across multiple disks
- **Local Access**: Each Pi can access data locally when possible
- **Parallel Operations**: Multiple concurrent operations

### Scalability
- **Easy Expansion**: Add more Pis with SSDs to increase capacity
- **Elastic Volumes**: Expand storage without downtime
- **Load Distribution**: Automatic load balancing across nodes

## Troubleshooting

### Storage Not Detected
If 250GB SSDs aren't detected:
1. Check connections: `lsblk`
2. Verify SSD health: `sudo smartctl -a /dev/sda`
3. Manual detection: Set `STORAGE_DEVICE="/dev/sda1"` before deployment

### GlusterFS Issues
```bash
# Restart GlusterFS
sudo systemctl restart glusterd

# Force heal volumes
sudo gluster volume heal VOLUME_NAME

# Check logs
sudo tail -f /var/log/glusterfs/glusterd.log
```

### Docker Storage Issues
```bash
# Restart Docker with new config
sudo systemctl restart docker

# Check Docker storage driver
docker info | grep "Storage Driver"

# Verify volume mounts
docker volume ls
docker volume inspect VOLUME_NAME
```

## Advanced Configuration

### Custom Storage Devices
To use different storage devices:
```bash
export STORAGE_DEVICE="/dev/sdb1"  # Custom device
export STORAGE_SOLUTION="glusterfs"
./deploy.sh
```

### Multiple Storage Solutions
Future support for:
- **NFS**: Network File System
- **Longhorn**: Cloud-native distributed storage
- **Local**: Individual Pi storage (no sharing)

### Performance Tuning
Optimize for your workload:
```bash
# High-performance applications
sudo gluster volume set VOLUME_NAME performance.cache-size 512MB

# Network optimization
sudo gluster volume set VOLUME_NAME network.ping-timeout 10
```

## Security

### Access Control
- GlusterFS uses trusted networks
- SSH key authentication between nodes
- Filesystem permissions enforced

### Data Encryption
Future enhancement:
- At-rest encryption for stored data
- In-transit encryption between nodes

## Monitoring Integration

### Grafana Dashboards
- Storage capacity and usage
- GlusterFS performance metrics
- I/O patterns and bottlenecks

### Prometheus Metrics
- Disk utilization
- Network throughput
- Storage health status

### Alerting
- Disk space warnings
- Node failures
- Performance degradation

## Backup and Recovery

### Automated Backups
The system includes:
- Configuration backups
- Volume snapshots
- Cross-node replication

### Disaster Recovery
- Full cluster rebuild procedures
- Data recovery from replicas
- Point-in-time restore capabilities

## Next Steps

1. **Deploy**: Run `./deploy.sh` with storage enabled
2. **Monitor**: Access Grafana dashboard for storage metrics
3. **Optimize**: Tune performance based on your workload
4. **Scale**: Add more Pis with SSDs as needed

For support and advanced configurations, see:
- `/home/luser/PI-Swarm/docs/TROUBLESHOOTING.md`
- `/home/luser/PI-Swarm/docs/FAQ.md`
- Storage logs: `/home/luser/PI-Swarm/data/logs/`
