#!/bin/bash
set -euo pipefail

# Prompt for required environment variables if not set (must be before sourcing anything)
if [[ -z "${NODES_DEFAULT_USER:-}" ]]; then
    read -r -p "Enter SSH username for Pis: " NODES_DEFAULT_USER
    export NODES_DEFAULT_USER
fi
if [[ -z "${NODES_DEFAULT_PASS:-}" ]]; then
    read -r -s -p "Enter SSH password for $NODES_DEFAULT_USER: " NODES_DEFAULT_PASS
    echo
    export NODES_DEFAULT_PASS
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swarm-cluster.sh"

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

test_count=0
pass_count=0
fail_count=0
skip_count=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    ((test_count++))
    
    echo -n "Testing $test_name... "
    if eval "$test_cmd" &>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        ((pass_count++))
    else
        echo -e "${RED}FAIL${NC}"
        ((fail_count++))
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    echo -e "Testing $test_name... ${YELLOW}SKIP${NC} ($reason)"
    ((skip_count++))
}

# Parse arguments
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
    esac
done

echo "=== Testing Dependencies ==="
for cmd in docker ssh nmap yq sshpass; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: Required command '$cmd' not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ $cmd${NC}"
done

echo -e "\n=== Testing Configuration ==="
run_test "config.yml exists" "test -f $SCRIPT_DIR/config.yml"
if [[ $DRY_RUN -eq 0 ]]; then
    run_test "config loading" "load_config"
else
    skip_test "config loading" "dry run"
fi

echo -e "\n=== Testing Network ==="
run_test "Network interface detection" "default_iface"
run_test "Network gateway detection" "default_gateway"
run_test "Network DNS detection" "default_dns"
run_test "IP validation" "validate_network_config '192.168.1.1' '255.255.255.0' '192.168.1.1'"

if [[ $DRY_RUN -eq 0 ]]; then
    echo -e "\n=== Testing Lock Mechanism ==="
    run_test "Lock acquisition" "acquire_lock"
    run_test "Lock release" "release_lock"
    
    # Test SSH if credentials available
    if [[ -n "${NODES_DEFAULT_USER:-}" ]] && [[ -n "${NODES_DEFAULT_PASS:-}" ]]; then
        echo -e "\n=== Testing SSH ==="
        for ip in "${PI_IPS[@]:-}"; do
            run_test "SSH to $ip" "sshpass -p '$NODES_DEFAULT_PASS' ssh -o StrictHostKeyChecking=no '$NODES_DEFAULT_USER@$ip' exit"
        done
    fi
else
    echo -e "\n${YELLOW}[DRY RUN]${NC} Skipping live tests (lock and SSH)"
fi

# Print summary
echo -e "\n=== Test Summary ==="
echo "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
if [[ $skip_count -gt 0 ]]; then
    echo -e "${YELLOW}Skipped: $skip_count${NC}"
fi

# Exit with failure if any tests failed
exit $((fail_count > 0))
