#!/usr/bin/env python3
"""
Pi-Swarm Network Discovery Module

This module provides network discovery functionality for Pi-Swarm,
replacing complex Bash network scanning with Python-based discovery.

Features:
- Network range scanning
- Pi device detection
- Service discovery
- Network validation
- Offline mode support
"""

import argparse
import json
import subprocess
import sys
import socket
import ipaddress
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Optional, Tuple
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NetworkDiscovery:
    """Network discovery and validation for Pi-Swarm"""
    
    def __init__(self, offline_mode: bool = False, timeout: int = 5):
        self.offline_mode = offline_mode
        self.timeout = timeout
        self.common_pi_ports = [22, 80, 443, 5000, 8080]  # SSH, HTTP, HTTPS, etc.
        
    def get_local_network_ranges(self) -> List[str]:
        """Get local network ranges to scan"""
        ranges = []
        
        if self.offline_mode:
            # In offline mode, return common private ranges
            return ["192.168.1.0/24", "192.168.0.0/24", "10.0.0.0/24"]
        
        try:
            # Get network interfaces and their subnets
            result = subprocess.run(['ip', 'route'], capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'src' in line and '/' in line:
                        parts = line.split()
                        for part in parts:
                            if '/' in part and not part.startswith('169.254'):
                                try:
                                    network = ipaddress.ip_network(part, strict=False)
                                    if network.is_private:
                                        ranges.append(str(network))
                                except:
                                    continue
        except Exception as e:
            logger.warning(f"Failed to get network ranges: {e}")
            # Fallback to common ranges
            ranges = ["192.168.1.0/24", "192.168.0.0/24", "10.0.0.0/24"]
        
        return list(set(ranges)) if ranges else ["192.168.1.0/24"]
    
    def ping_host(self, host: str) -> bool:
        """Ping a host to check if it's alive"""
        if self.offline_mode:
            # In offline mode, simulate some responses for testing
            return host.split('.')[-1] in ['100', '101', '102', '200', '201']
        
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', str(self.timeout), host],
                capture_output=True,
                timeout=self.timeout + 2
            )
            return result.returncode == 0
        except Exception:
            return False
    
    def scan_port(self, host: str, port: int) -> bool:
        """Check if a port is open on a host"""
        if self.offline_mode:
            # Simulate port responses for testing
            if host.split('.')[-1] in ['100', '101', '102']:
                return port in [22, 80]  # Simulate SSH and HTTP
            return False
        
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(self.timeout)
                result = sock.connect_ex((host, port))
                return result == 0
        except Exception:
            return False
    
    def get_hostname(self, host: str) -> Optional[str]:
        """Get hostname for an IP address"""
        if self.offline_mode:
            # Return simulated hostnames for testing
            last_octet = host.split('.')[-1]
            if last_octet in ['100', '101', '102']:
                return f"pi-node-{last_octet}"
            return None
        
        try:
            hostname = socket.gethostbyaddr(host)[0]
            return hostname
        except Exception:
            return None
    
    def detect_pi_device(self, host: str) -> Dict:
        """Detect if a host is likely a Pi device"""
        device_info = {
            'ip': host,
            'hostname': self.get_hostname(host),
            'is_pi': False,
            'services': [],
            'os_info': None,
            'pi_score': 0
        }
        
        # Check common Pi ports
        open_ports = []
        for port in self.common_pi_ports:
            if self.scan_port(host, port):
                open_ports.append(port)
                device_info['services'].append(f"port-{port}")
        
        # SSH is common on Pi devices
        if 22 in open_ports:
            device_info['pi_score'] += 30
        
        # Check hostname patterns
        hostname = device_info['hostname']
        if hostname:
            pi_indicators = ['pi', 'raspberry', 'rpi', 'raspberrypi']
            for indicator in pi_indicators:
                if indicator.lower() in hostname.lower():
                    device_info['pi_score'] += 40
                    break
        
        # Try to get OS information via SSH (if available)
        if not self.offline_mode and 22 in open_ports:
            try:
                # This would require SSH credentials, so we'll skip for now
                # Could be enhanced to work with the SSH manager
                pass
            except Exception:
                pass
        
        # Determine if it's likely a Pi
        device_info['is_pi'] = device_info['pi_score'] >= 30
        
        return device_info
    
    def scan_network_range(self, network_range: str, max_workers: int = 20) -> List[Dict]:
        """Scan a network range for Pi devices"""
        logger.info(f"Scanning network range: {network_range}")
        
        try:
            network = ipaddress.ip_network(network_range)
        except ValueError as e:
            logger.error(f"Invalid network range {network_range}: {e}")
            return []
        
        # Limit scan to reasonable size
        if network.num_addresses > 1000:
            logger.warning(f"Network range {network_range} is large, limiting scan")
            hosts = list(network.hosts())[:254]  # Limit to /24 equivalent
        else:
            hosts = list(network.hosts())
        
        pi_devices = []
        alive_hosts = []
        
        # First, ping all hosts to find alive ones
        logger.info(f"Pinging {len(hosts)} hosts...")
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            ping_futures = {executor.submit(self.ping_host, str(host)): host for host in hosts}
            
            for future in as_completed(ping_futures):
                host = ping_futures[future]
                try:
                    if future.result():
                        alive_hosts.append(str(host))
                except Exception as e:
                    logger.debug(f"Ping failed for {host}: {e}")
        
        logger.info(f"Found {len(alive_hosts)} alive hosts")
        
        # Then scan alive hosts for Pi devices
        if alive_hosts:
            logger.info("Detecting Pi devices...")
            with ThreadPoolExecutor(max_workers=min(max_workers, len(alive_hosts))) as executor:
                scan_futures = {executor.submit(self.detect_pi_device, host): host for host in alive_hosts}
                
                for future in as_completed(scan_futures):
                    host = scan_futures[future]
                    try:
                        device_info = future.result()
                        if device_info['is_pi'] or device_info['pi_score'] > 0:
                            pi_devices.append(device_info)
                            logger.info(f"Found potential Pi device: {host} (score: {device_info['pi_score']})")
                    except Exception as e:
                        logger.debug(f"Device detection failed for {host}: {e}")
        
        return sorted(pi_devices, key=lambda x: x['pi_score'], reverse=True)
    
    def discover_pi_devices(self, custom_ranges: Optional[List[str]] = None) -> Dict:
        """Discover Pi devices on the network"""
        logger.info("Starting Pi device discovery...")
        
        if self.offline_mode:
            logger.info("Running in offline mode - using simulated discovery")
        
        # Get network ranges to scan
        if custom_ranges:
            ranges = custom_ranges
        else:
            ranges = self.get_local_network_ranges()
        
        logger.info(f"Scanning network ranges: {ranges}")
        
        all_devices = []
        for network_range in ranges:
            devices = self.scan_network_range(network_range)
            all_devices.extend(devices)
        
        # Remove duplicates based on IP
        unique_devices = {}
        for device in all_devices:
            ip = device['ip']
            if ip not in unique_devices or device['pi_score'] > unique_devices[ip]['pi_score']:
                unique_devices[ip] = device
        
        final_devices = list(unique_devices.values())
        pi_devices = [d for d in final_devices if d['is_pi']]
        
        result = {
            'pi_devices': pi_devices,
            'all_devices': final_devices,
            'discovery_time': time.time(),
            'offline_mode': self.offline_mode,
            'ranges_scanned': ranges
        }
        
        logger.info(f"Discovery complete: found {len(pi_devices)} Pi devices out of {len(final_devices)} total devices")
        
        return result
    
    def validate_network_connectivity(self, hosts: List[str]) -> Dict:
        """Validate network connectivity to specific hosts"""
        logger.info(f"Validating connectivity to {len(hosts)} hosts...")
        
        results = {}
        
        with ThreadPoolExecutor(max_workers=10) as executor:
            ping_futures = {executor.submit(self.ping_host, host): host for host in hosts}
            
            for future in as_completed(ping_futures):
                host = ping_futures[future]
                try:
                    is_reachable = future.result()
                    results[host] = {
                        'reachable': is_reachable,
                        'ssh_available': self.scan_port(host, 22) if is_reachable else False
                    }
                except Exception as e:
                    results[host] = {
                        'reachable': False,
                        'ssh_available': False,
                        'error': str(e)
                    }
        
        return results

def main():
    parser = argparse.ArgumentParser(description='Pi-Swarm Network Discovery')
    parser.add_argument('command', choices=['discover', 'validate', 'scan-range'], 
                       help='Command to execute')
    parser.add_argument('--offline', action='store_true', 
                       help='Run in offline mode (for testing)')
    parser.add_argument('--timeout', type=int, default=5, 
                       help='Network timeout in seconds')
    parser.add_argument('--ranges', nargs='+', 
                       help='Custom network ranges to scan')
    parser.add_argument('--hosts', nargs='+', 
                       help='Specific hosts to validate')
    parser.add_argument('--output', help='Output file for results')
    parser.add_argument('--format', choices=['json', 'bash'], default='json',
                       help='Output format')
    parser.add_argument('--max-workers', type=int, default=20,
                       help='Maximum number of worker threads')
    
    args = parser.parse_args()
    
    # Set up discovery
    discovery = NetworkDiscovery(offline_mode=args.offline, timeout=args.timeout)
    
    try:
        if args.command == 'discover':
            result = discovery.discover_pi_devices(args.ranges)
            
            if args.format == 'bash':
                # Output in format suitable for Bash consumption
                pi_ips = [d['ip'] for d in result['pi_devices']]
                pi_hostnames = [d['hostname'] or 'unknown' for d in result['pi_devices']]
                
                print(f"PI_IPS='{' '.join(pi_ips)}'")
                print(f"PI_HOSTNAMES='{' '.join(pi_hostnames)}'")
                print(f"PI_COUNT={len(pi_ips)}")
            else:
                print(json.dumps(result, indent=2))
        
        elif args.command == 'validate':
            if not args.hosts:
                print("Error: --hosts required for validate command", file=sys.stderr)
                sys.exit(1)
            
            result = discovery.validate_network_connectivity(args.hosts)
            print(json.dumps(result, indent=2))
        
        elif args.command == 'scan-range':
            if not args.ranges:
                print("Error: --ranges required for scan-range command", file=sys.stderr)
                sys.exit(1)
            
            all_devices = []
            for range_str in args.ranges:
                devices = discovery.scan_network_range(range_str, args.max_workers)
                all_devices.extend(devices)
            
            print(json.dumps(all_devices, indent=2))
        
        # Save output if requested
        if args.output:
            with open(args.output, 'w') as f:
                if args.command == 'discover':
                    json.dump(result, f, indent=2)
                elif args.command == 'validate':
                    json.dump(result, f, indent=2)
                elif args.command == 'scan-range':
                    json.dump(all_devices, f, indent=2)
    
    except KeyboardInterrupt:
        logger.info("Discovery interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Discovery failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
