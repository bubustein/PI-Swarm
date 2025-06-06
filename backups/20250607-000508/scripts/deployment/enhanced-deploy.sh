#!/bin/bash

# Enhanced Interactive Pi-Swarm Deployment
# Uses enhanced Pi discovery with network scanning and manual fallback
set -euo pipefail

# Initialize alert variables early to prevent unbound variable errors
ALERT_EMAIL=""
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""
WHATSAPP_PHONE_ID=""
WHATSAPP_TOKEN=""
WHATSAPP_RECIPIENT=""

echo "🚀 Enhanced Pi-Swarm Interactive Deployment"
echo "============================================"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

# Source functions
source lib/source_functions.sh
source_functions

# Source Python integration functions if available
if [[ -f "lib/python_integration.sh" ]]; then
    source lib/python_integration.sh
    echo "🐍 Enhanced Python modules loaded"
    PYTHON_ENHANCED=true
    
    # Test Python integration capabilities
    if test_python_integration; then
        echo "🎉 Full Python integration available"
    else
        echo "🔧 Using Python integration with Bash fallbacks"
    fi
else
    PYTHON_ENHANCED=false
fi

# Initialize variables to prevent unbound variable errors
ALERT_EMAIL=""
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""
SSL_DOMAIN=""

echo "🎯 This deployment method provides:"
echo "   • Automatic Pi discovery with network scanning"
echo "   • Interactive configuration with explanations" 
echo "   • Enhanced error handling and recovery"
echo "   • Detailed progress feedback"
echo ""

# Step 1: Enhanced Pi Discovery
echo "🔍 Step 1: Discovering Raspberry Pi devices"
echo "============================================="

if ! discover_pis; then
    log ERROR "Pi discovery failed. Please check your network setup and try again."
    exit 1
fi

echo ""
echo "✅ Pi discovery completed successfully!"
echo "   Found Pi IPs: $PI_IPS"
echo ""

# Step 2: Pre-deployment Validation
echo "🧹 Step 2: Pre-deployment Validation & Cleanup"
echo "==============================================="
echo "This step ensures your Pis are in optimal state for deployment."
echo "It will check connectivity, resources, and clean up if needed."
echo ""

# Ask user if they want to run validation
while true; do
    echo "Would you like to run pre-deployment validation? (Recommended)"
    echo "  • Validates Pi connectivity and resources"
    echo "  • Cleans up old Docker containers and images"
    echo "  • Optimizes system performance"
    echo "  • Ensures network requirements are met"
    echo ""
    read -p "Run pre-deployment validation? (Y/n): " run_validation
    run_validation=${run_validation:-Y}
    
    case ${run_validation,,} in
        y|yes)
            echo "✅ Will run pre-deployment validation"
            RUN_VALIDATION=true
            break
            ;;
        n|no)
            echo "⚠️ Skipping pre-deployment validation (not recommended)"
            RUN_VALIDATION=false
            break
            ;;
        *)
            echo "❌ Please enter Y or N"
            ;;
    esac
done

echo ""

# Step 3: Configuration
echo "🔧 Step 3: Configuration Setup"
echo "==============================="

# Get cluster name
while true; do
    echo "Enter a name for your Pi cluster (e.g., 'home-cluster', 'lab-swarm'):"
    read -p "Cluster name: " CLUSTER_NAME
    if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        break
    else
        echo "❌ Invalid cluster name. Use only letters, numbers, hyphens, and underscores."
    fi
done

# Get username
echo ""
echo "What username do you use to connect to your Raspberry Pis?"
echo "💡 For Ubuntu 24.04.2 LTS: typically 'ubuntu'"
echo "💡 For Raspberry Pi OS: typically 'pi'"
echo "💡 For custom setups: your configured username"
while true; do
    read -p "Username: " USERNAME
    if [[ -n "$USERNAME" ]]; then
        break
    else
        echo "❌ Username cannot be empty."
    fi
done

# SSH Key setup
echo ""
echo "🔑 SSH Key Configuration"
echo "========================"
echo "For secure access, we can set up SSH keys to avoid password prompts."
echo "Choose an option:"
echo "1. Generate new SSH keys (recommended)"
echo "2. Use existing SSH keys"
echo "3. Skip SSH key setup (use passwords)"

while true; do
    read -p "Enter choice (1-3): " ssh_choice
    case $ssh_choice in
        1)
            SSH_KEY_SETUP="generate"
            echo "✅ Will generate new SSH keys"
            break
            ;;
        2)
            SSH_KEY_SETUP="existing"
            echo "✅ Will use existing SSH keys"
            break
            ;;
        3)
            SSH_KEY_SETUP="skip"
            echo "⚠️ Will use password authentication"
            break
            ;;
        *)
            echo "❌ Invalid choice. Please enter 1, 2, or 3."
            ;;
    esac
done

# Password Collection (when SSH keys are skipped or as fallback)
echo ""
if [[ "$SSH_KEY_SETUP" == "skip" ]]; then
    echo "🔐 Password Authentication"
    echo "========================="
    echo "Since you chose to skip SSH keys, you'll need to provide the password for $USERNAME"
    while true; do
        read -sp "Enter password for $USERNAME: " PASSWORD
        echo ""
        if [[ -n "$PASSWORD" ]]; then
            read -sp "Confirm password: " PASSWORD_CONFIRM
            echo ""
            if [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]]; then
                echo "✅ Password confirmed"
                break
            else
                echo "❌ Passwords don't match. Please try again."
            fi
        else
            echo "❌ Password cannot be empty."
        fi
    done
else
    echo "💡 Note: If SSH key setup fails, you may be prompted for passwords during deployment"
    echo "Would you like to provide a fallback password just in case?"
    read -p "Enter fallback password (optional, press Enter to skip): " -s PASSWORD
    echo ""
    if [[ -n "$PASSWORD" ]]; then
        echo "✅ Fallback password saved"
    else
        echo "⚠️ No fallback password set - deployment may prompt you if SSH keys fail"
    fi
fi

# SSL Configuration
echo ""
echo "🔒 SSL/HTTPS Configuration"
echo "=========================="
echo "Enable HTTPS with Let's Encrypt SSL certificates?"
echo "💡 This secures web interfaces but requires a domain name"
while true; do
    read -p "Enable SSL? (y/n): " ssl_choice
    case $ssl_choice in
        [Yy]*)
            ENABLE_LETSENCRYPT="yes"
            echo "Enter your domain name (e.g., cluster.yourdomain.com):"
            read -p "Domain: " SSL_DOMAIN
            if [[ -z "$SSL_DOMAIN" ]]; then
                echo "❌ Domain required for SSL. Disabling SSL."
                ENABLE_LETSENCRYPT="no"
                SSL_DOMAIN=""
            else
                echo "✅ SSL enabled for domain: $SSL_DOMAIN"
            fi
            break
            ;;
        [Nn]*)
            ENABLE_LETSENCRYPT="no"
            SSL_DOMAIN=""
            echo "✅ SSL disabled - using HTTP"
            break
            ;;
        *)
            echo "❌ Please answer y or n."
            ;;
    esac
done

# Monitoring setup
echo ""
echo "📊 Monitoring Configuration"
echo "============================"
echo "Enable advanced monitoring with Grafana dashboards?"
echo "💡 This includes system metrics, Docker stats, and alerting"
while true; do
    read -p "Enable monitoring? (y/n): " monitoring_choice
    case $monitoring_choice in
        [Yy]*)
            ENABLE_MONITORING="yes"
            echo "✅ Advanced monitoring enabled"
            
            # Alert configuration
            echo ""
            echo "🚨 Alert Configuration"
            echo "Choose alert methods (you can enable multiple):"
            echo "1. Email alerts"
            echo "2. Slack notifications" 
            echo "3. Discord notifications"
            echo "4. WhatsApp Business API alerts"
            echo "5. LLM-powered intelligent alerts (AI analysis & auto-remediation)"
            echo "6. No alerts"
            
            ALERT_EMAIL=""
            SLACK_WEBHOOK=""
            DISCORD_WEBHOOK=""
            WHATSAPP_PHONE_ID=""
            WHATSAPP_TOKEN=""
            WHATSAPP_RECIPIENT=""
            LLM_PROVIDER=""
            LLM_API_KEY=""
            LLM_API_ENDPOINT=""
            LLM_MODEL=""
            LLM_AUTO_REMEDIATION=""
            
            while true; do
                read -p "Select alert method (1-6): " alert_choice
                case $alert_choice in
                    1)
                        read -p "Enter email address for alerts: " ALERT_EMAIL
                        echo "✅ Email alerts configured"
                        break
                        ;;
                    2)
                        read -p "Enter Slack webhook URL: " SLACK_WEBHOOK
                        echo "✅ Slack notifications configured"
                        break
                        ;;
                    3)
                        read -p "Enter Discord webhook URL: " DISCORD_WEBHOOK
                        echo "✅ Discord notifications configured"
                        break
                        ;;
                    4)
                        echo "📱 WhatsApp Business API Configuration"
                        echo "💡 You need a WhatsApp Business Account and API access"
                        echo "   Get started at: https://developers.facebook.com/docs/whatsapp"
                        read -p "Enter Phone Number ID: " WHATSAPP_PHONE_ID
                        read -p "Enter Access Token: " WHATSAPP_TOKEN
                        read -p "Enter recipient phone number (with country code, e.g., +1234567890): " WHATSAPP_RECIPIENT
                        if [[ -n "$WHATSAPP_PHONE_ID" && -n "$WHATSAPP_TOKEN" && -n "$WHATSAPP_RECIPIENT" ]]; then
                            echo "✅ WhatsApp alerts configured"
                        else
                            echo "❌ All WhatsApp fields are required"
                            continue
                        fi
                        break
                        ;;
                    5)
                        echo "🤖 LLM-Powered Intelligent Alerts Configuration"
                        echo "💡 AI-powered alert analysis with automated remediation suggestions"
                        echo ""
                        echo "Choose LLM provider:"
                        echo "1. OpenAI (GPT-4/GPT-3.5)"
                        echo "2. Anthropic (Claude)"
                        echo "3. Azure OpenAI"
                        echo "4. Ollama (Local/Private)"
                        
                        read -p "Select provider (1-4): " llm_provider_choice
                        case $llm_provider_choice in
                            1)
                                LLM_PROVIDER="openai"
                                read -p "Enter OpenAI API key: " LLM_API_KEY
                                read -p "Model name (default: gpt-4): " LLM_MODEL
                                LLM_MODEL="${LLM_MODEL:-gpt-4}"
                                ;;
                            2)
                                LLM_PROVIDER="anthropic"
                                read -p "Enter Anthropic API key: " LLM_API_KEY
                                read -p "Model name (default: claude-3-sonnet-20240229): " LLM_MODEL
                                LLM_MODEL="${LLM_MODEL:-claude-3-sonnet-20240229}"
                                ;;
                            3)
                                LLM_PROVIDER="azure"
                                read -p "Enter Azure OpenAI API key: " LLM_API_KEY
                                read -p "Enter Azure endpoint: " LLM_API_ENDPOINT
                                read -p "Deployment name: " LLM_MODEL
                                ;;
                            4)
                                LLM_PROVIDER="ollama"
                                read -p "Ollama endpoint (default: http://localhost:11434): " LLM_API_ENDPOINT
                                LLM_API_ENDPOINT="${LLM_API_ENDPOINT:-http://localhost:11434}"
                                read -p "Model name (default: llama3:8b): " LLM_MODEL
                                LLM_MODEL="${LLM_MODEL:-llama3:8b}"
                                ;;
                            *)
                                echo "❌ Invalid choice"
                                continue
                                ;;
                        esac
                        
                        echo ""
                        read -p "Enable automated remediation for safe commands? (y/n): " auto_remediation
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
                        
                        if [[ -n "$LLM_PROVIDER" && ( -n "$LLM_API_KEY" || "$LLM_PROVIDER" == "ollama" ) ]]; then
                            echo "✅ LLM-powered alerts configured with $LLM_PROVIDER"
                        else
                            echo "❌ LLM configuration incomplete"
                            continue
                        fi
                        break
                        ;;
                    6)
                        echo "✅ No alerts configured"
                        break
                        ;;
                    *)
                        echo "❌ Invalid choice. Please enter 1-6."
                        ;;
                esac
            done
            break
            ;;
        [Nn]*)
            ENABLE_MONITORING="no"
            echo "✅ Basic monitoring only"
            break
            ;;
        *)
            echo "❌ Please answer y or n."
            ;;
    esac
done

# Storage Configuration
echo ""
# Source storage management functions
if [[ -f "$SCRIPT_DIR/lib/storage/storage_management.sh" ]]; then
    source "$SCRIPT_DIR/lib/storage/storage_management.sh"
    configure_storage_interactive
else
    log WARN "Storage management module not found - skipping storage setup"
    STORAGE_SOLUTION="skip"
fi

# Configuration Summary
echo ""
echo "📋 Configuration Summary"
echo "========================"
echo "Cluster Name:     $CLUSTER_NAME"
echo "Pi IPs:           $PI_IPS"
echo "Username:         $USERNAME"
echo "SSH Key Setup:    $SSH_KEY_SETUP"
echo "SSL Enabled:      $ENABLE_LETSENCRYPT"
if [[ "$ENABLE_LETSENCRYPT" == "yes" ]]; then
    echo "SSL Domain:       $SSL_DOMAIN"
fi
echo "Monitoring:       $ENABLE_MONITORING"
echo "Storage Solution: ${STORAGE_SOLUTION:-skip}"
if [[ "${STORAGE_SOLUTION:-skip}" != "skip" ]]; then
    echo "Storage Device:   ${STORAGE_DEVICE:-auto}"
    echo "Shared Storage:   ${SHARED_STORAGE_PATH:-/mnt/shared-storage}"
fi
if [[ -n "$ALERT_EMAIL" ]]; then
    echo "Email Alerts:     $ALERT_EMAIL"
fi
if [[ -n "$SLACK_WEBHOOK" ]]; then
    echo "Slack Alerts:     Configured"
fi
if [[ -n "$DISCORD_WEBHOOK" ]]; then
    echo "Discord Alerts:   Configured"
fi
if [[ -n "$WHATSAPP_PHONE_ID" ]]; then
    echo "WhatsApp Alerts:  Configured (${WHATSAPP_RECIPIENT})"
fi
if [[ -n "$LLM_PROVIDER" ]]; then
    echo "LLM AI Alerts:    Configured ($LLM_PROVIDER - $LLM_MODEL)"
    if [[ "$LLM_AUTO_REMEDIATION" == "true" ]]; then
        echo "Auto-Remediation: Enabled"
    else
        echo "Auto-Remediation: Manual review required"
    fi
fi
echo ""

while true; do
    read -p "Proceed with deployment? (y/n): " proceed
    case $proceed in
        [Yy]*)
            break
            ;;
        [Nn]*)
            echo "Deployment cancelled."
            exit 0
            ;;
        *)
            echo "❌ Please answer y or n."
            ;;
    esac
done

# Export variables for main script
export PI_IPS
export CLUSTER_NAME
export USERNAME
export SSH_KEY_SETUP
export ENABLE_LETSENCRYPT
export SSL_DOMAIN
export ENABLE_MONITORING
export ALERT_EMAIL
export SLACK_WEBHOOK
export DISCORD_WEBHOOK
export STORAGE_SOLUTION
export STORAGE_DEVICE
export SHARED_STORAGE_PATH
export DOCKER_STORAGE_PATH

# Step 3: Run Deployment
echo ""
echo "🚀 Step 3: Starting Pi-Swarm Deployment"
echo "========================================"

log INFO "Starting enhanced interactive deployment with configuration:"
log INFO "  Cluster: $CLUSTER_NAME"
log INFO "  Pis: $PI_IPS"
log INFO "  User: $USERNAME"
log INFO "  SSL: $ENABLE_LETSENCRYPT"
log INFO "  Monitoring: $ENABLE_MONITORING"

# Run the main deployment script with exported environment
# Export configuration variables for the main script
export PI_IPS
export CLUSTER_NAME
export PI_USER="$USERNAME"
export PI_PASS="$PASSWORD"
export USERNAME
export PASSWORD  
export ENABLE_LETSENCRYPT
export ENABLE_MONITORING
export ALERT_EMAIL
export SLACK_WEBHOOK
export DISCORD_WEBHOOK
export WHATSAPP_PHONE_ID
export WHATSAPP_TOKEN
export WHATSAPP_RECIPIENT
export LLM_PROVIDER
export LLM_API_KEY
export LLM_API_ENDPOINT
export LLM_MODEL
export LLM_AUTO_REMEDIATION
export FUNCTIONS_DIR="$SCRIPT_DIR/lib"

# Run pre-deployment validation if requested
if [[ "$RUN_VALIDATION" == "true" ]]; then
    echo ""
    echo "🧹 Running Pre-deployment Validation"
    echo "===================================="
    
    # Source the pre-deployment validation functions
    if [[ -f "$SCRIPT_DIR/../lib/deployment/pre_deployment_validation.sh" ]]; then
        source "$SCRIPT_DIR/../lib/deployment/pre_deployment_validation.sh"
        
        # Convert PI_IPS string to array
        IFS=' ' read -ra pi_array <<< "$PI_IPS"
        
        # Run validation with proper username
        export USERNAME="$USERNAME"
        export USER="$USERNAME"
        
        # Use enhanced validation if Python modules are available
        if [[ "$PYTHON_ENHANCED" == "true" ]]; then
            echo "🐍 Using enhanced Python-based validation..."
            if validate_and_prepare_pi_state_enhanced "${pi_array[@]}"; then
                echo ""
                echo "✅ Enhanced pre-deployment validation completed successfully!"
                echo "   Your Pis are ready for optimal deployment with Python enhancements."
            else
                echo ""
                echo "❌ Enhanced pre-deployment validation failed!"
                echo "   Please address the issues above before proceeding."
                read -p "Continue anyway? (y/N): " force_continue
                force_continue=${force_continue:-N}
                if [[ ! "${force_continue,,}" =~ ^(y|yes)$ ]]; then
                    echo "Deployment cancelled due to validation failures."
                    exit 1
                fi
            fi
        else
            echo "🔧 Using standard validation..."
            if validate_and_prepare_pi_state "${pi_array[@]}"; then
                echo ""
                echo "✅ Pre-deployment validation completed successfully!"
                echo "   Your Pis are ready for optimal deployment."
            else
                echo ""
                echo "❌ Pre-deployment validation failed!"
                echo "   Please address the issues above before proceeding."
                read -p "Continue anyway? (y/N): " force_continue
                force_continue=${force_continue:-N}
                if [[ ! "${force_continue,,}" =~ ^(y|yes)$ ]]; then
                    echo "Deployment cancelled due to validation failures."
                    exit 1
                fi
            fi
        fi
    else
        log "WARN" "Pre-deployment validation script not found, skipping..."
    fi
    echo ""
fi

if cd "$SCRIPT_DIR" && bash core/swarm-cluster.sh; then
    echo ""
    echo "🎉 Enhanced Deployment Completed Successfully!"
    echo "=============================================="
    
    # Show deployment summary
    if command -v deployment_summary >/dev/null 2>&1; then
        deployment_summary
    else
        echo "✅ Your Pi-Swarm cluster is now ready!"
        echo ""
        echo "🌐 Access your services at:"
        first_ip=$(echo "$PI_IPS" | awk '{print $1}')
        echo "   • Portainer (Container Management): http://$first_ip:9000"
        echo "   • Grafana (Monitoring): http://$first_ip:3000"  
        echo "   • Prometheus (Metrics): http://$first_ip:9090"
        echo ""
        echo "📚 For more information, see the documentation in the docs/ directory"
    fi
else
    echo ""
    echo "❌ Deployment failed!"
    echo "====================="
    echo ""
    echo "📋 Troubleshooting steps:"
    echo "1. Check the log file: data/logs/piswarm-$(date +%Y%m%d).log"
    echo "2. Verify Pi connectivity: ping each Pi IP address"
    echo "3. Check SSH access: ssh $USERNAME@<pi-ip>"
    echo "4. Review the troubleshooting guide: docs/TROUBLESHOOTING.md"
    echo ""
    echo "💬 For support, visit: https://github.com/bubustein/PI-Swarm/issues"
    echo "   • docs/TROUBLESHOOTING.md"
    echo "   • docs/FAQ.md" 
    echo "   • GitHub Issues: https://github.com/yourusername/pi-swarm/issues"
    exit 1
fi

exit $deployment_status
