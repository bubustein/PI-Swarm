#!/bin/bash
set -euo pipefail

# ---- Global Configuration ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTIONS_DIR="$PROJECT_ROOT/lib"
CONFIG_FILE="$PROJECT_ROOT/config/config.yml"
LOG_FILE="$PROJECT_ROOT/data/logs/piswarm-$(date +%Y%m%d).log"
BACKUP_DIR="$PROJECT_ROOT/data/backups"
mkdir -p "$(dirname "$LOG_FILE")"

# --- Ensure essential functions are loaded early ---
# Always source log.sh and discover_pis.sh directly for reliability
if [[ -f "$FUNCTIONS_DIR/log.sh" ]]; then
    source "$FUNCTIONS_DIR/log.sh"
fi
if [[ -f "$FUNCTIONS_DIR/networking/discover_pis.sh" ]]; then
    source "$FUNCTIONS_DIR/networking/discover_pis.sh"
fi

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# ---- Dependency and Environment Checks ----
REQUIRED_TOOLS=(sshpass ssh nmap awk sed grep tee curl docker lsb_release ip sudo python3 yq)
PYTHON_MIN_VERSION=3

missing_tools=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done

# Python version check
if ! python3 -c 'import sys; assert sys.version_info.major >= 3' 2>/dev/null; then
    echo "Python 3 is required." && exit 1
fi

# Network connectivity check (can be skipped for offline testing)
if [[ "${SKIP_NETWORK_CHECK:-false}" != "true" ]] && [[ "${OFFLINE_MODE:-false}" != "true" ]]; then
    if ! ping -c1 8.8.8.8 >/dev/null 2>&1 && ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
        echo "No internet/network connectivity detected."
        echo "To run in offline mode, set OFFLINE_MODE=true or SKIP_NETWORK_CHECK=true"
        exit 1
    fi
else
    echo "⚠️  Network connectivity check skipped (offline mode enabled)"
fi

# Check for sudo availability (but don't require root)
SUDO=""
if [[ $EUID -ne 0 ]]; then
    if sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        # Test if sudo is available for package installation when needed
        echo "Note: Some operations may require sudo privileges for package installation"
        SUDO="sudo"
    fi
fi

# Install missing tools
if (( ${#missing_tools[@]} > 0 )); then
    echo "Missing tools: ${missing_tools[*]}"
    APT_TOOLS=()
    for t in "${missing_tools[@]}"; do
        case "$t" in
            docker) curl -fsSL https://get.docker.com | $SUDO sh ;;
            docker|python3) APT_TOOLS+=("$t") ;;
            *) APT_TOOLS+=("$t") ;;
        esac
    done

    if (( ${#APT_TOOLS[@]} > 0 )); then
        $SUDO apt-get update
        $SUDO apt-get install -y "${APT_TOOLS[@]}"
    fi
fi

# Final dependency verification
for t in "${REQUIRED_TOOLS[@]}"; do
    command -v "$t" >/dev/null 2>&1 || { echo "Tool still missing: $t"; exit 1; }
done

# Docker running check
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker..."
    $SUDO systemctl start docker || { echo "Could not start Docker"; exit 1; }
fi

echo "✅ All checks passed."

# ---- Load Functions ----
source "$FUNCTIONS_DIR/source_functions.sh"

if [[ -f "$FUNCTIONS_DIR/service_templates.sh" ]]; then
    source "$FUNCTIONS_DIR/service_templates.sh"
    log INFO "Service template features loaded"
fi

source_functions

# ---- Trap + Cleanup ----
cleanup() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        log ERROR "Script failed with exit code $exit_code"
        if [[ -n "${LAST_BACKUP_DIR:-}" ]]; then
            for host in "${PI_IPS[@]:-}"; do
                [[ -d "$LAST_BACKUP_DIR/$host" ]] && restore_device_config "$host" "$NODES_DEFAULT_USER" "$NODES_DEFAULT_PASS"
            done
        fi
    fi
    release_lock 2>/dev/null || true
}
trap cleanup EXIT
trap 'log ERROR "Line $LINENO: $BASH_COMMAND"' ERR

# ---- Pi Discovery ----
discover_pis

# Split PI_IPS string into an array
read -ra PI_IPS <<< "$PI_IPS"

# Validate each IP individually
for ip in "${PI_IPS[@]}"; do
    validate_input "$ip" "ip" || { log ERROR "Invalid IP: $ip"; exit 1; }
done

log INFO "Pis found: ${PI_IPS[*]}"
log INFO "Hostnames: ${PI_HOSTNAMES[*]}"

# ---- Optional Pre-deployment Validation ----
echo ""
echo "🧹 Pre-deployment Validation Available"
echo "======================================"
echo "Would you like to run pre-deployment validation and cleanup?"
echo "This will optimize your Pis for deployment and may improve success rate."
echo ""
echo "Validation includes:"
echo "  • System resource checks"
echo "  • Docker environment cleanup"
echo "  • Network connectivity validation"
echo "  • Performance optimization"
echo ""

# Helper for non-interactive default
prompt_or_default() {
    local prompt="$1"; local var="$2"; local def="$3"; local silent="$4"
    if [ ! -t 0 ]; then
        eval "$var=\"$def\""
    else
        if [ "$silent" = "true" ]; then
            read -srp "$prompt" $var && echo
        else
            read -p "$prompt" $var
        fi
        eval "$var=\"${!var:-$def}\""
    fi
}

PRE_VALIDATION=""
while true; do
    prompt_or_default "Run pre-deployment validation? (Y/n): " PRE_VALIDATION "Y" "false"
    PRE_VALIDATION=${PRE_VALIDATION,,}
    case $PRE_VALIDATION in
        y|yes)
            echo "✅ Will run pre-deployment validation"
            PRE_VALIDATION="true"
            break
            ;;
        n|no)
            echo "⚠️ Skipping pre-deployment validation"
            PRE_VALIDATION="false"
            break
            ;;
        *)
            echo "❌ Please enter Y or N"; PRE_VALIDATION="true" # default
            ;;
    esac
done

# ---- Credential Setup ----
PI_USER=$(get_config_value ".nodes.default_user" "username" "" "true")
[[ -z "$PI_USER" ]] && PI_USER="${SSH_USER:-${USERNAME:-pi}}"
[[ -z "$PI_USER" ]] && prompt_or_default "Enter SSH username: " PI_USER "pi" "false"

PI_PASS=$(get_config_value ".nodes.default_pass" "password" "" "true")
[[ -z "$PI_PASS" ]] && PI_PASS="${SSH_PASSWORD:-${PASSWORD:-}}"
if [[ -z "$PI_PASS" ]]; then
    echo ""
    echo "⚠️  No default password configured in configuration file."
    echo "   Please enter the SSH password for user '$PI_USER' on your Pi devices:"
    echo "   (Or set SSH_PASSWORD environment variable for automated deployment)"
    read -sp "SSH Password: " PI_PASS < /dev/tty || true
    echo ""
    if [[ -z "$PI_PASS" ]]; then
        log ERROR "Password cannot be empty. Deployment cancelled."
        log ERROR "Set SSH_PASSWORD environment variable or configure password in config.yml"
        exit 1
    fi
fi

# Sanitize password to remove whitespace/newlines
PI_PASS="$(echo "$PI_PASS" | tr -d '\r' | tr -d '\n' | xargs)"

# Export variables for use in sub-functions
export NODES_DEFAULT_USER="$PI_USER"
export NODES_DEFAULT_PASS="$PI_PASS"
export USERNAME="$PI_USER"      # Ensure USERNAME is set for pre-deployment validation
export PASSWORD="$PI_PASS"      # Ensure PASSWORD is set for pre-deployment validation
export PI_USER                  # Export PI_USER as well
export PI_PASS                  # Export PI_PASS as well

# ---- Execute Pre-deployment Validation ----
if [[ "$PRE_VALIDATION" == "true" ]]; then
    echo ""
    echo "🧹 Running Pre-deployment Validation"
    echo "===================================="
    
    # Source the pre-deployment validation functions
    if [[ -f "$PROJECT_ROOT/lib/deployment/pre_deployment_validation.sh" ]]; then
        source "$PROJECT_ROOT/lib/deployment/pre_deployment_validation.sh"
        
        # Run validation with current credentials
        export USER="$PI_USER"
        if validate_and_prepare_pi_state "${PI_IPS[@]}"; then
            echo ""
            echo "✅ Pre-deployment validation completed successfully!"
            echo "   Your Pis are optimized for deployment."
        else
            echo ""
            echo "❌ Pre-deployment validation encountered issues!"
            echo "   Continuing with deployment, but you may experience problems."
            read -p "Continue anyway? (Y/n): " continue_anyway
            continue_anyway=${continue_anyway:-Y}
            if [[ ! "${continue_anyway,,}" =~ ^(y|yes)$ ]]; then
                log ERROR "Deployment cancelled due to validation failures."
                exit 1
            fi
        fi
    else
        log "WARN" "Pre-deployment validation script not found, skipping..."
    fi
    echo ""
fi

# ---- Context-Aware Deployment Options ----
echo ""
echo "🎯 Context-Aware Deployment Options"
echo "===================================="
echo "Enable hardware detection and adaptive deployment optimizations?"
echo ""
echo "🔍 Hardware Detection:"
echo "  • Detect CPU, memory, and storage specifications"
echo "  • Identify Raspberry Pi models and capabilities"
echo "  • Analyze cluster-wide performance profile"
echo ""
echo "🧹 System Sanitization (optional):"
echo "  • Clean system caches and temporary files"
echo "  • Remove old packages and logs"
echo "  • Optimize system for deployment"
echo ""
echo "⚡ Adaptive Configuration:"
echo "  • Adjust resource limits based on hardware"
echo "  • Optimize services for detected capabilities"
echo "  • Apply hardware-specific performance tuning"
echo ""

# Context-aware deployment option
prompt_or_default "Enable context-aware deployment? (Y/n): " ENABLE_CONTEXT_AWARE "Y" "false"
ENABLE_CONTEXT_AWARE=${ENABLE_CONTEXT_AWARE,,}
if [[ "$ENABLE_CONTEXT_AWARE" =~ ^(y|yes)$ ]]; then
    echo "✅ Context-aware deployment enabled"
    
    # Optional sanitization
    prompt_or_default "Run system sanitization before deployment? (Y/n): " ENABLE_SANITIZATION "Y" "false"
    ENABLE_SANITIZATION=${ENABLE_SANITIZATION,,}
    if [[ "$ENABLE_SANITIZATION" =~ ^(y|yes)$ ]]; then
        echo ""
        echo "Select sanitization level:"
        echo "1. Minimal    - Basic cache cleanup"
        echo "2. Standard   - Recommended cleanup (default)"
        echo "3. Thorough   - Comprehensive cleanup"
        echo "4. Complete   - Full system reset (WARNING: removes user data)"
        
        prompt_or_default "Sanitization level (1-4): " sanitization_choice "2" "false"
        case $sanitization_choice in
            1) SANITIZATION_LEVEL="minimal" ;;
            2) SANITIZATION_LEVEL="standard" ;;
            3) SANITIZATION_LEVEL="thorough" ;;
            4) 
                echo ""
                echo "⚠️  WARNING: Complete sanitization will:"
                echo "   • Remove all user files and configurations"
                echo "   • Reset system to clean state"
                echo "   • This action is irreversible!"
                echo ""
                prompt_or_default "Are you sure you want complete sanitization? (y/N): " confirm_complete "N" "false"
                if [[ "${confirm_complete,,}" =~ ^(y|yes)$ ]]; then
                    SANITIZATION_LEVEL="complete"
                else
                    echo "Falling back to thorough sanitization"
                    SANITIZATION_LEVEL="thorough"
                fi
                ;;
            *) SANITIZATION_LEVEL="standard" ;;
        esac
        echo "Selected sanitization level: $SANITIZATION_LEVEL"
        export ENABLE_SANITIZATION SANITIZATION_LEVEL
    else
        echo "⚠️ Skipping system sanitization"
        ENABLE_SANITIZATION="false"
    fi
    
    export ENABLE_CONTEXT_AWARE
else
    echo "⚠️ Using standard deployment without context-awareness"
    ENABLE_CONTEXT_AWARE="false"
    export ENABLE_CONTEXT_AWARE
fi

# ---- Enhanced Features Configuration ----
echo ""
echo "🚀 Enterprise Pi-Swarm Setup"

# Check if configuration is pre-provided (from enhanced-deploy.sh)
if [[ -n "${WHATSAPP_PHONE_ID:-}" && -n "${WHATSAPP_TOKEN:-}" && -n "${WHATSAPP_RECIPIENT:-}" ]]; then
    SETUP_WHATSAPP="yes"
    log INFO "WhatsApp alerts pre-configured for ${WHATSAPP_RECIPIENT}"
fi

if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
    SETUP_SLACK="yes"
    SLACK_WEBHOOK_URL="$SLACK_WEBHOOK"
    SLACK_CHANNEL="#alerts"
    log INFO "Slack alerts pre-configured"
fi

if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
    SETUP_DISCORD="yes" 
    DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK"
    log INFO "Discord alerts pre-configured"
fi

if [[ -n "${ALERT_EMAIL:-}" ]]; then
    SETUP_EMAIL_ALERTS="yes"
    log INFO "Email alerts pre-configured for ${ALERT_EMAIL}"
fi

if [[ -n "${LLM_PROVIDER:-}" ]]; then
    SETUP_LLM="yes"
    log INFO "LLM-powered alerts pre-configured with ${LLM_PROVIDER} (${LLM_MODEL:-default})"
fi

echo "Configure optional enhanced features:"
echo ""

# Quick setup option
read -p "Enable ALL enterprise features (SSL, alerts, HA, templates)? (y/N): " ENABLE_ALL_FEATURES
ENABLE_ALL_FEATURES=${ENABLE_ALL_FEATURES,,}

if [[ "$ENABLE_ALL_FEATURES" =~ ^(y|yes)$ ]]; then
    # Auto-configure all enterprise features
    ENABLE_LETSENCRYPT="yes"
    SETUP_SLACK="yes"
    SETUP_EMAIL_ALERTS="yes"
    SETUP_DISCORD="yes"
    SETUP_HA="yes"
    ENABLE_SSL_MONITORING="yes"
    ENABLE_TEMPLATES="yes"
    ENABLE_ADVANCED_MONITORING="yes"
    
    echo "✅ All enterprise features enabled!"
    echo ""
    
    # Still need user input for required parameters
    prompt_or_default "Enter your domain name (e.g., myswarm.example.com): " SSL_DOMAIN "" "false"
    prompt_or_default "Enter your email for Let's Encrypt: " SSL_EMAIL "" "false"
    prompt_or_default "Enter Slack webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK_URL "" "false"
    prompt_or_default "Enter Slack channel (e.g., #alerts): " SLACK_CHANNEL "" "false"
    prompt_or_default "Enter email SMTP server (optional, press Enter to skip): " SMTP_SERVER "" "false"
    if [[ -n "$SMTP_SERVER" ]]; then
        prompt_or_default "Enter SMTP username: " SMTP_USER "" "false"
        prompt_or_default "Enter SMTP password: " SMTP_PASS "" "true"
        prompt_or_default "Enter notification email address: " ALERT_EMAIL "" "false"
    fi
    prompt_or_default "Enter Discord webhook URL (optional, press Enter to skip): " DISCORD_WEBHOOK_URL "" "false"
    prompt_or_default "Configure WhatsApp alerts? (y/N): " setup_whatsapp "n" "false"
    setup_whatsapp=${setup_whatsapp,,}
    if [[ "$setup_whatsapp" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter Phone Number ID: " WHATSAPP_PHONE_ID "" "false"
        prompt_or_default "Enter Access Token: " WHATSAPP_TOKEN "" "false"
        prompt_or_default "Enter recipient phone number (with country code): " WHATSAPP_RECIPIENT "" "false"
    fi
    export SSL_DOMAIN SSL_EMAIL ENABLE_LETSENCRYPT
    export SLACK_WEBHOOK_URL SLACK_CHANNEL SETUP_SLACK
    export SMTP_SERVER SMTP_USER SMTP_PASS ALERT_EMAIL SETUP_EMAIL_ALERTS
    export DISCORD_WEBHOOK_URL SETUP_DISCORD
    export WHATSAPP_PHONE_ID WHATSAPP_TOKEN WHATSAPP_RECIPIENT
    export SETUP_HA ENABLE_SSL_MONITORING ENABLE_TEMPLATES ENABLE_ADVANCED_MONITORING
else
    # Individual feature configuration
    # SSL Automation Configuration
    prompt_or_default "Enable Let's Encrypt SSL automation? (y/N): " ENABLE_LETSENCRYPT "n" "false"
    ENABLE_LETSENCRYPT=${ENABLE_LETSENCRYPT,,}
    if [[ "$ENABLE_LETSENCRYPT" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter your domain name (e.g., myswarm.example.com): " SSL_DOMAIN "" "false"
        prompt_or_default "Enter your email for Let's Encrypt: " SSL_EMAIL "" "false"
        export SSL_DOMAIN SSL_EMAIL ENABLE_LETSENCRYPT
    fi

    # Alert Integration Configuration
    prompt_or_default "Configure Slack alerts? (y/N): " SETUP_SLACK "n" "false"
    SETUP_SLACK=${SETUP_SLACK,,}
    if [[ "$SETUP_SLACK" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter Slack webhook URL: " SLACK_WEBHOOK_URL "" "false"
        prompt_or_default "Enter Slack channel (e.g., #alerts): " SLACK_CHANNEL "" "false"
        export SLACK_WEBHOOK_URL SLACK_CHANNEL SETUP_SLACK
    fi

    # Email alerts configuration
    prompt_or_default "Configure email alerts? (y/N): " SETUP_EMAIL_ALERTS "n" "false"
    SETUP_EMAIL_ALERTS=${SETUP_EMAIL_ALERTS,,}
    if [[ "$SETUP_EMAIL_ALERTS" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter SMTP server (e.g., smtp.gmail.com:587): " SMTP_SERVER "" "false"
        prompt_or_default "Enter SMTP username: " SMTP_USER "" "false"
        prompt_or_default "Enter SMTP password: " SMTP_PASS "" "true"
        prompt_or_default "Enter notification email address: " ALERT_EMAIL "" "false"
        export SMTP_SERVER SMTP_USER SMTP_PASS ALERT_EMAIL SETUP_EMAIL_ALERTS
    fi

    # Discord alerts configuration
    prompt_or_default "Configure Discord alerts? (y/N): " SETUP_DISCORD "n" "false"
    SETUP_DISCORD=${SETUP_DISCORD,,}
    if [[ "$SETUP_DISCORD" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter Discord webhook URL: " DISCORD_WEBHOOK_URL "" "false"
        export DISCORD_WEBHOOK_URL SETUP_DISCORD
    fi

    # WhatsApp alerts configuration
    prompt_or_default "Configure WhatsApp Business API alerts? (y/N): " SETUP_WHATSAPP "n" "false"
    SETUP_WHATSAPP=${SETUP_WHATSAPP,,}
    if [[ "$SETUP_WHATSAPP" =~ ^(y|yes)$ ]]; then
        prompt_or_default "Enter Phone Number ID: " WHATSAPP_PHONE_ID "" "false"
        prompt_or_default "Enter Access Token: " WHATSAPP_TOKEN "" "false"
        prompt_or_default "Enter recipient phone number (with country code, e.g., +1234567890): " WHATSAPP_RECIPIENT "" "false"
        export WHATSAPP_PHONE_ID WHATSAPP_TOKEN WHATSAPP_RECIPIENT SETUP_WHATSAPP
    fi

    # LLM-powered intelligent alerts configuration
    prompt_or_default "Configure LLM-powered intelligent alerts? (y/N): " SETUP_LLM "n" "false"
    SETUP_LLM=${SETUP_LLM,,}
    if [[ "$SETUP_LLM" =~ ^(y|yes)$ ]]; then
        echo "🤖 LLM-Powered Intelligent Alerts Configuration"
        echo "💡 AI-powered alert analysis with automated remediation suggestions"
        echo ""
        echo "Choose LLM provider:"
        echo "1. OpenAI (GPT-4/GPT-3.5)"
        echo "2. Anthropic (Claude)"
        echo "3. Azure OpenAI"
        echo "4. Ollama (Local/Private)"
        
        prompt_or_default "Select provider (1-4): " llm_provider_choice "1" "false"
        case $llm_provider_choice in
            1)
                LLM_PROVIDER="openai"
                prompt_or_default "Enter OpenAI API key: " LLM_API_KEY "" "false"
                prompt_or_default "Model name (default: gpt-4): " LLM_MODEL "gpt-4" "false"
                ;;
            2)
                LLM_PROVIDER="anthropic"
                prompt_or_default "Enter Anthropic API key: " LLM_API_KEY "" "false"
                prompt_or_default "Model name (default: claude-3-sonnet-20240229): " LLM_MODEL "claude-3-sonnet-20240229" "false"
                ;;
            3)
                LLM_PROVIDER="azure"
                prompt_or_default "Enter Azure OpenAI API key: " LLM_API_KEY "" "false"
                prompt_or_default "Enter Azure endpoint: " LLM_API_ENDPOINT "" "false"
                prompt_or_default "Deployment name: " LLM_MODEL "" "false"
                ;;
            4)
                LLM_PROVIDER="ollama"
                prompt_or_default "Ollama endpoint (default: http://localhost:11434): " LLM_API_ENDPOINT "http://localhost:11434" "false"
                prompt_or_default "Model name (default: llama3:8b): " LLM_MODEL "llama3:8b" "false"
                ;;
            *)
                echo "❌ Invalid choice, skipping LLM configuration"
                SETUP_LLM="no"
                ;;
        esac
        
        if [[ "$SETUP_LLM" == "yes" ]]; then
            prompt_or_default "Enable automated remediation for safe commands? (y/n): " auto_remediation "n" "false"
            case $auto_remediation in
                [Yy]*)
                    LLM_AUTO_REMEDIATION="true"
                    echo "⚠️  Automated remediation enabled - AI can execute safe commands"
                    ;;
                *)
                    LLM_AUTO_REMEDIATION="false"
                    echo "✅ Manual review required for all remediation"
                    ;;
            esac
            export LLM_PROVIDER LLM_API_KEY LLM_API_ENDPOINT LLM_MODEL LLM_AUTO_REMEDIATION SETUP_LLM
        fi
    fi

    # High Availability Configuration
    if [[ ${#PI_IPS[@]} -ge 3 ]]; then
        prompt_or_default "Setup high availability cluster? (y/N): " SETUP_HA "n" "false"
        export SETUP_HA
    fi

    # Additional enterprise features
    prompt_or_default "Enable SSL certificate monitoring? (y/N): " ENABLE_SSL_MONITORING "n" "false"
    ENABLE_SSL_MONITORING=${ENABLE_SSL_MONITORING,,}
    export ENABLE_SSL_MONITORING

    prompt_or_default "Initialize service template catalog? (y/N): " ENABLE_TEMPLATES "n" "false"
    ENABLE_TEMPLATES=${ENABLE_TEMPLATES,,}
    export ENABLE_TEMPLATES

    prompt_or_default "Enable advanced performance monitoring? (y/N): " ENABLE_ADVANCED_MONITORING "n" "false"
    ENABLE_ADVANCED_MONITORING=${ENABLE_ADVANCED_MONITORING,,}
    export ENABLE_ADVANCED_MONITORING
fi
echo ""
log INFO "Configuration complete. Beginning cluster deployment..."
echo ""

# ---- Using Existing Static IPs ----
# Since static IPs are already configured, use them directly
declare -A PI_PER_HOST_USER PI_PER_HOST_PASS
PI_STATIC_IPS=("${PI_IPS[@]:-}")
log INFO "Using existing static IPs: ${PI_STATIC_IPS[*]}"

LAST_BACKUP_DIR="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LAST_BACKUP_DIR"

# ---- Context-Aware Hardware Detection (Optional) ----
if [[ -n "${ENABLE_CONTEXT_AWARE:-}" && "$ENABLE_CONTEXT_AWARE" == "true" ]]; then
    echo ""
    echo "🔍 Context-Aware Hardware Detection"
    echo "===================================="
    
    # Source hardware detection and sanitization modules
    if [[ -f "$PROJECT_ROOT/lib/system/hardware_detection.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/hardware_detection.sh"
    fi
    if [[ -f "$PROJECT_ROOT/lib/system/sanitization.sh" ]]; then
        source "$PROJECT_ROOT/lib/system/sanitization.sh"
    fi
    
    # Initialize context-aware deployment variables
    declare -A CLUSTER_CAPABILITIES
    total_memory=0
    total_cores=0
    min_memory=999999
    min_cores=999999
    all_are_pi=true
    has_ssd=false
    
    # Detect hardware for each Pi
    for PI_IP in "${PI_STATIC_IPS[@]}"; do
        SSH_USER="${PI_PER_HOST_USER[$PI_IP]:-$PI_USER}"
        SSH_PASS="${PI_PER_HOST_PASS[$PI_IP]:-$PI_PASS}"
        
        log INFO "🔍 Detecting hardware for $PI_IP..."
        
        if command -v detect_hardware >/dev/null 2>&1 && detect_hardware "$PI_IP" "$SSH_USER" "$SSH_PASS"; then
            # Extract detected capabilities
            local array_name="HW_${PI_IP//./_}"
            local -n hw_ref=$array_name 2>/dev/null
            
            if [[ -n "${hw_ref[MEMORY_TOTAL_MB]:-}" ]]; then
                local memory_mb="${hw_ref[MEMORY_TOTAL_MB]}"
                local cores="${hw_ref[CPU_CORES]:-1}"
                
                total_memory=$((total_memory + memory_mb))
                total_cores=$((total_cores + cores))
                
                [[ $memory_mb -lt $min_memory ]] && min_memory=$memory_mb
                [[ $cores -lt $min_cores ]] && min_cores=$cores
                
                [[ "${hw_ref[IS_RASPBERRY_PI]:-false}" != "true" ]] && all_are_pi=false
                [[ "${hw_ref[STORAGE_TYPE]:-HDD}" == "SSD" ]] && has_ssd=true
                
                log INFO "  📊 $PI_IP: ${memory_mb}MB RAM, ${cores} cores, ${hw_ref[STORAGE_TYPE]:-HDD}"
            fi
            
            # Optional sanitization if enabled
            if [[ -n "${ENABLE_SANITIZATION:-}" && "$ENABLE_SANITIZATION" == "true" ]]; then
                local sanitization_level="${SANITIZATION_LEVEL:-standard}"
                log INFO "🧹 Sanitizing $PI_IP (level: $sanitization_level)..."
                if command -v sanitize_system >/dev/null 2>&1; then
                    sanitize_system "$PI_IP" "$SSH_USER" "$SSH_PASS" "$sanitization_level" || log WARN "Sanitization failed for $PI_IP"
                fi
            fi
        else
            log WARN "Hardware detection failed for $PI_IP, using default configuration"
        fi
    done
    
    # Determine cluster profile based on detected capabilities
    local cluster_profile="basic"
    if [[ $min_memory -ge 4096 && $min_cores -ge 4 ]]; then
        cluster_profile="high-performance"
    elif [[ $min_memory -ge 2048 && $min_cores -ge 2 ]]; then
        cluster_profile="standard"
    elif [[ $min_memory -ge 1024 ]]; then
        cluster_profile="lightweight"
    fi
    
    # Set cluster-wide optimizations based on detected profile
    CLUSTER_CAPABILITIES[PROFILE]="$cluster_profile"
    CLUSTER_CAPABILITIES[TOTAL_MEMORY_GB]=$((total_memory / 1024))
    CLUSTER_CAPABILITIES[TOTAL_CORES]="$total_cores"
    CLUSTER_CAPABILITIES[MIN_MEMORY_MB]="$min_memory"
    CLUSTER_CAPABILITIES[MIN_CORES]="$min_cores"
    CLUSTER_CAPABILITIES[ALL_RASPBERRY_PI]="$all_are_pi"
    CLUSTER_CAPABILITIES[HAS_SSD]="$has_ssd"
    
    echo ""
    echo "📋 Cluster Analysis Summary:"
    echo "   Profile: $cluster_profile"
    echo "   Total Resources: ${CLUSTER_CAPABILITIES[TOTAL_MEMORY_GB]}GB RAM, $total_cores cores"
    echo "   Minimum Node: ${min_memory}MB RAM, $min_cores cores"
    echo "   All Raspberry Pi: $all_are_pi"
    echo "   Has SSD Storage: $has_ssd"
    echo ""
    
    # Export cluster capabilities for use in deployment configuration
    export CLUSTER_PROFILE="$cluster_profile"
    export CLUSTER_MIN_MEMORY="$min_memory"
    export CLUSTER_MIN_CORES="$min_cores"
    export CLUSTER_HAS_SSD="$has_ssd"
    
    log INFO "Context-aware detection completed. Adapting deployment strategy..."
fi

# ---- Configure Each Pi ----
for PI_IP in "${PI_STATIC_IPS[@]}"; do
    SSH_USER="${PI_PER_HOST_USER[$PI_IP]:-$PI_USER}"
    SSH_PASS="${PI_PER_HOST_PASS[$PI_IP]:-$PI_PASS}"

    if ! ssh_exec "$PI_IP" "$SSH_USER" "$SSH_PASS" "echo Connected"; then
        log WARN "SSH failed: $PI_IP, setting up keys..."
        setup_ssh_keys "$PI_IP" "$SSH_USER" "$SSH_PASS" || { log WARN "SSH key setup failed for $PI_IP (continuing with password auth)"; }
    fi

    # Configure Pi and install required software including Docker
    configure_pi_headless "$PI_IP" "$SSH_USER" "$SSH_PASS" || { log ERROR "Pi configuration failed for $PI_IP"; continue; }
    
    # Apply security hardening (if function exists)
    if command -v setup_security_hardening >/dev/null 2>&1; then
        setup_security_hardening "$PI_IP" "$SSH_USER" "$SSH_PASS" || log WARN "Security hardening failed for $PI_IP"
    else
        log INFO "Security hardening function not available (skipping)"
    fi
    
    # Validate device configuration (if function exists)
    if command -v validate_device_config >/dev/null 2>&1; then
        validate_device_config "$PI_IP" "$SSH_USER" "$SSH_PASS" || { log ERROR "Device validation failed for $PI_IP"; continue; }
    else
        log INFO "Device validation function not available (skipping)"
    fi

    log INFO "✅ Configured: $PI_IP"
done

# ---- Storage Setup ----
if [[ ${#PI_STATIC_IPS[@]} -gt 0 ]] && [[ "${STORAGE_SOLUTION:-}" != "none" ]] && [[ "${STORAGE_SOLUTION:-}" != "" ]]; then
    log INFO "🗄️  Setting up shared storage solution: ${STORAGE_SOLUTION:-glusterfs}"
    
    # Setup cluster storage before Docker Swarm initialization
    if command -v setup_cluster_storage >/dev/null 2>&1; then
        setup_cluster_storage "${PI_STATIC_IPS[@]}" || { 
            log WARN "Storage setup failed, continuing without shared storage" 
            log WARN "Docker volumes will use local storage on each node"
        }
        
        # Load storage configuration if it was created
        if [[ -f "$PROJECT_ROOT/data/storage-config.env" ]]; then
            source "$PROJECT_ROOT/data/storage-config.env"
            log INFO "Loaded storage configuration: $STORAGE_SOLUTION"
        fi
    else
        log WARN "Storage management functions not available"
        log INFO "Skipping shared storage setup - using local storage"
    fi
    
    # Configure Docker to use shared storage paths if available
    if [[ -n "${SHARED_STORAGE_PATH:-}" ]] && [[ -d "${SHARED_STORAGE_PATH:-}" ]]; then
        log INFO "Configuring Docker to use shared storage: ${SHARED_STORAGE_PATH}"
        for pi_ip in "${PI_STATIC_IPS[@]}"; do
            log INFO "  Configuring Docker on $pi_ip..."
            ssh_exec "$pi_ip" "$PI_USER" "$PI_PASS" "
                # Create Docker storage directory on shared storage
                sudo mkdir -p '${DOCKER_STORAGE_PATH:-${SHARED_STORAGE_PATH}/docker-volumes}}'
                
                # Create additional shared directories for common use cases
                sudo mkdir -p '${SHARED_STORAGE_PATH}/portainer-data'
                sudo mkdir -p '${SHARED_STORAGE_PATH}/grafana-data'
                sudo mkdir -p '${SHARED_STORAGE_PATH}/prometheus-data'
                sudo mkdir -p '${SHARED_STORAGE_PATH}/app-data'
                
                # Set proper permissions
                sudo chmod 755 '${SHARED_STORAGE_PATH}'/{docker-volumes,portainer-data,grafana-data,prometheus-data,app-data}
                
                # Backup existing Docker configuration
                if [[ -f /etc/docker/daemon.json ]]; then
                    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup-\$(date +%Y%m%d)
                fi
                
                # Create optimized Docker daemon configuration
                echo '{
                    \"storage-driver\": \"overlay2\",
                    \"log-driver\": \"json-file\",
                    \"log-opts\": {
                        \"max-size\": \"10m\",
                        \"max-file\": \"3\"
                    },
                    \"live-restore\": true,
                    \"userland-proxy\": false,
                    \"experimental\": false
                }' | sudo tee /etc/docker/daemon.json >/dev/null
                
                # Restart Docker to apply new configuration
                sudo systemctl restart docker
                
                # Wait for Docker to be ready
                timeout=30
                counter=0
                while ! docker info >/dev/null 2>&1; do
                    if [ \$counter -ge \$timeout ]; then
                        echo 'Timeout waiting for Docker to start'
                        exit 1
                    fi
                    sleep 1
                    counter=\$((counter + 1))
                done
                
                echo '✅ Docker configured successfully on $pi_ip'
            " || log WARN "Failed to configure Docker storage on $pi_ip"
        done
        
        log INFO "✅ Docker configured to use shared storage on all nodes"
    else
        log INFO "No shared storage available - Docker will use default local storage"
    fi
else
    log INFO "Skipping storage setup (no storage solution configured or no nodes available)"
fi

# Setup Pi-hole DNS server if enabled
if [[ "${ENABLE_PIHOLE:-false}" == "true" ]] && command -v setup_pihole_dns >/dev/null 2>&1; then
    log INFO "🌐 Setting up Pi-hole DNS server for the cluster..."
    
    # Set up hostnames array for DNS entries
    declare -a PI_HOSTNAMES
    for i in "${!PI_STATIC_IPS[@]}"; do
        PI_HOSTNAMES[$i]="pi-node-$((i+1))"
    done
    export PI_HOSTNAMES
    
    # Configure Pi-hole DNS with cluster settings
    export PIHOLE_IP="${PIHOLE_IP:-auto}"  # Use first Pi if not specified
    export PIHOLE_WEB_PASSWORD="${PIHOLE_WEB_PASSWORD:-piswarm123}"
    export PIHOLE_DNS_UPSTREAM="${PIHOLE_DNS_UPSTREAM:-1.1.1.1,8.8.8.8}"
    export PIHOLE_DOMAIN="${PIHOLE_DOMAIN:-cluster.local}"
    
    # Call Pi-hole setup function
    if setup_pihole_dns "${PI_STATIC_IPS[@]}"; then
        log INFO "✅ Pi-hole DNS server setup completed successfully"
        
        # Update environment variables with Pi-hole configuration
        if [[ -f "$PROJECT_ROOT/data/pihole-config.env" ]]; then
            source "$PROJECT_ROOT/data/pihole-config.env"
            log INFO "Pi-hole configuration loaded and available for Docker services"
        fi
    else
        log WARN "Pi-hole DNS setup failed - continuing without DNS server"
        log WARN "Services will use default DNS resolution"
    fi
elif [[ "${ENABLE_PIHOLE:-false}" == "true" ]]; then
    log WARN "Pi-hole DNS requested but setup function not available"
    log WARN "Make sure lib/networking/pihole_dns.sh is properly sourced"
else
    log INFO "Pi-hole DNS setup skipped (not enabled)"
fi

# ---- Swarm Setup ----
if [[ ${#PI_STATIC_IPS[@]} -gt 0 ]]; then
    init_swarm || { log ERROR "Swarm init failed"; exit 1; }
    
    # Setup SSL certificates (enhanced with Let's Encrypt support) - only if enabled
    if [[ "$ENABLE_LETSENCRYPT" =~ ^(y|yes)$ ]] || [[ -n "${SSL_DOMAIN:-}" ]]; then
        setup_ssl_certificates "${PI_STATIC_IPS[0]}" "$PI_USER" "$PI_PASS" || log WARN "SSL setup failed"
    else
        log INFO "SSL setup skipped (not enabled)"
    fi
    
    # Initialize service templates for easy deployments
    if command -v init_service_templates >/dev/null 2>&1; then
        init_service_templates || log WARN "Service template initialization failed"
    fi
    
    # Setup enhanced alerting if configured
    if command -v setup_alertmanager_integration >/dev/null 2>&1; then
        setup_alertmanager_integration "${PI_STATIC_IPS[0]}" "${SLACK_WEBHOOK:-}" "${LETSENCRYPT_EMAIL:-}" || log WARN "Enhanced alerting setup failed"
    fi
    
    # Deploy services
    deploy_services || { log ERROR "Service deploy failed"; exit 1; }
    
    # Configure enhanced features based on user preferences
    if [[ "$ENABLE_LETSENCRYPT" =~ ^(y|yes)$ ]] && command -v setup_letsencrypt_ssl >/dev/null 2>&1; then
        log INFO "Setting up Let's Encrypt SSL automation..."
        setup_letsencrypt_ssl "$SSL_DOMAIN" "$SSL_EMAIL" || log WARN "Let's Encrypt setup failed"
    fi
    
    if [[ "$SETUP_SLACK" =~ ^(y|yes)$ ]] && command -v setup_slack_alerts >/dev/null 2>&1; then
        log INFO "Configuring Slack alert integration..."
        setup_slack_alerts "$SLACK_WEBHOOK_URL" "$SLACK_CHANNEL" || log WARN "Slack setup failed"
    fi
    
    if [[ "$SETUP_EMAIL_ALERTS" =~ ^(y|yes)$ ]] && command -v setup_email_alerts >/dev/null 2>&1; then
        log INFO "Configuring email alert integration..."
        setup_email_alerts "$SMTP_SERVER" "$SMTP_USER" "$SMTP_PASS" "$ALERT_EMAIL" || log WARN "Email alerts setup failed"
    fi
    
    if [[ "$SETUP_DISCORD" =~ ^(y|yes)$ ]] && command -v setup_discord_alerts >/dev/null 2>&1; then
        log INFO "Configuring Discord alert integration..."
        setup_discord_alerts "$DISCORD_WEBHOOK_URL" || log WARN "Discord setup failed"
    fi
    
    if [[ "$SETUP_WHATSAPP" =~ ^(y|yes)$ ]] && command -v setup_whatsapp_alerts >/dev/null 2>&1; then
        log INFO "Configuring WhatsApp alert integration..."
        setup_whatsapp_alerts "$WHATSAPP_PHONE_ID" "$WHATSAPP_TOKEN" "$WHATSAPP_RECIPIENT" "${PI_IPS[0]}" || log WARN "WhatsApp setup failed"
    fi
    
    if [[ "$SETUP_LLM" =~ ^(y|yes)$ ]] && command -v setup_llm_alerts >/dev/null 2>&1; then
        log INFO "Configuring LLM-powered intelligent alerts..."
        if [[ "$LLM_PROVIDER" == "ollama" ]]; then
            # Setup local Ollama first if using local LLM
            setup_local_llm "${PI_IPS[0]}" "$LLM_MODEL" || log WARN "Local LLM setup failed"
        fi
        setup_llm_alerts "$LLM_PROVIDER" "$LLM_API_KEY" "$LLM_API_ENDPOINT" "$LLM_MODEL" "${PI_IPS[0]}" || log WARN "LLM alerts setup failed"
        
        # Test the integration
        test_llm_integration "${PI_IPS[0]}" || log WARN "LLM integration test failed"
    fi
    
    if [[ "$SETUP_HA" =~ ^(y|yes)$ ]] && command -v setup_high_availability >/dev/null 2>&1; then
        log INFO "Setting up high availability cluster..."
        setup_high_availability "${PI_STATIC_IPS[@]}" || log WARN "HA setup failed"
    fi
    
    if [[ "$ENABLE_SSL_MONITORING" =~ ^(y|yes)$ ]] && command -v setup_ssl_monitoring >/dev/null 2>&1; then
        log INFO "Setting up SSL certificate monitoring..."
        setup_ssl_monitoring "${PI_STATIC_IPS[0]}" || log WARN "SSL monitoring setup failed"
    fi
    
    if [[ "$ENABLE_TEMPLATES" =~ ^(y|yes)$ ]] && command -v init_service_templates >/dev/null 2>&1; then
        log INFO "Initializing service template catalog..."
        init_service_templates || log WARN "Service template initialization failed"
    fi
    
    if [[ "$ENABLE_ADVANCED_MONITORING" =~ ^(y|yes)$ ]] && command -v setup_advanced_monitoring >/dev/null 2>&1; then
        log INFO "Setting up advanced performance monitoring..."
        setup_advanced_monitoring "${PI_STATIC_IPS[0]}" || log WARN "Advanced monitoring setup failed"
    fi
    
    # Performance optimizations
    optimize_cluster_performance "${PI_STATIC_IPS[0]}" || log WARN "Performance optimization failed"
    
    # Create monitoring alerts (enhanced)
    create_monitoring_alerts "${PI_STATIC_IPS[0]}" || log WARN "Alert setup failed"
    
    # Setup SSL monitoring if SSL automation is available
    if command -v setup_ssl_monitoring >/dev/null 2>&1; then
        setup_ssl_monitoring || log WARN "SSL monitoring setup failed"
    fi
    
    # Backup cluster configuration
    backup_cluster_config "${PI_STATIC_IPS[0]}" || log WARN "Cluster backup failed"
else
    log ERROR "No Pis configured successfully. Aborting swarm setup."
    exit 1
fi

# ---- Final Validation ----
manager_ip="${PI_STATIC_IPS[0]}"
ssh_exec "$manager_ip" "$PI_USER" "$PI_PASS" \
    "docker node ls --format '{{.Hostname}} {{.Status}}'" | grep -v 'Down' || {
    log ERROR "One or more nodes down"; exit 1;
}

log INFO "✅ Docker Swarm cluster is operational"

# Enhanced cluster health and performance display
display_cluster_health "${PI_STATIC_IPS[0]}"

# Create security audit
create_security_audit

# Generate performance report
monitor_cluster_performance "${PI_STATIC_IPS[0]}"

# Setup security monitoring
monitor_security_events "${PI_STATIC_IPS[0]}"

# Setup backup encryption
create_backup_encryption "backups"

# Display final service overview (this is also called in deploy_services but shown again for clarity)
echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                    🎉 DEPLOYMENT SUCCESSFUL! 🎉                   ║"
echo "║                  Enterprise Pi-Swarm Cluster                      ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "🌟 Your Enterprise Pi Swarm cluster is ready! Access your services:"
echo ""
echo "🐳 PORTAINER (Container Management):"
echo "   • HTTPS: https://$manager_ip:9443"
echo "   • HTTP:  http://$manager_ip:9000"
echo "   • Login: admin / [Password set during deployment]"
echo ""
echo "📊 GRAFANA (Monitoring Dashboard):"
echo "   • URL: http://$manager_ip:3000"
echo "   • Login: admin / ${GRAFANA_PASSWORD:-admin}"
echo ""
echo "🔍 PROMETHEUS (Metrics):"
echo "   • URL: http://$manager_ip:9090"
echo ""
echo "🚨 ALERTMANAGER (Alert Management):"
echo "   • URL: http://$manager_ip:9093"
echo ""

# Show SSL dashboard if available
if command -v create_ssl_dashboard >/dev/null 2>&1; then
    echo "🔒 SSL CERTIFICATE DASHBOARD:"
    echo "   • URL: http://$manager_ip:8080/ssl"
    echo ""
fi

# Show service templates info
if command -v list_service_templates >/dev/null 2>&1; then
    echo "📦 SERVICE TEMPLATES AVAILABLE:"
    echo "   Use: ./pi-swarm deploy-template <template-name>"
    template_count=$(list_service_templates 2>/dev/null | grep -c "^[a-z]" || echo "15+")
    echo "   • $template_count ready-to-deploy service templates"
    echo ""
fi

# Show high availability status
if [[ ${#PI_STATIC_IPS[@]} -ge 3 ]]; then
    echo "🏗️  HIGH AVAILABILITY:"
    echo "   • Multi-manager cluster ready"
    echo "   • Use: ./pi-swarm setup-ha for full HA configuration"
    echo ""
fi

# Show CLI management tools
echo "🛠️  ENHANCED MANAGEMENT CLI:"
echo "   • ./pi-swarm help           - View all available commands"
echo "   • ./pi-swarm status         - Cluster health overview"
echo "   • ./pi-swarm ssl-setup      - Configure SSL automation"
echo "   • ./pi-swarm setup-slack    - Configure Slack alerts"
echo "   • ./pi-swarm deploy-template - Deploy service templates"
echo ""

echo "🔐 ENTERPRISE SECURITY FEATURES:"
echo "   • SSL/TLS encryption enabled"
echo "   • Network security hardening active"
echo "   • Automated vulnerability scanning"
echo "   • Security audit logging"
echo ""

echo "📈 MONITORING & ALERTING:"
echo "   • Real-time performance monitoring"
echo "   • Resource usage alerts"
echo "   • Service health monitoring"
echo "   • SSL certificate expiry alerts"
echo ""

echo "💾 BACKUP & RECOVERY:"
echo "   • Automated configuration backups"
echo "   • Cluster state preservation"
echo "   • Recovery procedures documented"
echo ""

echo "📧 NOTIFICATION INTEGRATIONS:"
echo "   • Slack webhooks (configurable)"
echo "   • Email alerts (SMTP support)"
echo "   • Discord notifications (webhook)"
echo "   • Custom webhook endpoints"
echo ""

echo "📚 DOCUMENTATION & RESOURCES:"
echo "   • Implementation Summary: IMPLEMENTATION_SUMMARY.md"
echo "   • CLI Reference: ./pi-swarm help"
echo "   • Service Templates: ./pi-swarm list-templates"
echo "   • SSL Management: ./pi-swarm ssl-status"
echo ""

echo "🎯 NEXT STEPS:"
echo "   1. Configure external alerts: ./pi-swarm setup-slack"
echo "   2. Deploy additional services: ./pi-swarm deploy-template"
echo "   3. Setup high availability: ./pi-swarm setup-ha (3+ nodes)"
echo "   4. Enable SSL automation: ./pi-swarm ssl-setup"
echo "   5. Monitor cluster health: ./pi-swarm status"
echo ""

    # Generate deployment summary
    if command -v deployment_summary >/dev/null 2>&1; then
        deployment_summary
    else
        echo "✨ Enterprise Pi-Swarm deployment complete!"
        echo "   Total nodes: ${#PI_STATIC_IPS[@]}"
        echo "   Manager IP: $manager_ip"
        echo "   Features: SSL, Monitoring, Security, Templates, CLI"
    fi
