import sys
sys.path.insert(0, '.')

import pytest
from lib.python.service_orchestrator import ServiceOrchestrator, ServiceStatus

class DummyOrchestrator(ServiceOrchestrator):
    def __init__(self):
        super().__init__(manager_host='localhost')
        self.commands = []

    def _execute_remote_command(self, command: str, timeout: int = 60):
        self.commands.append(command)
        # Simulate success for scale command
        return True, "scaled", ""

    def get_service_status(self, service_name: str = None):
        return [ServiceStatus(
            name=service_name,
            desired_replicas=1,
            running_replicas=1,
            state='running',
            image='test:latest',
            created=None,
            updated=None
        )]


def test_generate_service_templates_names():
    orch = ServiceOrchestrator('localhost')
    templates = orch.generate_service_templates()
    assert {'nginx-web', 'portainer', 'prometheus', 'grafana'} <= set(templates.keys())


def test_scale_service_success():
    orch = DummyOrchestrator()
    result = orch.scale_service('web', 3)
    assert result.success
    assert result.old_replicas == 1
    assert result.new_replicas == 3
    assert any('docker service scale web=3' in c for c in orch.commands)


def test_scale_service_not_found(monkeypatch):
    orch = ServiceOrchestrator('localhost')

    def fake_status(name=None):
        return []

    monkeypatch.setattr(orch, 'get_service_status', fake_status)
    result = orch.scale_service('missing', 2)
    assert not result.success
    assert result.message == 'Service not found'

