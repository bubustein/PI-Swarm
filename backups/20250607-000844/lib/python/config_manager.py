#!/usr/bin/env python3
"""
Pi-Swarm Configuration Management Module

This module provides Python-based configuration parsing and validation
for the Pi-Swarm cluster deployment system.

Features:
- YAML configuration file parsing
- Environment variable integration
- Configuration validation and schema checking
- Default value management
- Configuration merging and inheritance
"""

import os
import sys
import yaml
import json
import re
from pathlib import Path
from typing import Dict, Any, List, Optional, Union
from dataclasses import dataclass, field


@dataclass
class NetworkConfig:
    """Network configuration settings."""
    subnet: str = "192.168.1.0/24"
    gateway: str = "192.168.1.1"
    dns_servers: List[str] = field(default_factory=lambda: ["1.1.1.1", "8.8.8.8"])
    pi_ip_range: str = "192.168.1.100-192.168.1.199"
    
    def validate(self) -> List[str]:
        """Validate network configuration."""
        errors = []
        
        # Validate subnet format
        if not re.match(r'^\d+\.\d+\.\d+\.\d+/\d+$', self.subnet):
            errors.append(f"Invalid subnet format: {self.subnet}")
        
        # Validate gateway IP
        if not re.match(r'^\d+\.\d+\.\d+\.\d+$', self.gateway):
            errors.append(f"Invalid gateway IP: {self.gateway}")
        
        # Validate DNS servers
        for dns in self.dns_servers:
            if not re.match(r'^\d+\.\d+\.\d+\.\d+$', dns):
                errors.append(f"Invalid DNS server IP: {dns}")
        
        return errors


@dataclass
class StorageConfig:
    """Storage configuration settings."""
    enable_shared_storage: bool = False
    storage_solution: str = "glusterfs"  # glusterfs, nfs, longhorn
    storage_path: str = "/mnt/shared"
    auto_detect_ssd: bool = True
    min_storage_size_gb: int = 32
    
    def validate(self) -> List[str]:
        """Validate storage configuration."""
        errors = []
        
        if self.storage_solution not in ["glusterfs", "nfs", "longhorn", "local"]:
            errors.append(f"Invalid storage solution: {self.storage_solution}")
        
        if self.min_storage_size_gb < 1:
            errors.append("Minimum storage size must be at least 1 GB")
        
        return errors


@dataclass
class DNSConfig:
    """DNS configuration settings."""
    enable_pihole: bool = False
    pihole_ip: str = "auto"
    domain: str = "cluster.local"
    upstream_dns: List[str] = field(default_factory=lambda: ["1.1.1.1", "8.8.8.8"])
    admin_password: str = "piswarm123"
    
    def validate(self) -> List[str]:
        """Validate DNS configuration."""
        errors = []
        
        # Validate domain format
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$', self.domain):
            errors.append(f"Invalid domain format: {self.domain}")
        
        # Validate upstream DNS
        for dns in self.upstream_dns:
            if not re.match(r'^\d+\.\d+\.\d+\.\d+$', dns):
                errors.append(f"Invalid upstream DNS server IP: {dns}")
        
        return errors


@dataclass
class SecurityConfig:
    """Security configuration settings."""
    enable_firewall: bool = True
    ssh_port: int = 22
    disable_password_auth: bool = True
    enable_fail2ban: bool = True
    ssl_cert_email: str = ""
    
    def validate(self) -> List[str]:
        """Validate security configuration."""
        errors = []
        
        if not (1 <= self.ssh_port <= 65535):
            errors.append(f"SSH port must be between 1 and 65535: {self.ssh_port}")
        
        if self.ssl_cert_email and not re.match(r'^[^@]+@[^@]+\.[^@]+$', self.ssl_cert_email):
            errors.append(f"Invalid email format: {self.ssl_cert_email}")
        
        return errors


@dataclass
class MonitoringConfig:
    """Monitoring configuration settings."""
    enable_monitoring: bool = True
    prometheus_retention: str = "15d"
    grafana_admin_password: str = "admin"
    enable_alerts: bool = True
    alert_channels: List[str] = field(default_factory=lambda: ["email"])
    
    def validate(self) -> List[str]:
        """Validate monitoring configuration."""
        errors = []
        
        # Validate retention period format
        if not re.match(r'^\d+[dwmy]$', self.prometheus_retention):
            errors.append(f"Invalid retention period format: {self.prometheus_retention}")
        
        # Validate alert channels
        valid_channels = ["email", "slack", "discord", "whatsapp"]
        for channel in self.alert_channels:
            if channel not in valid_channels:
                errors.append(f"Invalid alert channel: {channel}")
        
        return errors


@dataclass
class PiSwarmConfig:
    """Main Pi-Swarm configuration."""
    version: str = "2.0.0"
    cluster_name: str = "pi-swarm"
    deployment_mode: str = "automated"  # automated, interactive
    
    # Component configurations
    network: NetworkConfig = field(default_factory=NetworkConfig)
    storage: StorageConfig = field(default_factory=StorageConfig)
    dns: DNSConfig = field(default_factory=DNSConfig)
    security: SecurityConfig = field(default_factory=SecurityConfig)
    monitoring: MonitoringConfig = field(default_factory=MonitoringConfig)
    
    def validate(self) -> List[str]:
        """Validate complete configuration."""
        errors = []
        
        # Validate deployment mode
        if self.deployment_mode not in ["automated", "interactive"]:
            errors.append(f"Invalid deployment mode: {self.deployment_mode}")
        
        # Validate cluster name
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$', self.cluster_name):
            errors.append(f"Invalid cluster name format: {self.cluster_name}")
        
        # Validate component configurations
        errors.extend(self.network.validate())
        errors.extend(self.storage.validate())
        errors.extend(self.dns.validate())
        errors.extend(self.security.validate())
        errors.extend(self.monitoring.validate())
        
        return errors


class ConfigManager:
    """Configuration file management and parsing."""
    
    def __init__(self, config_file: Optional[str] = None):
        self.config_file = config_file or "config/config.yml"
        self.config = PiSwarmConfig()
        
    def load_config(self, config_file: Optional[str] = None) -> PiSwarmConfig:
        """Load configuration from YAML file."""
        if config_file:
            self.config_file = config_file
        
        config_path = Path(self.config_file)
        
        if not config_path.exists():
            print(f"Warning: Config file {self.config_file} not found, using defaults", file=sys.stderr)
            return self.config
        
        try:
            with open(config_path, 'r') as f:
                yaml_data = yaml.safe_load(f) or {}
            
            # Parse configuration sections
            self.config = self._parse_config_dict(yaml_data)
            
            # Merge with environment variables
            self._merge_environment_variables()
            
            return self.config
            
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML in config file: {e}")
        except Exception as e:
            raise ValueError(f"Error loading config file: {e}")
    
    def _parse_config_dict(self, data: Dict[str, Any]) -> PiSwarmConfig:
        """Parse configuration dictionary into PiSwarmConfig object."""
        config = PiSwarmConfig()
        
        # Main config
        config.version = data.get('version', config.version)
        config.cluster_name = data.get('cluster_name', config.cluster_name)
        config.deployment_mode = data.get('deployment_mode', config.deployment_mode)
        
        # Network config
        if 'network' in data:
            net_data = data['network']
            config.network = NetworkConfig(
                subnet=net_data.get('subnet', config.network.subnet),
                gateway=net_data.get('gateway', config.network.gateway),
                dns_servers=net_data.get('dns_servers', config.network.dns_servers),
                pi_ip_range=net_data.get('pi_ip_range', config.network.pi_ip_range)
            )
        
        # Storage config
        if 'storage' in data:
            storage_data = data['storage']
            config.storage = StorageConfig(
                enable_shared_storage=storage_data.get('enable_shared_storage', config.storage.enable_shared_storage),
                storage_solution=storage_data.get('storage_solution', config.storage.storage_solution),
                storage_path=storage_data.get('storage_path', config.storage.storage_path),
                auto_detect_ssd=storage_data.get('auto_detect_ssd', config.storage.auto_detect_ssd),
                min_storage_size_gb=storage_data.get('min_storage_size_gb', config.storage.min_storage_size_gb)
            )
        
        # DNS config
        if 'dns' in data:
            dns_data = data['dns']
            config.dns = DNSConfig(
                enable_pihole=dns_data.get('enable_pihole', config.dns.enable_pihole),
                pihole_ip=dns_data.get('pihole_ip', config.dns.pihole_ip),
                domain=dns_data.get('domain', config.dns.domain),
                upstream_dns=dns_data.get('upstream_dns', config.dns.upstream_dns),
                admin_password=dns_data.get('admin_password', config.dns.admin_password)
            )
        
        # Security config
        if 'security' in data:
            sec_data = data['security']
            config.security = SecurityConfig(
                enable_firewall=sec_data.get('enable_firewall', config.security.enable_firewall),
                ssh_port=sec_data.get('ssh_port', config.security.ssh_port),
                disable_password_auth=sec_data.get('disable_password_auth', config.security.disable_password_auth),
                enable_fail2ban=sec_data.get('enable_fail2ban', config.security.enable_fail2ban),
                ssl_cert_email=sec_data.get('ssl_cert_email', config.security.ssl_cert_email)
            )
        
        # Monitoring config
        if 'monitoring' in data:
            mon_data = data['monitoring']
            config.monitoring = MonitoringConfig(
                enable_monitoring=mon_data.get('enable_monitoring', config.monitoring.enable_monitoring),
                prometheus_retention=mon_data.get('prometheus_retention', config.monitoring.prometheus_retention),
                grafana_admin_password=mon_data.get('grafana_admin_password', config.monitoring.grafana_admin_password),
                enable_alerts=mon_data.get('enable_alerts', config.monitoring.enable_alerts),
                alert_channels=mon_data.get('alert_channels', config.monitoring.alert_channels)
            )
        
        return config
    
    def _merge_environment_variables(self):
        """Merge environment variables into configuration."""
        env_mappings = {
            # Main config
            'PI_SWARM_CLUSTER_NAME': ('cluster_name', str),
            'PI_SWARM_DEPLOYMENT_MODE': ('deployment_mode', str),
            
            # Network
            'PI_SWARM_SUBNET': ('network.subnet', str),
            'PI_SWARM_GATEWAY': ('network.gateway', str),
            
            # Storage
            'ENABLE_STORAGE': ('storage.enable_shared_storage', bool),
            'STORAGE_SOLUTION': ('storage.storage_solution', str),
            'AUTO_DETECT_SSD': ('storage.auto_detect_ssd', bool),
            
            # DNS
            'ENABLE_PIHOLE': ('dns.enable_pihole', bool),
            'PIHOLE_IP': ('dns.pihole_ip', str),
            'PIHOLE_DOMAIN': ('dns.domain', str),
            'PIHOLE_WEB_PASSWORD': ('dns.admin_password', str),
            
            # Security
            'SSH_PORT': ('security.ssh_port', int),
            'DISABLE_PASSWORD_AUTH': ('security.disable_password_auth', bool),
            
            # Monitoring
            'ENABLE_MONITORING': ('monitoring.enable_monitoring', bool),
            'GRAFANA_ADMIN_PASSWORD': ('monitoring.grafana_admin_password', str),
        }
        
        for env_var, (config_path, var_type) in env_mappings.items():
            env_value = os.environ.get(env_var)
            if env_value is not None:
                try:
                    # Convert value to appropriate type
                    if var_type == bool:
                        value = env_value.lower() in ('true', '1', 'yes', 'on')
                    elif var_type == int:
                        value = int(env_value)
                    else:
                        value = env_value
                    
                    # Set value in config
                    self._set_nested_value(config_path, value)
                    
                except ValueError as e:
                    print(f"Warning: Invalid value for {env_var}: {env_value}", file=sys.stderr)
    
    def _set_nested_value(self, path: str, value: Any):
        """Set a nested configuration value using dot notation."""
        parts = path.split('.')
        obj = self.config
        
        for part in parts[:-1]:
            obj = getattr(obj, part)
        
        setattr(obj, parts[-1], value)
    
    def save_config(self, config_file: Optional[str] = None) -> None:
        """Save configuration to YAML file."""
        if config_file:
            self.config_file = config_file
        
        config_dict = self._config_to_dict()
        
        # Ensure directory exists
        config_path = Path(self.config_file)
        config_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(config_path, 'w') as f:
            yaml.dump(config_dict, f, default_flow_style=False, indent=2)
    
    def _config_to_dict(self) -> Dict[str, Any]:
        """Convert PiSwarmConfig to dictionary."""
        return {
            'version': self.config.version,
            'cluster_name': self.config.cluster_name,
            'deployment_mode': self.config.deployment_mode,
            'network': {
                'subnet': self.config.network.subnet,
                'gateway': self.config.network.gateway,
                'dns_servers': self.config.network.dns_servers,
                'pi_ip_range': self.config.network.pi_ip_range,
            },
            'storage': {
                'enable_shared_storage': self.config.storage.enable_shared_storage,
                'storage_solution': self.config.storage.storage_solution,
                'storage_path': self.config.storage.storage_path,
                'auto_detect_ssd': self.config.storage.auto_detect_ssd,
                'min_storage_size_gb': self.config.storage.min_storage_size_gb,
            },
            'dns': {
                'enable_pihole': self.config.dns.enable_pihole,
                'pihole_ip': self.config.dns.pihole_ip,
                'domain': self.config.dns.domain,
                'upstream_dns': self.config.dns.upstream_dns,
                'admin_password': self.config.dns.admin_password,
            },
            'security': {
                'enable_firewall': self.config.security.enable_firewall,
                'ssh_port': self.config.security.ssh_port,
                'disable_password_auth': self.config.security.disable_password_auth,
                'enable_fail2ban': self.config.security.enable_fail2ban,
                'ssl_cert_email': self.config.security.ssl_cert_email,
            },
            'monitoring': {
                'enable_monitoring': self.config.monitoring.enable_monitoring,
                'prometheus_retention': self.config.monitoring.prometheus_retention,
                'grafana_admin_password': self.config.monitoring.grafana_admin_password,
                'enable_alerts': self.config.monitoring.enable_alerts,
                'alert_channels': self.config.monitoring.alert_channels,
            }
        }
    
    def validate_config(self) -> List[str]:
        """Validate the current configuration."""
        return self.config.validate()
    
    def get_config_summary(self) -> str:
        """Get a human-readable configuration summary."""
        summary = f"""Pi-Swarm Configuration Summary
================================

Cluster: {self.config.cluster_name} (v{self.config.version})
Mode: {self.config.deployment_mode}

Network:
  Subnet: {self.config.network.subnet}
  Gateway: {self.config.network.gateway}
  DNS Servers: {', '.join(self.config.network.dns_servers)}

Storage:
  Enabled: {self.config.storage.enable_shared_storage}
  Solution: {self.config.storage.storage_solution}
  Path: {self.config.storage.storage_path}

DNS:
  Pi-hole: {self.config.dns.enable_pihole}
  Domain: {self.config.dns.domain}

Security:
  Firewall: {self.config.security.enable_firewall}
  SSH Port: {self.config.security.ssh_port}
  Fail2ban: {self.config.security.enable_fail2ban}

Monitoring:
  Enabled: {self.config.monitoring.enable_monitoring}
  Alerts: {self.config.monitoring.enable_alerts}
"""
        return summary


def main():
    """Command line interface for configuration management."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Pi-Swarm Configuration Management')
    parser.add_argument('--config', '-c', default='config/config.yml',
                       help='Configuration file path')
    parser.add_argument('--validate', action='store_true',
                       help='Validate configuration')
    parser.add_argument('--summary', action='store_true',
                       help='Show configuration summary')
    parser.add_argument('--create-default', action='store_true',
                       help='Create default configuration file')
    parser.add_argument('--format', choices=['yaml', 'json'], default='yaml',
                       help='Output format')
    
    args = parser.parse_args()
    
    config_manager = ConfigManager(args.config)
    
    if args.create_default:
        # Create default configuration
        config_manager.save_config()
        print(f"Default configuration created at {args.config}")
        return
    
    try:
        # Load configuration
        config = config_manager.load_config()
        
        if args.validate:
            # Validate configuration
            errors = config_manager.validate_config()
            if errors:
                print("Configuration validation failed:")
                for error in errors:
                    print(f"  ❌ {error}")
                sys.exit(1)
            else:
                print("✅ Configuration is valid")
        
        if args.summary:
            # Show summary
            print(config_manager.get_config_summary())
        
        if not args.validate and not args.summary:
            # Output configuration
            if args.format == 'json':
                print(json.dumps(config_manager._config_to_dict(), indent=2))
            else:
                config_dict = config_manager._config_to_dict()
                print(yaml.dump(config_dict, default_flow_style=False, indent=2))
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
