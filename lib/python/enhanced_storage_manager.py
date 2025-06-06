#!/usr/bin/env python3
"""
Enhanced Storage Manager for Pi-Swarm
Provides comprehensive storage management, including GlusterFS, NFS, and local storage solutions.
"""

import argparse
import json
import logging
import sys
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import concurrent.futures
from dataclasses import dataclass
import yaml
import tempfile

# Enhanced logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class StorageDevice:
    """Storage device information"""
    name: str
    size: str
    type: str
    mountpoint: str
    filesystem: str
    available: bool
    
@dataclass
class StorageNode:
    """Storage node information"""
    ip: str
    hostname: str
    devices: List[StorageDevice]
    status: str
    role: str

@dataclass 
class StorageVolume:
    """Storage volume information"""
    name: str
    type: str
    size: str
    replicas: int
    nodes: List[str]
    status: str
    mountpoint: str

class StorageManager:
    """Enhanced storage management for Pi-Swarm"""
    
    SUPPORTED_SOLUTIONS = ["glusterfs", "nfs", "longhorn", "local"]
    
    def __init__(self, nodes: List[str], ssh_user: str = "pi", ssh_pass: str = "",
                 config_file: str = "/etc/piswarm/storage.yml"):
        self.nodes = nodes
        self.ssh_user = ssh_user
        self.ssh_pass = ssh_pass
        self.config_file = Path(config_file)
        self.config = self._load_config()
        
        # Default configuration
        self.default_config = {
            'storage_solution': 'glusterfs',
            'storage_device': 'auto',
            'storage_size_min': 100,  # GB
            'shared_storage_path': '/mnt/shared-storage',
            'docker_storage_path': '/mnt/shared-storage/docker-volumes',
            'glusterfs': {
                'volume_name': 'piswarm-data',
                'replica_count': 2,
                'transport': 'tcp'
            },
            'nfs': {
                'export_path': '/srv/nfs',
                'client_options': 'rw,sync,no_subtree_check'
            }
        }
    
    def _load_config(self) -> Dict:
        """Load storage configuration"""
        if self.config_file.exists():
            try:
                with open(self.config_file) as f:
                    return yaml.safe_load(f) or {}
            except Exception as e:
                logger.warning(f"Failed to load config: {e}")
        return {}
    
    def _save_config(self):
        """Save storage configuration"""
        try:
            self.config_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.config_file, 'w') as f:
                yaml.dump(self.config, f, default_flow_style=False)
        except Exception as e:
            logger.error(f"Failed to save config: {e}")
    
    def _ssh_exec(self, node_ip: str, command: str, timeout: int = 30) -> Tuple[str, str, int]:
        """Execute command via SSH"""
        if self.ssh_pass:
            ssh_cmd = [
                'sshpass', '-p', self.ssh_pass,
                'ssh', '-o', 'StrictHostKeyChecking=no',
                '-o', f'ConnectTimeout={timeout}',
                f'{self.ssh_user}@{node_ip}',
                command
            ]
        else:
            ssh_cmd = [
                'ssh', '-o', 'StrictHostKeyChecking=no',
                '-o', f'ConnectTimeout={timeout}',
                f'{self.ssh_user}@{node_ip}',
                command
            ]
        
        try:
            result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=timeout)
            return result.stdout.strip(), result.stderr.strip(), result.returncode
        except subprocess.TimeoutExpired:
            return "", "SSH command timed out", 124
        except Exception as e:
            return "", f"SSH execution failed: {e}", 1
    
    def detect_storage_devices(self, node_ip: str) -> List[StorageDevice]:
        """Detect available storage devices on a node"""
        command = """
        lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | jq -r '.blockdevices[] | 
        select(.type=="disk") | 
        {name: .name, size: .size, type: .type, mountpoint: .mountpoint, fstype: .fstype} | 
        @json'
        """
        
        stdout, stderr, returncode = self._ssh_exec(node_ip, command)
        devices = []
        
        if returncode == 0 and stdout:
            for line in stdout.strip().split('\n'):
                try:
                    device_data = json.loads(line)
                    
                    # Skip devices mounted to root or boot
                    mountpoint = device_data.get('mountpoint') or ''
                    if mountpoint in ['/', '/boot'] or mountpoint.startswith('/boot'):
                        continue
                    
                    # Check if device size suggests it's suitable for storage
                    size_str = device_data.get('size', '')
                    size_gb = self._parse_size_to_gb(size_str)
                    
                    if size_gb >= self.default_config['storage_size_min']:
                        devices.append(StorageDevice(
                            name=f"/dev/{device_data.get('name', '')}",
                            size=size_str,
                            type=device_data.get('type', 'disk'),
                            mountpoint=mountpoint,
                            filesystem=device_data.get('fstype', ''),
                            available=not bool(mountpoint)
                        ))
                except (json.JSONDecodeError, KeyError) as e:
                    logger.warning(f"Failed to parse device data: {e}")
                    continue
        
        return devices
    
    def _parse_size_to_gb(self, size_str: str) -> float:
        """Parse size string to GB"""
        if not size_str:
            return 0
            
        size_str = size_str.upper().strip()
        multipliers = {'K': 0.001, 'M': 1/1024, 'G': 1, 'T': 1024}
        
        for suffix, multiplier in multipliers.items():
            if size_str.endswith(suffix):
                try:
                    return float(size_str[:-1]) * multiplier
                except ValueError:
                    break
        
        try:
            return float(size_str) / (1024**3)  # Assume bytes
        except ValueError:
            return 0
    
    def scan_storage_nodes(self) -> List[StorageNode]:
        """Scan all nodes for storage information"""
        storage_nodes = []
        
        def scan_node(node_ip: str) -> StorageNode:
            # Get hostname
            hostname_cmd = "hostname"
            hostname, _, ret = self._ssh_exec(node_ip, hostname_cmd)
            if ret != 0:
                hostname = f"node-{node_ip.split('.')[-1]}"
            
            # Detect storage devices
            devices = self.detect_storage_devices(node_ip)
            
            # Check node status
            status_cmd = "uptime"
            _, _, status_ret = self._ssh_exec(node_ip, status_cmd)
            status = "online" if status_ret == 0 else "offline"
            
            return StorageNode(
                ip=node_ip,
                hostname=hostname,
                devices=devices,
                status=status,
                role="storage"
            )
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_ip = {
                executor.submit(scan_node, node_ip): node_ip 
                for node_ip in self.nodes
            }
            
            for future in concurrent.futures.as_completed(future_to_ip):
                try:
                    node = future.result()
                    storage_nodes.append(node)
                except Exception as e:
                    node_ip = future_to_ip[future]
                    logger.error(f"Failed to scan node {node_ip}: {e}")
        
        return storage_nodes
    
    def setup_glusterfs(self, nodes: List[str], volume_name: str = "piswarm-data", 
                       replica_count: int = 2) -> bool:
        """Setup GlusterFS cluster"""
        logger.info(f"Setting up GlusterFS cluster with {len(nodes)} nodes")
        
        # Install GlusterFS on all nodes
        install_cmd = """
        sudo apt-get update && 
        sudo apt-get install -y glusterfs-server && 
        sudo systemctl enable glusterd && 
        sudo systemctl start glusterd
        """
        
        def install_on_node(node_ip: str) -> bool:
            stdout, stderr, ret = self._ssh_exec(node_ip, install_cmd, timeout=300)
            if ret != 0:
                logger.error(f"Failed to install GlusterFS on {node_ip}: {stderr}")
                return False
            return True
        
        # Install GlusterFS on all nodes in parallel
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            install_results = list(executor.map(install_on_node, nodes))
        
        if not all(install_results):
            logger.error("Failed to install GlusterFS on some nodes")
            return False
        
        # Peer probe from first node to others
        primary_node = nodes[0]
        for node_ip in nodes[1:]:
            probe_cmd = f"sudo gluster peer probe {node_ip}"
            stdout, stderr, ret = self._ssh_exec(primary_node, probe_cmd)
            if ret != 0:
                logger.error(f"Failed to probe peer {node_ip}: {stderr}")
                return False
            logger.info(f"Successfully probed peer {node_ip}")
        
        # Create brick directories
        brick_path = f"/gluster/brick1/{volume_name}"
        for node_ip in nodes:
            mkdir_cmd = f"sudo mkdir -p {brick_path}"
            stdout, stderr, ret = self._ssh_exec(node_ip, mkdir_cmd)
            if ret != 0:
                logger.error(f"Failed to create brick directory on {node_ip}: {stderr}")
                return False
        
        # Create GlusterFS volume
        brick_list = " ".join([f"{node}:{brick_path}" for node in nodes])
        
        if replica_count > 1 and len(nodes) >= replica_count:
            create_cmd = f"sudo gluster volume create {volume_name} replica {replica_count} {brick_list} force"
        else:
            create_cmd = f"sudo gluster volume create {volume_name} {brick_list} force"
        
        stdout, stderr, ret = self._ssh_exec(primary_node, create_cmd)
        if ret != 0:
            logger.error(f"Failed to create GlusterFS volume: {stderr}")
            return False
        
        # Start the volume
        start_cmd = f"sudo gluster volume start {volume_name}"
        stdout, stderr, ret = self._ssh_exec(primary_node, start_cmd)
        if ret != 0:
            logger.error(f"Failed to start GlusterFS volume: {stderr}")
            return False
        
        # Mount volume on all nodes
        mount_point = self.default_config['shared_storage_path']
        for node_ip in nodes:
            mount_cmds = [
                f"sudo mkdir -p {mount_point}",
                f"sudo mount -t glusterfs localhost:/{volume_name} {mount_point}",
                f"echo 'localhost:/{volume_name} {mount_point} glusterfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab"
            ]
            
            for cmd in mount_cmds:
                stdout, stderr, ret = self._ssh_exec(node_ip, cmd)
                if ret != 0:
                    logger.warning(f"Command failed on {node_ip}: {cmd} - {stderr}")
        
        logger.info(f"GlusterFS setup completed for volume {volume_name}")
        return True
    
    def setup_nfs(self, server_node: str, client_nodes: List[str]) -> bool:
        """Setup NFS server and clients"""
        logger.info(f"Setting up NFS server on {server_node}")
        
        export_path = self.default_config['nfs']['export_path']
        mount_point = self.default_config['shared_storage_path']
        
        # Setup NFS server
        server_cmds = [
            "sudo apt-get update && sudo apt-get install -y nfs-kernel-server",
            f"sudo mkdir -p {export_path}",
            f"sudo chown nobody:nogroup {export_path}",
            f"sudo chmod 777 {export_path}",
            f"echo '{export_path} *(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports",
            "sudo exportfs -a",
            "sudo systemctl restart nfs-kernel-server"
        ]
        
        for cmd in server_cmds:
            stdout, stderr, ret = self._ssh_exec(server_node, cmd, timeout=120)
            if ret != 0:
                logger.error(f"NFS server setup failed: {cmd} - {stderr}")
                return False
        
        # Setup NFS clients
        def setup_client(client_ip: str) -> bool:
            client_cmds = [
                "sudo apt-get update && sudo apt-get install -y nfs-common",
                f"sudo mkdir -p {mount_point}",
                f"sudo mount -t nfs {server_node}:{export_path} {mount_point}",
                f"echo '{server_node}:{export_path} {mount_point} nfs defaults 0 0' | sudo tee -a /etc/fstab"
            ]
            
            for cmd in client_cmds:
                stdout, stderr, ret = self._ssh_exec(client_ip, cmd, timeout=60)
                if ret != 0:
                    logger.error(f"NFS client setup failed on {client_ip}: {cmd} - {stderr}")
                    return False
            return True
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            client_results = list(executor.map(setup_client, client_nodes))
        
        if not all(client_results):
            logger.error("Failed to setup NFS on some client nodes")
            return False
        
        logger.info("NFS setup completed successfully")
        return True
    
    def get_storage_status(self) -> Dict[str, Any]:
        """Get comprehensive storage status"""
        status = {
            'nodes': [],
            'volumes': [],
            'summary': {
                'total_nodes': len(self.nodes),
                'online_nodes': 0,
                'total_volumes': 0,
                'healthy_volumes': 0
            }
        }
        
        # Scan storage nodes
        storage_nodes = self.scan_storage_nodes()
        
        for node in storage_nodes:
            status['nodes'].append({
                'ip': node.ip,
                'hostname': node.hostname,
                'status': node.status,
                'devices': [
                    {
                        'name': dev.name,
                        'size': dev.size,
                        'type': dev.type,
                        'filesystem': dev.filesystem,
                        'available': dev.available,
                        'mountpoint': dev.mountpoint
                    }
                    for dev in node.devices
                ]
            })
            
            if node.status == "online":
                status['summary']['online_nodes'] += 1
        
        # Check for GlusterFS volumes (if available)
        if self.nodes:
            gluster_cmd = "sudo gluster volume info"
            stdout, stderr, ret = self._ssh_exec(self.nodes[0], gluster_cmd)
            if ret == 0 and stdout:
                # Parse GlusterFS volume information
                volume_info = self._parse_gluster_volume_info(stdout)
                status['volumes'].extend(volume_info)
                status['summary']['total_volumes'] = len(volume_info)
                status['summary']['healthy_volumes'] = sum(
                    1 for vol in volume_info if vol.get('status') == 'Started'
                )
        
        return status
    
    def _parse_gluster_volume_info(self, volume_info: str) -> List[Dict]:
        """Parse GlusterFS volume information"""
        volumes = []
        current_volume = {}
        
        for line in volume_info.split('\n'):
            line = line.strip()
            if line.startswith('Volume Name:'):
                if current_volume:
                    volumes.append(current_volume)
                current_volume = {'name': line.split(':', 1)[1].strip()}
            elif line.startswith('Type:'):
                current_volume['type'] = line.split(':', 1)[1].strip()
            elif line.startswith('Status:'):
                current_volume['status'] = line.split(':', 1)[1].strip()
            elif line.startswith('Number of Bricks:'):
                current_volume['brick_count'] = line.split(':', 1)[1].strip()
        
        if current_volume:
            volumes.append(current_volume)
        
        return volumes
    
    def create_docker_volume(self, volume_name: str, driver: str = "local", 
                           options: Optional[Dict] = None) -> bool:
        """Create a Docker volume with specified driver"""
        if not options:
            options = {}
        
        # Build docker volume create command
        cmd_parts = ["docker", "volume", "create"]
        
        if driver != "local":
            cmd_parts.extend(["--driver", driver])
        
        for key, value in options.items():
            cmd_parts.extend(["--opt", f"{key}={value}"])
        
        cmd_parts.append(volume_name)
        cmd = " ".join(cmd_parts)
        
        # Create volume on the first node (manager)
        stdout, stderr, ret = self._ssh_exec(self.nodes[0], cmd)
        if ret != 0:
            logger.error(f"Failed to create Docker volume {volume_name}: {stderr}")
            return False
        
        logger.info(f"Docker volume {volume_name} created successfully")
        return True
    
    def optimize_storage_performance(self) -> Dict[str, Any]:
        """Apply storage performance optimizations"""
        optimizations = {
            'applied': [],
            'failed': [],
            'recommendations': []
        }
        
        def optimize_node(node_ip: str) -> List[str]:
            node_optimizations = []
            
            # Optimize filesystem mount options
            remount_cmd = "sudo mount -o remount,noatime,nodiratime /"
            stdout, stderr, ret = self._ssh_exec(node_ip, remount_cmd)
            if ret == 0:
                node_optimizations.append(f"{node_ip}: Filesystem mount optimized")
            
            # Set optimal I/O scheduler for SSDs
            ssd_cmd = """
            for dev in /sys/block/*/queue/scheduler; do
                if [[ -f "$dev" ]]; then
                    echo noop | sudo tee "$dev" > /dev/null 2>&1
                fi
            done
            """
            stdout, stderr, ret = self._ssh_exec(node_ip, ssd_cmd)
            if ret == 0:
                node_optimizations.append(f"{node_ip}: I/O scheduler optimized")
            
            return node_optimizations
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_ip = {
                executor.submit(optimize_node, node_ip): node_ip 
                for node_ip in self.nodes
            }
            
            for future in concurrent.futures.as_completed(future_to_ip):
                try:
                    node_optimizations = future.result()
                    optimizations['applied'].extend(node_optimizations)
                except Exception as e:
                    node_ip = future_to_ip[future]
                    optimizations['failed'].append(f"{node_ip}: {str(e)}")
        
        return optimizations
    
    def cleanup_storage(self, dry_run: bool = True) -> Dict[str, Any]:
        """Clean up unused storage resources"""
        cleanup_results = {
            'docker_cleanup': [],
            'system_cleanup': [],
            'space_freed': 0,
            'dry_run': dry_run
        }
        
        def cleanup_node(node_ip: str) -> Dict[str, Any]:
            node_results = {'docker': [], 'system': []}
            
            # Docker cleanup
            docker_cmds = [
                "docker system prune -f --volumes" if not dry_run else "docker system df",
                "docker image prune -a -f" if not dry_run else "docker images --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}'"
            ]
            
            for cmd in docker_cmds:
                stdout, stderr, ret = self._ssh_exec(node_ip, cmd)
                if ret == 0:
                    node_results['docker'].append(f"{node_ip}: {stdout}")
            
            # System cleanup
            system_cmds = [
                "sudo apt-get autoremove -y" if not dry_run else "apt list --installed | wc -l",
                "sudo apt-get autoclean" if not dry_run else "du -sh /var/cache/apt/"
            ]
            
            for cmd in system_cmds:
                stdout, stderr, ret = self._ssh_exec(node_ip, cmd)
                if ret == 0:
                    node_results['system'].append(f"{node_ip}: {stdout}")
            
            return node_results
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(cleanup_node, node_ip): node_ip 
                for node_ip in self.nodes
            }
            
            for future in concurrent.futures.as_completed(futures):
                try:
                    node_results = future.result()
                    cleanup_results['docker_cleanup'].extend(node_results['docker'])
                    cleanup_results['system_cleanup'].extend(node_results['system'])
                except Exception as e:
                    node_ip = futures[future]
                    logger.error(f"Cleanup failed on {node_ip}: {e}")
        
        return cleanup_results

def main():
    parser = argparse.ArgumentParser(description="Enhanced Pi-Swarm Storage Manager")
    parser.add_argument("--nodes", required=True, nargs="+", help="Node IP addresses")
    parser.add_argument("--ssh-user", default="luser", help="SSH username")
    parser.add_argument("--ssh-pass", default="", help="SSH password")
    parser.add_argument("--config", default="/etc/piswarm/storage.yml", 
                       help="Storage configuration file")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Storage scanning
    subparsers.add_parser("scan", help="Scan storage devices on all nodes")
    
    # Storage status
    subparsers.add_parser("status", help="Get storage status")
    
    # GlusterFS setup
    gluster_parser = subparsers.add_parser("setup-glusterfs", help="Setup GlusterFS cluster")
    gluster_parser.add_argument("--volume-name", default="piswarm-data", help="Volume name")
    gluster_parser.add_argument("--replica-count", type=int, default=2, help="Replica count")
    
    # NFS setup
    nfs_parser = subparsers.add_parser("setup-nfs", help="Setup NFS server/clients")
    nfs_parser.add_argument("--server", required=True, help="NFS server node IP")
    
    # Docker volume creation
    volume_parser = subparsers.add_parser("create-volume", help="Create Docker volume")
    volume_parser.add_argument("--name", required=True, help="Volume name")
    volume_parser.add_argument("--driver", default="local", help="Volume driver")
    volume_parser.add_argument("--options", help="JSON string of volume options")
    
    # Performance optimization
    subparsers.add_parser("optimize", help="Apply storage performance optimizations")
    
    # Storage cleanup
    cleanup_parser = subparsers.add_parser("cleanup", help="Clean up storage resources")
    cleanup_parser.add_argument("--dry-run", action="store_true", help="Show what would be cleaned")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        storage = StorageManager(
            nodes=args.nodes,
            ssh_user=args.ssh_user,
            ssh_pass=args.ssh_pass,
            config_file=args.config
        )
        
        if args.command == "scan":
            print("🔍 Scanning storage devices...")
            nodes = storage.scan_storage_nodes()
            for node in nodes:
                print(f"\n📊 Node: {node.hostname} ({node.ip}) - {node.status}")
                for device in node.devices:
                    status = "Available" if device.available else f"Mounted: {device.mountpoint}"
                    print(f"  💾 {device.name}: {device.size} ({device.filesystem}) - {status}")
        
        elif args.command == "status":
            print("📊 Getting storage status...")
            status = storage.get_storage_status()
            print(f"\nNodes: {status['summary']['online_nodes']}/{status['summary']['total_nodes']} online")
            print(f"Volumes: {status['summary']['healthy_volumes']}/{status['summary']['total_volumes']} healthy")
            
            for node in status['nodes']:
                print(f"\n🖥️  {node['hostname']} ({node['ip']}) - {node['status']}")
                for device in node['devices']:
                    print(f"  💾 {device['name']}: {device['size']} - {'Available' if device['available'] else 'In Use'}")
        
        elif args.command == "setup-glusterfs":
            print(f"🗄️  Setting up GlusterFS cluster...")
            success = storage.setup_glusterfs(args.nodes, args.volume_name, args.replica_count)
            if success:
                print("✅ GlusterFS setup completed successfully")
            else:
                print("❌ GlusterFS setup failed")
                return 1
        
        elif args.command == "setup-nfs":
            client_nodes = [node for node in args.nodes if node != args.server]
            print(f"🗄️  Setting up NFS server on {args.server}...")
            success = storage.setup_nfs(args.server, client_nodes)
            if success:
                print("✅ NFS setup completed successfully")
            else:
                print("❌ NFS setup failed")
                return 1
        
        elif args.command == "create-volume":
            options = {}
            if args.options:
                try:
                    options = json.loads(args.options)
                except json.JSONDecodeError:
                    print("❌ Invalid JSON in options")
                    return 1
            
            success = storage.create_docker_volume(args.name, args.driver, options)
            if success:
                print(f"✅ Docker volume '{args.name}' created successfully")
            else:
                print(f"❌ Failed to create Docker volume '{args.name}'")
                return 1
        
        elif args.command == "optimize":
            print("🔧 Applying storage optimizations...")
            result = storage.optimize_storage_performance()
            print(f"Applied: {len(result['applied'])}")
            print(f"Failed: {len(result['failed'])}")
            for item in result['applied']:
                print(f"  ✅ {item}")
            for item in result['failed']:
                print(f"  ❌ {item}")
        
        elif args.command == "cleanup":
            print(f"🧹 {'Simulating' if args.dry_run else 'Performing'} storage cleanup...")
            result = storage.cleanup_storage(args.dry_run)
            print(f"Docker cleanup results: {len(result['docker_cleanup'])}")
            print(f"System cleanup results: {len(result['system_cleanup'])}")
            for item in result['docker_cleanup'][:5]:  # Show first 5
                print(f"  🐳 {item}")
            for item in result['system_cleanup'][:5]:  # Show first 5
                print(f"  🗂️  {item}")
        
        return 0
        
    except Exception as e:
        logger.error(f"Command failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
