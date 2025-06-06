#!/usr/bin/env python3
"""
Pi-Swarm Service Orchestration Module

This module provides Python-based service orchestration capabilities
for Docker Swarm clusters in the Pi-Swarm deployment system.

Features:
- Docker Swarm service management
- Service template generation and deployment
- Health monitoring and auto-recovery
- Rolling updates and scaling
- Resource constraint management
- Service dependency resolution
"""

import subprocess
import json
import yaml
import time
import re
from typing import Dict, List, Optional, Any, Union, Tuple
from dataclasses import dataclass, field
from pathlib import Path
from datetime import datetime, timedelta
import logging


@dataclass
class ServiceTemplate:
    """Docker service template definition."""
    name: str
    image: str
    replicas: int = 1
    ports: List[str] = field(default_factory=list)
    environment: Dict[str, str] = field(default_factory=dict)
    volumes: List[str] = field(default_factory=list)
    networks: List[str] = field(default_factory=list)
    constraints: List[str] = field(default_factory=list)
    resources: Dict[str, Any] = field(default_factory=dict)
    labels: Dict[str, str] = field(default_factory=dict)
    depends_on: List[str] = field(default_factory=list)
    health_check: Optional[Dict[str, Any]] = None
    update_config: Optional[Dict[str, Any]] = None


@dataclass
class ServiceStatus:
    """Current status of a deployed service."""
    name: str
    desired_replicas: int
    running_replicas: int
    state: str  # running, converged, updating, etc.
    image: str
    created: datetime
    updated: datetime
    ports: List[str] = field(default_factory=list)
    error_message: Optional[str] = None


@dataclass
class DeploymentResult:
    """Result of a service deployment operation."""
    service_name: str
    success: bool
    message: str
    deployment_time: float = 0.0
    service_id: Optional[str] = None


@dataclass
class ScalingResult:
    """Result of a service scaling operation."""
    service_name: str
    success: bool
    old_replicas: int
    new_replicas: int
    message: str


class ServiceOrchestrator:
    """Manages Docker Swarm service orchestration."""
    
    def __init__(self, manager_host: str, ssh_manager=None):
        self.manager_host = manager_host
        self.ssh_manager = ssh_manager
        self.logger = self._setup_logger()
    
    def _setup_logger(self) -> logging.Logger:
        """Setup logging for service orchestration."""
        logger = logging.getLogger('service_orchestrator')
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)
        return logger
    
    def _execute_remote_command(self, command: str, timeout: int = 60) -> Tuple[bool, str, str]:
        """Execute a command on the manager node."""
        if self.ssh_manager:
            # Use SSH manager if available
            from .ssh_manager import SSHCredentials
            # This would need proper credentials setup
            pass
        
        # Fallback to subprocess for now
        try:
            result = subprocess.run(
                ['ssh', self.manager_host, command],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", f"Command timeout after {timeout} seconds"
        except Exception as e:
            return False, "", str(e)
    
    def generate_service_templates(self) -> Dict[str, ServiceTemplate]:
        """Generate common service templates for Pi-Swarm deployment."""
        templates = {}
        
        # Web Services
        templates['nginx-web'] = ServiceTemplate(
            name='nginx-web',
            image='nginx:alpine',
            replicas=2,
            ports=['80:80', '443:443'],
            volumes=['/var/www:/usr/share/nginx/html:ro'],
            constraints=['node.role==worker'],
            resources={
                'limits': {'memory': '128M', 'cpus': '0.5'},
                'reservations': {'memory': '64M', 'cpus': '0.25'}
            },
            labels={'traefik.enable': 'true'},
            health_check={
                'test': ['CMD', 'wget', '--quiet', '--tries=1', '--spider', 'http://localhost/'],
                'interval': '30s',
                'timeout': '10s',
                'retries': 3
            }
        )
        
        templates['portainer'] = ServiceTemplate(
            name='portainer',
            image='portainer/portainer-ce:latest',
            replicas=1,
            ports=['9000:9000'],
            volumes=[
                '/var/run/docker.sock:/var/run/docker.sock',
                'portainer_data:/data'
            ],
            constraints=['node.role==manager'],
            resources={
                'limits': {'memory': '256M', 'cpus': '0.5'},
                'reservations': {'memory': '128M', 'cpus': '0.25'}
            },
            labels={
                'traefik.enable': 'true',
                'traefik.http.routers.portainer.rule': 'Host(`portainer.local`)',
                'traefik.http.services.portainer.loadbalancer.server.port': '9000'
            }
        )
        
        # Monitoring Services
        templates['prometheus'] = ServiceTemplate(
            name='prometheus',
            image='prom/prometheus:latest',
            replicas=1,
            ports=['9090:9090'],
            volumes=[
                'prometheus_data:/prometheus',
                '/opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro'
            ],
            constraints=['node.role==manager'],
            environment={
                'PROMETHEUS_RETENTION_TIME': '30d',
                'PROMETHEUS_RETENTION_SIZE': '10GB'
            },
            resources={
                'limits': {'memory': '512M', 'cpus': '1.0'},
                'reservations': {'memory': '256M', 'cpus': '0.5'}
            }
        )
        
        templates['grafana'] = ServiceTemplate(
            name='grafana',
            image='grafana/grafana:latest',
            replicas=1,
            ports=['3000:3000'],
            volumes=['grafana_data:/var/lib/grafana'],
            environment={
                'GF_SECURITY_ADMIN_USER': 'admin',
                'GF_SECURITY_ADMIN_PASSWORD': 'admin',
                'GF_USERS_ALLOW_SIGN_UP': 'false'
            },
            depends_on=['prometheus'],
            resources={
                'limits': {'memory': '256M', 'cpus': '0.5'},
                'reservations': {'memory': '128M', 'cpus': '0.25'}
            }
        )
        
        # Database Services
        templates['redis'] = ServiceTemplate(
            name='redis',
            image='redis:alpine',
            replicas=1,
            ports=['6379:6379'],
            volumes=['redis_data:/data'],
            constraints=['node.role==worker'],
            resources={
                'limits': {'memory': '128M', 'cpus': '0.5'},
                'reservations': {'memory': '64M', 'cpus': '0.25'}
            },
            health_check={
                'test': ['CMD', 'redis-cli', 'ping'],
                'interval': '30s',
                'timeout': '10s',
                'retries': 3
            }
        )
        
        templates['mysql'] = ServiceTemplate(
            name='mysql',
            image='mysql:8.0',
            replicas=1,
            ports=['3306:3306'],
            volumes=['mysql_data:/var/lib/mysql'],
            environment={
                'MYSQL_ROOT_PASSWORD': 'rootpassword',
                'MYSQL_DATABASE': 'piswarm',
                'MYSQL_USER': 'piuser',
                'MYSQL_PASSWORD': 'pipassword'
            },
            constraints=['node.role==worker'],
            resources={
                'limits': {'memory': '512M', 'cpus': '1.0'},
                'reservations': {'memory': '256M', 'cpus': '0.5'}
            },
            health_check={
                'test': ['CMD', 'mysqladmin', 'ping', '-h', 'localhost'],
                'interval': '30s',
                'timeout': '10s',
                'retries': 3
            }
        )
        
        return templates
    
    def generate_docker_compose(self, services: List[ServiceTemplate]) -> str:
        """Generate Docker Compose YAML from service templates."""
        compose_dict = {
            'version': '3.8',
            'services': {},
            'volumes': {},
            'networks': {
                'pi-swarm-network': {
                    'driver': 'overlay',
                    'attachable': True
                }
            }
        }
        
        # Process services in dependency order
        ordered_services = self._resolve_dependencies(services)
        
        for service in ordered_services:
            service_config = {
                'image': service.image,
                'deploy': {
                    'replicas': service.replicas,
                    'placement': {
                        'constraints': service.constraints
                    }
                }
            }
            
            # Add ports
            if service.ports:
                service_config['ports'] = service.ports
            
            # Add environment variables
            if service.environment:
                service_config['environment'] = service.environment
            
            # Add volumes
            if service.volumes:
                service_config['volumes'] = service.volumes
                # Extract named volumes
                for volume in service.volumes:
                    if ':' in volume:
                        vol_name = volume.split(':')[0]
                        if not vol_name.startswith('/') and vol_name not in compose_dict['volumes']:
                            compose_dict['volumes'][vol_name] = {}
            
            # Add networks
            networks = service.networks if service.networks else ['pi-swarm-network']
            service_config['networks'] = networks
            
            # Add resources
            if service.resources:
                if 'deploy' not in service_config:
                    service_config['deploy'] = {}
                service_config['deploy']['resources'] = service.resources
            
            # Add labels
            if service.labels:
                if 'deploy' not in service_config:
                    service_config['deploy'] = {}
                service_config['deploy']['labels'] = service.labels
            
            # Add health check
            if service.health_check:
                service_config['healthcheck'] = service.health_check
            
            # Add update config
            if service.update_config:
                if 'deploy' not in service_config:
                    service_config['deploy'] = {}
                service_config['deploy']['update_config'] = service.update_config
            
            compose_dict['services'][service.name] = service_config
        
        return yaml.dump(compose_dict, default_flow_style=False, sort_keys=False)
    
    def _resolve_dependencies(self, services: List[ServiceTemplate]) -> List[ServiceTemplate]:
        """Resolve service dependencies and return ordered list."""
        # Simple topological sort
        resolved = []
        remaining = services.copy()
        
        while remaining:
            # Find services with no unresolved dependencies
            ready = []
            for service in remaining:
                deps_resolved = all(
                    any(s.name == dep for s in resolved) 
                    for dep in service.depends_on
                )
                if deps_resolved:
                    ready.append(service)
            
            if not ready:
                # Circular dependency or missing dependency
                self.logger.warning("Circular dependency detected, deploying remaining services anyway")
                ready = remaining
            
            resolved.extend(ready)
            for service in ready:
                remaining.remove(service)
        
        return resolved
    
    def deploy_service(self, service: ServiceTemplate) -> DeploymentResult:
        """Deploy a single service to the Docker Swarm."""
        start_time = time.time()
        
        self.logger.info(f"🚀 Deploying service: {service.name}")
        
        # Generate Docker service create command
        cmd_parts = ['docker', 'service', 'create']
        cmd_parts.extend(['--name', service.name])
        cmd_parts.extend(['--replicas', str(service.replicas)])
        
        # Add ports
        for port in service.ports:
            cmd_parts.extend(['--publish', port])
        
        # Add environment variables
        for key, value in service.environment.items():
            cmd_parts.extend(['--env', f'{key}={value}'])
        
        # Add volumes
        for volume in service.volumes:
            cmd_parts.extend(['--mount', f'type=volume,source={volume.split(":")[0]},target={volume.split(":")[1]}'])
        
        # Add constraints
        for constraint in service.constraints:
            cmd_parts.extend(['--constraint', constraint])
        
        # Add resource limits
        if service.resources.get('limits'):
            limits = service.resources['limits']
            if 'memory' in limits:
                cmd_parts.extend(['--limit-memory', limits['memory']])
            if 'cpus' in limits:
                cmd_parts.extend(['--limit-cpu', str(limits['cpus'])])
        
        # Add resource reservations
        if service.resources.get('reservations'):
            reservations = service.resources['reservations']
            if 'memory' in reservations:
                cmd_parts.extend(['--reserve-memory', reservations['memory']])
            if 'cpus' in reservations:
                cmd_parts.extend(['--reserve-cpu', str(reservations['cpus'])])
        
        # Add labels
        for key, value in service.labels.items():
            cmd_parts.extend(['--label', f'{key}={value}'])
        
        # Add health check
        if service.health_check:
            hc = service.health_check
            if 'test' in hc:
                cmd_parts.extend(['--health-cmd', ' '.join(hc['test'][1:])])  # Skip 'CMD'
            if 'interval' in hc:
                cmd_parts.extend(['--health-interval', hc['interval']])
            if 'timeout' in hc:
                cmd_parts.extend(['--health-timeout', hc['timeout']])
            if 'retries' in hc:
                cmd_parts.extend(['--health-retries', str(hc['retries'])])
        
        # Add image
        cmd_parts.append(service.image)
        
        # Execute deployment command
        command = ' '.join(cmd_parts)
        success, stdout, stderr = self._execute_remote_command(command)
        
        deployment_time = time.time() - start_time
        
        if success:
            # Extract service ID from output
            service_id = stdout.strip() if stdout else None
            return DeploymentResult(
                service_name=service.name,
                success=True,
                message=f"Service deployed successfully in {deployment_time:.2f}s",
                deployment_time=deployment_time,
                service_id=service_id
            )
        else:
            return DeploymentResult(
                service_name=service.name,
                success=False,
                message=f"Deployment failed: {stderr}",
                deployment_time=deployment_time
            )
    
    def deploy_stack(self, stack_name: str, compose_content: str) -> Dict[str, DeploymentResult]:
        """Deploy a complete stack using Docker Compose."""
        self.logger.info(f"🚀 Deploying stack: {stack_name}")
        
        # Write compose file to remote host
        compose_path = f"/tmp/{stack_name}-compose.yml"
        write_cmd = f"cat > {compose_path} << 'EOF'\n{compose_content}\nEOF"
        
        success, stdout, stderr = self._execute_remote_command(write_cmd)
        if not success:
            return {stack_name: DeploymentResult(
                service_name=stack_name,
                success=False,
                message=f"Failed to write compose file: {stderr}"
            )}
        
        # Deploy stack
        deploy_cmd = f"docker stack deploy -c {compose_path} {stack_name}"
        success, stdout, stderr = self._execute_remote_command(deploy_cmd)
        
        if success:
            return {stack_name: DeploymentResult(
                service_name=stack_name,
                success=True,
                message="Stack deployed successfully"
            )}
        else:
            return {stack_name: DeploymentResult(
                service_name=stack_name,
                success=False,
                message=f"Stack deployment failed: {stderr}"
            )}
    
    def get_service_status(self, service_name: Optional[str] = None) -> List[ServiceStatus]:
        """Get status of deployed services."""
        if service_name:
            cmd = f"docker service ls --filter name={service_name} --format json"
        else:
            cmd = "docker service ls --format json"
        
        success, stdout, stderr = self._execute_remote_command(cmd)
        
        if not success:
            self.logger.error(f"Failed to get service status: {stderr}")
            return []
        
        services = []
        for line in stdout.strip().split('\n'):
            if line.strip():
                try:
                    service_data = json.loads(line)
                    
                    # Parse replicas (e.g., "2/3" -> desired=3, running=2)
                    replicas_str = service_data.get('Replicas', '0/0')
                    running_str, desired_str = replicas_str.split('/')
                    
                    services.append(ServiceStatus(
                        name=service_data.get('Name', ''),
                        desired_replicas=int(desired_str),
                        running_replicas=int(running_str),
                        state=service_data.get('Mode', ''),
                        image=service_data.get('Image', ''),
                        created=datetime.now(),  # Would need proper parsing
                        updated=datetime.now(),   # Would need proper parsing
                        ports=service_data.get('Ports', '').split(',') if service_data.get('Ports') else []
                    ))
                except (json.JSONDecodeError, ValueError, KeyError) as e:
                    self.logger.warning(f"Failed to parse service data: {e}")
        
        return services
    
    def scale_service(self, service_name: str, replicas: int) -> ScalingResult:
        """Scale a service to the specified number of replicas."""
        # Get current status
        current_services = self.get_service_status(service_name)
        if not current_services:
            return ScalingResult(
                service_name=service_name,
                success=False,
                old_replicas=0,
                new_replicas=replicas,
                message="Service not found"
            )
        
        current_service = current_services[0]
        old_replicas = current_service.desired_replicas
        
        # Scale service
        cmd = f"docker service scale {service_name}={replicas}"
        success, stdout, stderr = self._execute_remote_command(cmd)
        
        return ScalingResult(
            service_name=service_name,
            success=success,
            old_replicas=old_replicas,
            new_replicas=replicas,
            message=stdout if success else stderr
        )
    
    def remove_service(self, service_name: str) -> bool:
        """Remove a service from the swarm."""
        cmd = f"docker service rm {service_name}"
        success, stdout, stderr = self._execute_remote_command(cmd)
        
        if success:
            self.logger.info(f"✅ Service {service_name} removed successfully")
        else:
            self.logger.error(f"❌ Failed to remove service {service_name}: {stderr}")
        
        return success
    
    def update_service(self, service_name: str, image: Optional[str] = None, 
                      env_vars: Optional[Dict[str, str]] = None) -> bool:
        """Update a service with new image or environment variables."""
        cmd_parts = ['docker', 'service', 'update']
        
        if image:
            cmd_parts.extend(['--image', image])
        
        if env_vars:
            for key, value in env_vars.items():
                cmd_parts.extend(['--env-add', f'{key}={value}'])
        
        cmd_parts.append(service_name)
        
        command = ' '.join(cmd_parts)
        success, stdout, stderr = self._execute_remote_command(command)
        
        if success:
            self.logger.info(f"✅ Service {service_name} updated successfully")
        else:
            self.logger.error(f"❌ Failed to update service {service_name}: {stderr}")
        
        return success


def main():
    """Command-line interface for service orchestration."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Pi-Swarm Service Orchestration')
    parser.add_argument('action', choices=['generate', 'deploy', 'status', 'scale', 'remove'],
                       help='Action to perform')
    parser.add_argument('--manager-host', required=True,
                       help='Docker Swarm manager host')
    parser.add_argument('--service', help='Service name')
    parser.add_argument('--stack', help='Stack name')
    parser.add_argument('--replicas', type=int, help='Number of replicas for scaling')
    parser.add_argument('--output', help='Output file for generated compose')
    parser.add_argument('--template', help='Service template name')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    args = parser.parse_args()
    
    # Setup logging
    if args.verbose:
        logging.getLogger('service_orchestrator').setLevel(logging.DEBUG)
    
    # Create orchestrator
    orchestrator = ServiceOrchestrator(args.manager_host)
    
    if args.action == 'generate':
        templates = orchestrator.generate_service_templates()
        
        if args.template:
            if args.template in templates:
                service_list = [templates[args.template]]
            else:
                print(f"Template '{args.template}' not found")
                print(f"Available templates: {', '.join(templates.keys())}")
                return 1
        else:
            service_list = list(templates.values())
        
        compose_content = orchestrator.generate_docker_compose(service_list)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(compose_content)
            print(f"Docker Compose file written to {args.output}")
        else:
            print(compose_content)
    
    elif args.action == 'deploy':
        if args.stack:
            # Deploy stack from compose file
            if args.output and Path(args.output).exists():
                with open(args.output, 'r') as f:
                    compose_content = f.read()
                results = orchestrator.deploy_stack(args.stack, compose_content)
                for name, result in results.items():
                    print(f"{name}: {'✅' if result.success else '❌'} {result.message}")
            else:
                print("Error: --output file required for stack deployment")
                return 1
        else:
            print("Error: --stack required for deployment")
            return 1
    
    elif args.action == 'status':
        services = orchestrator.get_service_status(args.service)
        
        print(f"{'Service':<20} {'Image':<30} {'Replicas':<12} {'State':<15}")
        print("-" * 80)
        
        for service in services:
            print(f"{service.name:<20} {service.image:<30} "
                  f"{service.running_replicas}/{service.desired_replicas}:<12} {service.state:<15}")
    
    elif args.action == 'scale':
        if not args.service or args.replicas is None:
            print("Error: --service and --replicas required for scaling")
            return 1
        
        result = orchestrator.scale_service(args.service, args.replicas)
        print(f"{'✅' if result.success else '❌'} Scaling {args.service}: "
              f"{result.old_replicas} -> {result.new_replicas}")
        if not result.success:
            print(f"Error: {result.message}")
    
    elif args.action == 'remove':
        if not args.service:
            print("Error: --service required for removal")
            return 1
        
        success = orchestrator.remove_service(args.service)
        print(f"{'✅' if success else '❌'} Service removal: {args.service}")


if __name__ == '__main__':
    exit(main())
