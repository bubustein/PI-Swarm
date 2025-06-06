#!/bin/bash
# LLM-powered alert monitoring and automated remediation for Pi-Swarm
# Supports OpenAI GPT, Anthropic Claude, and other API-compatible LLMs

# LLM API Configuration
setup_llm_alerts() {
    local api_provider="$1"       # openai, anthropic, azure, ollama, etc.
    local api_key="$2"           # API key for the service
    local api_endpoint="$3"      # Custom endpoint (optional for local LLMs)
    local model_name="$4"        # Model to use (gpt-4, claude-3, etc.)
    local manager_ip="$5"        # Pi manager node IP
    
    log "INFO" "Setting up LLM-powered alert integration with $api_provider..."
    
    # Create LLM alert processing script
    cat > "/tmp/llm-alert-processor.sh" << 'EOF'
#!/bin/bash
# LLM-powered alert processor for Pi-Swarm

# Configuration (passed as environment variables)
API_PROVIDER="${API_PROVIDER:-openai}"
API_KEY="${API_KEY}"
API_ENDPOINT="${API_ENDPOINT}"
MODEL_NAME="${MODEL_NAME:-gpt-4}"
CLUSTER_NAME="${CLUSTER_NAME:-pi-swarm}"
AUTO_REMEDIATION="${AUTO_REMEDIATION:-false}"

# System information gathering
get_system_info() {
    local info=""
    info+="\n## Cluster Status\n"
    info+="- Node: $(hostname)\n"
    info+="- Time: $(date)\n"
    info+="- Uptime: $(uptime)\n"
    info+="- Load: $(cat /proc/loadavg)\n"
    info+="- Memory: $(free -h | grep '^Mem')\n"
    info+="- Disk: $(df -h / | tail -1)\n"
    
    # Docker status
    if command -v docker >/dev/null 2>&1; then
        info+="\n## Docker Status\n"
        info+="- Services: $(docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}' 2>/dev/null || echo 'Not in swarm mode')\n"
        info+="- Containers: $(docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null)\n"
    fi
    
    echo -e "$info"
}

# Send alert to LLM for analysis and remediation suggestions
analyze_alert_with_llm() {
    local alert_type="$1"
    local alert_message="$2"
    local system_info="$3"
    
    # Construct prompt for LLM
    local prompt="You are an expert DevOps engineer managing a Raspberry Pi Docker Swarm cluster. 

ALERT DETAILS:
- Type: $alert_type
- Message: $alert_message
- Cluster: $CLUSTER_NAME

CURRENT SYSTEM STATE:
$system_info

Please analyze this alert and provide:
1. **Root Cause Analysis**: What likely caused this issue?
2. **Severity Assessment**: Critical/High/Medium/Low and why
3. **Immediate Actions**: Steps to take right now
4. **Remediation Commands**: Specific bash commands to fix the issue (if safe to automate)
5. **Prevention**: How to prevent this in the future

Format your response as structured text with clear sections. For any commands you suggest, explain what they do and their risk level."

    local response=""
    
    # Call appropriate LLM API
    case "$API_PROVIDER" in
        "openai")
            response=$(call_openai_api "$prompt")
            ;;
        "anthropic")
            response=$(call_anthropic_api "$prompt")
            ;;
        "azure")
            response=$(call_azure_api "$prompt")
            ;;
        "ollama")
            response=$(call_ollama_api "$prompt")
            ;;
        *)
            response="Error: Unsupported API provider: $API_PROVIDER"
            ;;
    esac
    
    echo "$response"
}

# OpenAI API call
call_openai_api() {
    local prompt="$1"
    
    curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": \"You are an expert DevOps engineer specializing in Raspberry Pi clusters and Docker Swarm.\"
                },
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ],
            \"max_tokens\": 1500,
            \"temperature\": 0.1
        }" | jq -r '.choices[0].message.content // "API Error: " + .error.message'
}

# Anthropic Claude API call
call_anthropic_api() {
    local prompt="$1"
    
    curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"max_tokens\": 1500,
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ]
        }" | jq -r '.content[0].text // "API Error: " + .error.message'
}

# Azure OpenAI API call
call_azure_api() {
    local prompt="$1"
    local azure_endpoint="${API_ENDPOINT}/openai/deployments/$MODEL_NAME/chat/completions?api-version=2024-02-15-preview"
    
    curl -s -X POST "$azure_endpoint" \
        -H "api-key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": \"You are an expert DevOps engineer specializing in Raspberry Pi clusters.\"
                },
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ],
            \"max_tokens\": 1500,
            \"temperature\": 0.1
        }" | jq -r '.choices[0].message.content // "API Error: " + .error.message'
}

# Ollama (local LLM) API call
call_ollama_api() {
    local prompt="$1"
    local ollama_endpoint="${API_ENDPOINT:-http://localhost:11434}/api/generate"
    
    curl -s -X POST "$ollama_endpoint" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"prompt\": \"$prompt\",
            \"stream\": false
        }" | jq -r '.response // "API Error: Could not reach Ollama"'
}

# Extract and execute safe remediation commands
execute_safe_remediation() {
    local llm_response="$1"
    
    if [[ "$AUTO_REMEDIATION" != "true" ]]; then
        echo "Auto-remediation disabled. Manual review required."
        return 0
    fi
    
    # Extract commands marked as safe by the LLM
    local safe_commands=$(echo "$llm_response" | grep -A5 -B1 -i "safe.*command\|low.*risk" | grep -E "^\s*(docker|systemctl|sudo.*restart)" | head -3)
    
    if [[ -n "$safe_commands" ]]; then
        echo "Executing safe remediation commands:"
        echo "$safe_commands"
        
        # Execute each command with safety checks
        while IFS= read -r cmd; do
            if [[ -n "$cmd" && ! "$cmd" =~ (rm|delete|destroy|kill.*-9) ]]; then
                echo "Executing: $cmd"
                eval "$cmd" || echo "Command failed: $cmd"
                sleep 2
            fi
        done <<< "$safe_commands"
    else
        echo "No safe auto-remediation commands identified."
    fi
}

# Log LLM analysis
log_llm_analysis() {
    local alert_type="$1"
    local llm_response="$2"
    local log_file="/var/log/piswarm-llm-analysis.log"
    
    {
        echo "=== LLM Alert Analysis - $(date) ==="
        echo "Alert Type: $alert_type"
        echo "Cluster: $CLUSTER_NAME"
        echo "Node: $(hostname)"
        echo ""
        echo "$llm_response"
        echo ""
        echo "=============================================="
        echo ""
    } >> "$log_file"
}

# Main alert processing function
process_alert() {
    local alert_type="$1"
    local alert_message="$2"
    
    echo "🤖 Processing alert with LLM: $alert_type"
    
    # Gather system information
    local system_info=$(get_system_info)
    
    # Get LLM analysis
    local llm_response=$(analyze_alert_with_llm "$alert_type" "$alert_message" "$system_info")
    
    # Log the analysis
    log_llm_analysis "$alert_type" "$llm_response"
    
    # Display analysis
    echo "🧠 LLM Analysis Results:"
    echo "========================"
    echo "$llm_response"
    echo ""
    
    # Execute safe remediation if enabled
    if [[ "$AUTO_REMEDIATION" == "true" ]]; then
        echo "🔧 Attempting automated remediation..."
        execute_safe_remediation "$llm_response"
    fi
    
    # Send results to other alert channels if configured
    if command -v slack-notify >/dev/null 2>&1; then
        echo "📱 Sending LLM analysis to Slack..."
        slack-notify "llm-analysis" "🤖 LLM Alert Analysis for $alert_type: $llm_response"
    fi
    
    if command -v whatsapp-notify >/dev/null 2>&1; then
        echo "📱 Sending LLM summary to WhatsApp..."
        local summary=$(echo "$llm_response" | head -5 | tail -3)
        whatsapp-notify "$WHATSAPP_PHONE_ID" "$WHATSAPP_TOKEN" "$WHATSAPP_RECIPIENT" "llm-analysis" "🤖 AI Analysis: $summary"
    fi
}

# Alert type handlers
alert_service_down() {
    local service="$1"
    process_alert "service-down" "Service $service has stopped responding"
}

alert_node_down() {
    local node="$1"
    process_alert "node-down" "Node $node is unreachable"
}

alert_high_usage() {
    local resource="$1"
    local usage="$2"
    process_alert "high-usage" "High $resource usage: $usage%"
}

alert_ssl_expiry() {
    local domain="$1"
    local days="$2"
    process_alert "ssl-expiry" "SSL certificate for $domain expires in $days days"
}

alert_deployment_issue() {
    local error="$1"
    process_alert "deployment-failed" "Deployment failed: $error"
}

# Main script execution
case "$6" in
    "service-down")
        alert_service_down "$7"
        ;;
    "node-down")
        alert_node_down "$7"
        ;;
    "high-usage")
        alert_high_usage "$7" "$8"
        ;;
    "ssl-expiry")
        alert_ssl_expiry "$7" "$8"
        ;;
    "deployment-failed")
        alert_deployment_issue "$7"
        ;;
    "test")
        process_alert "test" "Testing LLM integration with sample alert"
        ;;
    *)
        echo "Usage: $0 api_provider api_key api_endpoint model_name cluster_name {service-down|node-down|high-usage|ssl-expiry|deployment-failed|test} [args...]"
        exit 1
        ;;
esac
EOF
    
    # Deploy LLM alert processor
    scp "/tmp/llm-alert-processor.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/llm-alert-processor.sh /usr/local/bin/llm-alert-processor && sudo chmod +x /usr/local/bin/llm-alert-processor"
    
    # Create environment configuration
    cat > "/tmp/llm-config.env" << EOF
API_PROVIDER=$api_provider
API_KEY=$api_key
API_ENDPOINT=$api_endpoint
MODEL_NAME=$model_name
CLUSTER_NAME=$CLUSTER_NAME
AUTO_REMEDIATION=${AUTO_REMEDIATION:-false}
EOF
    
    scp "/tmp/llm-config.env" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/llm-config.env /etc/piswarm/llm-config.env && sudo chmod 600 /etc/piswarm/llm-config.env"
    
    log "INFO" "✅ LLM alert integration setup complete"
    log "INFO" "🤖 AI-powered monitoring enabled with $api_provider ($model_name)"
}

# Setup Ollama for local LLM processing (privacy-focused option)
setup_local_llm() {
    local manager_ip="$1"
    local model_name="${2:-llama3:8b}"
    
    log "INFO" "Setting up local LLM (Ollama) for private AI processing..."
    
    # Install Ollama on the manager node
    ssh "$USER@$manager_ip" << EOF
        # Download and install Ollama
        curl -fsSL https://ollama.ai/install.sh | sh
        
        # Start Ollama service
        sudo systemctl enable ollama
        sudo systemctl start ollama
        
        # Pull the specified model
        ollama pull $model_name
        
        # Create systemd service for Ollama
        sudo tee /etc/systemd/system/ollama-api.service > /dev/null << SERVICE
[Unit]
Description=Ollama API Server
After=network.target

[Service]
Type=simple
User=ollama
Environment=OLLAMA_HOST=0.0.0.0:11434
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

        sudo systemctl daemon-reload
        sudo systemctl enable ollama-api
        sudo systemctl start ollama-api
EOF
    
    log "INFO" "✅ Local LLM (Ollama) setup complete"
    log "INFO" "🔒 Privacy-focused AI processing available at http://$manager_ip:11434"
}

# Test LLM integration
test_llm_integration() {
    local manager_ip="$1"
    
    log "INFO" "Testing LLM alert integration..."
    
    # Source the environment config and test
    ssh "$USER@$manager_ip" << 'EOF'
        source /etc/piswarm/llm-config.env
        export API_PROVIDER API_KEY API_ENDPOINT MODEL_NAME CLUSTER_NAME AUTO_REMEDIATION
        
        echo "Testing LLM integration with sample alert..."
        /usr/local/bin/llm-alert-processor "$API_PROVIDER" "$API_KEY" "$API_ENDPOINT" "$MODEL_NAME" "$CLUSTER_NAME" "test"
EOF
    
    log "INFO" "✅ LLM integration test complete"
}

# Export functions
export -f setup_llm_alerts
export -f setup_local_llm
export -f test_llm_integration
