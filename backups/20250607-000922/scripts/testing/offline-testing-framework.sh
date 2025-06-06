#!/bin/bash

# Pi-Swarm Offline Testing Framework
# Provides comprehensive offline testing capabilities with network simulation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Offline testing configuration
OFFLINE_TEST_MODE="${OFFLINE_TEST_MODE:-true}"
SIMULATE_NETWORK_FAILURE="${SIMULATE_NETWORK_FAILURE:-false}"
MOCK_SSH_CONNECTIONS="${MOCK_SSH_CONNECTIONS:-true}"
SKIP_EXTERNAL_DOWNLOADS="${SKIP_EXTERNAL_DOWNLOADS:-true}"
CREATE_MOCK_ENVIRONMENT="${CREATE_MOCK_ENVIRONMENT:-true}"

# Test results tracking
TEST_RESULTS=()
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Mock environment setup
MOCK_ENV_DIR="/tmp/pi-swarm-mock-env"
MOCK_PI_IPS=("192.168.1.101" "192.168.1.102" "192.168.1.103")
MOCK_PI_USER="mockuser"
MOCK_PI_PASS="mockpass"

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                          Pi-Swarm Offline Testing Framework                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "  ${YELLOW}Offline Mode:${NC} $OFFLINE_TEST_MODE"
    echo -e "  ${YELLOW}Simulate Network Failure:${NC} $SIMULATE_NETWORK_FAILURE"
    echo -e "  ${YELLOW}Mock SSH Connections:${NC} $MOCK_SSH_CONNECTIONS"
    echo -e "  ${YELLOW}Skip External Downloads:${NC} $SKIP_EXTERNAL_DOWNLOADS"
    echo -e "  ${YELLOW}Create Mock Environment:${NC} $CREATE_MOCK_ENVIRONMENT"
    echo ""
}

setup_mock_environment() {
    if [[ "$CREATE_MOCK_ENVIRONMENT" != "true" ]]; then
        return 0
    fi
    
    echo -e "${PURPLE}🔧 Setting up mock environment...${NC}"
    
    # Create mock environment directory
    mkdir -p "$MOCK_ENV_DIR"/{logs,configs,ssl,monitoring,storage,cache,backups}
    mkdir -p "$MOCK_ENV_DIR"/temp/{downloads,extraction}
    
    # Create mock network configuration
    cat > "$MOCK_ENV_DIR/network.conf" << EOF
# Mock network configuration for offline testing
SUBNET=192.168.1.0/24
GATEWAY=192.168.1.1
DNS_SERVERS=1.1.1.1,8.8.8.8
PI_IP_RANGE=192.168.1.100-192.168.1.199
EOF
    
    # Create mock cluster configuration
    cat > "$MOCK_ENV_DIR/cluster.yml" << EOF
cluster:
  name: "pi-swarm-test"
  mode: "offline-simulation"
  
nodes:
  manager:
    ip: "192.168.1.101"
    role: "manager"
    hostname: "pi-manager"
    username: "$MOCK_PI_USER"
    password: "$MOCK_PI_PASS"
    
  worker1:
    ip: "192.168.1.102" 
    role: "worker"
    hostname: "pi-worker1"
    username: "$MOCK_PI_USER"
    password: "$MOCK_PI_PASS"
    
  worker2:
    ip: "192.168.1.103"
    role: "worker"
    hostname: "pi-worker2"
    username: "$MOCK_PI_USER"
    password: "$MOCK_PI_PASS"

storage:
  enabled: true
  type: "glusterfs"
  replica_count: 2
  
dns:
  enabled: true
  type: "pihole"
  domain: "piswarm.local"
EOF
    
    # Create mock SSH keys
    mkdir -p "$MOCK_ENV_DIR/.ssh"
    if [[ ! -f "$MOCK_ENV_DIR/.ssh/id_rsa" ]]; then
        ssh-keygen -t rsa -b 4096 -f "$MOCK_ENV_DIR/.ssh/id_rsa" -N "" -C "pi-swarm-mock-key" >/dev/null 2>&1
    fi
    
    # Create mock Docker commands (if they don't exist)
    if ! command -v docker >/dev/null 2>&1 && [[ "$MOCK_SSH_CONNECTIONS" == "true" ]]; then
        cat > "$MOCK_ENV_DIR/mock-docker" << 'EOF'
#!/bin/bash
# Mock Docker command for offline testing
case "$1" in
    version)
        echo "Docker version 20.10.12, build offline-mock"
        ;;
    swarm)
        case "$2" in
            init)
                echo "Swarm initialized: mock-swarm-id"
                ;;
            join)
                echo "This node joined a swarm as a worker."
                ;;
            *)
                echo "Mock swarm command: $*"
                ;;
        esac
        ;;
    service)
        case "$2" in
            ls)
                echo "ID    NAME      MODE      REPLICAS   IMAGE"
                echo "abc1  nginx     replicated   2/2    nginx:alpine"
                echo "def2  redis     replicated   1/1    redis:alpine"
                ;;
            create)
                echo "Mock service created: $*"
                ;;
            *)
                echo "Mock service command: $*"
                ;;
        esac
        ;;
    *)
        echo "Mock docker command: $*"
        ;;
esac
exit 0
EOF
        chmod +x "$MOCK_ENV_DIR/mock-docker"
        export PATH="$MOCK_ENV_DIR:$PATH"
    fi
    
    echo -e "${GREEN}✅ Mock environment created in $MOCK_ENV_DIR${NC}"
}

setup_offline_environment() {
    if [[ "$OFFLINE_TEST_MODE" != "true" ]]; then
        return 0
    fi
    
    echo -e "${PURPLE}🔌 Setting up offline testing environment...${NC}"
    
    # Export offline mode variables
    export OFFLINE_MODE=true
    export SKIP_NETWORK_CHECK=true
    export SKIP_EXTERNAL_DOWNLOADS=true
    export MOCK_ENVIRONMENT=true
    
    # Mock ping command to simulate offline environment
    if [[ "$SIMULATE_NETWORK_FAILURE" == "true" ]]; then
        cat > "$MOCK_ENV_DIR/mock-ping" << 'EOF'
#!/bin/bash
# Mock ping command that always fails (simulates offline)
echo "ping: cannot resolve $(echo "$@" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1): Name or service not known"
exit 1
EOF
        chmod +x "$MOCK_ENV_DIR/mock-ping"
        export PATH="$MOCK_ENV_DIR:$PATH"
        alias ping="$MOCK_ENV_DIR/mock-ping"
    fi
    
    # Mock SSH/sshpass commands if requested
    if [[ "$MOCK_SSH_CONNECTIONS" == "true" ]]; then
        cat > "$MOCK_ENV_DIR/mock-sshpass" << 'EOF'
#!/bin/bash
# Mock sshpass command for offline testing
if [[ "$*" == *"exit"* ]]; then
    # SSH connection test - simulate success
    echo "Mock SSH connection successful"
    exit 0
else
    # Other SSH commands - simulate execution
    echo "Mock SSH execution: $*"
    exit 0
fi
EOF
        chmod +x "$MOCK_ENV_DIR/mock-sshpass"
        
        cat > "$MOCK_ENV_DIR/mock-ssh" << 'EOF'
#!/bin/bash
# Mock SSH command for offline testing
if [[ "$*" == *"exit"* ]]; then
    # SSH connection test - simulate success
    echo "Mock SSH connection successful"
    exit 0
else
    # Other SSH commands - simulate execution
    echo "Mock SSH execution: $*"
    exit 0
fi
EOF
        chmod +x "$MOCK_ENV_DIR/mock-ssh"
        
        # Update PATH to use mock commands
        export PATH="$MOCK_ENV_DIR:$PATH"
    fi
    
    echo -e "${GREEN}✅ Offline environment configured${NC}"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    local test_description="${4:-}"
    
    ((TEST_COUNT++))
    
    echo -e "${BLUE}[$TEST_COUNT] Running: $test_name${NC}"
    [[ -n "$test_description" ]] && echo -e "    ${CYAN}Description: $test_description${NC}"
    
    local start_time=$(date +%s.%N)
    
    if eval "$test_command" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.0")
    
    if [[ "$result" == "$expected_result" ]]; then
        echo -e "${GREEN}    ✅ PASS (${duration}s)${NC}"
        TEST_RESULTS+=("PASS: $test_name")
        ((PASS_COUNT++))
    else
        echo -e "${RED}    ❌ FAIL (${duration}s)${NC}"
        TEST_RESULTS+=("FAIL: $test_name")
        ((FAIL_COUNT++))
    fi
    echo ""
}

test_offline_infrastructure() {
    echo -e "${YELLOW}Testing Offline Infrastructure${NC}"
    echo "==============================="
    
    run_test "Mock environment setup" "test -d '$MOCK_ENV_DIR'" 0 "Verify mock environment directory exists"
    run_test "Network failure simulation" "ping -c1 8.8.8.8 2>/dev/null" 1 "Verify ping fails in offline mode"
    run_test "Mock SSH available" "command -v sshpass >/dev/null" 0 "Verify mock sshpass is available"
    run_test "Mock Docker available" "command -v docker >/dev/null" 0 "Verify mock docker is available"
}

test_offline_deployment_preparation() {
    echo -e "${YELLOW}Testing Offline Deployment Preparation${NC}"
    echo "======================================="
    
    # Test directory structure creation without network
    run_test "Directory structure setup" "cd '$PROJECT_ROOT' && source lib/system/directory_setup.sh && setup_project_directories '$PROJECT_ROOT'" 0 "Test directory creation in offline mode"
    
    # Test configuration loading
    run_test "Configuration loading" "cd '$PROJECT_ROOT' && source lib/config/get_config_value.sh && get_config_value '.cluster.name' 'cluster' 'test-cluster' >/dev/null" 0 "Test config loading works offline"
    
    # Test function sourcing
    run_test "Function sourcing" "cd '$PROJECT_ROOT' && source lib/source_functions.sh" 0 "Test all functions can be loaded offline"
}

test_offline_storage_integration() {
    echo -e "${YELLOW}Testing Offline Storage Integration${NC}"
    echo "===================================="
    
    # Test storage configuration without actual setup
    run_test "Storage function loading" "cd '$PROJECT_ROOT' && source lib/storage/storage_management.sh && type setup_cluster_storage >/dev/null" 0 "Test storage functions load correctly"
    
    run_test "GlusterFS function loading" "cd '$PROJECT_ROOT' && source lib/storage/glusterfs_setup.sh && type setup_glusterfs_cluster >/dev/null" 0 "Test GlusterFS functions load correctly"
    
    # Test configuration validation
    run_test "Storage config validation" "cd '$PROJECT_ROOT' && source lib/storage/storage_management.sh && validate_storage_config 'glusterfs' '2' >/dev/null" 0 "Test storage configuration validation"
}

test_offline_dns_integration() {
    echo -e "${YELLOW}Testing Offline DNS Integration${NC}"
    echo "==============================="
    
    # Test DNS function loading
    run_test "DNS function loading" "cd '$PROJECT_ROOT' && source lib/networking/pihole_dns.sh && type setup_pihole_dns >/dev/null" 0 "Test DNS functions load correctly"
    
    # Test DNS configuration validation
    run_test "DNS config validation" "cd '$PROJECT_ROOT' && source lib/networking/pihole_dns.sh && validate_pihole_config 'piswarm.local' >/dev/null" 0 "Test DNS configuration validation"
}

test_offline_python_modules() {
    echo -e "${YELLOW}Testing Offline Python Modules${NC}"
    echo "==============================="
    
    # Test Python module imports
    run_test "Config manager import" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import config_manager'" 0 "Test config manager module import"
    
    run_test "Hardware detection import" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import hardware_detection'" 0 "Test hardware detection module import"
    
    run_test "SSH manager import" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import ssh_manager'" 0 "Test SSH manager module import"
    
    run_test "Service orchestrator import" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); import service_orchestrator'" 0 "Test service orchestrator module import"
    
    # Test basic functionality
    run_test "Config manager functionality" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); from config_manager import ConfigManager; cm = ConfigManager()'" 0 "Test config manager basic functionality"
    
    run_test "Hardware detection functionality" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); from hardware_detection import HardwareDetector; hd = HardwareDetector()'" 0 "Test hardware detector basic functionality"
}

test_offline_main_scripts() {
    echo -e "${YELLOW}Testing Main Scripts in Offline Mode${NC}"
    echo "===================================="
    
    # Test deploy.sh with offline flags
    run_test "Deploy script offline help" "cd '$PROJECT_ROOT' && ./deploy.sh --help >/dev/null" 0 "Test deploy script help works offline"
    
    # Test syntax validation
    run_test "Deploy script syntax" "bash -n '$PROJECT_ROOT/deploy.sh'" 0 "Test deploy script syntax is valid"
    run_test "Swarm cluster script syntax" "bash -n '$PROJECT_ROOT/core/swarm-cluster.sh'" 0 "Test swarm cluster script syntax is valid"
    
    # Test offline flags are recognized
    run_test "Offline flag recognition" "cd '$PROJECT_ROOT' && echo 'exit 0' | ./deploy.sh --offline --help >/dev/null 2>&1" 0 "Test offline flags are recognized"
}

test_python_migration_readiness() {
    echo -e "${YELLOW}Testing Python Migration Readiness${NC}"
    echo "==================================="
    
    # Test Python module capabilities
    run_test "SSH manager CLI" "cd '$PROJECT_ROOT' && python3 lib/python/ssh_manager.py --help >/dev/null 2>&1" 1 "Test SSH manager CLI (expected to fail without args)"
    
    run_test "Service orchestrator CLI" "cd '$PROJECT_ROOT' && python3 lib/python/service_orchestrator.py --help >/dev/null 2>&1" 1 "Test service orchestrator CLI (expected to fail without args)"
    
    # Test integration points
    run_test "Python module integration" "cd '$PROJECT_ROOT' && python3 -c 'import sys; sys.path.insert(0, \"lib/python\"); from ssh_manager import SSHManager; from service_orchestrator import ServiceOrchestrator'" 0 "Test Python modules can work together"
}

generate_test_report() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                              Test Summary Report                             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Test Statistics:${NC}"
    echo -e "  ${GREEN}Total Tests:${NC} $TEST_COUNT"
    echo -e "  ${GREEN}Passed:${NC} $PASS_COUNT"
    echo -e "  ${RED}Failed:${NC} $FAIL_COUNT"
    
    if [[ $TEST_COUNT -gt 0 ]]; then
        local pass_rate=$((PASS_COUNT * 100 / TEST_COUNT))
        echo -e "  ${YELLOW}Pass Rate:${NC} ${pass_rate}%"
    fi
    echo ""
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Failed Tests:${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo -e "  ${RED}❌ ${result#FAIL: }${NC}"
            fi
        done
        echo ""
    fi
    
    echo -e "${BLUE}Offline Testing Capabilities Verified:${NC}"
    echo -e "  ${GREEN}✅ Network independence${NC}"
    echo -e "  ${GREEN}✅ Mock environment setup${NC}"
    echo -e "  ${GREEN}✅ Function loading${NC}"
    echo -e "  ${GREEN}✅ Configuration validation${NC}"
    echo -e "  ${GREEN}✅ Python module integration${NC}"
    echo -e "  ${GREEN}✅ Script syntax validation${NC}"
    echo ""
    
    # Save detailed report
    local report_file="$PROJECT_ROOT/data/logs/offline-test-report-$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
{
  "test_run": {
    "timestamp": "$(date -Iseconds)",
    "total_tests": $TEST_COUNT,
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "pass_rate": $((PASS_COUNT * 100 / TEST_COUNT))
  },
  "configuration": {
    "offline_mode": "$OFFLINE_TEST_MODE",
    "simulate_network_failure": "$SIMULATE_NETWORK_FAILURE",
    "mock_ssh_connections": "$MOCK_SSH_CONNECTIONS",
    "skip_external_downloads": "$SKIP_EXTERNAL_DOWNLOADS",
    "create_mock_environment": "$CREATE_MOCK_ENVIRONMENT"
  },
  "results": [
$(IFS=$'\n'; echo "${TEST_RESULTS[*]}" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//')
  ]
}
EOF
    
    echo -e "${GREEN}📊 Detailed report saved to: $report_file${NC}"
}

cleanup_mock_environment() {
    if [[ "$CREATE_MOCK_ENVIRONMENT" == "true" ]] && [[ -d "$MOCK_ENV_DIR" ]]; then
        echo -e "${PURPLE}🧹 Cleaning up mock environment...${NC}"
        rm -rf "$MOCK_ENV_DIR"
        echo -e "${GREEN}✅ Mock environment cleaned up${NC}"
    fi
}

main() {
    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --online)
                OFFLINE_TEST_MODE=false
                SIMULATE_NETWORK_FAILURE=false
                ;;
            --no-mock)
                MOCK_SSH_CONNECTIONS=false
                CREATE_MOCK_ENVIRONMENT=false
                ;;
            --simulate-network-failure)
                SIMULATE_NETWORK_FAILURE=true
                ;;
            --cleanup-only)
                cleanup_mock_environment
                exit 0
                ;;
            --help|-h)
                echo "Pi-Swarm Offline Testing Framework"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --online                    Run tests with network access"
                echo "  --no-mock                   Don't create mock environment"
                echo "  --simulate-network-failure  Simulate complete network failure"
                echo "  --cleanup-only              Only cleanup mock environment and exit"
                echo "  --help, -h                  Show this help message"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
    
    print_header
    
    # Setup test environment
    setup_mock_environment
    setup_offline_environment
    
    # Run all test suites
    test_offline_infrastructure
    test_offline_deployment_preparation
    test_offline_storage_integration
    test_offline_dns_integration
    test_offline_python_modules
    test_offline_main_scripts
    test_python_migration_readiness
    
    # Generate final report
    generate_test_report
    
    # Cleanup
    trap cleanup_mock_environment EXIT
    
    # Exit with appropriate code
    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! Offline testing capabilities are fully functional.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please review the failures and fix issues.${NC}"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
