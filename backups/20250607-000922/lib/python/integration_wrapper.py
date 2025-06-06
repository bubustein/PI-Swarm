#!/usr/bin/env python3
"""
Pi-Swarm Python Integration Wrapper

This module provides a bridge between Bash scripts and Python modules,
allowing gradual migration from Bash to Python while maintaining
compatibility with existing deployment workflows.
"""

import sys
import os
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Any

# Add lib/python to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from ssh_manager import SSHManager, SSHCredentials
from directory_manager import DirectoryManager, DirectorySpec
from service_orchestrator import ServiceOrchestrator


class PiSwarmIntegrationWrapper:
    """Wrapper class that integrates Python modules with Bash workflows."""
    
    def __init__(self, project_root: str = None):
        self.project_root = Path(project_root) if project_root else Path(__file__).parent.parent.parent
        self.ssh_manager = None
        self.directory_manager = DirectoryManager()
        self.service_orchestrator = None
        
    def setup_ssh_manager(self, hosts: List[str], credentials: Dict[str, str]) -> bool:
        """Initialize SSH manager with connection pool."""
        try:
            creds = SSHCredentials(
                username=credentials.get('username', 'pi'),
                password=credentials.get('password'),
                private_key_path=credentials.get('private_key_path'),
                port=int(credentials.get('port', 22))
            )
            
            self.ssh_manager = SSHManager(hosts, creds)
            return True
        except Exception as e:
            print(f"Error setting up SSH manager: {e}", file=sys.stderr)
            return False
    
    def execute_ssh_commands(self, commands: List[str], hosts: List[str] = None) -> Dict[str, Any]:
        """Execute commands via SSH using Python SSH manager."""
        if not self.ssh_manager:
            return {"success": False, "error": "SSH manager not initialized"}
        
        try:
            if hosts:
                results = self.ssh_manager.execute_on_subset(commands, hosts)
            else:
                results = self.ssh_manager.execute_parallel(commands)
            
            return {"success": True, "results": results}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def setup_directories(self, directory_specs: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Setup directory structure using Python directory manager."""
        try:
            specs = []
            for spec_dict in directory_specs:
                spec = DirectorySpec(
                    path=spec_dict['path'],
                    permissions=spec_dict.get('permissions', 0o755),
                    owner=spec_dict.get('owner'),
                    group=spec_dict.get('group'),
                    description=spec_dict.get('description', ''),
                    cleanup_after_days=spec_dict.get('cleanup_after_days'),
                    required=spec_dict.get('required', True)
                )
                specs.append(spec)
            
            results = self.directory_manager.create_structure(specs)
            return {"success": True, "results": results}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def validate_directories(self, paths: List[str]) -> Dict[str, Any]:
        """Validate directory structure."""
        try:
            results = self.directory_manager.validate_structure(paths)
            return {"success": True, "results": results}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def setup_service_orchestrator(self, swarm_manager: str, credentials: Dict[str, str]) -> bool:
        """Initialize service orchestrator."""
        try:
            self.service_orchestrator = ServiceOrchestrator(
                swarm_manager=swarm_manager,
                ssh_credentials=SSHCredentials(
                    username=credentials.get('username', 'pi'),
                    password=credentials.get('password'),
                    private_key_path=credentials.get('private_key_path')
                )
            )
            return True
        except Exception as e:
            print(f"Error setting up service orchestrator: {e}", file=sys.stderr)
            return False
    
    def deploy_services(self, services: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Deploy services using Python orchestrator."""
        if not self.service_orchestrator:
            return {"success": False, "error": "Service orchestrator not initialized"}
        
        try:
            results = []
            for service_config in services:
                result = self.service_orchestrator.deploy_service(service_config)
                results.append(result)
            
            return {"success": True, "results": results}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def get_service_status(self, service_names: List[str] = None) -> Dict[str, Any]:
        """Get status of services."""
        if not self.service_orchestrator:
            return {"success": False, "error": "Service orchestrator not initialized"}
        
        try:
            if service_names:
                results = {name: self.service_orchestrator.get_service_status(name) for name in service_names}
            else:
                results = self.service_orchestrator.list_services()
            
            return {"success": True, "results": results}
        except Exception as e:
            return {"success": False, "error": str(e)}


def main():
    """CLI interface for the integration wrapper."""
    if len(sys.argv) < 2:
        print("Usage: python3 integration_wrapper.py <command> [args...]")
        print("\nCommands:")
        print("  ssh-setup <hosts_json> <credentials_json>")
        print("  ssh-execute <commands_json> [hosts_json]")
        print("  dir-setup <specs_json>")
        print("  dir-validate <paths_json>")
        print("  service-setup <manager> <credentials_json>")
        print("  service-deploy <services_json>")
        print("  service-status [names_json]")
        sys.exit(1)
    
    wrapper = PiSwarmIntegrationWrapper()
    command = sys.argv[1]
    
    try:
        if command == "ssh-setup":
            hosts = json.loads(sys.argv[2])
            credentials = json.loads(sys.argv[3])
            success = wrapper.setup_ssh_manager(hosts, credentials)
            print(json.dumps({"success": success}))
        
        elif command == "ssh-execute":
            commands = json.loads(sys.argv[2])
            hosts = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
            result = wrapper.execute_ssh_commands(commands, hosts)
            print(json.dumps(result))
        
        elif command == "dir-setup":
            specs = json.loads(sys.argv[2])
            result = wrapper.setup_directories(specs)
            print(json.dumps(result))
        
        elif command == "dir-validate":
            paths = json.loads(sys.argv[2])
            result = wrapper.validate_directories(paths)
            print(json.dumps(result))
        
        elif command == "service-setup":
            manager = sys.argv[2]
            credentials = json.loads(sys.argv[3])
            success = wrapper.setup_service_orchestrator(manager, credentials)
            print(json.dumps({"success": success}))
        
        elif command == "service-deploy":
            services = json.loads(sys.argv[2])
            result = wrapper.deploy_services(services)
            print(json.dumps(result))
        
        elif command == "service-status":
            names = json.loads(sys.argv[2]) if len(sys.argv) > 2 else None
            result = wrapper.get_service_status(names)
            print(json.dumps(result))
        
        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            sys.exit(1)
    
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
