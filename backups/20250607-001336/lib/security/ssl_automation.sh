#!/bin/bash

# SSL Certificate Automation for Pi-Swarm
# Handles SSL certificate generation and Let's Encrypt automation

# Function to set up SSL certificates for the cluster
setup_ssl_certificates() {
    local manager_ip="${1:-${MANAGER_IP:-}}"
    local ssh_user="${2:-${NODES_DEFAULT_USER:-luser}}"
    local ssh_pass="${3:-${NODES_DEFAULT_PASS:-}}"
    
    if [[ -z "$manager_ip" ]]; then
        log "WARN" "No manager IP provided for SSL setup"
        return 1
    fi
    
    log "INFO" "Setting up SSL certificates for manager: $manager_ip"
    
    # Create SSL directory on manager
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "
        sudo mkdir -p /etc/ssl/piswarm
        sudo chmod 755 /etc/ssl/piswarm
    " || return 1
    
    # Generate self-signed certificates as fallback
    generate_wildcard_ssl "$manager_ip" "$ssh_user" "$ssh_pass"
}

# Generate wildcard SSL certificate
generate_wildcard_ssl() {
    local manager_ip="$1"
    local ssh_user="${2:-luser}"
    local ssh_pass="${3:-}"
    
    log "INFO" "Generating wildcard SSL certificate for $manager_ip"
    
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "
        # Generate private key
        sudo openssl genrsa -out /etc/ssl/piswarm/wildcard.key 2048
        
        # Generate certificate signing request
        sudo openssl req -new -key /etc/ssl/piswarm/wildcard.key -out /etc/ssl/piswarm/wildcard.csr -subj '/CN=*.piswarm.local/O=PiSwarm/C=US'
        
        # Generate self-signed certificate
        sudo openssl x509 -req -in /etc/ssl/piswarm/wildcard.csr -signkey /etc/ssl/piswarm/wildcard.key -out /etc/ssl/piswarm/wildcard.crt -days 365
        
        # Set proper permissions
        sudo chmod 600 /etc/ssl/piswarm/*.key
        sudo chmod 644 /etc/ssl/piswarm/*.crt
        
        echo 'SSL certificates generated successfully'
    "
}

# setup_letsencrypt_ssl: Obtain and deploy Let's Encrypt SSL certificate
setup_letsencrypt_ssl() {
    local domain="${1:-}"
    local email="${2:-}"
    local manager_ip="${3:-${MANAGER_IP:-}}"
    local ssh_user="${4:-${NODES_DEFAULT_USER:-luser}}"
    local ssh_pass="${5:-${NODES_DEFAULT_PASS:-}}"
    
    # Validate required parameters
    if [[ -z "$domain" || -z "$email" || -z "$manager_ip" ]]; then
        log "WARN" "Let's Encrypt SSL requires domain, email, and manager IP. Skipping."
        return 1
    fi
    
    log "INFO" "Requesting Let's Encrypt SSL certificate for $domain on $manager_ip"
    
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "
        # Install certbot if not present
        if ! command -v certbot >/dev/null 2>&1; then
            sudo apt-get update -qq
            sudo apt-get install -y certbot
        fi
        
        # Request certificate
        sudo certbot certonly --standalone --non-interactive --agree-tos --email '$email' -d '$domain' || {
            echo 'Let\'s Encrypt certificate request failed'
            return 1
        }
        
        # Deploy certificate
        sudo mkdir -p /etc/ssl/piswarm
        sudo ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/ssl/piswarm/${domain}.crt
        sudo ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/ssl/piswarm/${domain}.key
        
        echo 'Let\'s Encrypt certificate deployed successfully'
    " || {
        log "WARN" "Let's Encrypt setup failed, falling back to self-signed certificates"
        generate_wildcard_ssl "$manager_ip" "$ssh_user" "$ssh_pass"
        return 1
    }
    
    log "INFO" "Let's Encrypt certificate deployed successfully"
}

# Set up SSL monitoring and auto-renewal
setup_ssl_monitoring() {
    local manager_ip="${1:-${MANAGER_IP:-}}"
    local ssh_user="${2:-${NODES_DEFAULT_USER:-luser}}"
    local ssh_pass="${3:-${NODES_DEFAULT_PASS:-}}"
    
    if [[ -z "$manager_ip" ]]; then
        log "WARN" "No manager IP provided for SSL monitoring setup"
        return 1
    fi
    
    log "INFO" "Setting up SSL certificate monitoring on $manager_ip"
    
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "
        # Create SSL monitoring script
        sudo tee /usr/local/bin/check-ssl-expiry > /dev/null << 'MONITORING_EOF'
#!/bin/bash
# Check SSL certificate expiry
cert_file=\"/etc/ssl/piswarm/wildcard.crt\"
if [[ -f \"\$cert_file\" ]]; then
    expiry_date=\$(openssl x509 -enddate -noout -in \"\$cert_file\" | cut -d= -f2)
    expiry_epoch=\$(date -d \"\$expiry_date\" +%s)
    current_epoch=\$(date +%s)
    days_until_expiry=\$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [[ \$days_until_expiry -lt 30 ]]; then
        echo \"SSL certificate expires in \$days_until_expiry days - renewal recommended\"
        # Attempt automatic renewal if Let's Encrypt
        if command -v certbot >/dev/null 2>&1; then
            certbot renew --quiet
        fi
    fi
fi
MONITORING_EOF

        sudo chmod +x /usr/local/bin/check-ssl-expiry
        
        # Set up cron job for SSL monitoring
        echo '0 6 * * * root /usr/local/bin/check-ssl-expiry' | sudo tee /etc/cron.d/ssl-monitor >/dev/null
        
        echo 'SSL monitoring configured successfully'
    "
}

# Export functions
export -f setup_ssl_certificates
export -f generate_wildcard_ssl  
export -f setup_letsencrypt_ssl
export -f setup_ssl_monitoring
