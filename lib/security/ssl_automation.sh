#!/bin/bash

# setup_ssl_certificates: Wrapper for SSL setup (Let's Encrypt or self-signed)
# Usage: setup_ssl_certificates <manager_ip> <ssh_user> <ssh_pass>
setup_ssl_certificates() {
    local manager_ip="$1"
    local ssh_user="$2"
    local ssh_pass="$3"
    if [[ -n "${SSL_DOMAIN:-}" && -n "${SSL_EMAIL:-}" ]]; then
        log INFO "Setting up Let's Encrypt SSL certificates on $manager_ip for $SSL_DOMAIN"
        setup_letsencrypt_ssl "$SSL_DOMAIN" "$SSL_EMAIL" "$manager_ip" "$ssh_user" "$ssh_pass"
    else
        log INFO "Setting up self-signed SSL certificates on $manager_ip"
        generate_wildcard_ssl "piswarm.local" "$manager_ip" "$ssh_user" "$ssh_pass"
    fi
}

# generate_wildcard_ssl: Generate a self-signed wildcard SSL certificate for a given domain and deploy to the manager node
# Usage: generate_wildcard_ssl <domain> <manager_ip> <ssh_user> <ssh_pass>
generate_wildcard_ssl() {
    local domain="$1"
    local manager_ip="$2"
    local ssh_user="$3"
    local ssh_pass="$4"
    local cert_dir="/etc/ssl/piswarm"
    local key_file="$cert_dir/${domain}.key"
    local cert_file="$cert_dir/${domain}.crt"
    log INFO "Generating self-signed wildcard SSL certificate for *.$domain on $manager_ip"
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "sudo mkdir -p $cert_dir && \
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
        -keyout $key_file -out $cert_file \
        -subj '/CN=*.$domain' -addext 'subjectAltName=DNS:*.$domain' && \
        sudo chmod 600 $key_file $cert_file"
    log INFO "Self-signed certificate deployed to $manager_ip:$cert_dir"
}

# setup_letsencrypt_ssl: Obtain and deploy Let's Encrypt SSL certificate for a domain on the manager node
# Usage: setup_letsencrypt_ssl <domain> <email> <manager_ip> <ssh_user> <ssh_pass>
setup_letsencrypt_ssl() {
    local domain="$1"
    local email="$2"
    local manager_ip="$3"
    local ssh_user="$4"
    local ssh_pass="$5"
    log INFO "Requesting Let's Encrypt SSL certificate for $domain on $manager_ip"
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "sudo apt-get update && sudo apt-get install -y certbot && \
        sudo certbot certonly --standalone --non-interactive --agree-tos --email $email -d $domain && \
        sudo ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/ssl/piswarm/${domain}.crt && \
        sudo ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/ssl/piswarm/${domain}.key"
    log INFO "Let's Encrypt certificate deployed to $manager_ip:/etc/ssl/piswarm/"
}

# setup_ssl_monitoring: Install simple certificate expiry check and cron job
# Usage: setup_ssl_monitoring <manager_ip> [ssh_user] [ssh_pass]
setup_ssl_monitoring() {
    local manager_ip="$1"
    local ssh_user="${2:-$NODES_DEFAULT_USER}"
    local ssh_pass="${3:-$NODES_DEFAULT_PASS}"

    log INFO "Configuring SSL monitoring on $manager_ip"
    ssh_exec "$manager_ip" "$ssh_user" "$ssh_pass" "cat <<'EOF' | sudo tee /usr/local/bin/check-ssl-expiry >/dev/null
#!/bin/bash
for cert in /etc/ssl/piswarm/*.crt; do
    [ -f \"$cert\" ] || continue
    end=\$(openssl x509 -enddate -noout -in \"$cert\" | cut -d= -f2)
    exp=\$(date -d \"$end\" +%s)
    now=\$(date +%s)
    days=\$(( (exp - now) / 86400 ))
    if (( days <= 30 )); then
        echo \"SSL certificate $cert expires in \$days days\"
    fi
done
EOF
sudo chmod +x /usr/local/bin/check-ssl-expiry
echo '0 6 * * * root /usr/local/bin/check-ssl-expiry' | sudo tee /etc/cron.d/ssl-monitor >/dev/null"
}

export -f setup_ssl_certificates
export -f generate_wildcard_ssl
export -f setup_letsencrypt_ssl
export -f setup_ssl_monitoring
