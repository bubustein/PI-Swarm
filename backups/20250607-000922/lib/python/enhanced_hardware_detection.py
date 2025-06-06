#!/usr/bin/env python3
"""
Enhanced Hardware Detection for Pi-Swarm
Detects system specifications, capabilities, and hardware characteristics
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from typing import Dict, List, Optional, Tuple, Any
import platform
from pathlib import Path
import re

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class HardwareDetector:
    """Comprehensive hardware detection and system profiling"""
    
    def __init__(self):
        """Initialize hardware detector"""
        self.system_info = {}
        self.detection_cache = {}
    
    def detect_system_hardware(self, host: str = 'localhost', ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect comprehensive hardware information for a system"""
        logger.info(f"🔍 Detecting hardware specifications for {host}...")
        
        # Use cached result if available
        cache_key = f"{host}:{ssh_user}"
        if cache_key in self.detection_cache:
            return self.detection_cache[cache_key]
        
        hardware_info = {
            'hostname': host,
            'detection_timestamp': time.time(),
            'cpu': self._detect_cpu_info(host, ssh_user, ssh_pass),
            'memory': self._detect_memory_info(host, ssh_user, ssh_pass),
            'storage': self._detect_storage_info(host, ssh_user, ssh_pass),
            'network': self._detect_network_info(host, ssh_user, ssh_pass),
            'platform': self._detect_platform_info(host, ssh_user, ssh_pass),
            'raspberry_pi': self._detect_raspberry_pi_info(host, ssh_user, ssh_pass),
            'docker': self._detect_docker_info(host, ssh_user, ssh_pass),
            'performance': self._assess_performance_capabilities(host, ssh_user, ssh_pass),
            'recommendations': []
        }
        
        # Generate deployment recommendations
        hardware_info['recommendations'] = self._generate_recommendations(hardware_info)
        
        # Cache the result
        self.detection_cache[cache_key] = hardware_info
        
        return hardware_info
    
    def _execute_command(self, command: str, host: str = 'localhost', ssh_user: str = None, ssh_pass: str = None) -> str:
        """Execute command locally or remotely via SSH"""
        try:
            if host == 'localhost' or not ssh_user:
                # Local execution
                result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
                return result.stdout.strip() if result.returncode == 0 else ""
            else:
                # Remote execution via SSH
                if ssh_pass:
                    # Using sshpass for password authentication
                    ssh_command = f"sshpass -p '{ssh_pass}' ssh -o StrictHostKeyChecking=no {ssh_user}@{host} '{command}'"
                else:
                    # Using key-based authentication
                    ssh_command = f"ssh -o StrictHostKeyChecking=no {ssh_user}@{host} '{command}'"
                
                result = subprocess.run(ssh_command, shell=True, capture_output=True, text=True, timeout=30)
                return result.stdout.strip() if result.returncode == 0 else ""
        except Exception as e:
            logger.warning(f"Command execution failed on {host}: {e}")
            return ""
    
    def _detect_cpu_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect CPU information"""
        cpu_info = {}
        
        try:
            # Basic CPU information
            cpu_info['model'] = self._execute_command(
                "grep '^model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs",
                host, ssh_user, ssh_pass
            )
            
            cpu_info['cores'] = int(self._execute_command("nproc", host, ssh_user, ssh_pass) or "0")
            cpu_info['architecture'] = self._execute_command("uname -m", host, ssh_user, ssh_pass)
            
            # CPU frequency information
            max_freq = self._execute_command(
                "lscpu | grep 'CPU max MHz' | awk '{print $4}' | cut -d'.' -f1",
                host, ssh_user, ssh_pass
            )
            cpu_info['max_frequency_mhz'] = int(max_freq) if max_freq.isdigit() else None
            
            # Current frequency
            current_freq = self._execute_command(
                "cat /proc/cpuinfo | grep 'cpu MHz' | head -1 | awk '{print $4}' | cut -d'.' -f1",
                host, ssh_user, ssh_pass
            )
            cpu_info['current_frequency_mhz'] = int(current_freq) if current_freq.isdigit() else None
            
            # CPU flags/features
            flags = self._execute_command(
                "grep '^flags' /proc/cpuinfo | head -1 | cut -d':' -f2",
                host, ssh_user, ssh_pass
            )
            cpu_info['features'] = flags.split() if flags else []
            
            # Performance characteristics
            cpu_info['performance_class'] = self._classify_cpu_performance(cpu_info)
            
        except Exception as e:
            logger.error(f"Error detecting CPU info: {e}")
        
        return cpu_info
    
    def _detect_memory_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect memory information"""
        memory_info = {}
        
        try:
            # Total memory
            total_kb = self._execute_command(
                "grep '^MemTotal:' /proc/meminfo | awk '{print $2}'",
                host, ssh_user, ssh_pass
            )
            memory_info['total_kb'] = int(total_kb) if total_kb.isdigit() else 0
            memory_info['total_mb'] = memory_info['total_kb'] // 1024
            memory_info['total_gb'] = round(memory_info['total_mb'] / 1024, 2)
            
            # Available memory
            available_kb = self._execute_command(
                "grep '^MemAvailable:' /proc/meminfo | awk '{print $2}'",
                host, ssh_user, ssh_pass
            )
            memory_info['available_kb'] = int(available_kb) if available_kb.isdigit() else 0
            memory_info['available_mb'] = memory_info['available_kb'] // 1024
            
            # Memory usage percentage
            if memory_info['total_kb'] > 0:
                used_kb = memory_info['total_kb'] - memory_info['available_kb']
                memory_info['used_percentage'] = round((used_kb / memory_info['total_kb']) * 100, 1)
            else:
                memory_info['used_percentage'] = 0
            
            # Swap information
            swap_total = self._execute_command(
                "grep '^SwapTotal:' /proc/meminfo | awk '{print $2}'",
                host, ssh_user, ssh_pass
            )
            memory_info['swap_total_kb'] = int(swap_total) if swap_total.isdigit() else 0
            memory_info['swap_total_mb'] = memory_info['swap_total_kb'] // 1024
            
            # Memory performance classification
            memory_info['performance_class'] = self._classify_memory_performance(memory_info)
            
        except Exception as e:
            logger.error(f"Error detecting memory info: {e}")
        
        return memory_info
    
    def _detect_storage_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect storage information"""
        storage_info = {}
        
        try:
            # Root filesystem storage
            df_output = self._execute_command("df -BG / | tail -1", host, ssh_user, ssh_pass)
            if df_output:
                parts = df_output.split()
                if len(parts) >= 4:
                    storage_info['root_total_gb'] = int(parts[1].replace('G', ''))
                    storage_info['root_used_gb'] = int(parts[2].replace('G', ''))
                    storage_info['root_available_gb'] = int(parts[3].replace('G', ''))
                    storage_info['root_used_percentage'] = round(
                        (storage_info['root_used_gb'] / storage_info['root_total_gb']) * 100, 1
                    )
            
            # Storage device types
            storage_devices = self._execute_command(
                "lsblk -d -o name,rota,type | grep -v NAME",
                host, ssh_user, ssh_pass
            )
            
            devices = []
            for line in storage_devices.split('\n'):
                if line.strip():
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        device = {
                            'name': parts[0],
                            'type': 'SSD' if parts[1] == '0' else 'HDD',
                            'device_type': parts[2]
                        }
                        devices.append(device)
            
            storage_info['devices'] = devices
            storage_info['primary_storage_type'] = devices[0]['type'] if devices else 'unknown'
            
            # Additional storage details
            storage_info['mount_points'] = self._get_mount_points(host, ssh_user, ssh_pass)
            storage_info['performance_class'] = self._classify_storage_performance(storage_info)
            
        except Exception as e:
            logger.error(f"Error detecting storage info: {e}")
        
        return storage_info
    
    def _detect_network_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect network information"""
        network_info = {}
        
        try:
            # Network interfaces
            interfaces_output = self._execute_command(
                "ip -o link show | grep -v 'lo:' | awk -F': ' '{print $2}'",
                host, ssh_user, ssh_pass
            )
            network_info['interfaces'] = [iface.strip() for iface in interfaces_output.split('\n') if iface.strip()]
            
            # Primary interface speed (if available)
            if network_info['interfaces']:
                primary_iface = network_info['interfaces'][0]
                speed = self._execute_command(
                    f"ethtool {primary_iface} 2>/dev/null | grep Speed | awk '{{print $2}}'",
                    host, ssh_user, ssh_pass
                )
                network_info['primary_interface_speed'] = speed if speed else 'unknown'
            
            # IP addresses
            ip_info = self._execute_command(
                "ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1",
                host, ssh_user, ssh_pass
            )
            network_info['ip_addresses'] = [ip.strip() for ip in ip_info.split('\n') if ip.strip()]
            
            # Network connectivity test
            network_info['internet_connectivity'] = self._test_internet_connectivity(host, ssh_user, ssh_pass)
            network_info['performance_class'] = self._classify_network_performance(network_info)
            
        except Exception as e:
            logger.error(f"Error detecting network info: {e}")
        
        return network_info
    
    def _detect_platform_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect platform and OS information"""
        platform_info = {}
        
        try:
            # OS information
            platform_info['os_name'] = self._execute_command("uname -s", host, ssh_user, ssh_pass)
            platform_info['os_release'] = self._execute_command("uname -r", host, ssh_user, ssh_pass)
            platform_info['os_version'] = self._execute_command("uname -v", host, ssh_user, ssh_pass)
            
            # Distribution information
            distro_info = self._execute_command("cat /etc/os-release 2>/dev/null", host, ssh_user, ssh_pass)
            if distro_info:
                for line in distro_info.split('\n'):
                    if line.startswith('PRETTY_NAME='):
                        platform_info['distribution'] = line.split('=', 1)[1].strip('"')
                        break
            
            # Hardware model
            model = self._execute_command("cat /proc/device-tree/model 2>/dev/null | tr -d '\\0'", host, ssh_user, ssh_pass)
            if not model:
                model = self._execute_command("cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null", host, ssh_user, ssh_pass)
            platform_info['hardware_model'] = model if model else 'unknown'
            
            # System uptime
            uptime = self._execute_command("uptime -p", host, ssh_user, ssh_pass)
            platform_info['uptime'] = uptime if uptime else 'unknown'
            
            # Kernel parameters
            platform_info['kernel_version'] = self._execute_command("uname -r", host, ssh_user, ssh_pass)
            
        except Exception as e:
            logger.error(f"Error detecting platform info: {e}")
        
        return platform_info
    
    def _detect_raspberry_pi_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect Raspberry Pi specific information"""
        pi_info = {'is_raspberry_pi': False}
        
        try:
            # Check if it's a Raspberry Pi
            model = self._execute_command("cat /proc/device-tree/model 2>/dev/null | tr -d '\\0'", host, ssh_user, ssh_pass)
            if 'Raspberry Pi' in model:
                pi_info['is_raspberry_pi'] = True
                pi_info['model'] = model
                
                # Pi-specific information
                pi_info['revision'] = self._execute_command("cat /proc/cpuinfo | grep '^Revision' | awk '{print $3}'", host, ssh_user, ssh_pass)
                pi_info['serial'] = self._execute_command("cat /proc/cpuinfo | grep '^Serial' | awk '{print $3}'", host, ssh_user, ssh_pass)
                
                # GPU memory split
                gpu_mem = self._execute_command("vcgencmd get_mem gpu 2>/dev/null", host, ssh_user, ssh_pass)
                pi_info['gpu_memory'] = gpu_mem if gpu_mem else 'unknown'
                
                # Temperature
                temp = self._execute_command("vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 | cut -d\"'\" -f1", host, ssh_user, ssh_pass)
                pi_info['temperature_celsius'] = float(temp) if temp and temp.replace('.', '').isdigit() else None
                
                # Throttling status
                throttle = self._execute_command("vcgencmd get_throttled 2>/dev/null", host, ssh_user, ssh_pass)
                pi_info['throttling_status'] = throttle if throttle else 'unknown'
                
                # Pi generation classification
                pi_info['generation'] = self._classify_pi_generation(model)
                pi_info['performance_class'] = self._classify_pi_performance(pi_info)
        
        except Exception as e:
            logger.error(f"Error detecting Raspberry Pi info: {e}")
        
        return pi_info
    
    def _detect_docker_info(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Detect Docker installation and capabilities"""
        docker_info = {'installed': False}
        
        try:
            # Check if Docker is installed
            docker_version = self._execute_command("docker --version 2>/dev/null", host, ssh_user, ssh_pass)
            if docker_version:
                docker_info['installed'] = True
                docker_info['version'] = docker_version
                
                # Docker daemon status
                docker_status = self._execute_command("systemctl is-active docker 2>/dev/null", host, ssh_user, ssh_pass)
                docker_info['daemon_active'] = docker_status == 'active'
                
                # Docker Swarm capability
                swarm_info = self._execute_command("docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null", host, ssh_user, ssh_pass)
                docker_info['swarm_status'] = swarm_info if swarm_info else 'unknown'
                
                # Available storage driver
                storage_driver = self._execute_command("docker info --format '{{.Driver}}' 2>/dev/null", host, ssh_user, ssh_pass)
                docker_info['storage_driver'] = storage_driver if storage_driver else 'unknown'
        
        except Exception as e:
            logger.error(f"Error detecting Docker info: {e}")
        
        return docker_info
    
    def _assess_performance_capabilities(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> Dict[str, Any]:
        """Assess overall system performance capabilities"""
        performance = {}
        
        try:
            # Load average
            load_avg = self._execute_command("uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'", host, ssh_user, ssh_pass)
            performance['load_average_1min'] = float(load_avg) if load_avg and load_avg.replace('.', '').isdigit() else None
            
            # Memory pressure
            memory_pressure = self._execute_command("cat /proc/pressure/memory 2>/dev/null | grep 'avg10=' | awk '{print $2}' | cut -d'=' -f2", host, ssh_user, ssh_pass)
            if memory_pressure:
                performance['memory_pressure_avg10'] = float(memory_pressure)
            
            # Disk I/O statistics
            disk_io = self._execute_command("iostat -d 1 2 2>/dev/null | tail -n +4 | tail -1", host, ssh_user, ssh_pass)
            if disk_io:
                parts = disk_io.split()
                if len(parts) >= 6:
                    performance['disk_read_kb_s'] = float(parts[2])
                    performance['disk_write_kb_s'] = float(parts[3])
            
            # Network throughput estimate
            performance['network_capability'] = self._estimate_network_throughput(host, ssh_user, ssh_pass)
            
            # Overall performance score
            performance['overall_score'] = self._calculate_performance_score(performance)
            
        except Exception as e:
            logger.error(f"Error assessing performance: {e}")
        
        return performance
    
    def _classify_cpu_performance(self, cpu_info: Dict) -> str:
        """Classify CPU performance level"""
        cores = cpu_info.get('cores', 0)
        freq = cpu_info.get('max_frequency_mhz', 0)
        
        if cores >= 8 and freq >= 2000:
            return 'high'
        elif cores >= 4 and freq >= 1000:
            return 'medium'
        else:
            return 'low'
    
    def _classify_memory_performance(self, memory_info: Dict) -> str:
        """Classify memory performance level"""
        total_gb = memory_info.get('total_gb', 0)
        
        if total_gb >= 8:
            return 'high'
        elif total_gb >= 4:
            return 'medium'
        else:
            return 'low'
    
    def _classify_storage_performance(self, storage_info: Dict) -> str:
        """Classify storage performance level"""
        storage_type = storage_info.get('primary_storage_type', 'unknown')
        total_gb = storage_info.get('root_total_gb', 0)
        
        if storage_type == 'SSD' and total_gb >= 100:
            return 'high'
        elif storage_type == 'SSD' or total_gb >= 50:
            return 'medium'
        else:
            return 'low'
    
    def _classify_network_performance(self, network_info: Dict) -> str:
        """Classify network performance level"""
        speed = network_info.get('primary_interface_speed', 'unknown')
        has_internet = network_info.get('internet_connectivity', False)
        
        if '1000' in speed or 'Gb' in speed:
            return 'high' if has_internet else 'medium'
        elif '100' in speed or 'Mb' in speed:
            return 'medium' if has_internet else 'low'
        else:
            return 'low'
    
    def _classify_pi_generation(self, model: str) -> str:
        """Classify Raspberry Pi generation"""
        if 'Pi 5' in model:
            return 'pi5'
        elif 'Pi 4' in model:
            return 'pi4'
        elif 'Pi 3' in model:
            return 'pi3'
        elif 'Pi 2' in model:
            return 'pi2'
        else:
            return 'pi1_or_older'
    
    def _classify_pi_performance(self, pi_info: Dict) -> str:
        """Classify Raspberry Pi performance level"""
        generation = pi_info.get('generation', 'unknown')
        
        if generation == 'pi5':
            return 'high'
        elif generation == 'pi4':
            return 'medium-high'
        elif generation == 'pi3':
            return 'medium'
        else:
            return 'low'
    
    def _get_mount_points(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> List[Dict]:
        """Get all mount points and their usage"""
        mount_points = []
        
        try:
            df_output = self._execute_command("df -h | grep -v tmpfs | grep -v udev", host, ssh_user, ssh_pass)
            for line in df_output.split('\n')[1:]:  # Skip header
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 6:
                        mount_point = {
                            'filesystem': parts[0],
                            'size': parts[1],
                            'used': parts[2],
                            'available': parts[3],
                            'use_percentage': parts[4],
                            'mount_point': parts[5]
                        }
                        mount_points.append(mount_point)
        except Exception as e:
            logger.error(f"Error getting mount points: {e}")
        
        return mount_points
    
    def _test_internet_connectivity(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> bool:
        """Test internet connectivity"""
        try:
            # Test connectivity to a reliable host
            result = self._execute_command("ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && echo 'connected'", host, ssh_user, ssh_pass)
            return result == 'connected'
        except:
            return False
    
    def _estimate_network_throughput(self, host: str, ssh_user: str = None, ssh_pass: str = None) -> str:
        """Estimate network throughput capability"""
        speed = self._execute_command("ethtool eth0 2>/dev/null | grep Speed | awk '{print $2}'", host, ssh_user, ssh_pass)
        if speed:
            return speed
        
        # Fallback: check interface statistics
        stats = self._execute_command("cat /proc/net/dev | grep eth0", host, ssh_user, ssh_pass)
        if stats:
            return 'variable'
        
        return 'unknown'
    
    def _calculate_performance_score(self, performance: Dict) -> int:
        """Calculate overall performance score (0-100)"""
        score = 50  # Base score
        
        # Adjust based on load average
        load_avg = performance.get('load_average_1min')
        if load_avg is not None:
            if load_avg < 1.0:
                score += 20
            elif load_avg < 2.0:
                score += 10
            elif load_avg > 4.0:
                score -= 20
        
        # Adjust based on memory pressure
        mem_pressure = performance.get('memory_pressure_avg10')
        if mem_pressure is not None:
            if mem_pressure < 10:
                score += 15
            elif mem_pressure > 50:
                score -= 25
        
        # Clamp score to 0-100 range
        return max(0, min(100, score))
    
    def _generate_recommendations(self, hardware_info: Dict) -> List[str]:
        """Generate deployment recommendations based on hardware"""
        recommendations = []
        
        # CPU recommendations
        cpu = hardware_info.get('cpu', {})
        if cpu.get('performance_class') == 'low':
            recommendations.append("Consider using lightweight containers and limiting concurrent services")
        
        # Memory recommendations
        memory = hardware_info.get('memory', {})
        if memory.get('total_gb', 0) < 2:
            recommendations.append("Low memory detected - enable swap and monitor memory usage carefully")
        elif memory.get('used_percentage', 0) > 80:
            recommendations.append("High memory usage detected - consider adding more RAM or reducing services")
        
        # Storage recommendations
        storage = hardware_info.get('storage', {})
        if storage.get('root_used_percentage', 0) > 80:
            recommendations.append("Disk space is running low - consider cleanup or adding storage")
        if storage.get('primary_storage_type') == 'HDD':
            recommendations.append("HDD storage detected - consider upgrading to SSD for better performance")
        
        # Network recommendations
        network = hardware_info.get('network', {})
        if not network.get('internet_connectivity', False):
            recommendations.append("No internet connectivity - ensure network configuration is correct")
        
        # Raspberry Pi specific recommendations
        pi_info = hardware_info.get('raspberry_pi', {})
        if pi_info.get('is_raspberry_pi', False):
            temp = pi_info.get('temperature_celsius')
            if temp and temp > 70:
                recommendations.append("High temperature detected - ensure adequate cooling")
            
            if pi_info.get('generation') in ['pi1_or_older', 'pi2']:
                recommendations.append("Older Pi model detected - consider upgrading for better Docker performance")
        
        # Docker recommendations
        docker_info = hardware_info.get('docker', {})
        if not docker_info.get('installed', False):
            recommendations.append("Docker not installed - install Docker to enable container deployment")
        elif not docker_info.get('daemon_active', False):
            recommendations.append("Docker daemon not running - start Docker service")
        
        return recommendations
    
    def export_hardware_profile(self, hardware_info: Dict, output_path: str = None) -> str:
        """Export hardware profile to JSON file"""
        if not output_path:
            hostname = hardware_info.get('hostname', 'unknown')
            timestamp = int(time.time())
            output_path = f"hardware_profile_{hostname}_{timestamp}.json"
        
        try:
            with open(output_path, 'w') as f:
                json.dump(hardware_info, f, indent=2, default=str)
            logger.info(f"✅ Hardware profile exported to: {output_path}")
            return output_path
        except Exception as e:
            logger.error(f"❌ Failed to export hardware profile: {e}")
            return ""
    
    def display_hardware_summary(self, hardware_info: Dict, detailed: bool = False):
        """Display hardware summary in a formatted way"""
        hostname = hardware_info.get('hostname', 'unknown')
        
        print(f"\n{'='*60}")
        print(f"🖥️  HARDWARE PROFILE: {hostname.upper()}")
        print(f"{'='*60}")
        
        # Platform information
        platform = hardware_info.get('platform', {})
        print(f"🔧 Platform: {platform.get('hardware_model', 'unknown')}")
        print(f"💿 OS: {platform.get('distribution', 'unknown')}")
        print(f"⏱️  Uptime: {platform.get('uptime', 'unknown')}")
        
        # Raspberry Pi specific info
        pi_info = hardware_info.get('raspberry_pi', {})
        if pi_info.get('is_raspberry_pi', False):
            print(f"🍓 Raspberry Pi: {pi_info.get('model', 'unknown')}")
            print(f"🏷️  Generation: {pi_info.get('generation', 'unknown')}")
            temp = pi_info.get('temperature_celsius')
            if temp:
                temp_status = "🔥" if temp > 70 else "🌡️ "
                print(f"{temp_status} Temperature: {temp}°C")
        
        # CPU information
        cpu = hardware_info.get('cpu', {})
        print(f"\n🖥️  CPU:")
        print(f"   Model: {cpu.get('model', 'unknown')}")
        print(f"   Cores: {cpu.get('cores', 'unknown')}")
        print(f"   Architecture: {cpu.get('architecture', 'unknown')}")
        print(f"   Performance: {cpu.get('performance_class', 'unknown')}")
        
        # Memory information
        memory = hardware_info.get('memory', {})
        print(f"\n💾 Memory:")
        print(f"   Total: {memory.get('total_gb', 'unknown')} GB")
        print(f"   Available: {memory.get('available_mb', 'unknown')} MB")
        print(f"   Usage: {memory.get('used_percentage', 'unknown')}%")
        print(f"   Performance: {memory.get('performance_class', 'unknown')}")
        
        # Storage information
        storage = hardware_info.get('storage', {})
        print(f"\n💽 Storage:")
        print(f"   Type: {storage.get('primary_storage_type', 'unknown')}")
        print(f"   Root: {storage.get('root_available_gb', 'unknown')}GB available of {storage.get('root_total_gb', 'unknown')}GB")
        print(f"   Usage: {storage.get('root_used_percentage', 'unknown')}%")
        print(f"   Performance: {storage.get('performance_class', 'unknown')}")
        
        # Network information
        network = hardware_info.get('network', {})
        print(f"\n🌐 Network:")
        print(f"   Interfaces: {', '.join(network.get('interfaces', []))}")
        print(f"   Speed: {network.get('primary_interface_speed', 'unknown')}")
        print(f"   Internet: {'✅' if network.get('internet_connectivity', False) else '❌'}")
        print(f"   Performance: {network.get('performance_class', 'unknown')}")
        
        # Docker information
        docker_info = hardware_info.get('docker', {})
        print(f"\n🐳 Docker:")
        if docker_info.get('installed', False):
            print(f"   Version: {docker_info.get('version', 'unknown')}")
            print(f"   Status: {'🟢 Active' if docker_info.get('daemon_active', False) else '🔴 Inactive'}")
            print(f"   Swarm: {docker_info.get('swarm_status', 'unknown')}")
        else:
            print(f"   Status: ❌ Not installed")
        
        # Performance assessment
        performance = hardware_info.get('performance', {})
        print(f"\n📊 Performance:")
        print(f"   Overall Score: {performance.get('overall_score', 'unknown')}/100")
        print(f"   Load Average: {performance.get('load_average_1min', 'unknown')}")
        
        # Recommendations
        recommendations = hardware_info.get('recommendations', [])
        if recommendations:
            print(f"\n💡 RECOMMENDATIONS:")
            for i, rec in enumerate(recommendations[:5], 1):
                print(f"   {i}. {rec}")
            if len(recommendations) > 5:
                print(f"   ... and {len(recommendations) - 5} more")
        
        if detailed:
            self._display_detailed_hardware_info(hardware_info)
        
        print(f"{'='*60}")
    
    def _display_detailed_hardware_info(self, hardware_info: Dict):
        """Display detailed hardware information"""
        print(f"\n📋 DETAILED INFORMATION:")
        
        # Mount points
        storage = hardware_info.get('storage', {})
        mount_points = storage.get('mount_points', [])
        if mount_points:
            print(f"\n💽 Mount Points:")
            for mp in mount_points:
                print(f"   {mp['mount_point']}: {mp['used']}/{mp['size']} ({mp['use_percentage']})")
        
        # Network interfaces details
        network = hardware_info.get('network', {})
        ip_addresses = network.get('ip_addresses', [])
        if ip_addresses:
            print(f"\n🌐 IP Addresses:")
            for ip in ip_addresses:
                print(f"   • {ip}")
        
        # CPU features
        cpu = hardware_info.get('cpu', {})
        features = cpu.get('features', [])
        if features:
            print(f"\n🖥️  CPU Features: {len(features)} features available")
            # Show first few features
            for feature in features[:10]:
                print(f"   • {feature}")
            if len(features) > 10:
                print(f"   ... and {len(features) - 10} more")

def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description='Pi-Swarm Hardware Detection')
    parser.add_argument('--host', type=str, default='localhost', help='Target host to analyze')
    parser.add_argument('--ssh-user', type=str, help='SSH username for remote hosts')
    parser.add_argument('--ssh-pass', type=str, help='SSH password for remote hosts')
    parser.add_argument('--export', type=str, help='Export hardware profile to JSON file')
    parser.add_argument('--detailed', action='store_true', help='Show detailed hardware information')
    parser.add_argument('--format', choices=['summary', 'json', 'yaml'], default='summary', help='Output format')
    
    args = parser.parse_args()
    
    try:
        detector = HardwareDetector()
        hardware_info = detector.detect_system_hardware(args.host, args.ssh_user, args.ssh_pass)
        
        if args.format == 'json':
            print(json.dumps(hardware_info, indent=2, default=str))
        elif args.format == 'yaml':
            import yaml
            print(yaml.dump(hardware_info, default_flow_style=False, indent=2))
        else:
            detector.display_hardware_summary(hardware_info, args.detailed)
        
        if args.export:
            detector.export_hardware_profile(hardware_info, args.export)
        
        return 0
        
    except KeyboardInterrupt:
        print("\n⚠️  Operation cancelled by user")
        return 1
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
