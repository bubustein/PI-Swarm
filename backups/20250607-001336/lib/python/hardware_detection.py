#!/usr/bin/env python3
"""
Pi-Swarm Hardware Detection Module

This module provides Python-based hardware detection capabilities
for the Pi-Swarm cluster deployment system.

Features:
- CPU and memory detection
- Storage device enumeration
- Network interface discovery
- GPIO and hardware capability detection
- System information gathering
"""

import subprocess
import json
import sys
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class HardwareDetector:
    """Hardware detection and system information gathering."""
    
    def __init__(self):
        self.is_raspberry_pi = self._detect_raspberry_pi()
        self.system_info = {}
        
    def _detect_raspberry_pi(self) -> bool:
        """Detect if running on a Raspberry Pi."""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                cpuinfo = f.read()
                return 'raspberry pi' in cpuinfo.lower()
        except (FileNotFoundError, PermissionError):
            return False
    
    def _run_command(self, command: List[str]) -> Tuple[bool, str, str]:
        """Run a shell command and return success, stdout, stderr."""
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=30
            )
            return result.returncode == 0, result.stdout, result.stderr
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False, "", "Command not found or timed out"
    
    def get_cpu_info(self) -> Dict:
        """Get detailed CPU information."""
        cpu_info = {
            'model': 'Unknown',
            'cores': 1,
            'architecture': 'Unknown',
            'frequency': 'Unknown',
            'temperature': None
        }
        
        try:
            # Get CPU model and info
            with open('/proc/cpuinfo', 'r') as f:
                cpuinfo = f.read()
                
            # Extract model
            model_match = re.search(r'Model\s*:\s*(.+)', cpuinfo, re.IGNORECASE)
            if model_match:
                cpu_info['model'] = model_match.group(1).strip()
            else:
                # Fallback to hardware field
                hw_match = re.search(r'Hardware\s*:\s*(.+)', cpuinfo, re.IGNORECASE)
                if hw_match:
                    cpu_info['model'] = hw_match.group(1).strip()
            
            # Count cores
            cores = cpuinfo.count('processor')
            cpu_info['cores'] = cores if cores > 0 else 1
            
            # Get architecture
            success, arch_output, _ = self._run_command(['uname', '-m'])
            if success:
                cpu_info['architecture'] = arch_output.strip()
            
            # Get CPU frequency
            if os.path.exists('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'):
                try:
                    with open('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq', 'r') as f:
                        freq_khz = int(f.read().strip())
                        cpu_info['frequency'] = f"{freq_khz / 1000:.0f} MHz"
                except (ValueError, FileNotFoundError):
                    pass
            
            # Get CPU temperature (Raspberry Pi specific)
            if self.is_raspberry_pi and os.path.exists('/sys/class/thermal/thermal_zone0/temp'):
                try:
                    with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                        temp_millic = int(f.read().strip())
                        cpu_info['temperature'] = f"{temp_millic / 1000:.1f}°C"
                except (ValueError, FileNotFoundError):
                    pass
                    
        except Exception as e:
            print(f"Warning: Could not get complete CPU info: {e}", file=sys.stderr)
        
        return cpu_info
    
    def get_memory_info(self) -> Dict:
        """Get memory information."""
        memory_info = {
            'total': 0,
            'available': 0,
            'used': 0,
            'swap_total': 0,
            'swap_used': 0
        }
        
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
            
            # Parse memory information
            for line in meminfo.split('\n'):
                if line.startswith('MemTotal:'):
                    memory_info['total'] = int(line.split()[1]) * 1024  # Convert KB to bytes
                elif line.startswith('MemAvailable:'):
                    memory_info['available'] = int(line.split()[1]) * 1024
                elif line.startswith('SwapTotal:'):
                    memory_info['swap_total'] = int(line.split()[1]) * 1024
                elif line.startswith('SwapFree:'):
                    swap_free = int(line.split()[1]) * 1024
                    memory_info['swap_used'] = memory_info['swap_total'] - swap_free
            
            memory_info['used'] = memory_info['total'] - memory_info['available']
            
        except Exception as e:
            print(f"Warning: Could not get memory info: {e}", file=sys.stderr)
        
        return memory_info
    
    def get_storage_devices(self) -> List[Dict]:
        """Get information about storage devices."""
        devices = []
        
        try:
            # Use lsblk to get block device information
            success, output, _ = self._run_command([
                'lsblk', '-J', '-o', 'NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL'
            ])
            
            if success:
                data = json.loads(output)
                for device in data.get('blockdevices', []):
                    if device.get('type') == 'disk':
                        device_info = {
                            'name': device.get('name', ''),
                            'size': device.get('size', ''),
                            'model': device.get('model', ''),
                            'type': device.get('type', ''),
                            'mountpoint': device.get('mountpoint'),
                            'fstype': device.get('fstype'),
                            'partitions': []
                        }
                        
                        # Add partition information
                        for child in device.get('children', []):
                            partition_info = {
                                'name': child.get('name', ''),
                                'size': child.get('size', ''),
                                'mountpoint': child.get('mountpoint'),
                                'fstype': child.get('fstype')
                            }
                            device_info['partitions'].append(partition_info)
                        
                        devices.append(device_info)
            
        except (json.JSONDecodeError, Exception) as e:
            print(f"Warning: Could not get storage device info: {e}", file=sys.stderr)
            
            # Fallback: parse /proc/partitions
            try:
                with open('/proc/partitions', 'r') as f:
                    lines = f.readlines()[2:]  # Skip header
                
                for line in lines:
                    parts = line.strip().split()
                    if len(parts) >= 4 and not parts[3].endswith(tuple('0123456789')):
                        device_info = {
                            'name': parts[3],
                            'size': f"{int(parts[2]) * 1024} bytes",  # Convert blocks to bytes
                            'model': 'Unknown',
                            'type': 'disk',
                            'mountpoint': None,
                            'fstype': None,
                            'partitions': []
                        }
                        devices.append(device_info)
                        
            except Exception as fallback_e:
                print(f"Warning: Fallback storage detection failed: {fallback_e}", file=sys.stderr)
        
        return devices
    
    def get_network_interfaces(self) -> List[Dict]:
        """Get network interface information."""
        interfaces = []
        
        try:
            # Get interface list
            success, output, _ = self._run_command(['ip', '-j', 'link'])
            
            if success:
                data = json.loads(output)
                for interface in data:
                    interface_info = {
                        'name': interface.get('ifname', ''),
                        'type': interface.get('link_type', 'unknown'),
                        'state': interface.get('operstate', 'unknown'),
                        'mac_address': interface.get('address', ''),
                        'mtu': interface.get('mtu', 0),
                        'ip_addresses': []
                    }
                    
                    # Get IP addresses for this interface
                    success_addr, addr_output, _ = self._run_command([
                        'ip', '-j', 'addr', 'show', interface['ifname']
                    ])
                    
                    if success_addr:
                        addr_data = json.loads(addr_output)
                        for addr_interface in addr_data:
                            for addr_info in addr_interface.get('addr_info', []):
                                interface_info['ip_addresses'].append({
                                    'address': addr_info.get('local', ''),
                                    'family': addr_info.get('family', ''),
                                    'scope': addr_info.get('scope', '')
                                })
                    
                    interfaces.append(interface_info)
                    
        except (json.JSONDecodeError, Exception) as e:
            print(f"Warning: Could not get network interface info: {e}", file=sys.stderr)
            
            # Fallback: parse /proc/net/dev
            try:
                with open('/proc/net/dev', 'r') as f:
                    lines = f.readlines()[2:]  # Skip header
                
                for line in lines:
                    interface_name = line.split(':')[0].strip()
                    if interface_name != 'lo':  # Skip loopback
                        interface_info = {
                            'name': interface_name,
                            'type': 'unknown',
                            'state': 'unknown',
                            'mac_address': '',
                            'mtu': 0,
                            'ip_addresses': []
                        }
                        interfaces.append(interface_info)
                        
            except Exception as fallback_e:
                print(f"Warning: Fallback network detection failed: {fallback_e}", file=sys.stderr)
        
        return interfaces
    
    def get_system_info(self) -> Dict:
        """Get comprehensive system information."""
        system_info = {
            'hostname': 'unknown',
            'os': 'unknown',
            'kernel': 'unknown',
            'uptime': 'unknown',
            'load_average': [],
            'is_raspberry_pi': self.is_raspberry_pi
        }
        
        try:
            # Hostname
            success, output, _ = self._run_command(['hostname'])
            if success:
                system_info['hostname'] = output.strip()
            
            # OS information
            success, output, _ = self._run_command(['lsb_release', '-d'])
            if success:
                system_info['os'] = output.split('\t')[1].strip()
            
            # Kernel version
            success, output, _ = self._run_command(['uname', '-r'])
            if success:
                system_info['kernel'] = output.strip()
            
            # Uptime
            try:
                with open('/proc/uptime', 'r') as f:
                    uptime_seconds = float(f.read().split()[0])
                    hours = int(uptime_seconds // 3600)
                    minutes = int((uptime_seconds % 3600) // 60)
                    system_info['uptime'] = f"{hours}h {minutes}m"
            except (FileNotFoundError, ValueError):
                pass
            
            # Load average
            try:
                with open('/proc/loadavg', 'r') as f:
                    load_data = f.read().split()[:3]
                    system_info['load_average'] = [float(x) for x in load_data]
            except (FileNotFoundError, ValueError):
                pass
                
        except Exception as e:
            print(f"Warning: Could not get complete system info: {e}", file=sys.stderr)
        
        return system_info
    
    def detect_ssd_devices(self) -> List[Dict]:
        """Detect SSD devices suitable for storage clustering."""
        ssd_devices = []
        storage_devices = self.get_storage_devices()
        
        for device in storage_devices:
            device_name = device['name']
            device_path = f"/dev/{device_name}"
            
            try:
                # Check if device is rotational (0 = SSD, 1 = HDD)
                rotational_path = f"/sys/block/{device_name}/queue/rotational"
                if os.path.exists(rotational_path):
                    with open(rotational_path, 'r') as f:
                        is_rotational = f.read().strip() == '1'
                    
                    if not is_rotational:
                        # Additional checks for SSD characteristics
                        device_info = device.copy()
                        device_info['device_path'] = device_path
                        device_info['suitable_for_clustering'] = True
                        
                        # Check if device is mounted
                        is_mounted = any(part.get('mountpoint') for part in device.get('partitions', []))
                        device_info['is_mounted'] = is_mounted
                        
                        # Get more detailed size info
                        try:
                            success, output, _ = self._run_command(['blockdev', '--getsize64', device_path])
                            if success:
                                size_bytes = int(output.strip())
                                device_info['size_bytes'] = size_bytes
                                device_info['size_gb'] = round(size_bytes / (1024**3), 1)
                        except (ValueError, subprocess.SubprocessError):
                            pass
                        
                        ssd_devices.append(device_info)
                        
            except (FileNotFoundError, PermissionError):
                # If we can't determine rotation, include larger devices as potential SSDs
                if 'GB' in device.get('size', '') or 'TB' in device.get('size', ''):
                    device_info = device.copy()
                    device_info['device_path'] = device_path
                    device_info['suitable_for_clustering'] = False  # Uncertain
                    ssd_devices.append(device_info)
        
        return ssd_devices
    
    def get_complete_hardware_report(self) -> Dict:
        """Generate a complete hardware report."""
        return {
            'timestamp': subprocess.run(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ'], 
                                      capture_output=True, text=True).stdout.strip(),
            'system': self.get_system_info(),
            'cpu': self.get_cpu_info(),
            'memory': self.get_memory_info(),
            'storage': self.get_storage_devices(),
            'network': self.get_network_interfaces(),
            'ssd_devices': self.detect_ssd_devices()
        }


def main():
    """Command line interface for hardware detection."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Pi-Swarm Hardware Detection')
    parser.add_argument('--format', choices=['json', 'yaml', 'summary'], default='json',
                       help='Output format')
    parser.add_argument('--component', choices=['cpu', 'memory', 'storage', 'network', 'ssd', 'all'],
                       default='all', help='Component to detect')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    
    args = parser.parse_args()
    
    detector = HardwareDetector()
    
    # Get requested component data
    if args.component == 'cpu':
        data = detector.get_cpu_info()
    elif args.component == 'memory':
        data = detector.get_memory_info()
    elif args.component == 'storage':
        data = detector.get_storage_devices()
    elif args.component == 'network':
        data = detector.get_network_interfaces()
    elif args.component == 'ssd':
        data = detector.detect_ssd_devices()
    else:  # all
        data = detector.get_complete_hardware_report()
    
    # Format output
    if args.format == 'json':
        output = json.dumps(data, indent=2)
    elif args.format == 'yaml':
        try:
            import yaml
            output = yaml.dump(data, default_flow_style=False)
        except ImportError:
            print("Error: PyYAML not installed. Using JSON format.", file=sys.stderr)
            output = json.dumps(data, indent=2)
    else:  # summary
        if args.component == 'all':
            output = f"""Hardware Summary for {data['system']['hostname']}
OS: {data['system']['os']}
CPU: {data['cpu']['model']} ({data['cpu']['cores']} cores, {data['cpu']['architecture']})
Memory: {data['memory']['total'] // (1024**3)} GB total, {data['memory']['available'] // (1024**3)} GB available
Storage: {len(data['storage'])} devices detected
Network: {len(data['network'])} interfaces
SSD Devices: {len(data['ssd_devices'])} suitable for clustering
"""
        else:
            output = json.dumps(data, indent=2)
    
    # Write output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Hardware report written to {args.output}")
    else:
        print(output)


if __name__ == '__main__':
    main()
