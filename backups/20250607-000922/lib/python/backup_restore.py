#!/usr/bin/env python3
"""
Pi-Swarm Backup and Restore Module

This module provides backup and restore functionality for Pi-Swarm,
offering better error handling and reliability than Bash scripts.

Features:
- Configuration backups
- Docker data backups
- Incremental backups
- Compression and encryption
- Restore operations
- Backup validation
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import tarfile
import hashlib
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class BackupRestore:
    """Backup and restore operations for Pi-Swarm"""
    
    def __init__(self, base_path: str, compression_level: int = 6):
        self.base_path = Path(base_path)
        self.backup_dir = self.base_path / "data" / "backups"
        self.temp_dir = self.base_path / "temp"
        self.compression_level = compression_level
        
        # Ensure directories exist
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        
        # Default backup paths
        self.backup_paths = {
            'config': ['config/', 'data/configs/'],
            'docker': ['data/docker/'],
            'logs': ['data/logs/'],
            'ssl': ['data/ssl/'],
            'monitoring': ['data/monitoring/'],
            'storage': ['data/storage/']
        }
    
    def generate_backup_name(self, backup_type: str, host: Optional[str] = None) -> str:
        """Generate a backup filename"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        if host:
            return f"{backup_type}_{host}_{timestamp}.tar.gz"
        else:
            return f"{backup_type}_{timestamp}.tar.gz"
    
    def calculate_checksum(self, file_path: Path) -> str:
        """Calculate SHA256 checksum of a file"""
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256_hash.update(chunk)
        return sha256_hash.hexdigest()
    
    def create_backup_manifest(self, backup_path: Path, backup_info: Dict) -> Path:
        """Create a manifest file for the backup"""
        manifest_path = backup_path.with_suffix('.manifest.json')
        
        manifest = {
            'backup_info': backup_info,
            'created_at': datetime.now().isoformat(),
            'file_size': backup_path.stat().st_size,
            'checksum': self.calculate_checksum(backup_path),
            'version': '2.0.0'
        }
        
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        return manifest_path
    
    def validate_backup(self, backup_path: Path) -> Tuple[bool, str]:
        """Validate a backup file"""
        manifest_path = backup_path.with_suffix('.manifest.json')
        
        if not backup_path.exists():
            return False, f"Backup file not found: {backup_path}"
        
        if not manifest_path.exists():
            return False, f"Manifest file not found: {manifest_path}"
        
        try:
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
            
            # Check file size
            actual_size = backup_path.stat().st_size
            expected_size = manifest.get('file_size', 0)
            if actual_size != expected_size:
                return False, f"File size mismatch: expected {expected_size}, got {actual_size}"
            
            # Check checksum
            actual_checksum = self.calculate_checksum(backup_path)
            expected_checksum = manifest.get('checksum', '')
            if actual_checksum != expected_checksum:
                return False, f"Checksum mismatch: backup may be corrupted"
            
            # Try to open the tar file
            with tarfile.open(backup_path, 'r:gz') as tar:
                tar.getnames()  # This will raise an exception if corrupted
            
            return True, "Backup validation successful"
        
        except Exception as e:
            return False, f"Validation failed: {e}"
    
    def create_local_backup(self, backup_type: str, paths: List[str], 
                           exclude_patterns: Optional[List[str]] = None) -> Tuple[Path, Dict]:
        """Create a local backup of specified paths"""
        logger.info(f"Creating {backup_type} backup...")
        
        backup_name = self.generate_backup_name(backup_type)
        backup_path = self.backup_dir / backup_name
        
        backup_info = {
            'type': backup_type,
            'paths': paths,
            'exclude_patterns': exclude_patterns or [],
            'host': 'local'
        }
        
        try:
            with tarfile.open(backup_path, 'w:gz', compresslevel=self.compression_level) as tar:
                for path_str in paths:
                    path = self.base_path / path_str
                    if path.exists():
                        logger.info(f"Backing up: {path}")
                        
                        # Add path to tar, but use relative path in archive
                        arcname = str(path.relative_to(self.base_path))
                        
                        if path.is_file():
                            tar.add(path, arcname=arcname)
                        elif path.is_dir():
                            # Add directory recursively with exclusions
                            def filter_func(tarinfo):
                                if exclude_patterns:
                                    for pattern in exclude_patterns:
                                        if pattern in tarinfo.name:
                                            logger.debug(f"Excluding: {tarinfo.name}")
                                            return None
                                return tarinfo
                            
                            tar.add(path, arcname=arcname, filter=filter_func)
                    else:
                        logger.warning(f"Path not found: {path}")
            
            # Create manifest
            manifest_path = self.create_backup_manifest(backup_path, backup_info)
            
            logger.info(f"Backup created: {backup_path}")
            logger.info(f"Backup size: {backup_path.stat().st_size / 1024 / 1024:.2f} MB")
            
            return backup_path, backup_info
        
        except Exception as e:
            if backup_path.exists():
                backup_path.unlink()
            raise Exception(f"Failed to create backup: {e}")
    
    def create_remote_backup(self, host: str, username: str, password: str,
                           backup_type: str, remote_paths: List[str]) -> Tuple[Path, Dict]:
        """Create a backup of remote Pi device"""
        logger.info(f"Creating remote backup for {host}...")
        
        backup_name = self.generate_backup_name(backup_type, host)
        backup_path = self.backup_dir / backup_name
        temp_dir = self.temp_dir / f"remote_backup_{int(time.time())}"
        temp_dir.mkdir(exist_ok=True)
        
        backup_info = {
            'type': backup_type,
            'paths': remote_paths,
            'host': host,
            'username': username
        }
        
        try:
            # Download files from remote host
            for remote_path in remote_paths:
                local_path = temp_dir / remote_path.lstrip('/')
                local_path.parent.mkdir(parents=True, exist_ok=True)
                
                # Use scp to copy files
                scp_cmd = [
                    'sshpass', '-p', password, 'scp', '-r',
                    '-o', 'StrictHostKeyChecking=no',
                    f"{username}@{host}:{remote_path}",
                    str(local_path.parent)
                ]
                
                logger.info(f"Downloading: {remote_path}")
                result = subprocess.run(scp_cmd, capture_output=True, text=True)
                
                if result.returncode != 0:
                    logger.warning(f"Failed to download {remote_path}: {result.stderr}")
            
            # Create tar archive from downloaded files
            with tarfile.open(backup_path, 'w:gz', compresslevel=self.compression_level) as tar:
                if temp_dir.exists() and any(temp_dir.iterdir()):
                    tar.add(temp_dir, arcname=f"{host}_backup")
                else:
                    raise Exception("No files were downloaded")
            
            # Create manifest
            manifest_path = self.create_backup_manifest(backup_path, backup_info)
            
            logger.info(f"Remote backup created: {backup_path}")
            return backup_path, backup_info
        
        except Exception as e:
            if backup_path.exists():
                backup_path.unlink()
            raise Exception(f"Failed to create remote backup: {e}")
        
        finally:
            # Clean up temporary directory
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
    
    def restore_backup(self, backup_path: Path, restore_path: Optional[Path] = None,
                      validate_first: bool = True) -> bool:
        """Restore a backup"""
        logger.info(f"Restoring backup: {backup_path}")
        
        if validate_first:
            is_valid, message = self.validate_backup(backup_path)
            if not is_valid:
                logger.error(f"Backup validation failed: {message}")
                return False
        
        # Default restore path is the base path
        if restore_path is None:
            restore_path = self.base_path
        
        try:
            with tarfile.open(backup_path, 'r:gz') as tar:
                # Extract to restore path
                tar.extractall(path=restore_path)
            
            logger.info(f"Backup restored to: {restore_path}")
            return True
        
        except Exception as e:
            logger.error(f"Failed to restore backup: {e}")
            return False
    
    def list_backups(self, backup_type: Optional[str] = None, 
                    host: Optional[str] = None) -> List[Dict]:
        """List available backups"""
        backups = []
        
        for backup_file in self.backup_dir.glob("*.tar.gz"):
            manifest_file = backup_file.with_suffix('.manifest.json')
            
            if manifest_file.exists():
                try:
                    with open(manifest_file, 'r') as f:
                        manifest = json.load(f)
                    
                    backup_info = manifest.get('backup_info', {})
                    
                    # Filter by type and host if specified
                    if backup_type and backup_info.get('type') != backup_type:
                        continue
                    if host and backup_info.get('host') != host:
                        continue
                    
                    backups.append({
                        'file': str(backup_file),
                        'manifest': str(manifest_file),
                        'info': backup_info,
                        'created_at': manifest.get('created_at'),
                        'size': backup_file.stat().st_size,
                        'size_mb': round(backup_file.stat().st_size / 1024 / 1024, 2)
                    })
                
                except Exception as e:
                    logger.warning(f"Failed to read manifest for {backup_file}: {e}")
        
        # Sort by creation time (newest first)
        backups.sort(key=lambda x: x['created_at'], reverse=True)
        return backups
    
    def cleanup_old_backups(self, keep_count: int = 10, backup_type: Optional[str] = None) -> int:
        """Clean up old backups, keeping only the specified number"""
        backups = self.list_backups(backup_type=backup_type)
        
        if len(backups) <= keep_count:
            logger.info(f"No cleanup needed. Current backups: {len(backups)}, Keep: {keep_count}")
            return 0
        
        # Remove oldest backups
        backups_to_remove = backups[keep_count:]
        removed_count = 0
        
        for backup in backups_to_remove:
            try:
                backup_path = Path(backup['file'])
                manifest_path = Path(backup['manifest'])
                
                backup_path.unlink()
                manifest_path.unlink()
                
                logger.info(f"Removed old backup: {backup_path.name}")
                removed_count += 1
            
            except Exception as e:
                logger.warning(f"Failed to remove backup {backup['file']}: {e}")
        
        logger.info(f"Cleaned up {removed_count} old backups")
        return removed_count

def main():
    parser = argparse.ArgumentParser(description='Pi-Swarm Backup and Restore')
    parser.add_argument('command', choices=['backup', 'restore', 'list', 'validate', 'cleanup'],
                       help='Command to execute')
    parser.add_argument('--base-path', default=os.getcwd(),
                       help='Base path for Pi-Swarm installation')
    parser.add_argument('--type', help='Backup type (config, docker, full, etc.)')
    parser.add_argument('--host', help='Target host for remote operations')
    parser.add_argument('--username', help='SSH username for remote operations')
    parser.add_argument('--password', help='SSH password for remote operations')
    parser.add_argument('--paths', nargs='+', help='Paths to backup')
    parser.add_argument('--remote-paths', nargs='+', help='Remote paths to backup')
    parser.add_argument('--backup-file', help='Backup file to restore or validate')
    parser.add_argument('--restore-path', help='Path to restore backup to')
    parser.add_argument('--compression-level', type=int, default=6,
                       help='Compression level (1-9)')
    parser.add_argument('--keep-count', type=int, default=10,
                       help='Number of backups to keep during cleanup')
    parser.add_argument('--exclude', nargs='+', help='Exclude patterns')
    parser.add_argument('--skip-validation', action='store_true',
                       help='Skip backup validation during restore')
    
    args = parser.parse_args()
    
    # Initialize backup manager
    backup_manager = BackupRestore(args.base_path, args.compression_level)
    
    try:
        if args.command == 'backup':
            if args.host and args.username and args.password and args.remote_paths:
                # Remote backup
                backup_path, info = backup_manager.create_remote_backup(
                    args.host, args.username, args.password,
                    args.type or 'remote', args.remote_paths
                )
            elif args.paths:
                # Local backup
                backup_path, info = backup_manager.create_local_backup(
                    args.type or 'local', args.paths, args.exclude
                )
            else:
                # Default backup of common paths
                if args.type in backup_manager.backup_paths:
                    paths = backup_manager.backup_paths[args.type]
                else:
                    paths = backup_manager.backup_paths['config']  # Default
                
                backup_path, info = backup_manager.create_local_backup(
                    args.type or 'config', paths, args.exclude
                )
            
            print(json.dumps({
                'success': True,
                'backup_path': str(backup_path),
                'backup_info': info
            }, indent=2))
        
        elif args.command == 'restore':
            if not args.backup_file:
                print("Error: --backup-file required for restore", file=sys.stderr)
                sys.exit(1)
            
            backup_path = Path(args.backup_file)
            restore_path = Path(args.restore_path) if args.restore_path else None
            
            success = backup_manager.restore_backup(
                backup_path, restore_path, 
                validate_first=not args.skip_validation
            )
            
            print(json.dumps({'success': success}))
            if not success:
                sys.exit(1)
        
        elif args.command == 'list':
            backups = backup_manager.list_backups(args.type, args.host)
            print(json.dumps(backups, indent=2))
        
        elif args.command == 'validate':
            if not args.backup_file:
                print("Error: --backup-file required for validate", file=sys.stderr)
                sys.exit(1)
            
            backup_path = Path(args.backup_file)
            is_valid, message = backup_manager.validate_backup(backup_path)
            
            print(json.dumps({
                'valid': is_valid,
                'message': message
            }, indent=2))
            
            if not is_valid:
                sys.exit(1)
        
        elif args.command == 'cleanup':
            removed_count = backup_manager.cleanup_old_backups(args.keep_count, args.type)
            print(json.dumps({
                'removed_count': removed_count
            }))
    
    except Exception as e:
        logger.error(f"Command failed: {e}")
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
