#!/bin/bash
# Demo script for WhatsApp integration in Pi-Swarm

echo "📱 WhatsApp Business API Integration Demo"
echo "========================================"
echo ""

echo "Simulating WhatsApp alert messages..."
echo ""

# Simulate different alert types
echo "1. 🔴 Service Down Alert:"
echo "   🚨 *Pi-Swarm Alert*"
echo "   "
echo "   *Cluster:* home-cluster"
echo "   *Node:* pi-manager-01"
echo "   *Time:* $(date)"
echo "   *Alert:* Service DOWN: Portainer has stopped responding"
echo ""

echo "2. ⚠️  High Usage Warning:"
echo "   🚨 *Pi-Swarm Alert*"
echo "   "
echo "   *Cluster:* home-cluster"
echo "   *Node:* pi-worker-02"
echo "   *Time:* $(date)"
echo "   *Alert:* HIGH USAGE: Memory at 89%"
echo ""

echo "3. ✅ Deployment Success:"
echo "   🚨 *Pi-Swarm Alert*"
echo "   "
echo "   *Cluster:* home-cluster"
echo "   *Node:* pi-manager-01"
echo "   *Time:* $(date)"
echo "   *Alert:* DEPLOYMENT: Successfully deployed version v2.1.0"
echo ""

echo "4. 🔒 SSL Expiry Warning:"
echo "   🚨 *Pi-Swarm Alert*"
echo "   "
echo "   *Cluster:* home-cluster"
echo "   *Node:* pi-manager-01"
echo "   *Time:* $(date)"
echo "   *Alert:* SSL EXPIRY: Certificate for cluster.example.com expires in 7 days"
echo ""

echo "📋 To enable WhatsApp alerts in your Pi-Swarm:"
echo "   1. Run: ./scripts/deployment/enhanced-deploy.sh"
echo "   2. Choose option 4 when prompted for alerts"
echo "   3. Provide WhatsApp Business API credentials"
echo ""
echo "📖 For setup instructions, see: docs/WHATSAPP_INTEGRATION.md"
