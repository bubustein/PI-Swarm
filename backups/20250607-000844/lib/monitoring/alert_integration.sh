# functions/alert_integration.sh
# External alert integration for Slack, email, and other notification systems

# Configure Slack integration
setup_slack_alerts() {
    local webhook_url="$1"
    local channel="$2"
    local manager_ip="$3"
    
    log "INFO" "Setting up Slack alert integration..."
    
    # Create Slack notification script
    cat > "/tmp/slack-notify.sh" << EOF
#!/bin/bash
# Slack notification script for Pi-Swarm alerts

WEBHOOK_URL="$webhook_url"
CHANNEL="$channel"
HOSTNAME=\$(hostname)
CLUSTER_NAME="Pi-Swarm"

send_slack_message() {
    local message="\$1"
    local color="\$2"
    local title="\$3"
    
    curl -X POST -H 'Content-type: application/json' \\
        --data "{
            \"channel\": \"$channel\",
            \"username\": \"Pi-Swarm Bot\",
            \"icon_emoji\": \":robot_face:\",
            \"attachments\": [{
                \"color\": \"\$color\",
                \"title\": \"\$title\",
                \"text\": \"\$message\",
                \"fields\": [{
                    \"title\": \"Cluster\",
                    \"value\": \"\$CLUSTER_NAME\",
                    \"short\": true
                }, {
                    \"title\": \"Manager Node\",
                    \"value\": \"\$HOSTNAME\",
                    \"short\": true
                }, {
                    \"title\": \"Timestamp\",
                    \"value\": \"\$(date)\",
                    \"short\": false
                }]
            }]
        }" \\
        "\$WEBHOOK_URL"
}

# Alert functions
alert_service_down() {
    local service_name="\$1"
    send_slack_message "🚨 Service \$service_name is down or unhealthy!" "danger" "Service Alert"
}

alert_node_down() {
    local node_name="\$1"
    send_slack_message "🚨 Node \$node_name is unreachable!" "danger" "Node Alert"
}

alert_high_resource_usage() {
    local resource="\$1"
    local usage="\$2"
    local threshold="\$3"
    send_slack_message "⚠️ High \$resource usage: \$usage% (threshold: \$threshold%)" "warning" "Resource Alert"
}

alert_ssl_expiry() {
    local domain="\$1"
    local days="\$2"
    send_slack_message "🔒 SSL certificate for \$domain expires in \$days days!" "warning" "SSL Alert"
}

alert_deployment_success() {
    local service="\$1"
    send_slack_message "✅ Successfully deployed \$service to Pi-Swarm cluster" "good" "Deployment Success"
}

alert_backup_complete() {
    local backup_path="\$1"
    send_slack_message "💾 Cluster backup completed successfully\\nLocation: \$backup_path" "good" "Backup Complete"
}

# Main command handler
case "\$1" in
    "service-down")
        alert_service_down "\$2"
        ;;
    "node-down")
        alert_node_down "\$2"
        ;;
    "high-usage")
        alert_high_resource_usage "\$2" "\$3" "\$4"
        ;;
    "ssl-expiry")
        alert_ssl_expiry "\$2" "\$3"
        ;;
    "deployment")
        alert_deployment_success "\$2"
        ;;
    "backup")
        alert_backup_complete "\$2"
        ;;
    *)
        echo "Usage: \$0 {service-down|node-down|high-usage|ssl-expiry|deployment|backup} [args...]"
        exit 1
        ;;
esac
EOF
    
    # Deploy Slack notification script
    scp "/tmp/slack-notify.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/slack-notify.sh /usr/local/bin/slack-notify && sudo chmod +x /usr/local/bin/slack-notify"
    
    log "INFO" "✅ Slack integration setup complete"
}

# Configure email alerts
setup_email_alerts() {
    local smtp_server="$1"
    local smtp_port="$2"
    local email_from="$3"
    local email_to="$4"
    local smtp_user="$5"
    local smtp_pass="$6"
    local manager_ip="$7"
    
    log "INFO" "Setting up email alert integration..."
    
    # Install mail utilities
    ssh "$USER@$manager_ip" "sudo apt update && sudo apt install -y msmtp msmtp-mta mailutils"
    
    # Create msmtp configuration
    cat > "/tmp/msmtprc" << EOF
# Set default values for all following accounts.
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

# Gmail
account        piswarm
host           $smtp_server
port           $smtp_port
from           $email_from
user           $smtp_user
password       $smtp_pass

# Set a default account
account default : piswarm
EOF
    
    # Deploy mail configuration
    scp "/tmp/msmtprc" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "mv /tmp/msmtprc ~/.msmtprc && chmod 600 ~/.msmtprc"
    
    # Create email notification script
    cat > "/tmp/email-notify.sh" << EOF
#!/bin/bash
# Email notification script for Pi-Swarm alerts

EMAIL_TO="$email_to"
EMAIL_FROM="$email_from"
HOSTNAME=\$(hostname)
CLUSTER_NAME="Pi-Swarm"

send_email() {
    local subject="\$1"
    local message="\$2"
    local priority="\$3"
    
    {
        echo "To: \$EMAIL_TO"
        echo "From: \$EMAIL_FROM"
        echo "Subject: [\$CLUSTER_NAME] \$subject"
        echo "Priority: \$priority"
        echo "Content-Type: text/html; charset=UTF-8"
        echo ""
        echo "<html><body>"
        echo "<h2>Pi-Swarm Cluster Alert</h2>"
        echo "<p><strong>Cluster:</strong> \$CLUSTER_NAME</p>"
        echo "<p><strong>Manager Node:</strong> \$HOSTNAME</p>"
        echo "<p><strong>Timestamp:</strong> \$(date)</p>"
        echo "<hr>"
        echo "<p>\$message</p>"
        echo "</body></html>"
    } | msmtp "\$EMAIL_TO"
}

# Alert functions
alert_service_down() {
    local service_name="\$1"
    send_email "🚨 Service Down: \$service_name" "Service <strong>\$service_name</strong> is down or unhealthy!" "high"
}

alert_node_down() {
    local node_name="\$1"
    send_email "🚨 Node Down: \$node_name" "Node <strong>\$node_name</strong> is unreachable!" "high"
}

alert_high_resource_usage() {
    local resource="\$1"
    local usage="\$2"
    local threshold="\$3"
    send_email "⚠️ High Resource Usage" "High <strong>\$resource</strong> usage: <strong>\$usage%</strong> (threshold: \$threshold%)" "normal"
}

alert_ssl_expiry() {
    local domain="\$1"
    local days="\$2"
    send_email "🔒 SSL Certificate Expiry Warning" "SSL certificate for <strong>\$domain</strong> expires in <strong>\$days days</strong>!" "normal"
}

alert_deployment_success() {
    local service="\$1"
    send_email "✅ Deployment Success" "Successfully deployed <strong>\$service</strong> to Pi-Swarm cluster" "low"
}

# Main command handler
case "\$1" in
    "service-down")
        alert_service_down "\$2"
        ;;
    "node-down")
        alert_node_down "\$2"
        ;;
    "high-usage")
        alert_high_resource_usage "\$2" "\$3" "\$4"
        ;;
    "ssl-expiry")
        alert_ssl_expiry "\$2" "\$3"
        ;;
    "deployment")
        alert_deployment_success "\$2"
        ;;
    *)
        echo "Usage: \$0 {service-down|node-down|high-usage|ssl-expiry|deployment} [args...]"
        exit 1
        ;;
esac
EOF
    
    # Deploy email notification script
    scp "/tmp/email-notify.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/email-notify.sh /usr/local/bin/email-notify && sudo chmod +x /usr/local/bin/email-notify"
    
    log "INFO" "✅ Email integration setup complete"
}

# Setup Discord webhook integration
setup_discord_alerts() {
    local webhook_url="$1"
    local manager_ip="$2"
    
    log "INFO" "Setting up Discord alert integration..."
    
    cat > "/tmp/discord-notify.sh" << EOF
#!/bin/bash
# Discord notification script for Pi-Swarm alerts

WEBHOOK_URL="$webhook_url"
HOSTNAME=\$(hostname)
CLUSTER_NAME="Pi-Swarm"

send_discord_message() {
    local message="\$1"
    local color="\$2"
    local title="\$3"
    
    curl -H "Content-Type: application/json" \\
         -X POST \\
         -d "{
            \"embeds\": [{
                \"title\": \"\$title\",
                \"description\": \"\$message\",
                \"color\": \$color,
                \"fields\": [
                    {\"name\": \"Cluster\", \"value\": \"\$CLUSTER_NAME\", \"inline\": true},
                    {\"name\": \"Manager\", \"value\": \"\$HOSTNAME\", \"inline\": true},
                    {\"name\": \"Time\", \"value\": \"\$(date)\", \"inline\": false}
                ],
                \"thumbnail\": {\"url\": \"https://cdn-icons-png.flaticon.com/512/919/919827.png\"}
            }]
         }" \\
         "\$WEBHOOK_URL"
}

# Alert functions with color codes
alert_service_down() {
    send_discord_message "🚨 Service **\$1** is down or unhealthy!" "15158332" "Service Alert"
}

alert_deployment_success() {
    send_discord_message "✅ Successfully deployed **\$1** to cluster" "3066993" "Deployment Success"
}

# Main handler
case "\$1" in
    "service-down") alert_service_down "\$2" ;;
    "deployment") alert_deployment_success "\$2" ;;
    *) echo "Usage: \$0 {service-down|deployment} [args...]" ;;
esac
EOF
    
    scp "/tmp/discord-notify.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/discord-notify.sh /usr/local/bin/discord-notify && sudo chmod +x /usr/local/bin/discord-notify"
    
    log "INFO" "✅ Discord integration setup complete"
}

# Configure WhatsApp Business API alerts
setup_whatsapp_alerts() {
    local phone_number_id="$1"
    local access_token="$2"
    local recipient_number="$3"
    local manager_ip="$4"
    
    log "INFO" "Setting up WhatsApp alert integration..."
    
    # Create WhatsApp notification script
    cat > "/tmp/whatsapp-notify.sh" << 'EOF'
#!/bin/bash
# WhatsApp Business API notification script for Pi-Swarm alerts

PHONE_NUMBER_ID="$1"
ACCESS_TOKEN="$2"
RECIPIENT_NUMBER="$3"
HOSTNAME=$(hostname)
CLUSTER_NAME="Pi-Swarm"

send_whatsapp_message() {
    local message="$1"
    local template_type="$2"
    
    # Format message with cluster info
    local full_message="🚨 *Pi-Swarm Alert*
    
*Cluster:* $CLUSTER_NAME
*Node:* $HOSTNAME
*Time:* $(date)
*Alert:* $message"
    
    # Send via WhatsApp Business API
    curl -X POST \
        "https://graph.facebook.com/v18.0/$PHONE_NUMBER_ID/messages" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"messaging_product\": \"whatsapp\",
            \"to\": \"$RECIPIENT_NUMBER\",
            \"type\": \"text\",
            \"text\": {
                \"body\": \"$full_message\"
            }
        }" || {
        echo "Failed to send WhatsApp message"
        return 1
    }
}

# Alert functions
alert_service_down() {
    local service="$1"
    send_whatsapp_message "🔴 Service DOWN: $service has stopped responding" "critical"
}

alert_node_down() {
    local node="$1"
    send_whatsapp_message "📴 Node OFFLINE: $node is unreachable" "critical"
}

alert_high_usage() {
    local resource="$1"
    local usage="$2"
    send_whatsapp_message "⚠️ HIGH USAGE: $resource at $usage%" "warning"
}

alert_ssl_expiry() {
    local domain="$1"
    local days="$2"
    send_whatsapp_message "🔒 SSL EXPIRY: Certificate for $domain expires in $days days" "warning"
}

alert_deployment_success() {
    local version="$1"
    send_whatsapp_message "✅ DEPLOYMENT: Successfully deployed version $version" "info"
}

alert_backup_complete() {
    local backup_size="$1"
    send_whatsapp_message "💾 BACKUP: Cluster backup completed ($backup_size)" "info"
}

# Main script execution
case "$4" in
    "service-down")
        alert_service_down "$5"
        ;;
    "node-down")
        alert_node_down "$5"
        ;;
    "high-usage")
        alert_high_usage "$5" "$6"
        ;;
    "ssl-expiry")
        alert_ssl_expiry "$5" "$6"
        ;;
    "deployment")
        alert_deployment_success "$5"
        ;;
    "backup")
        alert_backup_complete "$5"
        ;;
    *)
        echo "Usage: $0 phone_number_id access_token recipient_number {service-down|node-down|high-usage|ssl-expiry|deployment|backup} [args...]"
        exit 1
        ;;
esac
EOF
    
    # Deploy WhatsApp notification script
    scp "/tmp/whatsapp-notify.sh" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "sudo mv /tmp/whatsapp-notify.sh /usr/local/bin/whatsapp-notify && sudo chmod +x /usr/local/bin/whatsapp-notify"
    
    log "INFO" "✅ WhatsApp integration setup complete"
    log "INFO" "📱 WhatsApp alerts will be sent to: $recipient_number"
}

# Setup comprehensive alerting with Alertmanager
setup_alertmanager_integration() {
    local manager_ip="$1"
    local slack_webhook="$2"
    local email_to="$3"
    
    log "INFO" "Setting up Alertmanager with external integrations..."
    
    # Create enhanced Alertmanager configuration
    cat > "/tmp/alertmanager.yml" << EOF
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'piswarm@localhost'
  slack_api_url: '$slack_webhook'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: 'critical-alerts'
  - match:
      severity: warning
    receiver: 'warning-alerts'

receivers:
- name: 'web.hook'
  webhook_configs:
  - url: 'http://localhost:5001/'

- name: 'critical-alerts'
  slack_configs:
  - channel: '#piswarm-alerts'
    title: '🚨 Critical Alert: {{ .GroupLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
    color: 'danger'
  email_configs:
  - to: '$email_to'
    subject: '[CRITICAL] Pi-Swarm Alert: {{ .GroupLabels.alertname }}'
    html: |
      <h3>Critical Alert</h3>
      <p><strong>Alert:</strong> {{ .GroupLabels.alertname }}</p>
      {{ range .Alerts }}
      <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
      <p><strong>Description:</strong> {{ .Annotations.description }}</p>
      {{ end }}

- name: 'warning-alerts'
  slack_configs:
  - channel: '#piswarm-warnings'
    title: '⚠️ Warning: {{ .GroupLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
    color: 'warning'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
    
    # Deploy Alertmanager configuration
    scp "/tmp/alertmanager.yml" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "mkdir -p ~/alertmanager && mv /tmp/alertmanager.yml ~/alertmanager/"
    
    log "INFO" "✅ Alertmanager integration setup complete"
}

# Test all notification systems
test_alert_integrations() {
    local manager_ip="$1"
    
    log "INFO" "Testing all alert integrations..."
    
    # Test Slack
    if ssh "$USER@$manager_ip" "command -v slack-notify &> /dev/null"; then
        ssh "$USER@$manager_ip" "slack-notify deployment 'Alert Integration Test'"
        log "INFO" "✅ Slack test sent"
    fi
    
    # Test Email
    if ssh "$USER@$manager_ip" "command -v email-notify &> /dev/null"; then
        ssh "$USER@$manager_ip" "email-notify deployment 'Alert Integration Test'"
        log "INFO" "✅ Email test sent"
    fi
    
    # Test Discord
    if ssh "$USER@$manager_ip" "command -v discord-notify &> /dev/null"; then
        ssh "$USER@$manager_ip" "discord-notify deployment 'Alert Integration Test'"
        log "INFO" "✅ Discord test sent"
    fi
    
    # Test WhatsApp
    if ssh "$USER@$manager_ip" "command -v whatsapp-notify &> /dev/null"; then
        ssh "$USER@$manager_ip" "whatsapp-notify deployment 'Alert Integration Test'"
        log "INFO" "✅ WhatsApp test sent"
    fi
    
    log "INFO" "✅ All alert integration tests complete"
}

# Export all alert integration functions
export -f setup_slack_alerts
export -f setup_email_alerts  
export -f setup_discord_alerts
export -f setup_whatsapp_alerts
export -f setup_alertmanager_integration
export -f test_alert_integrations
