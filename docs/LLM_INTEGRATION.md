# LLM Integration for Pi-Swarm

## Overview

The Pi-Swarm project now includes LLM-powered intelligent alert monitoring and automated remediation capabilities. This system leverages artificial intelligence to provide intelligent analysis of system alerts, root cause analysis, and automated remediation suggestions.

## Features

### 🤖 Intelligent Alert Analysis
- **Root Cause Analysis**: AI analyzes alerts to identify likely causes
- **Severity Assessment**: Automatic priority classification (Critical/High/Medium/Low)
- **Context-Aware**: Considers current system state and cluster configuration
- **Multi-Alert Correlation**: Links related alerts for comprehensive analysis

### 🔧 Automated Remediation
- **Safe Command Execution**: AI suggests and optionally executes safe remediation commands
- **Risk Assessment**: Commands are validated for safety before execution
- **Manual Override**: All automation can be disabled for manual review
- **Command Logging**: All executed commands are logged for audit trails

### 🔒 Privacy & Security
- **Local LLM Support**: Use Ollama for on-premise AI processing
- **Secure API Key Storage**: Encrypted storage of API credentials
- **No Data Leakage**: System information is only sent when alerts occur
- **Audit Logging**: Complete audit trail of all AI interactions

## Supported LLM Providers

### 1. OpenAI (GPT-4/GPT-3.5)
```bash
Provider: openai
Models: gpt-4, gpt-3.5-turbo, gpt-4-turbo
API Key: Required (sk-...)
Endpoint: https://api.openai.com/v1/chat/completions
```

### 2. Anthropic (Claude)
```bash
Provider: anthropic  
Models: claude-3-opus, claude-3-sonnet, claude-3-haiku
API Key: Required (sk-ant-...)
Endpoint: https://api.anthropic.com/v1/messages
```

### 3. Azure OpenAI
```bash
Provider: azure
Models: Your deployment name
API Key: Required (Azure key)
Endpoint: https://your-resource.openai.azure.com
```

### 4. Ollama (Local/Private)
```bash
Provider: ollama
Models: llama3:8b, llama3:70b, codellama, mistral
API Key: Not required
Endpoint: http://localhost:11434 (default)
```

## Setup Instructions

### Method 1: Enhanced Deployment Script (Recommended)

1. **Run Enhanced Deployment**:
   ```bash
   cd /path/to/PI-Swarm
   ./scripts/deployment/enhanced-deploy.sh
   ```

2. **Select LLM Option**:
   - When prompted for alert configuration, select option 5: "LLM-powered intelligent alerts"
   - Choose your preferred provider (1-4)
   - Enter API credentials (if required)
   - Configure automated remediation settings

3. **Complete Deployment**:
   - The system will automatically configure LLM integration
   - Test alerts will be sent to verify functionality

### Method 2: Manual Configuration

1. **Configure Environment**:
   ```bash
   export LLM_PROVIDER="openai"  # or anthropic, azure, ollama
   export LLM_API_KEY="your-api-key"
   export LLM_MODEL="gpt-4"
   export LLM_AUTO_REMEDIATION="false"  # or "true" for automation
   ```

2. **Run Main Deployment**:
   ```bash
   cd /path/to/PI-Swarm
   bash core/swarm-cluster.sh
   ```

3. **Test Integration**:
   ```bash
   ./scripts/testing/test-llm-integration.sh
   ```

## Configuration Options

### Basic Configuration

```bash
# Required settings
LLM_PROVIDER="openai"              # Provider: openai, anthropic, azure, ollama
LLM_API_KEY="sk-your-api-key"      # API key (not needed for Ollama)
LLM_MODEL="gpt-4"                  # Model name
LLM_AUTO_REMEDIATION="false"       # Enable/disable automated fixes

# Optional settings
LLM_API_ENDPOINT="custom-endpoint" # Custom API endpoint
CLUSTER_NAME="my-cluster"          # Cluster identifier
```

### Provider-Specific Configuration

#### OpenAI
```bash
LLM_PROVIDER="openai"
LLM_API_KEY="sk-proj-..."
LLM_MODEL="gpt-4"  # or gpt-3.5-turbo, gpt-4-turbo
```

#### Anthropic Claude
```bash
LLM_PROVIDER="anthropic"
LLM_API_KEY="sk-ant-..."
LLM_MODEL="claude-3-sonnet-20240229"
```

#### Azure OpenAI
```bash
LLM_PROVIDER="azure"
LLM_API_KEY="your-azure-key"
LLM_API_ENDPOINT="https://your-resource.openai.azure.com"
LLM_MODEL="your-deployment-name"
```

#### Ollama (Local)
```bash
LLM_PROVIDER="ollama"
LLM_API_ENDPOINT="http://localhost:11434"
LLM_MODEL="llama3:8b"  # or llama3:70b, codellama, mistral
```

## Usage Examples

### Trigger LLM Analysis

1. **Test Alert**:
   ```bash
   /usr/local/bin/llm-alert-processor openai sk-key "" gpt-4 my-cluster test
   ```

2. **Service Down Alert**:
   ```bash
   /usr/local/bin/llm-alert-processor openai sk-key "" gpt-4 my-cluster service-down nginx
   ```

3. **High Usage Alert**:
   ```bash
   /usr/local/bin/llm-alert-processor openai sk-key "" gpt-4 my-cluster high-usage CPU 95
   ```

### Monitor LLM Analysis

```bash
# View analysis logs
tail -f /var/log/piswarm-llm-analysis.log

# View system logs
journalctl -u piswarm-llm -f
```

## Alert Types

The LLM system can analyze and provide remediation for:

1. **Service Down**: Container or service failures
2. **Node Down**: Unresponsive cluster nodes
3. **High Usage**: CPU, memory, or disk alerts
4. **SSL Expiry**: Certificate expiration warnings
5. **Deployment Issues**: Failed deployments or updates
6. **Network Issues**: Connectivity problems
7. **Security Alerts**: Unauthorized access attempts
8. **Backup Failures**: Backup and recovery issues

## Sample LLM Response

```
🧠 LLM Analysis Results:
========================

## Root Cause Analysis
The nginx service failure is likely caused by insufficient memory allocation or 
port conflicts. Container logs show OOMKilled status.

## Severity Assessment  
**HIGH** - Critical web service affecting user access

## Immediate Actions
1. Check container resource limits
2. Verify port availability
3. Review recent configuration changes
4. Check node memory usage

## Remediation Commands
```bash
# Safe to execute automatically
docker service update --limit-memory 512M nginx-service
docker service logs nginx-service --tail 50

# Requires manual review
docker node ls
systemctl restart docker
```

## Prevention
- Implement memory monitoring alerts
- Set appropriate resource limits
- Regular health checks for critical services
```

## Integration with Existing Alerts

The LLM system integrates seamlessly with existing alert channels:

### WhatsApp Integration
```bash
# LLM analysis summary sent to WhatsApp
whatsapp-notify "$PHONE_ID" "$TOKEN" "$RECIPIENT" "llm-analysis" "🤖 AI Analysis: Service nginx is down due to memory limits. Recommended: increase memory allocation."
```

### Slack Integration
```bash
# Full LLM analysis sent to Slack
slack-notify "llm-analysis" "🤖 LLM Alert Analysis for service-down: [full analysis text]"
```

### Email Integration
```bash
# LLM analysis included in email alerts
send-email "AI Analysis: Critical Alert" "LLM has analyzed the alert and suggests..."
```

## Automated Remediation

### Safe Commands Only
The system only executes commands deemed safe by the LLM:
- Service restarts
- Configuration updates
- Log collection
- Status checks

### Excluded Commands
Dangerous commands are never executed automatically:
- `rm`, `delete`, `destroy`
- `kill -9`
- System shutdowns
- Data manipulation

### Manual Override
```bash
# Disable automation globally
export LLM_AUTO_REMEDIATION="false"

# Enable for specific severity levels
export LLM_AUTO_REMEDIATION="low,medium"  # Not high/critical
```

## Local LLM Setup (Ollama)

For privacy-focused deployments, use Ollama for local AI processing:

### Installation
```bash
# Automatic setup during deployment
./scripts/deployment/enhanced-deploy.sh
# Select option 5 -> option 4 (Ollama)

# Manual setup
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull llama3:8b
```

### Benefits
- **Privacy**: No data leaves your network
- **Cost**: No API usage fees
- **Latency**: Faster response times
- **Availability**: Works without internet

### Considerations
- Requires more local compute resources
- May have slower processing than cloud models
- Limited to available open-source models

## Troubleshooting

### Common Issues

1. **API Key Invalid**:
   ```bash
   # Check API key format
   echo $LLM_API_KEY | wc -c  # Should be appropriate length
   
   # Test API connectivity
   curl -H "Authorization: Bearer $LLM_API_KEY" https://api.openai.com/v1/models
   ```

2. **Ollama Not Responding**:
   ```bash
   # Check Ollama service
   systemctl status ollama
   
   # Test endpoint
   curl http://localhost:11434/api/tags
   
   # Restart service
   systemctl restart ollama
   ```

3. **No LLM Responses**:
   ```bash
   # Check processor script
   ls -la /usr/local/bin/llm-alert-processor
   
   # Check permissions
   cat /etc/piswarm/llm-config.env
   
   # Test manually
   /usr/local/bin/llm-alert-processor test
   ```

4. **High API Costs**:
   ```bash
   # Switch to Ollama for cost savings
   export LLM_PROVIDER="ollama"
   
   # Or use smaller model
   export LLM_MODEL="gpt-3.5-turbo"
   ```

### Log Analysis

```bash
# LLM-specific logs
tail -f /var/log/piswarm-llm-analysis.log

# System integration logs  
grep "LLM" /var/log/piswarm-*.log

# Docker service logs
docker service logs piswarm-monitoring
```

## Security Considerations

### API Key Security
- API keys are stored in `/etc/piswarm/llm-config.env` with 600 permissions
- Keys are never logged in plain text
- Environment variables are cleared after use

### Data Privacy
- Only alert metadata and system status are sent to LLM providers
- No sensitive data (passwords, keys, personal info) is transmitted
- Use Ollama for complete data privacy

### Network Security
- All API communications use HTTPS/TLS encryption
- Local Ollama deployment eliminates external data transmission
- API endpoints are validated before use

## Performance Optimization

### Response Time
- Average cloud LLM response: 2-5 seconds
- Local Ollama response: 5-15 seconds (depending on hardware)
- Caching can be implemented for similar alerts

### Resource Usage
- Cloud providers: Minimal local resource usage
- Ollama: Requires 4-8GB RAM for 8B parameter models
- CPU usage spikes during analysis but returns to baseline

### Cost Management
- OpenAI GPT-4: ~$0.01-0.03 per alert analysis
- Anthropic Claude: ~$0.008-0.024 per alert
- Azure OpenAI: Variable based on deployment
- Ollama: No per-use costs after setup

## Advanced Configuration

### Custom Prompts
Modify the analysis prompt in `/usr/local/bin/llm-alert-processor`:

```bash
# Edit the prompt section
local prompt="You are an expert DevOps engineer managing a Raspberry Pi Docker Swarm cluster.
[Custom instructions here]
..."
```

### Integration Webhooks
Set up custom webhooks for LLM analysis results:

```bash
# Add to alert processor
curl -X POST "$CUSTOM_WEBHOOK" -d "{\"analysis\": \"$llm_response\"}"
```

### Multiple Model Support
Configure different models for different alert types:

```bash
# High-priority alerts use GPT-4
if [[ "$alert_type" == "service-down" ]]; then
    MODEL_NAME="gpt-4"
else
    MODEL_NAME="gpt-3.5-turbo"
fi
```

## Future Enhancements

### Planned Features
- **Learning Mode**: AI learns from historical alerts and resolutions
- **Predictive Analysis**: Forecast potential issues before they occur
- **Custom Model Training**: Train models on your specific infrastructure
- **Multi-Language Support**: Analysis in multiple languages
- **Integration APIs**: REST API for external LLM integration

### Community Contributions
- Submit LLM provider integrations
- Share custom prompts and configurations
- Contribute remediation command libraries
- Report issues and improvements

## Support

### Documentation
- Implementation Guide: `docs/IMPLEMENTATION_SUMMARY.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`
- API Reference: `docs/API_REFERENCE.md`

### Testing
```bash
# Run comprehensive LLM tests
./scripts/testing/test-llm-integration.sh

# Test specific provider
./scripts/testing/test-llm-integration.sh 192.168.1.100 openai gpt-4 sk-key

# Test local LLM
./scripts/testing/test-llm-integration.sh 192.168.1.100 ollama llama3:8b
```

### Community
- GitHub Issues: [Report bugs and feature requests]
- Discussions: [Ask questions and share configurations]
- Wiki: [Community documentation and examples]

---

**Note**: This LLM integration is designed to augment human decision-making, not replace it. Always review AI suggestions before implementing changes in production environments.
