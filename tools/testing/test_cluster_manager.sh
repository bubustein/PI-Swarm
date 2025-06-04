#!/bin/bash
source lib/log.sh
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}Available Cluster Profiles${NC}"
echo "=========================="
echo ""

echo -e "${GREEN}basic${NC} - Minimal Resources"
echo "  • Memory: 256MB Prometheus, 256MB Grafana, 128MB Portainer"
echo ""

echo -e "${GREEN}lightweight${NC} - Pi Zero/1 Optimized"
echo "  • Memory: 512MB Prometheus, 512MB Grafana, 256MB Portainer"
echo ""

echo -e "${GREEN}standard${NC} - Balanced Configuration"
echo "  • Memory: 2GB Prometheus, 1GB Grafana, 512MB Portainer"
echo ""

echo -e "${GREEN}high-performance${NC} - Full Features"
echo "  • Memory: 3GB Prometheus, 2GB Grafana, 512MB Portainer"
echo ""
