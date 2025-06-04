# functions/service_templates.sh
# Custom service templates for easy deployment of common applications

# Initialize service templates directory
init_service_templates() {
    local manager_ip="${1:-}"
    
    if [[ -z "$manager_ip" ]]; then
        log "ERROR" "Manager IP not provided to init_service_templates"
        return 1
    fi
    
    log "INFO" "Initializing service templates..."
    
    ssh "$USER@$manager_ip" "mkdir -p ~/templates/{web,database,monitoring,backup,security}"
    
    # Create template index
    create_template_index "$manager_ip"
    
    # Create common service templates
    create_web_templates "$manager_ip"
    create_database_templates "$manager_ip"
    create_monitoring_templates "$manager_ip"
    create_backup_templates "$manager_ip"
    create_security_templates "$manager_ip"
    
    log "INFO" "✅ Service templates initialized"
}

# Create template index for easy reference
create_template_index() {
    local manager_ip="$1"
    
    cat > "/tmp/template-index.md" << 'EOF'
# Pi-Swarm Service Templates

## 🌐 Web Applications
- **nginx-web** - NGINX web server with SSL
- **apache-web** - Apache web server with PHP
- **nodejs-app** - Node.js application template
- **python-flask** - Python Flask web application
- **wordpress** - WordPress with MySQL
- **nextcloud** - Personal cloud storage

## 🗄️ Databases
- **mysql-cluster** - MySQL with replication
- **postgresql** - PostgreSQL database
- **mongodb** - MongoDB document database
- **redis** - Redis cache/database
- **mariadb** - MariaDB database

## 📊 Monitoring & Analytics
- **elk-stack** - Elasticsearch, Logstash, Kibana
- **influxdb-grafana** - InfluxDB with Grafana
- **prometheus-stack** - Prometheus monitoring suite
- **jaeger** - Distributed tracing

## 🔐 Security & Networking
- **openvpn** - OpenVPN server
- **wireguard** - WireGuard VPN
- **nginx-proxy** - NGINX reverse proxy
- **fail2ban** - Intrusion prevention

## 💾 Backup & Storage
- **rsync-backup** - Automated rsync backups
- **duplicati** - Web-based backup solution
- **minio** - S3-compatible object storage
- **samba** - File sharing server

## Usage
```bash
# Deploy a template
./pi-swarm deploy-template <template-name>

# List available templates
./pi-swarm list-templates

# Customize template
./pi-swarm customize-template <template-name>
```
EOF
    
    scp "/tmp/template-index.md" "$USER@$manager_ip:/tmp/"
    ssh "$USER@$manager_ip" "mv /tmp/template-index.md ~/templates/"
}

# Create web application templates
create_web_templates() {
    local manager_ip="$1"
    
    log "INFO" "Creating web application templates..."
    
    # NGINX Web Server Template
    cat > "/tmp/nginx-web.yml" << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - nginx_config:/etc/nginx/conf.d
      - nginx_html:/usr/share/nginx/html
      - nginx_ssl:/etc/nginx/ssl
    environment:
      - NGINX_ENTRYPOINT_QUIET_LOGS=1
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.role == worker
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    networks:
      - web-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  nginx_config:
  nginx_html:
  nginx_ssl:

networks:
  web-network:
    driver: overlay
    attachable: true
EOF
    
    # Node.js Application Template
    cat > "/tmp/nodejs-app.yml" << 'EOF'
version: '3.8'

services:
  nodejs-app:
    image: node:18-alpine
    working_dir: /app
    command: ["npm", "start"]
    ports:
      - "3000:3000"
    volumes:
      - app_code:/app
      - node_modules:/app/node_modules
    environment:
      - NODE_ENV=production
      - PORT=3000
    deploy:
      replicas: 3
      placement:
        constraints:
          - node.role == worker
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  app_code:
  node_modules:

networks:
  app-network:
    driver: overlay
EOF
    
    # WordPress Template
    cat > "/tmp/wordpress.yml" << 'EOF'
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: mysql
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress_password
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wordpress_data:/var/www/html
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.role == worker
    networks:
      - wordpress-network
    depends_on:
      - mysql

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress_password
      MYSQL_ROOT_PASSWORD: mysql_root_password
    volumes:
      - mysql_data:/var/lib/mysql
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
    networks:
      - wordpress-network

volumes:
  wordpress_data:
  mysql_data:

networks:
  wordpress-network:
    driver: overlay
EOF
    
    # Deploy web templates
    scp "/tmp/nginx-web.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/nodejs-app.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/wordpress.yml" "$USER@$manager_ip:/tmp/"
    
    ssh "$USER@$manager_ip" << 'EOF'
mv /tmp/nginx-web.yml ~/templates/web/
mv /tmp/nodejs-app.yml ~/templates/web/
mv /tmp/wordpress.yml ~/templates/web/
EOF
}

# Create database templates
create_database_templates() {
    local manager_ip="$1"
    
    log "INFO" "Creating database templates..."
    
    # PostgreSQL Template
    cat > "/tmp/postgresql.yml" << 'EOF'
version: '3.8'

services:
  postgresql:
    image: postgres:15
    environment:
      POSTGRES_DB: piswarm_db
      POSTGRES_USER: piswarm
      POSTGRES_PASSWORD: secure_password
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgresql_data:/var/lib/postgresql/data
      - postgresql_backups:/backups
    ports:
      - "5432:5432"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
    networks:
      - database-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U piswarm"]
      interval: 30s
      timeout: 10s
      retries: 5

  postgresql-backup:
    image: postgres:15
    environment:
      PGPASSWORD: secure_password
    volumes:
      - postgresql_backups:/backups
    command: |
      sh -c '
      while true; do
        sleep 3600
        pg_dump -h postgresql -U piswarm piswarm_db > /backups/backup_$$(date +%Y%m%d_%H%M%S).sql
        find /backups -name "backup_*.sql" -mtime +7 -delete
      done'
    deploy:
      replicas: 1
    networks:
      - database-network
    depends_on:
      - postgresql

volumes:
  postgresql_data:
  postgresql_backups:

networks:
  database-network:
    driver: overlay
EOF
    
    # MongoDB Template
    cat > "/tmp/mongodb.yml" << 'EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:6.0
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: mongodb_root_password
      MONGO_INITDB_DATABASE: piswarm_db
    volumes:
      - mongodb_data:/data/db
      - mongodb_config:/data/configdb
    ports:
      - "27017:27017"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
    networks:
      - mongodb-network
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet
      interval: 30s
      timeout: 10s
      retries: 5

  mongo-express:
    image: mongo-express
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: root
      ME_CONFIG_MONGODB_ADMINPASSWORD: mongodb_root_password
      ME_CONFIG_MONGODB_URL: mongodb://root:mongodb_root_password@mongodb:27017/
    ports:
      - "8081:8081"
    deploy:
      replicas: 1
    networks:
      - mongodb-network
    depends_on:
      - mongodb

volumes:
  mongodb_data:
  mongodb_config:

networks:
  mongodb-network:
    driver: overlay
EOF
    
    # Redis Template
    cat > "/tmp/redis.yml" << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass redis_password
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
    networks:
      - redis-network
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis-commander:
    image: rediscommander/redis-commander:latest
    environment:
      REDIS_HOSTS: local:redis:6379:0:redis_password
    ports:
      - "8082:8081"
    deploy:
      replicas: 1
    networks:
      - redis-network
    depends_on:
      - redis

volumes:
  redis_data:

networks:
  redis-network:
    driver: overlay
EOF
    
    # Deploy database templates
    scp "/tmp/postgresql.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/mongodb.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/redis.yml" "$USER@$manager_ip:/tmp/"
    
    ssh "$USER@$manager_ip" << 'EOF'
mv /tmp/postgresql.yml ~/templates/database/
mv /tmp/mongodb.yml ~/templates/database/
mv /tmp/redis.yml ~/templates/database/
EOF
}

# Create monitoring templates
create_monitoring_templates() {
    local manager_ip="$1"
    
    log "INFO" "Creating monitoring templates..."
    
    # ELK Stack Template
    cat > "/tmp/elk-stack.yml" << 'EOF'
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.8.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.security.enabled=false
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
    networks:
      - elk-network

  logstash:
    image: docker.elastic.co/logstash/logstash:8.8.0
    volumes:
      - logstash_config:/usr/share/logstash/config
      - logstash_pipeline:/usr/share/logstash/pipeline
    ports:
      - "5044:5044"
    deploy:
      replicas: 1
    networks:
      - elk-network
    depends_on:
      - elasticsearch

  kibana:
    image: docker.elastic.co/kibana/kibana:8.8.0
    environment:
      ELASTICSEARCH_HOSTS: http://elasticsearch:9200
    ports:
      - "5601:5601"
    deploy:
      replicas: 1
    networks:
      - elk-network
    depends_on:
      - elasticsearch

volumes:
  elasticsearch_data:
  logstash_config:
  logstash_pipeline:

networks:
  elk-network:
    driver: overlay
EOF
    
    # InfluxDB + Grafana Template
    cat > "/tmp/influxdb-grafana.yml" << 'EOF'
version: '3.8'

services:
  influxdb:
    image: influxdb:2.7
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: influx_password
      DOCKER_INFLUXDB_INIT_ORG: piswarm
      DOCKER_INFLUXDB_INIT_BUCKET: metrics
    volumes:
      - influxdb_data:/var/lib/influxdb2
      - influxdb_config:/etc/influxdb2
    ports:
      - "8086:8086"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
    networks:
      - monitoring-network

  grafana:
    image: grafana/grafana:latest
    environment:
      GF_SECURITY_ADMIN_PASSWORD: grafana_password
      GF_INSTALL_PLUGINS: grafana-influxdb-datasource
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3001:3000"
    deploy:
      replicas: 1
    networks:
      - monitoring-network
    depends_on:
      - influxdb

volumes:
  influxdb_data:
  influxdb_config:
  grafana_data:

networks:
  monitoring-network:
    driver: overlay
EOF
    
    # Deploy monitoring templates
    scp "/tmp/elk-stack.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/influxdb-grafana.yml" "$USER@$manager_ip:/tmp/"
    
    ssh "$USER@$manager_ip" << 'EOF'
mv /tmp/elk-stack.yml ~/templates/monitoring/
mv /tmp/influxdb-grafana.yml ~/templates/monitoring/
EOF
}

# Create backup templates
create_backup_templates() {
    local manager_ip="$1"
    
    log "INFO" "Creating backup templates..."
    
    # Duplicati Backup Template
    cat > "/tmp/duplicati.yml" << 'EOF'
version: '3.8'

services:
  duplicati:
    image: linuxserver/duplicati
    environment:
      PUID: 1000
      PGID: 1000
      TZ: UTC
    volumes:
      - duplicati_config:/config
      - duplicati_backups:/backups
      - /var/lib/docker/volumes:/source:ro
    ports:
      - "8200:8200"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    networks:
      - backup-network

volumes:
  duplicati_config:
  duplicati_backups:

networks:
  backup-network:
    driver: overlay
EOF
    
    # MinIO Object Storage Template
    cat > "/tmp/minio.yml" << 'EOF'
version: '3.8'

services:
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minio_admin
      MINIO_ROOT_PASSWORD: minio_password
    volumes:
      - minio_data:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
    networks:
      - storage-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

volumes:
  minio_data:

networks:
  storage-network:
    driver: overlay
EOF
    
    # Deploy backup templates
    scp "/tmp/duplicati.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/minio.yml" "$USER@$manager_ip:/tmp/"
    
    ssh "$USER@$manager_ip" << 'EOF'
mv /tmp/duplicati.yml ~/templates/backup/
mv /tmp/minio.yml ~/templates/backup/
EOF
}

# Create security templates
create_security_templates() {
    local manager_ip="$1"
    
    log "INFO" "Creating security templates..."
    
    # OpenVPN Template
    cat > "/tmp/openvpn.yml" << 'EOF'
version: '3.8'

services:
  openvpn:
    image: kylemanna/openvpn
    cap_add:
      - NET_ADMIN
    ports:
      - "1194:1194/udp"
    volumes:
      - openvpn_data:/etc/openvpn
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    networks:
      - vpn-network

volumes:
  openvpn_data:

networks:
  vpn-network:
    driver: overlay
EOF
    
    # WireGuard Template
    cat > "/tmp/wireguard.yml" << 'EOF'
version: '3.8'

services:
  wireguard:
    image: linuxserver/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      PUID: 1000
      PGID: 1000
      TZ: UTC
      SERVERURL: auto
      SERVERPORT: 51820
      PEERS: 10
      PEERDNS: auto
      INTERNAL_SUBNET: 10.13.13.0
    volumes:
      - wireguard_config:/config
      - /lib/modules:/lib/modules
    ports:
      - "51820:51820/udp"
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    networks:
      - wireguard-network

volumes:
  wireguard_config:

networks:
  wireguard-network:
    driver: overlay
EOF
    
    # Deploy security templates
    scp "/tmp/openvpn.yml" "$USER@$manager_ip:/tmp/"
    scp "/tmp/wireguard.yml" "$USER@$manager_ip:/tmp/"
    
    ssh "$USER@$manager_ip" << 'EOF'
mv /tmp/openvpn.yml ~/templates/security/
mv /tmp/wireguard.yml ~/templates/security/
EOF
}

# Deploy a service template
deploy_service_template() {
    local template_name="$1"
    local stack_name="$2"
    local manager_ip="$3"
    
    log "INFO" "Deploying service template: $template_name as stack: $stack_name"
    
    # Find template file
    local template_path=$(ssh "$USER@$manager_ip" "find ~/templates -name '$template_name.yml' -type f | head -1")
    
    if [[ -z "$template_path" ]]; then
        log "ERROR" "Template '$template_name' not found"
        return 1
    fi
    
    # Deploy the stack
    ssh "$USER@$manager_ip" "docker stack deploy -c $template_path $stack_name" || {
        log "ERROR" "Failed to deploy template $template_name"
        return 1
    }
    
    log "INFO" "✅ Successfully deployed $template_name as stack $stack_name"
    
    # Send deployment notification
    if ssh "$USER@$manager_ip" "command -v slack-notify &> /dev/null"; then
        ssh "$USER@$manager_ip" "slack-notify deployment '$template_name deployed as $stack_name'"
    fi
}

# List available templates
list_service_templates() {
    local manager_ip="$1"
    
    log "INFO" "Available service templates:"
    
    ssh "$USER@$manager_ip" << 'EOF'
echo "🌐 Web Applications:"
ls ~/templates/web/*.yml 2>/dev/null | sed 's/.*\///g; s/\.yml//g' | sed 's/^/  - /'

echo ""
echo "🗄️  Databases:"
ls ~/templates/database/*.yml 2>/dev/null | sed 's/.*\///g; s/\.yml//g' | sed 's/^/  - /'

echo ""
echo "📊 Monitoring:"
ls ~/templates/monitoring/*.yml 2>/dev/null | sed 's/.*\///g; s/\.yml//g' | sed 's/^/  - /'

echo ""
echo "💾 Backup & Storage:"
ls ~/templates/backup/*.yml 2>/dev/null | sed 's/.*\///g; s/\.yml//g' | sed 's/^/  - /'

echo ""
echo "🔐 Security:"
ls ~/templates/security/*.yml 2>/dev/null | sed 's/.*\///g; s/\.yml//g' | sed 's/^/  - /'
EOF
}
