import sys
sys.path.insert(0, '.')

import pytest
from lib.python.network_discovery import NetworkDiscovery


def test_get_local_network_ranges_offline():
    nd = NetworkDiscovery(offline_mode=True)
    ranges = nd.get_local_network_ranges()
    assert "192.168.1.0/24" in ranges
    assert "10.0.0.0/24" in ranges


def test_ping_host_offline():
    nd = NetworkDiscovery(offline_mode=True)
    assert nd.ping_host("192.168.1.100")
    assert not nd.ping_host("192.168.1.50")


def test_ping_host_online_mock(monkeypatch):
    nd = NetworkDiscovery(offline_mode=False)

    class Result:
        def __init__(self, returncode):
            self.returncode = returncode

    def run_mock(*args, **kwargs):
        return Result(0)

    monkeypatch.setattr("subprocess.run", run_mock)
    assert nd.ping_host("127.0.0.1")

    monkeypatch.setattr("subprocess.run", lambda *a, **k: Result(1))
    assert not nd.ping_host("127.0.0.1")


def test_scan_network_range_invalid():
    nd = NetworkDiscovery(offline_mode=True)
    devices = nd.scan_network_range("invalid")
    assert devices == []


def test_scan_network_range_offline():
    nd = NetworkDiscovery(offline_mode=True)
    devices = nd.scan_network_range("192.168.1.100/30")
    ips = {d['ip'] for d in devices}
    assert {"192.168.1.101", "192.168.1.102"} <= ips

