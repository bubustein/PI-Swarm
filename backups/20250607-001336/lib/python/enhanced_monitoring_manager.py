#!/usr/bin/env python3
"""
Enhanced Monitoring Manager for Pi-Swarm
Provides comprehensive system monitoring, performance analysis, and alert management.
"""

import argparse
import json
import logging
import sys
import time
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import requests
import concurrent.futures
from dataclasses import dataclass
import sqlite3

# Enhanced logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceStatus:
    """Service status information"""
    name: str
    replicas_running: int
    replicas_desired: int
    status: str
    created: str
    updated: str
    ports: List[str]
    
    @property
    def is_healthy(self) -> bool:
        return self.replicas_running == self.replicas_desired and self.replicas_desired > 0

@dataclass 
class NodeInfo:
    """Node information"""
    id: str
    hostname: str
    status: str
    availability: str
    manager_status: str
    engine_version: str
    platform: Dict[str, str]
    resources: Dict[str, Any]

@dataclass
class ClusterMetrics:
    """Cluster performance metrics"""
    timestamp: datetime
    nodes: List[NodeInfo]
    services: List[ServiceStatus]
    system_metrics: Dict[str, Any]
    docker_metrics: Dict[str, Any]
    network_metrics: Dict[str, Any]

class MonitoringManager:
    """Enhanced monitoring and performance management for Pi-Swarm"""
    
    def __init__(self, manager_ip: str, ssh_user: str = "pi", ssh_pass: str = "", 
                 data_dir: str = "/var/lib/piswarm/monitoring"):
        self.manager_ip = manager_ip
        self.ssh_user = ssh_user
        self.ssh_pass = ssh_pass
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize metrics database
        self.db_path = self.data_dir / "metrics.db"
        self._init_database()
        
        # Default endpoints for health checks
        self.default_endpoints = {
            'portainer': {'port': 9000, 'path': '/api/status', 'protocol': 'http'},
            'portainer_ssl': {'port': 9443, 'path': '/api/status', 'protocol': 'https'},
            'grafana': {'port': 3000, 'path': '/api/health', 'protocol': 'http'},
            'prometheus': {'port': 9090, 'path': '/-/healthy', 'protocol': 'http'},
            'node_exporter': {'port': 9100, 'path': '/metrics', 'protocol': 'http'}
        }
    
    def _init_database(self):
        """Initialize metrics database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS metrics (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                        metric_type TEXT NOT NULL,
                        node_id TEXT,
                        service_name TEXT,
                        metric_data TEXT NOT NULL
                    )
                ''')
                
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS alerts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                        alert_type TEXT NOT NULL,
                        severity TEXT NOT NULL,
                        title TEXT NOT NULL,
                        message TEXT NOT NULL,
                        resolved BOOLEAN DEFAULT FALSE,
                        resolved_at DATETIME
                    )
                ''')
                conn.commit()
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}")
    
    def _ssh_exec(self, command: str, timeout: int = 30) -> Tuple[str, str, int]:
        """Execute command via SSH"""
        if self.ssh_pass:
            ssh_cmd = [
                'sshpass', '-p', self.ssh_pass,
                'ssh', '-o', 'StrictHostKeyChecking=no',
                '-o', f'ConnectTimeout={timeout}',
                f'{self.ssh_user}@{self.manager_ip}',
                command
            ]
        else:
            ssh_cmd = [
                'ssh', '-o', 'StrictHostKeyChecking=no',
                '-o', f'ConnectTimeout={timeout}',
                f'{self.ssh_user}@{self.manager_ip}',
                command
            ]
        
        try:
            result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=timeout)
            return result.stdout.strip(), result.stderr.strip(), result.returncode
        except subprocess.TimeoutExpired:
            return "", "SSH command timed out", 124
        except Exception as e:
            return "", f"SSH execution failed: {e}", 1
    
    def get_cluster_nodes(self) -> List[NodeInfo]:
        """Get information about all cluster nodes"""
        stdout, stderr, returncode = self._ssh_exec(
            "docker node ls --format '{{json .}}'"
        )
        
        nodes = []
        if returncode == 0 and stdout:
            for line in stdout.strip().split('\n'):
                try:
                    node_data = json.loads(line)
                    # Get detailed node info
                    node_id = node_data.get('ID', '')
                    detail_cmd = f"docker node inspect {node_id} --format '{{{{json .}}}}'"
                    detail_stdout, _, detail_ret = self._ssh_exec(detail_cmd)
                    
                    if detail_ret == 0 and detail_stdout:
                        detail_data = json.loads(detail_stdout)
                        spec = detail_data.get('Spec', {})
                        description = detail_data.get('Description', {})
                        status = detail_data.get('Status', {})
                        
                        nodes.append(NodeInfo(
                            id=node_id,
                            hostname=spec.get('Labels', {}).get('hostname', description.get('Hostname', 'unknown')),
                            status=status.get('State', 'unknown'),
                            availability=spec.get('Availability', 'unknown'),
                            manager_status=detail_data.get('ManagerStatus', {}).get('Reachability', 'worker'),
                            engine_version=description.get('Engine', {}).get('EngineVersion', 'unknown'),
                            platform=description.get('Platform', {}),
                            resources=description.get('Resources', {})
                        ))
                except (json.JSONDecodeError, KeyError) as e:
                    logger.warning(f"Failed to parse node data: {e}")
                    continue
        
        return nodes
    
    def get_service_status(self) -> List[ServiceStatus]:
        """Get status of all Docker Swarm services"""
        stdout, stderr, returncode = self._ssh_exec(
            "docker service ls --format '{{json .}}'"
        )
        
        services = []
        if returncode == 0 and stdout:
            for line in stdout.strip().split('\n'):
                try:
                    service_data = json.loads(line)
                    
                    # Parse replicas (format: "1/1" or "0/1")
                    replicas_str = service_data.get('Replicas', '0/0')
                    if '/' in replicas_str:
                        running, desired = map(int, replicas_str.split('/'))
                    else:
                        running = desired = 0
                    
                    services.append(ServiceStatus(
                        name=service_data.get('Name', 'unknown'),
                        replicas_running=running,
                        replicas_desired=desired,
                        status='healthy' if running == desired and desired > 0 else 'unhealthy',
                        created=service_data.get('CreatedAt', ''),
                        updated=service_data.get('UpdatedAt', ''),
                        ports=service_data.get('Ports', '').split(',') if service_data.get('Ports') else []
                    ))
                except (json.JSONDecodeError, KeyError, ValueError) as e:
                    logger.warning(f"Failed to parse service data: {e}")
                    continue
        
        return services
    
    def get_system_metrics(self) -> Dict[str, Any]:
        """Collect system metrics from the manager node"""
        metrics = {
            'cpu': {},
            'memory': {},
            'disk': {},
            'load': {},
            'uptime': 0
        }
        
        # CPU usage
        stdout, _, ret = self._ssh_exec("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1")
        if ret == 0 and stdout:
            try:
                metrics['cpu']['usage_percent'] = float(stdout)
            except ValueError:
                pass
        
        # Memory usage
        stdout, _, ret = self._ssh_exec("free -m | awk 'NR==2{printf \"%.2f\", $3*100/$2}'")
        if ret == 0 and stdout:
            try:
                metrics['memory']['usage_percent'] = float(stdout)
            except ValueError:
                pass
        
        # Disk usage
        stdout, _, ret = self._ssh_exec("df -h / | awk 'NR==2{print $5}' | cut -d'%' -f1")
        if ret == 0 and stdout:
            try:
                metrics['disk']['root_usage_percent'] = float(stdout)
            except ValueError:
                pass
        
        # Load average
        stdout, _, ret = self._ssh_exec("uptime | awk -F'load average:' '{print $2}' | awk '{print $1,$2,$3}' | tr -d ','")
        if ret == 0 and stdout:
            try:
                load_values = stdout.split()
                if len(load_values) >= 3:
                    metrics['load'] = {
                        '1min': float(load_values[0]),
                        '5min': float(load_values[1]),
                        '15min': float(load_values[2])
                    }
            except (ValueError, IndexError):
                pass
        
        # Uptime
        stdout, _, ret = self._ssh_exec("cat /proc/uptime | awk '{print $1}'")
        if ret == 0 and stdout:
            try:
                metrics['uptime'] = float(stdout)
            except ValueError:
                pass
        
        return metrics
    
    def test_service_endpoints(self, custom_endpoints: Optional[Dict] = None) -> Dict[str, Dict]:
        """Test connectivity to service endpoints"""
        endpoints = {**self.default_endpoints}
        if custom_endpoints:
            endpoints.update(custom_endpoints)
        
        results = {}
        
        def test_endpoint(name: str, config: Dict) -> Tuple[str, Dict]:
            port = config['port']
            path = config.get('path', '/')
            protocol = config.get('protocol', 'http')
            timeout = config.get('timeout', 5)
            
            url = f"{protocol}://{self.manager_ip}:{port}{path}"
            
            try:
                response = requests.get(
                    url, 
                    timeout=timeout, 
                    verify=False if protocol == 'https' else True
                )
                return name, {
                    'status': 'healthy',
                    'url': url,
                    'response_code': response.status_code,
                    'response_time': response.elapsed.total_seconds()
                }
            except requests.exceptions.RequestException as e:
                return name, {
                    'status': 'unhealthy',
                    'url': url,
                    'error': str(e)
                }
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(test_endpoint, name, config): name 
                for name, config in endpoints.items()
            }
            
            for future in concurrent.futures.as_completed(futures):
                try:
                    endpoint_name, result = future.result()
                    results[endpoint_name] = result
                except Exception as e:
                    endpoint_name = futures[future]
                    results[endpoint_name] = {
                        'status': 'error',
                        'error': str(e)
                    }
        
        return results
    
    def collect_full_metrics(self) -> ClusterMetrics:
        """Collect comprehensive cluster metrics"""
        timestamp = datetime.now()
        
        # Collect all metrics
        nodes = self.get_cluster_nodes()
        services = self.get_service_status()
        system_metrics = self.get_system_metrics()
        
        # Docker metrics
        docker_metrics = {}
        stdout, _, ret = self._ssh_exec("docker system df --format 'table {{.Type}}\\t{{.TotalCount}}\\t{{.Size}}\\t{{.Reclaimable}}'")
        if ret == 0 and stdout:
            docker_metrics['system_df'] = stdout
        
        # Network metrics (basic)
        network_metrics = {}
        stdout, _, ret = self._ssh_exec("docker network ls --format '{{.Name}}\\t{{.Driver}}\\t{{.Scope}}'")
        if ret == 0 and stdout:
            network_metrics['networks'] = stdout.split('\n')
        
        metrics = ClusterMetrics(
            timestamp=timestamp,
            nodes=nodes,
            services=services,
            system_metrics=system_metrics,
            docker_metrics=docker_metrics,
            network_metrics=network_metrics
        )
        
        # Store metrics in database
        self._store_metrics(metrics)
        
        return metrics
    
    def _store_metrics(self, metrics: ClusterMetrics):
        """Store metrics in database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                # Store cluster overview
                conn.execute('''
                    INSERT INTO metrics (metric_type, metric_data)
                    VALUES (?, ?)
                ''', ('cluster_overview', json.dumps({
                    'timestamp': metrics.timestamp.isoformat(),
                    'node_count': len(metrics.nodes),
                    'service_count': len(metrics.services),
                    'healthy_services': sum(1 for s in metrics.services if s.is_healthy),
                    'system_metrics': metrics.system_metrics
                })))
                
                # Store individual service metrics
                for service in metrics.services:
                    conn.execute('''
                        INSERT INTO metrics (metric_type, service_name, metric_data)
                        VALUES (?, ?, ?)
                    ''', ('service_status', service.name, json.dumps({
                        'replicas_running': service.replicas_running,
                        'replicas_desired': service.replicas_desired,
                        'is_healthy': service.is_healthy,
                        'status': service.status
                    })))
                
                conn.commit()
        except Exception as e:
            logger.error(f"Failed to store metrics: {e}")
    
    def generate_health_report(self, output_file: Optional[str] = None) -> Dict:
        """Generate comprehensive health report"""
        metrics = self.collect_full_metrics()
        endpoints = self.test_service_endpoints()
        
        # Calculate health scores
        total_services = len(metrics.services)
        healthy_services = sum(1 for s in metrics.services if s.is_healthy)
        service_health_score = (healthy_services / total_services * 100) if total_services > 0 else 0
        
        healthy_endpoints = sum(1 for e in endpoints.values() if e.get('status') == 'healthy')
        total_endpoints = len(endpoints)
        endpoint_health_score = (healthy_endpoints / total_endpoints * 100) if total_endpoints > 0 else 0
        
        report = {
            'timestamp': metrics.timestamp.isoformat(),
            'cluster_summary': {
                'nodes': len(metrics.nodes),
                'services': total_services,
                'healthy_services': healthy_services,
                'service_health_score': service_health_score,
                'endpoint_health_score': endpoint_health_score
            },
            'nodes': [
                {
                    'hostname': node.hostname,
                    'status': node.status,
                    'availability': node.availability,
                    'role': 'manager' if node.manager_status != 'worker' else 'worker',
                    'engine_version': node.engine_version
                }
                for node in metrics.nodes
            ],
            'services': [
                {
                    'name': service.name,
                    'replicas': f"{service.replicas_running}/{service.replicas_desired}",
                    'status': service.status,
                    'is_healthy': service.is_healthy,
                    'ports': service.ports
                }
                for service in metrics.services
            ],
            'endpoints': endpoints,
            'system_metrics': metrics.system_metrics,
            'recommendations': self._generate_recommendations(metrics, endpoints)
        }
        
        if output_file:
            output_path = Path(output_file)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, 'w') as f:
                json.dump(report, f, indent=2)
            logger.info(f"Health report saved to {output_path}")
        
        return report
    
    def _generate_recommendations(self, metrics: ClusterMetrics, endpoints: Dict) -> List[str]:
        """Generate recommendations based on metrics"""
        recommendations = []
        
        # Service health recommendations
        unhealthy_services = [s for s in metrics.services if not s.is_healthy]
        if unhealthy_services:
            recommendations.append(
                f"⚠️  {len(unhealthy_services)} services are unhealthy. "
                f"Check: {', '.join(s.name for s in unhealthy_services[:3])}"
            )
        
        # System metrics recommendations
        if 'cpu' in metrics.system_metrics and 'usage_percent' in metrics.system_metrics['cpu']:
            cpu_usage = metrics.system_metrics['cpu']['usage_percent']
            if cpu_usage > 80:
                recommendations.append(f"🔥 High CPU usage detected: {cpu_usage:.1f}%")
        
        if 'memory' in metrics.system_metrics and 'usage_percent' in metrics.system_metrics['memory']:
            memory_usage = metrics.system_metrics['memory']['usage_percent']
            if memory_usage > 85:
                recommendations.append(f"💾 High memory usage detected: {memory_usage:.1f}%")
        
        if 'disk' in metrics.system_metrics and 'root_usage_percent' in metrics.system_metrics['disk']:
            disk_usage = metrics.system_metrics['disk']['root_usage_percent']
            if disk_usage > 90:
                recommendations.append(f"💿 High disk usage detected: {disk_usage:.1f}%")
        
        # Endpoint recommendations
        unhealthy_endpoints = [name for name, info in endpoints.items() if info.get('status') != 'healthy']
        if unhealthy_endpoints:
            recommendations.append(
                f"🌐 {len(unhealthy_endpoints)} endpoints are unreachable: "
                f"{', '.join(unhealthy_endpoints[:3])}"
            )
        
        if not recommendations:
            recommendations.append("✅ All systems appear to be operating normally")
        
        return recommendations
    
    def setup_alerts(self, webhook_url: Optional[str] = None, 
                    email_config: Optional[Dict] = None) -> bool:
        """Setup monitoring alerts"""
        try:
            alert_config = {
                'webhook_url': webhook_url,
                'email_config': email_config,
                'thresholds': {
                    'cpu_usage': 80,
                    'memory_usage': 85,
                    'disk_usage': 90,
                    'service_downtime': 300  # 5 minutes
                }
            }
            
            config_file = self.data_dir / "alert_config.json"
            with open(config_file, 'w') as f:
                json.dump(alert_config, f, indent=2)
            
            logger.info(f"Alert configuration saved to {config_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to setup alerts: {e}")
            return False
    
    def optimize_performance(self) -> Dict[str, Any]:
        """Apply performance optimizations"""
        optimizations = {
            'applied': [],
            'failed': [],
            'recommendations': []
        }
        
        # Docker system cleanup
        stdout, stderr, ret = self._ssh_exec("docker system prune -f")
        if ret == 0:
            optimizations['applied'].append("Docker system cleanup completed")
        else:
            optimizations['failed'].append(f"Docker cleanup failed: {stderr}")
        
        # Update Docker daemon configuration for better performance
        daemon_config = {
            "log-driver": "json-file",
            "log-opts": {
                "max-size": "10m",
                "max-file": "3"
            },
            "storage-driver": "overlay2"
        }
        
        try:
            config_json = json.dumps(daemon_config, indent=2)
            cmd = f"echo '{config_json}' | sudo tee /etc/docker/daemon.json > /dev/null && sudo systemctl reload docker"
            stdout, stderr, ret = self._ssh_exec(cmd)
            if ret == 0:
                optimizations['applied'].append("Docker daemon configuration optimized")
            else:
                optimizations['failed'].append(f"Docker daemon config failed: {stderr}")
        except Exception as e:
            optimizations['failed'].append(f"Docker daemon config error: {e}")
        
        return optimizations

def main():
    parser = argparse.ArgumentParser(description="Enhanced Pi-Swarm Monitoring Manager")
    parser.add_argument("--manager-ip", required=True, help="Manager node IP address")
    parser.add_argument("--ssh-user", default="pi", help="SSH username")
    parser.add_argument("--ssh-pass", default="", help="SSH password")
    parser.add_argument("--data-dir", default="/var/lib/piswarm/monitoring", 
                       help="Data directory for metrics storage")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Health report command
    health_parser = subparsers.add_parser("health", help="Generate health report")
    health_parser.add_argument("--output", help="Output file for health report")
    health_parser.add_argument("--format", choices=["json", "summary"], default="summary",
                             help="Output format")
    
    # Metrics collection command
    metrics_parser = subparsers.add_parser("metrics", help="Collect metrics")
    metrics_parser.add_argument("--store", action="store_true", help="Store metrics in database")
    
    # Service status command
    subparsers.add_parser("services", help="Check service status")
    
    # Endpoint testing command
    endpoints_parser = subparsers.add_parser("endpoints", help="Test service endpoints")
    endpoints_parser.add_argument("--custom", help="JSON file with custom endpoints")
    
    # Performance optimization command
    subparsers.add_parser("optimize", help="Apply performance optimizations")
    
    # Alert setup command
    alerts_parser = subparsers.add_parser("alerts", help="Setup monitoring alerts")
    alerts_parser.add_argument("--webhook", help="Webhook URL for alerts")
    alerts_parser.add_argument("--email-config", help="JSON file with email configuration")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        monitor = MonitoringManager(
            manager_ip=args.manager_ip,
            ssh_user=args.ssh_user,
            ssh_pass=args.ssh_pass,
            data_dir=args.data_dir
        )
        
        if args.command == "health":
            report = monitor.generate_health_report(args.output)
            if args.format == "summary":
                print(f"\n🏥 CLUSTER HEALTH SUMMARY")
                print("=" * 50)
                print(f"Nodes: {report['cluster_summary']['nodes']}")
                print(f"Services: {report['cluster_summary']['healthy_services']}/{report['cluster_summary']['services']}")
                print(f"Service Health: {report['cluster_summary']['service_health_score']:.1f}%")
                print(f"Endpoint Health: {report['cluster_summary']['endpoint_health_score']:.1f}%")
                print("\n📋 RECOMMENDATIONS:")
                for rec in report['recommendations']:
                    print(f"  {rec}")
            else:
                print(json.dumps(report, indent=2))
                
        elif args.command == "metrics":
            metrics = monitor.collect_full_metrics()
            print(f"Collected metrics at {metrics.timestamp}")
            print(f"Nodes: {len(metrics.nodes)}, Services: {len(metrics.services)}")
            
        elif args.command == "services":
            services = monitor.get_service_status()
            print("\n🔍 SERVICE STATUS:")
            for service in services:
                status_icon = "✅" if service.is_healthy else "⚠️"
                print(f"  {status_icon} {service.name}: {service.replicas_running}/{service.replicas_desired}")
                
        elif args.command == "endpoints":
            custom_endpoints = {}
            if args.custom and Path(args.custom).exists():
                with open(args.custom) as f:
                    custom_endpoints = json.load(f)
            
            endpoints = monitor.test_service_endpoints(custom_endpoints)
            print("\n🌐 ENDPOINT CONNECTIVITY:")
            for name, info in endpoints.items():
                status_icon = "✅" if info.get('status') == 'healthy' else "❌"
                print(f"  {status_icon} {name}: {info.get('url', 'unknown')}")
                if 'response_time' in info:
                    print(f"    Response time: {info['response_time']:.3f}s")
        
        elif args.command == "optimize":
            print("🔧 Applying performance optimizations...")
            result = monitor.optimize_performance()
            print(f"Applied: {len(result['applied'])}")
            print(f"Failed: {len(result['failed'])}")
            for item in result['applied']:
                print(f"  ✅ {item}")
            for item in result['failed']:
                print(f"  ❌ {item}")
                
        elif args.command == "alerts":
            email_config = None
            if args.email_config and Path(args.email_config).exists():
                with open(args.email_config) as f:
                    email_config = json.load(f)
            
            success = monitor.setup_alerts(args.webhook, email_config)
            if success:
                print("✅ Alert configuration saved successfully")
            else:
                print("❌ Failed to setup alerts")
        
        return 0
        
    except Exception as e:
        logger.error(f"Command failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
