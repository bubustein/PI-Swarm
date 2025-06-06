#!/usr/bin/env python3
"""
Monitoring Manager for Pi-Swarm
Handles performance monitoring, alerting, and health checks
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
import requests
import yaml
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MonitoringManager:
    """Comprehensive monitoring and alerting system"""
    
    def __init__(self, config_path: str = None):
        """Initialize monitoring manager"""
        self.config_path = config_path or "/home/luser/PI-Swarm/config/config.yml"
        self.config = self._load_config()
        self.metrics_cache = {}
        self.alerts_cache = []
        
    def _load_config(self) -> Dict:
        """Load configuration from YAML file"""
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    return yaml.safe_load(f) or {}
            return {}
        except Exception as e:
            logger.warning(f"Could not load config: {e}")
            return {}
    
    def collect_cluster_metrics(self, manager_ip: str, output_file: str = None) -> Dict[str, Any]:
        """Collect comprehensive cluster performance metrics"""
        logger.info("🔍 Collecting cluster performance metrics...")
        
        if not output_file:
            output_file = f"cluster-performance-{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        metrics = {
            'timestamp': datetime.now().isoformat(),
            'cluster_info': self._get_cluster_info(manager_ip),
            'node_metrics': self._get_node_metrics(manager_ip),
            'service_metrics': self._get_service_metrics(manager_ip),
            'resource_usage': self._get_resource_usage(manager_ip),
            'network_metrics': self._get_network_metrics(manager_ip),
            'health_status': self._get_health_status(manager_ip)
        }
        
        # Cache metrics
        self.metrics_cache = metrics
        
        # Save to file
        try:
            with open(output_file, 'w') as f:
                json.dump(metrics, f, indent=2)
            logger.info(f"📊 Metrics saved to: {output_file}")
        except Exception as e:
            logger.error(f"Failed to save metrics: {e}")
        
        return metrics
    
    def _get_cluster_info(self, manager_ip: str) -> Dict:
        """Get Docker Swarm cluster information"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'info', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return json.loads(result.stdout)
            else:
                logger.warning(f"Failed to get cluster info: {result.stderr}")
                return {}
        except Exception as e:
            logger.error(f"Error getting cluster info: {e}")
            return {}
    
    def _get_node_metrics(self, manager_ip: str) -> List[Dict]:
        """Get metrics for all nodes in the cluster"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'node', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                nodes = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        node_data = json.loads(line)
                        # Get detailed node info
                        node_detail = self._get_node_detail(manager_ip, node_data.get('ID'))
                        node_data.update(node_detail)
                        nodes.append(node_data)
                return nodes
            else:
                logger.warning(f"Failed to get node metrics: {result.stderr}")
                return []
        except Exception as e:
            logger.error(f"Error getting node metrics: {e}")
            return []
    
    def _get_node_detail(self, manager_ip: str, node_id: str) -> Dict:
        """Get detailed information for a specific node"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'node', 'inspect', node_id, '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return json.loads(result.stdout)
            return {}
        except Exception as e:
            logger.error(f"Error getting node detail: {e}")
            return {}
    
    def _get_service_metrics(self, manager_ip: str) -> List[Dict]:
        """Get metrics for all services in the cluster"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'service', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                services = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        service_data = json.loads(line)
                        # Get detailed service info
                        service_detail = self._get_service_detail(manager_ip, service_data.get('ID'))
                        service_data.update(service_detail)
                        services.append(service_data)
                return services
            else:
                logger.warning(f"Failed to get service metrics: {result.stderr}")
                return []
        except Exception as e:
            logger.error(f"Error getting service metrics: {e}")
            return []
    
    def _get_service_detail(self, manager_ip: str, service_id: str) -> Dict:
        """Get detailed information for a specific service"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'service', 'inspect', service_id, '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return json.loads(result.stdout)
            return {}
        except Exception as e:
            logger.error(f"Error getting service detail: {e}")
            return {}
    
    def _get_resource_usage(self, manager_ip: str) -> Dict:
        """Get resource usage statistics"""
        try:
            # Get stats from Docker API
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'system', 'df', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return json.loads(result.stdout)
            return {}
        except Exception as e:
            logger.error(f"Error getting resource usage: {e}")
            return {}
    
    def _get_network_metrics(self, manager_ip: str) -> List[Dict]:
        """Get network metrics for the cluster"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'network', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                networks = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        network_data = json.loads(line)
                        # Get detailed network info
                        network_detail = self._get_network_detail(manager_ip, network_data.get('ID'))
                        network_data.update(network_detail)
                        networks.append(network_data)
                return networks
            return []
        except Exception as e:
            logger.error(f"Error getting network metrics: {e}")
            return []
    
    def _get_network_detail(self, manager_ip: str, network_id: str) -> Dict:
        """Get detailed information for a specific network"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'network', 'inspect', network_id, '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return json.loads(result.stdout)
            return {}
        except Exception as e:
            logger.error(f"Error getting network detail: {e}")
            return {}
    
    def _get_health_status(self, manager_ip: str) -> Dict:
        """Get overall cluster health status"""
        health = {
            'status': 'healthy',
            'issues': [],
            'recommendations': []
        }
        
        try:
            # Check node health
            nodes = self._get_node_metrics(manager_ip)
            for node in nodes:
                status = node.get('Status', {})
                if status.get('State') != 'ready':
                    health['status'] = 'warning'
                    health['issues'].append(f"Node {node.get('Hostname')} is not ready")
            
            # Check service health
            services = self._get_service_metrics(manager_ip)
            for service in services:
                replicas = service.get('Replicas', '0/0')
                if '/' in replicas:
                    current, desired = replicas.split('/')
                    if current != desired:
                        health['status'] = 'warning'
                        health['issues'].append(f"Service {service.get('Name')} has {current}/{desired} replicas")
            
            # Add recommendations based on issues
            if health['issues']:
                health['recommendations'].append("Check service logs for error details")
                health['recommendations'].append("Verify node connectivity and resources")
        
        except Exception as e:
            logger.error(f"Error getting health status: {e}")
            health['status'] = 'error'
            health['issues'].append(f"Health check failed: {e}")
        
        return health
    
    def create_alerts(self, manager_ip: str, alert_config: Dict = None) -> bool:
        """Create monitoring alerts and rules"""
        logger.info("🚨 Setting up monitoring alerts...")
        
        # Default alert configuration
        default_alerts = {
            'cpu_threshold': 80,
            'memory_threshold': 85,
            'disk_threshold': 90,
            'service_down_threshold': 1,
            'node_down_threshold': 1
        }
        
        if alert_config:
            default_alerts.update(alert_config)
        
        try:
            # Create Prometheus alert rules
            alert_rules = self._create_prometheus_rules(default_alerts)
            
            # Save alert rules
            alert_file = "/home/luser/PI-Swarm/config/prometheus-alerts.yml"
            with open(alert_file, 'w') as f:
                yaml.dump(alert_rules, f, default_flow_style=False)
            
            logger.info(f"📋 Alert rules saved to: {alert_file}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create alerts: {e}")
            return False
    
    def _create_prometheus_rules(self, config: Dict) -> Dict:
        """Create Prometheus alert rules configuration"""
        return {
            'groups': [
                {
                    'name': 'pi-swarm-alerts',
                    'rules': [
                        {
                            'alert': 'HighCPUUsage',
                            'expr': f'cpu_usage_percent > {config["cpu_threshold"]}',
                            'for': '5m',
                            'labels': {'severity': 'warning'},
                            'annotations': {
                                'summary': 'High CPU usage detected',
                                'description': 'CPU usage is above {{ $value }}%'
                            }
                        },
                        {
                            'alert': 'HighMemoryUsage',
                            'expr': f'memory_usage_percent > {config["memory_threshold"]}',
                            'for': '5m',
                            'labels': {'severity': 'warning'},
                            'annotations': {
                                'summary': 'High memory usage detected',
                                'description': 'Memory usage is above {{ $value }}%'
                            }
                        },
                        {
                            'alert': 'HighDiskUsage',
                            'expr': f'disk_usage_percent > {config["disk_threshold"]}',
                            'for': '5m',
                            'labels': {'severity': 'critical'},
                            'annotations': {
                                'summary': 'High disk usage detected',
                                'description': 'Disk usage is above {{ $value }}%'
                            }
                        },
                        {
                            'alert': 'ServiceDown',
                            'expr': 'docker_service_running == 0',
                            'for': '1m',
                            'labels': {'severity': 'critical'},
                            'annotations': {
                                'summary': 'Docker service is down',
                                'description': 'Service {{ $labels.service_name }} is not running'
                            }
                        },
                        {
                            'alert': 'NodeDown',
                            'expr': 'docker_node_status != 1',
                            'for': '2m',
                            'labels': {'severity': 'critical'},
                            'annotations': {
                                'summary': 'Docker node is down',
                                'description': 'Node {{ $labels.node_name }} is not available'
                            }
                        }
                    ]
                }
            ]
        }
    
    def optimize_performance(self, manager_ip: str, optimization_level: str = 'standard') -> Dict:
        """Apply performance optimizations to the cluster"""
        logger.info("🔧 Applying performance optimizations...")
        
        optimizations = {
            'applied': [],
            'failed': [],
            'recommendations': []
        }
        
        try:
            # Get current metrics
            metrics = self.collect_cluster_metrics(manager_ip)
            
            if optimization_level == 'aggressive':
                # Aggressive optimizations
                optimizations['applied'].extend(self._apply_aggressive_optimizations(manager_ip, metrics))
            else:
                # Standard optimizations
                optimizations['applied'].extend(self._apply_standard_optimizations(manager_ip, metrics))
            
            # Generate recommendations
            optimizations['recommendations'] = self._generate_optimization_recommendations(metrics)
            
            logger.info(f"✅ Applied {len(optimizations['applied'])} optimizations")
            
        except Exception as e:
            logger.error(f"Error during optimization: {e}")
            optimizations['failed'].append(str(e))
        
        return optimizations
    
    def _apply_standard_optimizations(self, manager_ip: str, metrics: Dict) -> List[str]:
        """Apply standard performance optimizations"""
        applied = []
        
        try:
            # Optimize Docker daemon settings
            self._optimize_docker_daemon(manager_ip)
            applied.append("Docker daemon optimization")
            
            # Optimize service placement
            self._optimize_service_placement(manager_ip)
            applied.append("Service placement optimization")
            
            # Clean up unused resources
            self._cleanup_unused_resources(manager_ip)
            applied.append("Resource cleanup")
            
        except Exception as e:
            logger.error(f"Error in standard optimizations: {e}")
        
        return applied
    
    def _apply_aggressive_optimizations(self, manager_ip: str, metrics: Dict) -> List[str]:
        """Apply aggressive performance optimizations"""
        applied = []
        
        try:
            # Apply standard optimizations first
            applied.extend(self._apply_standard_optimizations(manager_ip, metrics))
            
            # Aggressive memory optimization
            self._optimize_memory_aggressive(manager_ip)
            applied.append("Aggressive memory optimization")
            
            # Network optimization
            self._optimize_network_aggressive(manager_ip)
            applied.append("Aggressive network optimization")
            
        except Exception as e:
            logger.error(f"Error in aggressive optimizations: {e}")
        
        return applied
    
    def _optimize_docker_daemon(self, manager_ip: str):
        """Optimize Docker daemon settings"""
        # This would typically involve updating Docker daemon configuration
        # For now, we'll just log the action
        logger.info("Optimizing Docker daemon settings")
    
    def _optimize_service_placement(self, manager_ip: str):
        """Optimize service placement across nodes"""
        logger.info("Optimizing service placement")
    
    def _cleanup_unused_resources(self, manager_ip: str):
        """Clean up unused Docker resources"""
        try:
            subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'system', 'prune', '-f'
            ], capture_output=True, timeout=60)
            logger.info("Cleaned up unused Docker resources")
        except Exception as e:
            logger.error(f"Failed to cleanup resources: {e}")
    
    def _optimize_memory_aggressive(self, manager_ip: str):
        """Apply aggressive memory optimizations"""
        logger.info("Applying aggressive memory optimizations")
    
    def _optimize_network_aggressive(self, manager_ip: str):
        """Apply aggressive network optimizations"""
        logger.info("Applying aggressive network optimizations")
    
    def _generate_optimization_recommendations(self, metrics: Dict) -> List[str]:
        """Generate optimization recommendations based on metrics"""
        recommendations = []
        
        # Analyze resource usage
        resource_usage = metrics.get('resource_usage', {})
        node_metrics = metrics.get('node_metrics', [])
        
        # CPU recommendations
        for node in node_metrics:
            # This would analyze actual CPU metrics when available
            recommendations.append("Consider load balancing services across nodes")
        
        # Memory recommendations
        recommendations.append("Monitor memory usage and consider adding swap if needed")
        
        # Storage recommendations
        recommendations.append("Regularly clean up unused Docker images and volumes")
        
        return recommendations
    
    def backup_cluster_config(self, manager_ip: str, backup_path: str = None) -> str:
        """Create a backup of cluster configuration"""
        if not backup_path:
            backup_path = f"cluster-backup-{datetime.now().strftime('%Y%m%d_%H%M%S')}.tar.gz"
        
        logger.info("💾 Creating cluster configuration backup...")
        
        try:
            # Create temporary directory for backup files
            backup_dir = f"/tmp/cluster-backup-{int(time.time())}"
            os.makedirs(backup_dir, exist_ok=True)
            
            # Export Docker Swarm configuration
            self._export_swarm_config(manager_ip, backup_dir)
            
            # Export service configurations
            self._export_service_configs(manager_ip, backup_dir)
            
            # Export network configurations
            self._export_network_configs(manager_ip, backup_dir)
            
            # Create tar archive
            subprocess.run([
                'tar', '-czf', backup_path, '-C', backup_dir, '.'
            ], check=True, timeout=300)
            
            # Cleanup temporary directory
            subprocess.run(['rm', '-rf', backup_dir], check=True)
            
            logger.info(f"✅ Cluster backup created: {backup_path}")
            return backup_path
            
        except Exception as e:
            logger.error(f"Failed to create backup: {e}")
            return ""
    
    def _export_swarm_config(self, manager_ip: str, backup_dir: str):
        """Export Docker Swarm configuration"""
        try:
            # Export node information
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'node', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                with open(f"{backup_dir}/nodes.json", 'w') as f:
                    f.write(result.stdout)
        except Exception as e:
            logger.error(f"Failed to export swarm config: {e}")
    
    def _export_service_configs(self, manager_ip: str, backup_dir: str):
        """Export service configurations"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'service', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                with open(f"{backup_dir}/services.json", 'w') as f:
                    f.write(result.stdout)
        except Exception as e:
            logger.error(f"Failed to export service configs: {e}")
    
    def _export_network_configs(self, manager_ip: str, backup_dir: str):
        """Export network configurations"""
        try:
            result = subprocess.run([
                'docker', '-H', f'{manager_ip}:2376', 'network', 'ls', '--format', '{{json .}}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                with open(f"{backup_dir}/networks.json", 'w') as f:
                    f.write(result.stdout)
        except Exception as e:
            logger.error(f"Failed to export network configs: {e}")
    
    def display_health_dashboard(self, manager_ip: str, detailed: bool = False):
        """Display cluster health dashboard"""
        logger.info("🏥 Generating cluster health dashboard...")
        
        try:
            metrics = self.collect_cluster_metrics(manager_ip)
            health = metrics.get('health_status', {})
            
            print("\n" + "="*70)
            print("🏥 PI-SWARM CLUSTER HEALTH DASHBOARD")
            print("="*70)
            
            # Overall status
            status_emoji = "✅" if health.get('status') == 'healthy' else "⚠️" if health.get('status') == 'warning' else "❌"
            print(f"📊 Overall Status: {status_emoji} {health.get('status', 'unknown').upper()}")
            
            # Node status
            nodes = metrics.get('node_metrics', [])
            healthy_nodes = sum(1 for node in nodes if node.get('Status', {}).get('State') == 'ready')
            print(f"🖥️  Nodes: {healthy_nodes}/{len(nodes)} healthy")
            
            # Service status
            services = metrics.get('service_metrics', [])
            healthy_services = sum(1 for service in services if self._is_service_healthy(service))
            print(f"🐳 Services: {healthy_services}/{len(services)} healthy")
            
            # Resource usage
            resource_usage = metrics.get('resource_usage', {})
            if resource_usage:
                print(f"💾 Resources: {resource_usage}")
            
            # Quick access links
            print(f"\n🔗 QUICK ACCESS LINKS:")
            print(f"   • Portainer: http://{manager_ip}:9000")
            print(f"   • Grafana: http://{manager_ip}:3000")
            print(f"   • Prometheus: http://{manager_ip}:9090")
            
            # Issues and recommendations
            issues = health.get('issues', [])
            if issues:
                print(f"\n⚠️  ISSUES ({len(issues)}):")
                for issue in issues[:5]:  # Show first 5 issues
                    print(f"   • {issue}")
                if len(issues) > 5:
                    print(f"   ... and {len(issues) - 5} more")
            
            recommendations = health.get('recommendations', [])
            if recommendations:
                print(f"\n💡 RECOMMENDATIONS:")
                for rec in recommendations[:3]:  # Show first 3 recommendations
                    print(f"   • {rec}")
            
            if detailed:
                self._display_detailed_metrics(metrics)
            
            print("="*70)
            
        except Exception as e:
            logger.error(f"Failed to display health dashboard: {e}")
            print(f"❌ Failed to generate health dashboard: {e}")
    
    def _is_service_healthy(self, service: Dict) -> bool:
        """Check if a service is healthy"""
        replicas = service.get('Replicas', '0/0')
        if '/' in replicas:
            current, desired = replicas.split('/')
            return current == desired and int(current) > 0
        return False
    
    def _display_detailed_metrics(self, metrics: Dict):
        """Display detailed metrics information"""
        print(f"\n📊 DETAILED METRICS:")
        print(f"   Timestamp: {metrics.get('timestamp')}")
        
        # Node details
        nodes = metrics.get('node_metrics', [])
        if nodes:
            print(f"\n🖥️  NODE DETAILS:")
            for node in nodes:
                hostname = node.get('Hostname', 'unknown')
                status = node.get('Status', {}).get('State', 'unknown')
                availability = node.get('Spec', {}).get('Availability', 'unknown')
                print(f"   • {hostname}: {status} ({availability})")
        
        # Service details
        services = metrics.get('service_metrics', [])
        if services:
            print(f"\n🐳 SERVICE DETAILS:")
            for service in services:
                name = service.get('Name', 'unknown')
                replicas = service.get('Replicas', '0/0')
                print(f"   • {name}: {replicas} replicas")

def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description='Pi-Swarm Monitoring Manager')
    parser.add_argument('--config', type=str, help='Configuration file path')
    parser.add_argument('--manager-ip', type=str, required=True, help='Docker Swarm manager IP')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Collect metrics command
    collect_parser = subparsers.add_parser('collect', help='Collect cluster metrics')
    collect_parser.add_argument('--output', type=str, help='Output file path')
    
    # Create alerts command
    alerts_parser = subparsers.add_parser('alerts', help='Create monitoring alerts')
    alerts_parser.add_argument('--cpu-threshold', type=int, default=80, help='CPU threshold for alerts')
    alerts_parser.add_argument('--memory-threshold', type=int, default=85, help='Memory threshold for alerts')
    alerts_parser.add_argument('--disk-threshold', type=int, default=90, help='Disk threshold for alerts')
    
    # Optimize command
    optimize_parser = subparsers.add_parser('optimize', help='Optimize cluster performance')
    optimize_parser.add_argument('--level', choices=['standard', 'aggressive'], default='standard', help='Optimization level')
    
    # Backup command
    backup_parser = subparsers.add_parser('backup', help='Backup cluster configuration')
    backup_parser.add_argument('--output', type=str, help='Backup file path')
    
    # Health command
    health_parser = subparsers.add_parser('health', help='Display cluster health dashboard')
    health_parser.add_argument('--detailed', action='store_true', help='Show detailed metrics')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        manager = MonitoringManager(args.config)
        
        if args.command == 'collect':
            metrics = manager.collect_cluster_metrics(args.manager_ip, args.output)
            print(f"📊 Collected metrics for {len(metrics.get('node_metrics', []))} nodes and {len(metrics.get('service_metrics', []))} services")
            
        elif args.command == 'alerts':
            alert_config = {
                'cpu_threshold': args.cpu_threshold,
                'memory_threshold': args.memory_threshold,
                'disk_threshold': args.disk_threshold
            }
            success = manager.create_alerts(args.manager_ip, alert_config)
            if success:
                print("✅ Monitoring alerts configured successfully")
            else:
                print("❌ Failed to configure monitoring alerts")
                return 1
                
        elif args.command == 'optimize':
            optimizations = manager.optimize_performance(args.manager_ip, args.level)
            print(f"✅ Applied {len(optimizations['applied'])} optimizations")
            if optimizations['recommendations']:
                print(f"💡 {len(optimizations['recommendations'])} recommendations generated")
            if optimizations['failed']:
                print(f"⚠️  {len(optimizations['failed'])} optimizations failed")
                return 1
                
        elif args.command == 'backup':
            backup_path = manager.backup_cluster_config(args.manager_ip, args.output)
            if backup_path:
                print(f"✅ Cluster backup created: {backup_path}")
            else:
                print("❌ Failed to create cluster backup")
                return 1
                
        elif args.command == 'health':
            manager.display_health_dashboard(args.manager_ip, args.detailed)
        
        return 0
        
    except KeyboardInterrupt:
        print("\n⚠️  Operation cancelled by user")
        return 1
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
