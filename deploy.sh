#!/bin/bash

# Pi-Swarm v2.0.0 - Main Deployment Script
# This script provides easy access to all deployment options

set -euo pipefail

# ---- Command Line Arguments ----
# Parse command line arguments for offline mode and other options
OFFLINE_MODE=false
SKIP_NETWORK_CHECK=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --offline)
            OFFLINE_MODE=true
            SKIP_NETWORK_CHECK=true
            echo "🔌 Offline mode enabled - network checks will be skipped"
            shift
            ;;
        --skip-network-check)
            SKIP_NETWORK_CHECK=true
            echo "🌐 Network connectivity checks will be skipped"
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            set -x
            echo "🔍 Verbose mode enabled"
            shift
            ;;
        --help|-h)
            echo "Pi-Swarm Deployment Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --offline              Enable offline mode (skips all network checks)"
            echo "  --skip-network-check   Skip network connectivity checks only"
            echo "  --verbose, -v          Enable verbose output"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  OFFLINE_MODE=true      Same as --offline"
            echo "  SKIP_NETWORK_CHECK=true Same as --skip-network-check"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Export environment variables for child scripts
export OFFLINE_MODE
export SKIP_NETWORK_CHECK
export VERBOSE

# ---- Directory Structure Setup ----
echo "📁 Setting up project directories..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source Python integration helper
if [[ -f "$SCRIPT_DIR/lib/python_integration.sh" ]]; then
    source "$SCRIPT_DIR/lib/python_integration.sh"
    
    # Test Python integration capabilities
    test_python_integration
    
    # Use enhanced directory setup
    if setup_directories_enhanced "$SCRIPT_DIR"; then
        echo "✅ Enhanced directory setup completed"
    else
        echo "⚠️  Directory setup completed with fallbacks"
    fi
    
    # Run comprehensive system health check before deployment
    echo "🔍 Performing comprehensive system health check..."
    if health_check_comprehensive; then
        echo "✅ System health check passed"
    else
        echo "⚠️  System health check completed with warnings"
    fi
else
    # Fallback to original logic
    if [[ -f "$SCRIPT_DIR/lib/system/directory_setup.sh" ]]; then
        source "$SCRIPT_DIR/lib/system/directory_setup.sh"
        setup_project_directories "$SCRIPT_DIR"
    else
        mkdir -p data/{logs,backups,configs,ssl,monitoring,storage,cache}
        mkdir -p temp/{downloads,extraction}
        echo "✅ Created essential directories"
    fi
fi

# ---- Prerequisites Installation ----
echo "🔧 Checking and installing prerequisites..."

# Required tools for Pi-Swarm deployment
REQUIRED_TOOLS=(sshpass ssh nmap awk sed grep tee curl docker lsb_release iproute2 sudo python3 yq net-tools)

# Check for sudo availability
SUDO=""
if [[ $EUID -ne 0 ]]; then
    if sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        echo "Note: Some operations may require sudo privileges for package installation"
        SUDO="sudo"
    fi
fi

# Check which tools are missing
missing_tools=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    case "$tool" in
        iproute2)
            # iproute2 provides the 'ip' command
            command -v ip >/dev/null 2>&1 || missing_tools+=("$tool")
            ;;
        net-tools)
            # net-tools provides the 'arp' command
            command -v arp >/dev/null 2>&1 || missing_tools+=("$tool")
            ;;
        *)
            command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
            ;;
    esac
done

# Python version check
if ! python3 -c 'import sys; assert sys.version_info.major >= 3' 2>/dev/null; then
    echo "Python 3 is required but not found or incompatible version detected."
    missing_tools+=("python3")
fi

# Install missing tools
if (( ${#missing_tools[@]} > 0 )); then
    if [[ "$OFFLINE_MODE" == "true" ]]; then
        echo "⚠️  Missing tools detected but offline mode is enabled: ${missing_tools[*]}"
        echo "Please install these tools manually or run without --offline flag"
        echo "Required tools: ${missing_tools[*]}"
        echo ""
        echo "Some tests may fail without these tools installed."
        read -p "Continue anyway? (y/N): " continue_offline
        if [[ ! "$continue_offline" =~ ^[Yy]$ ]]; then
            echo "Exiting. Install missing tools or run without --offline flag."
            exit 1
        fi
    else
        echo "Missing tools detected: ${missing_tools[*]}"
        echo "Installing prerequisites..."
        
        # First, install basic tools via apt (including curl which is needed for Docker)
        APT_TOOLS=()
        SPECIAL_TOOLS=()
        for t in "${missing_tools[@]}"; do
            case "$t" in
                docker|yq)
                    SPECIAL_TOOLS+=("$t")
                    ;;
                *)
                    APT_TOOLS+=("$t")
                    ;;
            esac
        done

        # Install apt packages first
        if (( ${#APT_TOOLS[@]} > 0 )); then
            echo "Updating package lists..."
            $SUDO apt-get update
            echo "Installing: ${APT_TOOLS[*]}"
            $SUDO apt-get install -y "${APT_TOOLS[@]}"
        fi
    fi
    
    # Then install special tools that require curl or other dependencies
    for t in "${SPECIAL_TOOLS[@]}"; do
        case "$t" in
            docker)
                echo "Installing Docker..."
                if ! curl -fsSL https://get.docker.com | $SUDO sh; then
                    echo "❌ Failed to install Docker. Please install manually."
                    exit 1
                fi
                ;;
            yq)
                echo "Installing yq..."
                # Install yq from GitHub releases
                YQ_VERSION="v4.35.2"
                if ! $SUDO wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"; then
                    echo "❌ Failed to install yq. Please install manually."
                    exit 1
                fi
                $SUDO chmod +x /usr/local/bin/yq
                ;;
        esac
    done
fi

# Final verification
echo "Verifying all prerequisites..."
failed_tools=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    case "$tool" in
        iproute2)
            command -v ip >/dev/null 2>&1 || failed_tools+=("ip (from iproute2)")
            ;;
        net-tools)
            command -v arp >/dev/null 2>&1 || failed_tools+=("arp (from net-tools)")
            ;;
        *)
            command -v "$tool" >/dev/null 2>&1 || failed_tools+=("$tool")
            ;;
    esac
done

if (( ${#failed_tools[@]} > 0 )); then
    echo "❌ Failed to install required tools: ${failed_tools[*]}"
    echo "Please install these manually and run the script again."
    exit 1
fi

# Check Docker service
if ! systemctl is-active --quiet docker 2>/dev/null; then
    echo "Starting Docker service..."
    $SUDO systemctl start docker || {
        echo "❌ Could not start Docker service. Please start it manually."
        exit 1
    }
fi

echo "✅ All prerequisites installed and verified!"
echo ""

echo "🚀 Pi-Swarm v2.0.0 - Docker Swarm Orchestration Platform"
echo "========================================================="
echo ""

# Quick storage configuration prompt
echo "💾 STORAGE CONFIGURATION"
echo "========================"
echo "Do you want to configure shared storage for your Pi cluster?"
echo "This will set up GlusterFS using your 250GB SSDs for distributed storage."
echo ""
echo "Benefits of shared storage:"
echo "• Docker volumes accessible from all nodes"
echo "• High availability for persistent data"
echo "• Automatic data replication across Pis"
echo ""
read -p "Enable shared storage? (Y/n): " ENABLE_STORAGE
ENABLE_STORAGE=${ENABLE_STORAGE,,}

if [[ "$ENABLE_STORAGE" =~ ^(y|yes|)$ ]]; then
    echo "✅ Shared storage will be configured using GlusterFS"
    export STORAGE_SOLUTION="glusterfs"
    export STORAGE_DEVICE="auto"  # Auto-detect 250GB SSDs
    export SHARED_STORAGE_PATH="/mnt/shared-storage"
    export DOCKER_STORAGE_PATH="/mnt/shared-storage/docker-volumes"
else
    echo "⚠️  Shared storage disabled - using local storage on each Pi"
    export STORAGE_SOLUTION="none"
fi
echo ""

# DNS configuration prompt
echo "🌐 DNS CONFIGURATION"
echo "===================="
echo "Do you want to set up Pi-hole as a local DNS server?"
echo "This will provide local hostname resolution and ad-blocking for your cluster."
echo ""
echo "Benefits of Pi-hole DNS:"
echo "• Local hostname resolution (e.g., portainer.cluster.local)"
echo "• Ad-blocking and privacy protection"
echo "• Better container networking with DNS names"
echo "• Centralized DNS management for the cluster"
echo ""
read -p "Enable Pi-hole DNS server? (Y/n): " ENABLE_PIHOLE
ENABLE_PIHOLE=${ENABLE_PIHOLE,,}

if [[ "$ENABLE_PIHOLE" =~ ^(y|yes|)$ ]]; then
    echo "✅ Pi-hole DNS will be configured on the first Pi"
    export ENABLE_PIHOLE="true"
    export PIHOLE_IP="auto"  # Use first Pi
    export PIHOLE_DOMAIN="cluster.local"
    export PIHOLE_WEB_PASSWORD="piswarm123"  # Default password
    echo "   DNS domain: cluster.local"
    echo "   Admin password: piswarm123 (can be changed later)"
else
    echo "⚠️  Pi-hole DNS disabled - using external DNS servers"
    export ENABLE_PIHOLE="false"
fi
echo ""

echo "Please choose a deployment option:"
echo ""
echo "1. 🤖 Automated Deployment (Recommended for first-time users)"
echo "   • No user interaction required"
echo "   • Uses sensible defaults"
echo "   • Perfect for testing and CI/CD"
echo ""
echo "2. 🔧 Enhanced Interactive Deployment"
echo "   • Step-by-step configuration"
echo "   • Advanced options available"
echo "   • Better error handling and feedback"
echo ""
echo "3. 🎛️ Traditional Deployment"
echo "   • Full manual control"
echo "   • All enterprise features configurable"
echo "   • For experienced users"
echo ""
echo "4. 🧪 Validation Mode"
echo "   • Test without actual deployment"
echo "   • Validate configuration and connectivity"
echo "   • Perfect for troubleshooting"
echo ""
echo "5. 📊 Demo Mode"
echo "   • See all deployment options"
echo "   • Show project capabilities"
echo "   • Educational walkthrough"
echo ""

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo "🤖 Starting automated deployment..."
        exec ./scripts/deployment/automated-deploy.sh
        ;;
    2)
        echo "🔧 Starting enhanced interactive deployment..."
        exec ./scripts/deployment/enhanced-deploy.sh
        ;;
    3)
        echo "🎛️ Starting traditional deployment..."
        exec ./core/swarm-cluster.sh
        ;;
    4)
        echo "🧪 Running validation tests..."
        exec ./scripts/testing/final-validation-test.sh
        ;;
    5)
        echo "📊 Starting demo mode..."
        exec ./scripts/deployment/deployment-demo.sh
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again and choose 1-5."
        exit 1
        ;;
esac
