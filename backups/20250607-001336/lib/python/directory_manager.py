#!/usr/bin/env python3
"""
Pi-Swarm Directory Management Module

This module provides Python-based directory management capabilities
for the Pi-Swarm cluster deployment system.

Features:
- Automated directory structure creation
- Permission management and validation
- Directory cleanup and maintenance
- Cross-platform compatibility
- Integration with existing Bash scripts
"""

import os
import stat
import shutil
import json
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging


@dataclass
class DirectorySpec:
    """Specification for a directory to be created."""
    path: str
    permissions: int = 0o755
    owner: Optional[str] = None
    group: Optional[str] = None
    description: str = ""
    cleanup_after_days: Optional[int] = None
    required: bool = True


@dataclass
class DirectoryStatus:
    """Status of a directory."""
    path: str
    exists: bool
    permissions: Optional[int] = None
    owner: Optional[str] = None
    group: Optional[str] = None
    size_bytes: int = 0
    file_count: int = 0
    last_modified: Optional[datetime] = None
    issues: List[str] = field(default_factory=list)


class DirectoryManager:
    """Manages directory structures for Pi-Swarm deployment."""
    
    def __init__(self, project_root: str, dry_run: bool = False):
        self.project_root = Path(project_root).resolve()
        self.dry_run = dry_run
        self.logger = self._setup_logger()
        
        # Define directory specifications
        self.directory_specs = self._get_directory_specifications()
    
    def _setup_logger(self) -> logging.Logger:
        """Setup logging for directory management."""
        logger = logging.getLogger('directory_manager')
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)
        return logger
    
    def _get_directory_specifications(self) -> List[DirectorySpec]:
        """Get the complete directory specification for Pi-Swarm."""
        return [
            # Core data directories
            DirectorySpec("data", 0o755, description="Main data directory"),
            DirectorySpec("data/logs", 0o755, description="Application logs"),
            DirectorySpec("data/backups", 0o750, description="Backup storage"),
            DirectorySpec("data/configs", 0o755, description="Configuration files"),
            DirectorySpec("data/ssl", 0o700, description="SSL certificates and keys"),
            DirectorySpec("data/ssl/certs", 0o755, description="SSL certificates"),
            DirectorySpec("data/ssl/keys", 0o700, description="SSL private keys"),
            DirectorySpec("data/ssl/ca", 0o700, description="Certificate Authority files"),
            DirectorySpec("data/monitoring", 0o755, description="Monitoring data"),
            DirectorySpec("data/monitoring/prometheus", 0o755, description="Prometheus data"),
            DirectorySpec("data/monitoring/grafana", 0o755, description="Grafana data"),
            DirectorySpec("data/monitoring/logs", 0o755, description="Monitoring logs"),
            DirectorySpec("data/storage", 0o755, description="Shared storage mount points"),
            DirectorySpec("data/storage/glusterfs", 0o755, description="GlusterFS storage"),
            DirectorySpec("data/storage/nfs", 0o755, description="NFS storage"),
            DirectorySpec("data/storage/local", 0o755, description="Local storage"),
            DirectorySpec("data/cache", 0o755, description="Application cache", cleanup_after_days=30),
            DirectorySpec("data/cluster", 0o755, description="Cluster metadata"),
            DirectorySpec("data/cluster/nodes", 0o755, description="Node information"),
            DirectorySpec("data/cluster/services", 0o755, description="Service definitions"),
            DirectorySpec("data/cluster/volumes", 0o755, description="Volume configurations"),
            DirectorySpec("data/dns", 0o755, description="DNS configuration"),
            DirectorySpec("data/dns/pihole", 0o755, description="Pi-hole configuration"),
            DirectorySpec("data/dns/configs", 0o755, description="DNS config files"),
            DirectorySpec("data/python", 0o755, description="Python module data"),
            DirectorySpec("data/python/cache", 0o755, description="Python cache", cleanup_after_days=7),
            DirectorySpec("data/python/logs", 0o755, description="Python module logs"),
            
            # Temporary directories
            DirectorySpec("temp", 0o755, description="Temporary files", cleanup_after_days=7),
            DirectorySpec("temp/downloads", 0o755, description="Downloaded files", cleanup_after_days=3),
            DirectorySpec("temp/extraction", 0o755, description="Extracted archives", cleanup_after_days=1),
            DirectorySpec("temp/scripts", 0o755, description="Temporary scripts", cleanup_after_days=7),
            DirectorySpec("temp/logs", 0o755, description="Temporary logs", cleanup_after_days=7),
            DirectorySpec("temp/python", 0o755, description="Python temp files", cleanup_after_days=1),
            DirectorySpec("temp/testing", 0o755, description="Testing artifacts", cleanup_after_days=7),
            DirectorySpec("temp/mock", 0o755, description="Mock environment files", cleanup_after_days=1),
            
            # Backup subdirectories
            DirectorySpec("data/backups/configs", 0o750, description="Configuration backups"),
            DirectorySpec("data/backups/storage", 0o750, description="Storage backups"),
            DirectorySpec("data/backups/ssl", 0o700, description="SSL backups"),
            
            # Development directories (optional)
            DirectorySpec("dev", 0o755, description="Development files", required=False),
            DirectorySpec("dev/testing", 0o755, description="Development testing", required=False),
            DirectorySpec("dev/mock-data", 0o755, description="Mock data for testing", required=False),
            DirectorySpec("dev/experiments", 0o755, description="Experimental features", required=False),
            DirectorySpec("dev/python-migration", 0o755, description="Python migration work", required=False),
            DirectorySpec("dev/benchmarks", 0o755, description="Performance benchmarks", required=False),
        ]
    
    def create_directory_structure(self, include_optional: bool = False) -> Dict[str, Any]:
        """Create the complete directory structure."""
        self.logger.info(f"Creating Pi-Swarm directory structure in {self.project_root}")
        
        results = {
            'created': [],
            'existed': [],
            'failed': [],
            'skipped': [],
            'total': 0
        }
        
        for spec in self.directory_specs:
            if not spec.required and not include_optional:
                results['skipped'].append(spec.path)
                continue
                
            results['total'] += 1
            full_path = self.project_root / spec.path
            
            try:
                if full_path.exists():
                    self.logger.debug(f"Directory exists: {spec.path}")
                    results['existed'].append(spec.path)
                else:
                    if not self.dry_run:
                        full_path.mkdir(parents=True, exist_ok=True)
                        
                        # Set permissions
                        if spec.permissions:
                            full_path.chmod(spec.permissions)
                            
                        # Create .gitkeep for empty directories
                        self._create_gitkeep(full_path, spec.description)
                        
                    self.logger.info(f"{'[DRY RUN] Would create' if self.dry_run else 'Created'}: {spec.path}")
                    results['created'].append(spec.path)
                    
            except Exception as e:
                self.logger.error(f"Failed to create {spec.path}: {e}")
                results['failed'].append(spec.path)
        
        # Generate validation script
        if not self.dry_run:
            self._generate_validation_script()
        
        self.logger.info(f"Directory creation summary:")
        self.logger.info(f"  Created: {len(results['created'])}")
        self.logger.info(f"  Existed: {len(results['existed'])}")
        self.logger.info(f"  Failed: {len(results['failed'])}")
        self.logger.info(f"  Skipped: {len(results['skipped'])}")
        
        return results
    
    def _create_gitkeep(self, directory: Path, description: str):
        """Create a .gitkeep file in the directory."""
        gitkeep_file = directory / '.gitkeep'
        if not gitkeep_file.exists():
            content = f"""# This file keeps the directory in git even when empty
# Directory: {directory.relative_to(self.project_root)}
# Purpose: {description}
# Generated: {datetime.now().isoformat()}
"""
            gitkeep_file.write_text(content)
    
    def validate_directory_structure(self) -> List[DirectoryStatus]:
        """Validate the current directory structure."""
        self.logger.info("Validating Pi-Swarm directory structure")
        
        statuses = []
        
        for spec in self.directory_specs:
            full_path = self.project_root / spec.path
            status = DirectoryStatus(path=spec.path, exists=full_path.exists())
            
            if status.exists:
                try:
                    stat_info = full_path.stat()
                    status.permissions = stat.S_IMODE(stat_info.st_mode)
                    status.last_modified = datetime.fromtimestamp(stat_info.st_mtime)
                    
                    # Check if directory is empty or has files
                    if full_path.is_dir():
                        files = list(full_path.iterdir())
                        status.file_count = len(files)
                        status.size_bytes = sum(f.stat().st_size for f in files if f.is_file())
                    
                    # Validate permissions
                    if status.permissions != spec.permissions:
                        status.issues.append(
                            f"Incorrect permissions: {oct(status.permissions)} "
                            f"(expected {oct(spec.permissions)})"
                        )
                        
                except Exception as e:
                    status.issues.append(f"Error accessing directory: {e}")
            else:
                if spec.required:
                    status.issues.append("Required directory missing")
            
            statuses.append(status)
        
        # Summary
        missing = sum(1 for s in statuses if not s.exists and any('missing' in issue for issue in s.issues))
        issues = sum(len(s.issues) for s in statuses)
        
        self.logger.info(f"Validation complete: {missing} missing directories, {issues} total issues")
        
        return statuses
    
    def cleanup_old_files(self, max_age_days: int = 7) -> Dict[str, Any]:
        """Clean up old files based on directory specifications."""
        self.logger.info(f"Cleaning up files older than {max_age_days} days")
        
        results = {
            'cleaned_files': [],
            'cleaned_dirs': [],
            'freed_bytes': 0,
            'errors': []
        }
        
        cutoff_date = datetime.now() - timedelta(days=max_age_days)
        
        for spec in self.directory_specs:
            if spec.cleanup_after_days is None:
                continue
                
            cleanup_age = spec.cleanup_after_days
            dir_cutoff = datetime.now() - timedelta(days=cleanup_age)
            
            full_path = self.project_root / spec.path
            if not full_path.exists():
                continue
            
            try:
                for item in full_path.iterdir():
                    if item.is_file():
                        mod_time = datetime.fromtimestamp(item.stat().st_mtime)
                        if mod_time < dir_cutoff:
                            file_size = item.stat().st_size
                            
                            if not self.dry_run:
                                item.unlink()
                            
                            results['cleaned_files'].append(str(item.relative_to(self.project_root)))
                            results['freed_bytes'] += file_size
                            
                            self.logger.debug(f"{'[DRY RUN] Would clean' if self.dry_run else 'Cleaned'}: {item}")
                    
                    elif item.is_dir() and item.name not in ['.gitkeep', '.git']:
                        # Clean empty directories
                        try:
                            if not self.dry_run and not any(item.iterdir()):
                                item.rmdir()
                                results['cleaned_dirs'].append(str(item.relative_to(self.project_root)))
                        except OSError:
                            pass  # Directory not empty, skip
                            
            except Exception as e:
                error_msg = f"Error cleaning {spec.path}: {e}"
                self.logger.error(error_msg)
                results['errors'].append(error_msg)
        
        freed_mb = results['freed_bytes'] / (1024 * 1024)
        self.logger.info(f"Cleanup complete: {len(results['cleaned_files'])} files, "
                        f"{len(results['cleaned_dirs'])} directories, {freed_mb:.2f} MB freed")
        
        return results
    
    def _generate_validation_script(self):
        """Generate a Python validation script."""
        script_path = self.project_root / 'scripts' / 'testing' / 'validate-directory-structure.py'
        script_path.parent.mkdir(parents=True, exist_ok=True)
        
        script_content = f'''#!/usr/bin/env python3
"""
Auto-generated directory structure validation script for Pi-Swarm
Generated: {datetime.now().isoformat()}
"""

import sys
from pathlib import Path

# Add lib/python to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib" / "python"))

from directory_manager import DirectoryManager


def main():
    """Main validation function."""
    project_root = Path(__file__).parent.parent.parent
    manager = DirectoryManager(str(project_root))
    
    print("🔍 Validating Pi-Swarm directory structure...")
    statuses = manager.validate_directory_structure()
    
    # Summary
    total = len(statuses)
    existing = sum(1 for s in statuses if s.exists)
    missing = total - existing
    issues = sum(len(s.issues) for s in statuses)
    
    print(f"\\n📊 Summary:")
    print(f"  Total directories: {{total}}")
    print(f"  Existing: {{existing}}")
    print(f"  Missing: {{missing}}")
    print(f"  Issues: {{issues}}")
    
    if issues == 0:
        print("  ✅ All directories are correctly configured!")
        return 0
    else:
        print("  ❌ Issues found:")
        for status in statuses:
            if status.issues:
                print(f"    {{status.path}}: {{', '.join(status.issues)}}")
        return 1


if __name__ == '__main__':
    exit(main())
'''
        
        script_path.write_text(script_content)
        script_path.chmod(0o755)
        self.logger.info(f"Validation script generated: {script_path}")
    
    def get_directory_summary(self) -> Dict[str, Any]:
        """Get a summary of the directory structure."""
        statuses = self.validate_directory_structure()
        
        summary = {
            'project_root': str(self.project_root),
            'timestamp': datetime.now().isoformat(),
            'total_directories': len(statuses),
            'existing_directories': sum(1 for s in statuses if s.exists),
            'missing_directories': sum(1 for s in statuses if not s.exists),
            'permission_issues': sum(1 for s in statuses if any('permission' in issue.lower() for issue in s.issues)),
            'total_issues': sum(len(s.issues) for s in statuses),
            'total_files': sum(s.file_count for s in statuses if s.exists),
            'total_size_mb': sum(s.size_bytes for s in statuses if s.exists) / (1024 * 1024),
            'directories': [
                {
                    'path': s.path,
                    'exists': s.exists,
                    'permissions': oct(s.permissions) if s.permissions else None,
                    'file_count': s.file_count,
                    'size_bytes': s.size_bytes,
                    'issues': s.issues
                }
                for s in statuses
            ]
        }
        
        return summary
    
    def export_summary(self, output_file: Optional[str] = None) -> str:
        """Export directory summary to JSON file."""
        summary = self.get_directory_summary()
        
        if output_file is None:
            output_file = str(self.project_root / 'data' / 'logs' / f'directory-summary-{datetime.now().strftime("%Y%m%d-%H%M%S")}.json')
        
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w') as f:
            json.dump(summary, f, indent=2)
        
        self.logger.info(f"Directory summary exported to: {output_path}")
        return str(output_path)


def main():
    """Command-line interface for directory management."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Pi-Swarm Directory Management')
    parser.add_argument('action', choices=['create', 'create-structure', 'validate', 'cleanup', 'summary'],
                       help='Action to perform')
    parser.add_argument('--project-root', '--base-path', default='.',
                       help='Project root directory')
    parser.add_argument('--include-optional', action='store_true',
                       help='Include optional directories')
    parser.add_argument('--validate', action='store_true',
                       help='Validate structure after creation')
    parser.add_argument('--dev-structure', action='store_true',
                       help='Include development structure')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be done without making changes')
    parser.add_argument('--max-age-days', type=int, default=7,
                       help='Maximum age for cleanup (days)')
    parser.add_argument('--output', help='Output file for summary')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    args = parser.parse_args()
    
    # Setup logging
    if args.verbose:
        logging.getLogger('directory_manager').setLevel(logging.DEBUG)
    
    # Create directory manager
    manager = DirectoryManager(args.project_root, args.dry_run)
    
    if args.action in ['create', 'create-structure']:
        results = manager.create_directory_structure(args.include_optional)
        if results['failed']:
            print(f"❌ Failed to create {len(results['failed'])} directories")
            return 1
        else:
            print(f"✅ Directory structure created successfully")
            
            # Run validation if requested
            if args.validate:
                statuses = manager.validate_directory_structure()
                issues = sum(len(s.issues) for s in statuses)
                if issues > 0:
                    print(f"⚠️  Validation found {issues} issues after creation")
                    return 1
                else:
                    print("✅ Validation passed")
            return 0
            
    elif args.action == 'validate':
        statuses = manager.validate_directory_structure()
        issues = sum(len(s.issues) for s in statuses)
        
        if issues == 0:
            print("✅ All directories are correctly configured")
            return 0
        else:
            print(f"❌ Found {issues} issues")
            for status in statuses:
                if status.issues:
                    print(f"  {status.path}: {', '.join(status.issues)}")
            return 1
            
    elif args.action == 'cleanup':
        results = manager.cleanup_old_files(args.max_age_days)
        freed_mb = results['freed_bytes'] / (1024 * 1024)
        print(f"✅ Cleaned {len(results['cleaned_files'])} files, freed {freed_mb:.2f} MB")
        
        if results['errors']:
            print(f"❌ {len(results['errors'])} errors occurred")
            for error in results['errors']:
                print(f"  {error}")
            return 1
        return 0
        
    elif args.action == 'summary':
        summary_file = manager.export_summary(args.output)
        summary = manager.get_directory_summary()
        
        print(f"📊 Directory Summary:")
        print(f"  Total directories: {summary['total_directories']}")
        print(f"  Existing: {summary['existing_directories']}")
        print(f"  Missing: {summary['missing_directories']}")
        print(f"  Total files: {summary['total_files']}")
        print(f"  Total size: {summary['total_size_mb']:.2f} MB")
        print(f"  Issues: {summary['total_issues']}")
        print(f"  Summary saved to: {summary_file}")
        
        return 0 if summary['total_issues'] == 0 else 1


if __name__ == '__main__':
    exit(main())
