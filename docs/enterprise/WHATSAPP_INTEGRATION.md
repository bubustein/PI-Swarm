#!/bin/bash
# WhatsApp Integration Demo for Pi-Swarm
set -euo pipefail

echo "📱 Pi-Swarm WhatsApp Business API Integration Demo"
echo "=================================================="
echo ""

echo "🔧 This integration allows you to receive Pi-Swarm alerts via WhatsApp!"
echo ""
echo "📋 Setup Requirements:"
echo "   1. WhatsApp Business Account"
echo "   2. Facebook Developer Account"
echo "   3. WhatsApp Business API Access"
echo ""

echo "🛠️  Quick Setup Steps:"
echo "   1. Go to https://developers.facebook.com/apps/"
echo "   2. Create a new app and add WhatsApp Business API"
echo "   3. Get your Phone Number ID and Access Token"
echo "   4. Use these credentials in Pi-Swarm deployment"
echo ""

echo "📱 Alert Types Supported:"
echo "   • 🔴 Service Down alerts"
echo "   • 📴 Node Offline notifications"
echo "   • ⚠️  High resource usage warnings"
echo "   • 🔒 SSL certificate expiry reminders"
echo "   • ✅ Successful deployment notifications"
echo "   • 💾 Backup completion status"
echo ""

echo "🚀 How to Enable in Deployment:"
echo "   1. Run: ./scripts/deployment/enhanced-deploy.sh"
echo "   2. When prompted for alerts, choose option 4 (WhatsApp)"
echo "   3. Enter your Phone Number ID"
echo "   4. Enter your Access Token"
echo "   5. Enter recipient phone number (with country code)"
echo ""

echo "💡 Example Alert Message:"
echo "   🚨 *Pi-Swarm Alert*"
echo "   "
echo "   *Cluster:* home-cluster"
echo "   *Node:* pi-manager-01"
echo "   *Time:* $(date)"
echo "   *Alert:* Service DOWN: Portainer has stopped responding"
echo ""

echo "🔐 Security Notes:"
echo "   • Access tokens are stored securely on Pi nodes"
echo "   • Only authorized phone numbers receive alerts"
echo "   • Messages use WhatsApp's end-to-end encryption"
echo ""

echo "🔗 Useful Links:"
echo "   • WhatsApp Business API: https://developers.facebook.com/docs/whatsapp"
echo "   • Getting Started Guide: https://developers.facebook.com/docs/whatsapp/getting-started"
echo "   • Phone Number Setup: https://developers.facebook.com/docs/whatsapp/phone-numbers"
echo ""

echo "🎯 Ready to enable WhatsApp alerts? Run the enhanced deployment!"
echo "   ./scripts/deployment/enhanced-deploy.sh"
echo ""
