#!/usr/bin/env python3
"""
Enhanced Security Manager for Pi-Swarm
Provides comprehensive security management, SSL automation, and security hardening.
"""

import argparse
import json
import logging
import sys
import subprocess
import ssl
import socket
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import concurrent.futures
from dataclasses import dataclass
import yaml
try:
    import OpenSSL
    OPENSSL_AVAILABLE = True
except ImportError:
    OPENSSL_AVAILABLE = False
    print("Warning: OpenSSL not available. Some SSL features will be limited.")
import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

# Enhanced logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class SSLCertificate:
    """SSL certificate information"""
    domain: str
    issuer: str
    subject: str
    valid_from: datetime
    valid_until: datetime
    algorithm: str
    key_size: int
    is_expired: bool
    days_until_expiry: int

@dataclass
class SecurityAuditResult:
    """Security audit result"""
    node_ip: str
    hostname: str
    score: int
    max_score: int
    issues: List[str]
    recommendations: List[str]
    checks_passed: List[str]

class SecurityManager:
    """Enhanced security management for Pi-Swarm"""
    
    def __init__(self, nodes: List[str], ssh_user: str = "pi", ssh_pass: str = "", 
                 cert_dir: str = "/etc/ssl/piswarm"):
        self.nodes = nodes
        self.ssh_user = ssh_user
        self.ssh_pass = ssh_pass
        self.cert_dir = Path(cert_dir)
        
        # Security hardening checks
        self.security_checks = {
            'ssh_key_auth': {'weight': 10, 'description': 'SSH key-based authentication'},
            'ssh_root_disabled': {'weight': 15, 'description': 'SSH root login disabled'},
            'firewall_enabled': {'weight': 20, 'description': 'Firewall enabled and configured'},
            'fail2ban_installed': {'weight': 10, 'description': 'Fail2ban installed and active'},
            'unattended_upgrades': {'weight': 10, 'description': 'Automatic security updates enabled'},
            'docker_rootless': {'weight': 15, 'description': 'Docker running in rootless mode'},
            'ssl_certificates': {'weight': 10, 'description': 'SSL certificates properly configured'},
            'port_security': {'weight': 10, 'description': 'Unnecessary ports closed'}
        }
    
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
    
    def generate_self_signed_certificate(self, domain: str, 
                                       alt_names: Optional[List[str]] = None) -> Tuple[str, str]:
        """Generate self-signed SSL certificate"""
        if not alt_names:
            alt_names = []
        
        try:
            # Generate private key
            private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=4096,
            )
            
            # Create certificate
            subject = issuer = x509.Name([
                x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
                x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "CA"),
                x509.NameAttribute(NameOID.LOCALITY_NAME, "San Francisco"),
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Pi-Swarm"),
                x509.NameAttribute(NameOID.COMMON_NAME, domain),
            ])
            
            # Build certificate
            cert_builder = x509.CertificateBuilder()
            cert_builder = cert_builder.subject_name(subject)
            cert_builder = cert_builder.issuer_name(issuer)
            cert_builder = cert_builder.public_key(private_key.public_key())
            cert_builder = cert_builder.serial_number(x509.random_serial_number())
            cert_builder = cert_builder.not_valid_before(datetime.utcnow())
            cert_builder = cert_builder.not_valid_after(datetime.utcnow() + timedelta(days=365))
            
            # Add Subject Alternative Names
            san_list = [domain] + alt_names
            cert_builder = cert_builder.add_extension(
                x509.SubjectAlternativeName([
                    x509.DNSName(name) for name in san_list
                ]),
                critical=False,
            )
            
            # Sign certificate
            certificate = cert_builder.sign(private_key, hashes.SHA256())
            
            # Serialize certificate and key
            cert_pem = certificate.public_bytes(serialization.Encoding.PEM).decode('utf-8')
            key_pem = private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            ).decode('utf-8')
            
            return cert_pem, key_pem
            
        except Exception as e:
            logger.error(f"Failed to generate certificate using cryptography library: {e}")
            # Fallback to openssl command line tool
            return self._generate_cert_with_openssl(domain, alt_names)
    
    def _generate_cert_with_openssl(self, domain: str, alt_names: List[str]) -> Tuple[str, str]:
        """Fallback method using openssl command line tool"""
        try:
            import tempfile
            import subprocess
            
            with tempfile.TemporaryDirectory() as temp_dir:
                key_file = os.path.join(temp_dir, "key.pem")
                cert_file = os.path.join(temp_dir, "cert.pem")
                
                # Generate private key
                subprocess.run([
                    "openssl", "genrsa", "-out", key_file, "4096"
                ], check=True, capture_output=True)
                
                # Create certificate signing request
                csr_file = os.path.join(temp_dir, "csr.pem")
                subprocess.run([
                    "openssl", "req", "-new", "-key", key_file, "-out", csr_file,
                    "-subj", f"/C=US/ST=CA/L=San Francisco/O=Pi-Swarm/CN={domain}"
                ], check=True, capture_output=True)
                
                # Generate self-signed certificate
                subprocess.run([
                    "openssl", "x509", "-req", "-in", csr_file, "-signkey", key_file,
                    "-out", cert_file, "-days", "365"
                ], check=True, capture_output=True)
                
                # Read certificate and key
                with open(cert_file, 'r') as f:
                    cert_pem = f.read()
                with open(key_file, 'r') as f:
                    key_pem = f.read()
                
                return cert_pem, key_pem
                
        except Exception as e:
            logger.error(f"Failed to generate certificate using openssl: {e}")
            return "", ""
    
    def deploy_ssl_certificate(self, node_ip: str, domain: str, 
                              cert_content: str, key_content: str) -> bool:
        """Deploy SSL certificate to a node"""
        try:
            # Create certificate directory
            mkdir_cmd = f"sudo mkdir -p /etc/ssl/piswarm"
            stdout, stderr, ret = self._ssh_exec(node_ip, mkdir_cmd)
            if ret != 0:
                logger.error(f"Failed to create cert directory on {node_ip}: {stderr}")
                return False
            
            # Write certificate file
            cert_cmd = f"echo '{cert_content}' | sudo tee /etc/ssl/piswarm/{domain}.crt > /dev/null"
            stdout, stderr, ret = self._ssh_exec(node_ip, cert_cmd)
            if ret != 0:
                logger.error(f"Failed to write certificate on {node_ip}: {stderr}")
                return False
            
            # Write key file
            key_cmd = f"echo '{key_content}' | sudo tee /etc/ssl/piswarm/{domain}.key > /dev/null"
            stdout, stderr, ret = self._ssh_exec(node_ip, key_cmd)
            if ret != 0:
                logger.error(f"Failed to write private key on {node_ip}: {stderr}")
                return False
            
            # Set proper permissions
            chmod_cmd = "sudo chmod 600 /etc/ssl/piswarm/*.key && sudo chmod 644 /etc/ssl/piswarm/*.crt"
            stdout, stderr, ret = self._ssh_exec(node_ip, chmod_cmd)
            if ret != 0:
                logger.warning(f"Failed to set permissions on {node_ip}: {stderr}")
            
            logger.info(f"SSL certificate deployed to {node_ip} for domain {domain}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to deploy certificate to {node_ip}: {e}")
            return False
    
    def setup_letsencrypt(self, domain: str, email: str, 
                         webroot_path: str = "/var/www/html") -> bool:
        """Setup Let's Encrypt SSL certificate"""
        manager_node = self.nodes[0]  # Use first node as manager
        
        # Install certbot
        install_cmd = "sudo apt-get update && sudo apt-get install -y certbot"
        stdout, stderr, ret = self._ssh_exec(manager_node, install_cmd, timeout=120)
        if ret != 0:
            logger.error(f"Failed to install certbot: {stderr}")
            return False
        
        # Request certificate
        certbot_cmd = (
            f"sudo certbot certonly --webroot --webroot-path {webroot_path} "
            f"--email {email} --agree-tos --non-interactive -d {domain}"
        )
        stdout, stderr, ret = self._ssh_exec(manager_node, certbot_cmd, timeout=180)
        if ret != 0:
            logger.error(f"Failed to obtain Let's Encrypt certificate: {stderr}")
            return False
        
        # Create symbolic links for consistent path
        link_cmds = [
            f"sudo mkdir -p /etc/ssl/piswarm",
            f"sudo ln -sf /etc/letsencrypt/live/{domain}/fullchain.pem /etc/ssl/piswarm/{domain}.crt",
            f"sudo ln -sf /etc/letsencrypt/live/{domain}/privkey.pem /etc/ssl/piswarm/{domain}.key"
        ]
        
        for cmd in link_cmds:
            stdout, stderr, ret = self._ssh_exec(manager_node, cmd)
            if ret != 0:
                logger.warning(f"Link creation failed: {cmd} - {stderr}")
        
        # Setup auto-renewal
        cron_cmd = (
            "echo '0 2 * * * root certbot renew --quiet' | "
            "sudo tee -a /etc/crontab > /dev/null"
        )
        stdout, stderr, ret = self._ssh_exec(manager_node, cron_cmd)
        if ret != 0:
            logger.warning(f"Failed to setup auto-renewal: {stderr}")
        
        logger.info(f"Let's Encrypt certificate setup completed for {domain}")
        return True
    
    def check_ssl_certificates(self, node_ip: str) -> List[SSLCertificate]:
        """Check SSL certificates on a node"""
        certificates = []
        
        # List certificate files
        list_cmd = "sudo find /etc/ssl/piswarm -name '*.crt' 2>/dev/null || true"
        stdout, stderr, ret = self._ssh_exec(node_ip, list_cmd)
        
        if ret == 0 and stdout:
            cert_files = stdout.strip().split('\n')
            
            for cert_file in cert_files:
                if not cert_file.strip():
                    continue
                
                # Get certificate information
                cert_info_cmd = f"sudo openssl x509 -in {cert_file} -text -noout"
                cert_stdout, cert_stderr, cert_ret = self._ssh_exec(node_ip, cert_info_cmd)
                
                if cert_ret == 0 and cert_stdout:
                    try:
                        cert_info = self._parse_certificate_info(cert_stdout)
                        if cert_info:
                            certificates.append(cert_info)
                    except Exception as e:
                        logger.warning(f"Failed to parse certificate {cert_file}: {e}")
        
        return certificates
    
    def _parse_certificate_info(self, cert_text: str) -> Optional[SSLCertificate]:
        """Parse OpenSSL certificate text output"""
        try:
            lines = cert_text.split('\n')
            cert_info = {}
            
            for line in lines:
                line = line.strip()
                if 'Subject:' in line:
                    # Extract CN from subject
                    subject_parts = line.split('Subject: ')[1] if 'Subject: ' in line else ''
                    if 'CN=' in subject_parts:
                        cn_part = [part for part in subject_parts.split(', ') if part.startswith('CN=')]
                        if cn_part:
                            cert_info['domain'] = cn_part[0].replace('CN=', '')
                elif 'Issuer:' in line:
                    cert_info['issuer'] = line.split('Issuer: ')[1] if 'Issuer: ' in line else ''
                elif 'Not Before:' in line:
                    date_str = line.split('Not Before: ')[1] if 'Not Before: ' in line else ''
                    cert_info['valid_from'] = datetime.strptime(date_str.strip(), '%b %d %H:%M:%S %Y %Z')
                elif 'Not After :' in line:
                    date_str = line.split('Not After : ')[1] if 'Not After : ' in line else ''
                    cert_info['valid_until'] = datetime.strptime(date_str.strip(), '%b %d %H:%M:%S %Y %Z')
                elif 'Public Key Algorithm:' in line:
                    cert_info['algorithm'] = line.split(': ')[1] if ': ' in line else ''
                elif 'RSA Public-Key:' in line:
                    key_size_str = line.split('(')[1].split(' ')[0] if '(' in line else '0'
                    cert_info['key_size'] = int(key_size_str)
            
            if 'domain' in cert_info and 'valid_until' in cert_info:
                now = datetime.utcnow()
                days_until_expiry = (cert_info['valid_until'] - now).days
                
                return SSLCertificate(
                    domain=cert_info.get('domain', 'unknown'),
                    issuer=cert_info.get('issuer', 'unknown'),
                    subject=cert_info.get('subject', cert_info.get('domain', 'unknown')),
                    valid_from=cert_info.get('valid_from', now),
                    valid_until=cert_info.get('valid_until', now),
                    algorithm=cert_info.get('algorithm', 'unknown'),
                    key_size=cert_info.get('key_size', 0),
                    is_expired=days_until_expiry < 0,
                    days_until_expiry=days_until_expiry
                )
        except Exception as e:
            logger.warning(f"Certificate parsing error: {e}")
        
        return None
    
    def security_audit(self, node_ip: str) -> SecurityAuditResult:
        """Perform comprehensive security audit on a node"""
        audit_result = SecurityAuditResult(
            node_ip=node_ip,
            hostname="",
            score=0,
            max_score=sum(check['weight'] for check in self.security_checks.values()),
            issues=[],
            recommendations=[],
            checks_passed=[]
        )
        
        # Get hostname
        hostname_cmd = "hostname"
        hostname, _, ret = self._ssh_exec(node_ip, hostname_cmd)
        audit_result.hostname = hostname if ret == 0 else f"node-{node_ip.split('.')[-1]}"
        
        # Check SSH configuration
        if self._check_ssh_security(node_ip):
            audit_result.score += self.security_checks['ssh_key_auth']['weight']
            audit_result.checks_passed.append("SSH key-based authentication configured")
        else:
            audit_result.issues.append("SSH password authentication still enabled")
            audit_result.recommendations.append("Configure SSH key-based authentication")
        
        # Check SSH root login
        if self._check_ssh_root_disabled(node_ip):
            audit_result.score += self.security_checks['ssh_root_disabled']['weight']
            audit_result.checks_passed.append("SSH root login disabled")
        else:
            audit_result.issues.append("SSH root login is enabled")
            audit_result.recommendations.append("Disable SSH root login")
        
        # Check firewall
        if self._check_firewall_enabled(node_ip):
            audit_result.score += self.security_checks['firewall_enabled']['weight']
            audit_result.checks_passed.append("Firewall enabled")
        else:
            audit_result.issues.append("Firewall not properly configured")
            audit_result.recommendations.append("Enable and configure UFW firewall")
        
        # Check fail2ban
        if self._check_fail2ban(node_ip):
            audit_result.score += self.security_checks['fail2ban_installed']['weight']
            audit_result.checks_passed.append("Fail2ban installed and active")
        else:
            audit_result.issues.append("Fail2ban not installed or inactive")
            audit_result.recommendations.append("Install and configure fail2ban")
        
        # Check automatic updates
        if self._check_unattended_upgrades(node_ip):
            audit_result.score += self.security_checks['unattended_upgrades']['weight']
            audit_result.checks_passed.append("Automatic security updates enabled")
        else:
            audit_result.issues.append("Automatic security updates not configured")
            audit_result.recommendations.append("Enable unattended-upgrades")
        
        # Check SSL certificates
        certificates = self.check_ssl_certificates(node_ip)
        if certificates and not any(cert.is_expired for cert in certificates):
            audit_result.score += self.security_checks['ssl_certificates']['weight']
            audit_result.checks_passed.append("SSL certificates valid")
        else:
            audit_result.issues.append("SSL certificates missing or expired")
            audit_result.recommendations.append("Install valid SSL certificates")
        
        return audit_result
    
    def _check_ssh_security(self, node_ip: str) -> bool:
        """Check SSH security configuration"""
        ssh_config_cmd = "sudo grep -E '^(PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config || true"
        stdout, stderr, ret = self._ssh_exec(node_ip, ssh_config_cmd)
        
        if ret == 0 and stdout:
            config_lines = stdout.lower()
            has_pubkey = 'pubkeyauthentication yes' in config_lines
            no_password = 'passwordauthentication no' in config_lines
            return has_pubkey or no_password
        
        return False
    
    def _check_ssh_root_disabled(self, node_ip: str) -> bool:
        """Check if SSH root login is disabled"""
        root_login_cmd = "sudo grep -E '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin yes'"
        stdout, stderr, ret = self._ssh_exec(node_ip, root_login_cmd)
        
        if ret == 0:
            return 'permitrootlogin no' in stdout.lower()
        
        return False
    
    def _check_firewall_enabled(self, node_ip: str) -> bool:
        """Check if firewall is enabled"""
        ufw_status_cmd = "sudo ufw status | grep -i active || true"
        stdout, stderr, ret = self._ssh_exec(node_ip, ufw_status_cmd)
        
        return ret == 0 and 'active' in stdout.lower()
    
    def _check_fail2ban(self, node_ip: str) -> bool:
        """Check if fail2ban is installed and active"""
        fail2ban_cmd = "systemctl is-active fail2ban 2>/dev/null || echo 'inactive'"
        stdout, stderr, ret = self._ssh_exec(node_ip, fail2ban_cmd)
        
        return ret == 0 and stdout.strip() == 'active'
    
    def _check_unattended_upgrades(self, node_ip: str) -> bool:
        """Check if unattended upgrades are enabled"""
        upgrades_cmd = "dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && echo 'installed' || echo 'not installed'"
        stdout, stderr, ret = self._ssh_exec(node_ip, upgrades_cmd)
        
        return ret == 0 and 'installed' in stdout
    
    def harden_security(self, node_ip: str, apply_changes: bool = False) -> Dict[str, Any]:
        """Apply security hardening measures"""
        hardening_results = {
            'node_ip': node_ip,
            'actions_taken': [],
            'actions_failed': [],
            'recommendations': [],
            'dry_run': not apply_changes
        }
        
        # SSH hardening
        ssh_hardening_cmds = [
            "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
            "sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config",
            "sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
            "sudo systemctl reload sshd"
        ]
        
        if apply_changes:
            for cmd in ssh_hardening_cmds:
                stdout, stderr, ret = self._ssh_exec(node_ip, cmd)
                if ret == 0:
                    hardening_results['actions_taken'].append(f"SSH hardening: {cmd}")
                else:
                    hardening_results['actions_failed'].append(f"SSH hardening failed: {stderr}")
        else:
            hardening_results['recommendations'].extend([
                "Disable SSH password authentication",
                "Disable SSH root login",
                "Enable SSH public key authentication"
            ])
        
        # Firewall setup
        firewall_cmds = [
            "sudo ufw --force reset",
            "sudo ufw default deny incoming",
            "sudo ufw default allow outgoing",
            "sudo ufw allow ssh",
            "sudo ufw allow 2376/tcp",  # Docker daemon
            "sudo ufw allow 2377/tcp",  # Docker swarm management
            "sudo ufw allow 7946",      # Docker overlay networks
            "sudo ufw allow 4789/udp",  # Docker overlay networks
            "sudo ufw --force enable"
        ]
        
        if apply_changes:
            for cmd in firewall_cmds:
                stdout, stderr, ret = self._ssh_exec(node_ip, cmd)
                if ret == 0:
                    hardening_results['actions_taken'].append(f"Firewall: {cmd}")
                else:
                    hardening_results['actions_failed'].append(f"Firewall setup failed: {stderr}")
        else:
            hardening_results['recommendations'].append("Configure UFW firewall with Docker Swarm ports")
        
        # Install security tools
        security_tools_cmd = "sudo apt-get update && sudo apt-get install -y fail2ban unattended-upgrades"
        
        if apply_changes:
            stdout, stderr, ret = self._ssh_exec(node_ip, security_tools_cmd, timeout=180)
            if ret == 0:
                hardening_results['actions_taken'].append("Installed fail2ban and unattended-upgrades")
            else:
                hardening_results['actions_failed'].append(f"Security tools installation failed: {stderr}")
        else:
            hardening_results['recommendations'].append("Install fail2ban and unattended-upgrades")
        
        return hardening_results
    
    def generate_security_report(self, output_file: Optional[str] = None) -> Dict[str, Any]:
        """Generate comprehensive security report"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'nodes': [],
            'summary': {
                'total_nodes': len(self.nodes),
                'secure_nodes': 0,
                'avg_security_score': 0,
                'critical_issues': 0,
                'expiring_certificates': 0
            },
            'overall_recommendations': []
        }
        
        def audit_node(node_ip: str) -> Dict[str, Any]:
            audit_result = self.security_audit(node_ip)
            certificates = self.check_ssl_certificates(node_ip)
            
            return {
                'audit_result': audit_result,
                'certificates': certificates
            }
        
        # Audit all nodes in parallel
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_ip = {
                executor.submit(audit_node, node_ip): node_ip 
                for node_ip in self.nodes
            }
            
            for future in concurrent.futures.as_completed(future_to_ip):
                try:
                    node_ip = future_to_ip[future]
                    result = future.result()
                    audit_result = result['audit_result']
                    certificates = result['certificates']
                    
                    # Calculate security score percentage
                    score_percentage = (audit_result.score / audit_result.max_score) * 100
                    
                    node_report = {
                        'ip': node_ip,
                        'hostname': audit_result.hostname,
                        'security_score': audit_result.score,
                        'max_score': audit_result.max_score,
                        'score_percentage': round(score_percentage, 1),
                        'issues': audit_result.issues,
                        'recommendations': audit_result.recommendations,
                        'checks_passed': audit_result.checks_passed,
                        'certificates': [
                            {
                                'domain': cert.domain,
                                'valid_until': cert.valid_until.isoformat(),
                                'days_until_expiry': cert.days_until_expiry,
                                'is_expired': cert.is_expired
                            }
                            for cert in certificates
                        ]
                    }
                    
                    report['nodes'].append(node_report)
                    
                    # Update summary
                    if score_percentage >= 80:
                        report['summary']['secure_nodes'] += 1
                    
                    report['summary']['critical_issues'] += len([
                        issue for issue in audit_result.issues 
                        if any(keyword in issue.lower() for keyword in ['root', 'password', 'firewall'])
                    ])
                    
                    report['summary']['expiring_certificates'] += len([
                        cert for cert in certificates 
                        if cert.days_until_expiry < 30 and not cert.is_expired
                    ])
                    
                except Exception as e:
                    logger.error(f"Failed to audit node {future_to_ip[future]}: {e}")
        
        # Calculate average security score
        if report['nodes']:
            total_score = sum(node['score_percentage'] for node in report['nodes'])
            report['summary']['avg_security_score'] = round(total_score / len(report['nodes']), 1)
        
        # Generate overall recommendations
        if report['summary']['critical_issues'] > 0:
            report['overall_recommendations'].append("Address critical security issues immediately")
        
        if report['summary']['expiring_certificates'] > 0:
            report['overall_recommendations'].append("Renew expiring SSL certificates")
        
        if report['summary']['secure_nodes'] < len(self.nodes):
            report['overall_recommendations'].append("Apply security hardening to all nodes")
        
        # Save report
        if output_file:
            output_path = Path(output_file)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, 'w') as f:
                json.dump(report, f, indent=2)
            logger.info(f"Security report saved to {output_path}")
        
        return report

def main():
    parser = argparse.ArgumentParser(description="Enhanced Pi-Swarm Security Manager")
    parser.add_argument("--nodes", required=True, nargs="+", help="Node IP addresses")
    parser.add_argument("--ssh-user", default="luser", help="SSH username")
    parser.add_argument("--ssh-pass", default="", help="SSH password")
    parser.add_argument("--cert-dir", default="/etc/ssl/piswarm", help="Certificate directory")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # SSL certificate generation
    cert_parser = subparsers.add_parser("generate-cert", help="Generate self-signed certificate")
    cert_parser.add_argument("--domain", required=True, help="Domain name")
    cert_parser.add_argument("--alt-names", nargs="*", help="Alternative domain names")
    cert_parser.add_argument("--deploy", action="store_true", help="Deploy to all nodes")
    
    # Let's Encrypt setup
    letsencrypt_parser = subparsers.add_parser("setup-letsencrypt", help="Setup Let's Encrypt certificate")
    letsencrypt_parser.add_argument("--domain", required=True, help="Domain name")
    letsencrypt_parser.add_argument("--email", required=True, help="Email address")
    letsencrypt_parser.add_argument("--webroot", default="/var/www/html", help="Webroot path")
    
    # Certificate checking
    subparsers.add_parser("check-certs", help="Check SSL certificates on all nodes")
    
    # Security audit
    audit_parser = subparsers.add_parser("audit", help="Perform security audit")
    audit_parser.add_argument("--node", help="Audit specific node (default: all nodes)")
    
    # Security hardening
    harden_parser = subparsers.add_parser("harden", help="Apply security hardening")
    harden_parser.add_argument("--apply", action="store_true", help="Apply changes (default: dry run)")
    harden_parser.add_argument("--node", help="Harden specific node (default: all nodes)")
    
    # Security report
    report_parser = subparsers.add_parser("report", help="Generate security report")
    report_parser.add_argument("--output", help="Output file for report")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        security = SecurityManager(
            nodes=args.nodes,
            ssh_user=args.ssh_user,
            ssh_pass=args.ssh_pass,
            cert_dir=args.cert_dir
        )
        
        if args.command == "generate-cert":
            print(f"🔐 Generating self-signed certificate for {args.domain}...")
            cert_pem, key_pem = security.generate_self_signed_certificate(
                args.domain, args.alt_names
            )
            
            if args.deploy:
                print("📦 Deploying certificate to all nodes...")
                success_count = 0
                for node_ip in args.nodes:
                    if security.deploy_ssl_certificate(node_ip, args.domain, cert_pem, key_pem):
                        success_count += 1
                print(f"✅ Certificate deployed to {success_count}/{len(args.nodes)} nodes")
            else:
                print("Certificate generated. Use --deploy to deploy to nodes.")
        
        elif args.command == "setup-letsencrypt":
            print(f"🔐 Setting up Let's Encrypt certificate for {args.domain}...")
            success = security.setup_letsencrypt(args.domain, args.email, args.webroot)
            if success:
                print("✅ Let's Encrypt certificate setup completed")
            else:
                print("❌ Let's Encrypt setup failed")
                return 1
        
        elif args.command == "check-certs":
            print("🔍 Checking SSL certificates on all nodes...")
            for node_ip in args.nodes:
                certificates = security.check_ssl_certificates(node_ip)
                print(f"\n📋 Node: {node_ip}")
                if certificates:
                    for cert in certificates:
                        status = "❌ EXPIRED" if cert.is_expired else f"✅ Valid ({cert.days_until_expiry} days left)"
                        print(f"  🔐 {cert.domain}: {status}")
                else:
                    print("  ⚠️  No SSL certificates found")
        
        elif args.command == "audit":
            nodes_to_audit = [args.node] if args.node else args.nodes
            print(f"🔍 Performing security audit on {len(nodes_to_audit)} node(s)...")
            
            for node_ip in nodes_to_audit:
                audit_result = security.security_audit(node_ip)
                score_percentage = (audit_result.score / audit_result.max_score) * 100
                
                print(f"\n🛡️  Node: {audit_result.hostname} ({node_ip})")
                print(f"Security Score: {audit_result.score}/{audit_result.max_score} ({score_percentage:.1f}%)")
                
                if audit_result.checks_passed:
                    print("✅ Passed checks:")
                    for check in audit_result.checks_passed:
                        print(f"  • {check}")
                
                if audit_result.issues:
                    print("⚠️  Issues found:")
                    for issue in audit_result.issues:
                        print(f"  • {issue}")
                
                if audit_result.recommendations:
                    print("💡 Recommendations:")
                    for rec in audit_result.recommendations:
                        print(f"  • {rec}")
        
        elif args.command == "harden":
            nodes_to_harden = [args.node] if args.node else args.nodes
            action_text = "Applying" if args.apply else "Simulating"
            print(f"🔧 {action_text} security hardening on {len(nodes_to_harden)} node(s)...")
            
            for node_ip in nodes_to_harden:
                result = security.harden_security(node_ip, args.apply)
                print(f"\n🛡️  Node: {node_ip}")
                
                if result['actions_taken']:
                    print("✅ Actions taken:")
                    for action in result['actions_taken']:
                        print(f"  • {action}")
                
                if result['actions_failed']:
                    print("❌ Actions failed:")
                    for action in result['actions_failed']:
                        print(f"  • {action}")
                
                if result['recommendations']:
                    print("💡 Recommendations:")
                    for rec in result['recommendations']:
                        print(f"  • {rec}")
        
        elif args.command == "report":
            print("📊 Generating comprehensive security report...")
            report = security.generate_security_report(args.output)
            
            print(f"\n🛡️  SECURITY REPORT SUMMARY")
            print("=" * 40)
            print(f"Total Nodes: {report['summary']['total_nodes']}")
            print(f"Secure Nodes: {report['summary']['secure_nodes']}")
            print(f"Average Security Score: {report['summary']['avg_security_score']}%")
            print(f"Critical Issues: {report['summary']['critical_issues']}")
            print(f"Expiring Certificates: {report['summary']['expiring_certificates']}")
            
            if report['overall_recommendations']:
                print("\n💡 OVERALL RECOMMENDATIONS:")
                for rec in report['overall_recommendations']:
                    print(f"  • {rec}")
            
            if args.output:
                print(f"\n📄 Detailed report saved to: {args.output}")
        
        return 0
        
    except Exception as e:
        logger.error(f"Command failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
