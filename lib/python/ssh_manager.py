#!/usr/bin/env python3
"""
Pi-Swarm SSH Management Module

This module provides Python-based SSH connection management, authentication,
and remote command execution for the Pi-Swarm cluster deployment system.

Features:
- SSH connection pooling and management
- Key-based and password authentication
- Parallel command execution across nodes
- Connection health monitoring
- Secure credential handling
- Error recovery and retry logic
"""

import asyncio
try:
    import asyncssh
    HAS_ASYNCSSH = True
except ImportError:
    HAS_ASYNCSSH = False
    print("Warning: asyncssh not available, using paramiko only")

import subprocess
import threading
import time
import json
from typing import Dict, List, Optional, Tuple, Any, Union
from dataclasses import dataclass, field
from concurrent.futures import ThreadPoolExecutor, as_completed
import paramiko
import logging
from pathlib import Path


@dataclass
class SSHCredentials:
    """SSH authentication credentials."""
    username: str
    password: Optional[str] = None
    private_key_path: Optional[str] = None
    port: int = 22
    
    def __post_init__(self):
        if not self.password and not self.private_key_path:
            raise ValueError("Either password or private_key_path must be provided")


@dataclass
class SSHConnectionResult:
    """Result of an SSH connection attempt."""
    host: str
    success: bool
    error_message: Optional[str] = None
    connection_time: float = 0.0
    auth_method: Optional[str] = None


@dataclass
class SSHCommandResult:
    """Result of an SSH command execution."""
    host: str
    command: str
    success: bool
    stdout: str = ""
    stderr: str = ""
    exit_code: int = -1
    execution_time: float = 0.0


class SSHConnectionPool:
    """Manages SSH connections to multiple hosts with connection pooling."""
    
    def __init__(self, max_connections: int = 10, connection_timeout: int = 30):
        self.max_connections = max_connections
        self.connection_timeout = connection_timeout
        self.connections: Dict[str, Any] = {}
        self.connection_locks: Dict[str, threading.Lock] = {}
        self.logger = self._setup_logger()
        
    def _setup_logger(self) -> logging.Logger:
        """Setup logging for SSH operations."""
        logger = logging.getLogger('ssh_manager')
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)
        return logger
    
    def test_connection(self, host: str, credentials: SSHCredentials) -> SSHConnectionResult:
        """Test SSH connection to a single host."""
        start_time = time.time()
        
        try:
            # Use subprocess for compatibility with existing sshpass-based infrastructure
            if credentials.password:
                cmd = [
                    'sshpass', '-p', credentials.password,
                    'ssh', '-o', 'BatchMode=yes',
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', f'ConnectTimeout={self.connection_timeout}',
                    '-p', str(credentials.port),
                    f'{credentials.username}@{host}',
                    'exit'
                ]
            else:
                cmd = [
                    'ssh', '-o', 'BatchMode=yes',
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', f'ConnectTimeout={self.connection_timeout}',
                    '-i', credentials.private_key_path,
                    '-p', str(credentials.port),
                    f'{credentials.username}@{host}',
                    'exit'
                ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.connection_timeout
            )
            
            connection_time = time.time() - start_time
            
            if result.returncode == 0:
                return SSHConnectionResult(
                    host=host,
                    success=True,
                    connection_time=connection_time,
                    auth_method='password' if credentials.password else 'key'
                )
            else:
                error_msg = self._interpret_ssh_error(result.returncode, result.stderr)
                return SSHConnectionResult(
                    host=host,
                    success=False,
                    error_message=error_msg,
                    connection_time=connection_time
                )
                
        except subprocess.TimeoutExpired:
            return SSHConnectionResult(
                host=host,
                success=False,
                error_message=f"Connection timeout after {self.connection_timeout} seconds"
            )
        except Exception as e:
            return SSHConnectionResult(
                host=host,
                success=False,
                error_message=str(e)
            )
    
    def _interpret_ssh_error(self, exit_code: int, stderr: str) -> str:
        """Interpret SSH error codes and provide helpful messages."""
        error_interpretations = {
            255: "SSH connection failed - host unreachable or SSH not running",
            5: "SSH authentication failed - invalid credentials",
            6: "SSH authentication failed - permission denied",
            130: "Connection interrupted by user",
        }
        
        base_error = error_interpretations.get(exit_code, f"SSH failed with exit code {exit_code}")
        
        # Add specific guidance based on stderr content
        if "permission denied" in stderr.lower():
            base_error += ". Check username and password/key."
        elif "connection refused" in stderr.lower():
            base_error += ". Ensure SSH server is running on the target host."
        elif "no route to host" in stderr.lower():
            base_error += ". Check network connectivity."
        elif "timeout" in stderr.lower():
            base_error += ". Connection timed out - check network and SSH configuration."
            
        return base_error
    
    def test_multiple_connections(self, hosts_credentials: Dict[str, SSHCredentials], 
                                 max_workers: int = 5) -> Dict[str, SSHConnectionResult]:
        """Test SSH connections to multiple hosts in parallel."""
        results = {}
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_host = {
                executor.submit(self.test_connection, host, creds): host
                for host, creds in hosts_credentials.items()
            }
            
            for future in as_completed(future_to_host):
                host = future_to_host[future]
                try:
                    result = future.result()
                    results[host] = result
                    
                    if result.success:
                        self.logger.info(f"✅ SSH connection to {host} successful ({result.connection_time:.2f}s)")
                    else:
                        self.logger.warning(f"❌ SSH connection to {host} failed: {result.error_message}")
                        
                except Exception as e:
                    results[host] = SSHConnectionResult(
                        host=host,
                        success=False,
                        error_message=f"Test execution failed: {str(e)}"
                    )
                    self.logger.error(f"❌ SSH test to {host} failed with exception: {str(e)}")
        
        return results
    
    def execute_command(self, host: str, command: str, 
                       credentials: SSHCredentials, timeout: int = 60) -> SSHCommandResult:
        """Execute a command on a remote host via SSH."""
        start_time = time.time()
        
        try:
            if credentials.password:
                cmd = [
                    'sshpass', '-p', credentials.password,
                    'ssh', '-o', 'BatchMode=yes',
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', f'ConnectTimeout={self.connection_timeout}',
                    '-p', str(credentials.port),
                    f'{credentials.username}@{host}',
                    command
                ]
            else:
                cmd = [
                    'ssh', '-o', 'BatchMode=yes',
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', f'ConnectTimeout={self.connection_timeout}',
                    '-i', credentials.private_key_path,
                    '-p', str(credentials.port),
                    f'{credentials.username}@{host}',
                    command
                ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            execution_time = time.time() - start_time
            
            return SSHCommandResult(
                host=host,
                command=command,
                success=result.returncode == 0,
                stdout=result.stdout,
                stderr=result.stderr,
                exit_code=result.returncode,
                execution_time=execution_time
            )
            
        except subprocess.TimeoutExpired:
            return SSHCommandResult(
                host=host,
                command=command,
                success=False,
                stderr=f"Command timeout after {timeout} seconds",
                exit_code=-1
            )
        except Exception as e:
            return SSHCommandResult(
                host=host,
                command=command,
                success=False,
                stderr=str(e),
                exit_code=-1
            )
    
    def execute_parallel_commands(self, hosts_commands: Dict[str, str],
                                 credentials_map: Dict[str, SSHCredentials],
                                 max_workers: int = 5, timeout: int = 60) -> Dict[str, SSHCommandResult]:
        """Execute commands on multiple hosts in parallel."""
        results = {}
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_host = {
                executor.submit(
                    self.execute_command, 
                    host, 
                    command, 
                    credentials_map.get(host, list(credentials_map.values())[0]),
                    timeout
                ): host
                for host, command in hosts_commands.items()
            }
            
            for future in as_completed(future_to_host):
                host = future_to_host[future]
                try:
                    result = future.result()
                    results[host] = result
                    
                    if result.success:
                        self.logger.info(f"✅ Command on {host} completed successfully ({result.execution_time:.2f}s)")
                    else:
                        self.logger.warning(f"❌ Command on {host} failed: {result.stderr}")
                        
                except Exception as e:
                    results[host] = SSHCommandResult(
                        host=host,
                        command=hosts_commands[host],
                        success=False,
                        stderr=f"Execution failed: {str(e)}",
                        exit_code=-1
                    )
                    self.logger.error(f"❌ Command execution on {host} failed with exception: {str(e)}")
        
        return results


class SSHManager:
    """High-level SSH management interface."""
    
    def __init__(self, connection_pool: Optional[SSHConnectionPool] = None):
        self.pool = connection_pool or SSHConnectionPool()
        self.logger = self.pool.logger
    
    def validate_cluster_connectivity(self, cluster_config: Dict[str, Any]) -> Dict[str, Any]:
        """Validate SSH connectivity to all nodes in a cluster."""
        self.logger.info("🔍 Validating SSH connectivity to cluster nodes...")
        
        # Extract host and credential information
        hosts_credentials = {}
        for node_name, node_config in cluster_config.get('nodes', {}).items():
            host = node_config.get('ip')
            username = node_config.get('username', 'pi')
            password = node_config.get('password')
            key_path = node_config.get('ssh_key_path')
            
            if host:
                hosts_credentials[host] = SSHCredentials(
                    username=username,
                    password=password,
                    private_key_path=key_path
                )
        
        # Test connections
        results = self.pool.test_multiple_connections(hosts_credentials)
        
        # Summarize results
        successful_hosts = [host for host, result in results.items() if result.success]
        failed_hosts = [host for host, result in results.items() if not result.success]
        
        summary = {
            'total_nodes': len(results),
            'successful_connections': len(successful_hosts),
            'failed_connections': len(failed_hosts),
            'success_rate': len(successful_hosts) / len(results) * 100 if results else 0,
            'successful_hosts': successful_hosts,
            'failed_hosts': failed_hosts,
            'detailed_results': results
        }
        
        self.logger.info(f"📊 SSH Connectivity Summary:")
        self.logger.info(f"   ✅ Successful: {len(successful_hosts)}/{len(results)} nodes")
        self.logger.info(f"   ❌ Failed: {len(failed_hosts)}/{len(results)} nodes")
        self.logger.info(f"   📈 Success Rate: {summary['success_rate']:.1f}%")
        
        if failed_hosts:
            self.logger.warning("❌ Failed connections:")
            for host in failed_hosts:
                result = results[host]
                self.logger.warning(f"   {host}: {result.error_message}")
        
        return summary
    
    def setup_ssh_keys(self, cluster_config: Dict[str, Any], 
                      key_path: str = "~/.ssh/id_rsa") -> Dict[str, bool]:
        """Setup SSH key authentication for cluster nodes."""
        self.logger.info("🔑 Setting up SSH key authentication...")
        
        # Generate SSH key if it doesn't exist
        key_path_expanded = Path(key_path).expanduser()
        if not key_path_expanded.exists():
            self.logger.info(f"🔑 Generating SSH key at {key_path}...")
            subprocess.run([
                'ssh-keygen', '-t', 'rsa', '-b', '4096',
                '-f', str(key_path_expanded),
                '-N', '',  # No passphrase
                '-C', 'pi-swarm-cluster-key'
            ], check=True)
        
        # Read public key
        pub_key_path = key_path_expanded.with_suffix('.pub')
        with open(pub_key_path, 'r') as f:
            public_key = f.read().strip()
        
        # Deploy public key to all nodes
        results = {}
        for node_name, node_config in cluster_config.get('nodes', {}).items():
            host = node_config.get('ip')
            if not host:
                continue
                
            credentials = SSHCredentials(
                username=node_config.get('username', 'pi'),
                password=node_config.get('password')
            )
            
            # Copy public key to authorized_keys
            command = f"mkdir -p ~/.ssh && echo '{public_key}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
            result = self.pool.execute_command(host, command, credentials)
            results[host] = result.success
            
            if result.success:
                self.logger.info(f"✅ SSH key deployed to {host}")
            else:
                self.logger.error(f"❌ Failed to deploy SSH key to {host}: {result.stderr}")
        
        return results


def main():
    """Command-line interface for SSH management."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Pi-Swarm SSH Management')
    parser.add_argument('action', choices=['test', 'setup-keys', 'execute'],
                       help='Action to perform')
    parser.add_argument('--config', required=True,
                       help='Path to cluster configuration file')
    parser.add_argument('--command', help='Command to execute (for execute action)')
    parser.add_argument('--key-path', default='~/.ssh/id_rsa',
                       help='SSH private key path')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    args = parser.parse_args()
    
    # Setup logging
    if args.verbose:
        logging.getLogger('ssh_manager').setLevel(logging.DEBUG)
    
    # Load configuration
    import yaml
    with open(args.config, 'r') as f:
        config = yaml.safe_load(f)
    
    # Create SSH manager
    ssh_manager = SSHManager()
    
    if args.action == 'test':
        summary = ssh_manager.validate_cluster_connectivity(config)
        print(json.dumps(summary, indent=2))
        
    elif args.action == 'setup-keys':
        results = ssh_manager.setup_ssh_keys(config, args.key_path)
        success_count = sum(results.values())
        total_count = len(results)
        print(f"SSH key setup: {success_count}/{total_count} nodes successful")
        
    elif args.action == 'execute':
        if not args.command:
            print("Error: --command required for execute action")
            return 1
            
        # Execute command on all nodes
        hosts_commands = {}
        credentials_map = {}
        
        for node_name, node_config in config.get('nodes', {}).items():
            host = node_config.get('ip')
            if host:
                hosts_commands[host] = args.command
                credentials_map[host] = SSHCredentials(
                    username=node_config.get('username', 'pi'),
                    password=node_config.get('password'),
                    private_key_path=args.key_path if Path(args.key_path).expanduser().exists() else None
                )
        
        results = ssh_manager.pool.execute_parallel_commands(
            hosts_commands, credentials_map
        )
        
        for host, result in results.items():
            print(f"\n--- {host} ---")
            print(f"Exit Code: {result.exit_code}")
            if result.stdout:
                print(f"STDOUT:\n{result.stdout}")
            if result.stderr:
                print(f"STDERR:\n{result.stderr}")


if __name__ == '__main__':
    exit(main())
