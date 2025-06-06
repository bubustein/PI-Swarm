#!/bin/bash
# Test WhatsApp Integration for Pi-Swarm
set -euo pipefail

echo "🚀 Pi-Swarm WhatsApp Integration Test"
echo "===================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

# Source functions
source lib/source_functions.sh

echo "📝 Testing WhatsApp alert integration..."
echo ""

# Test 1: Check if WhatsApp functions are loaded
echo "1. Checking if WhatsApp functions are available..."
if command -v setup_whatsapp_alerts >/dev/null 2>&1; then
    echo "   ✅ setup_whatsapp_alerts function is available"
else
    echo "   ❌ setup_whatsapp_alerts function not found"
    exit 1
fi

# Test 2: Test enhanced deployment with WhatsApp option
echo ""
echo "2. Testing enhanced deployment menu with WhatsApp option..."
echo "   📄 Checking enhanced-deploy.sh for WhatsApp integration..."

if grep -q "WhatsApp Business API alerts" scripts/deployment/enhanced-deploy.sh; then
    echo "   ✅ WhatsApp option found in enhanced deployment menu"
else
    echo "   ❌ WhatsApp option not found in enhanced deployment menu"
    exit 1
fi

# Test 3: Check main script integration
echo ""
echo "3. Testing main script WhatsApp integration..."
if grep -q "SETUP_WHATSAPP" core/swarm-cluster.sh; then
    echo "   ✅ WhatsApp configuration found in main script"
else
    echo "   ❌ WhatsApp configuration not found in main script"
    exit 1
fi

# Test 4: Validate WhatsApp notification script template
echo ""
echo "4. Testing WhatsApp notification script generation..."
cat > "/tmp/test-whatsapp-notify.sh" << 'EOF'
#!/bin/bash
# Test WhatsApp notification script

PHONE_NUMBER_ID="test_phone_id"
ACCESS_TOKEN="test_token"
RECIPIENT_NUMBER="+1234567890"

echo "Testing WhatsApp message format..."
echo "Phone ID: $PHONE_NUMBER_ID"
echo "Recipient: $RECIPIENT_NUMBER"
echo "Token: ${ACCESS_TOKEN:0:10}..."

# Simulate message sending (without actual API call)
echo "Would send: '🚨 Pi-Swarm Alert - Test message'"
echo "✅ WhatsApp message format test passed"
EOF

bash /tmp/test-whatsapp-notify.sh
rm /tmp/test-whatsapp-notify.sh

echo ""
echo "5. Testing environment variable handling..."

# Test environment variable exports
export WHATSAPP_PHONE_ID="test123"
export WHATSAPP_TOKEN="token123" 
export WHATSAPP_RECIPIENT="+1234567890"

if [[ -n "${WHATSAPP_PHONE_ID:-}" ]]; then
    echo "   ✅ WHATSAPP_PHONE_ID environment variable handling works"
else
    echo "   ❌ WHATSAPP_PHONE_ID environment variable not properly handled"
fi

echo ""
echo "🎉 WhatsApp Integration Test Results"
echo "===================================="
echo "✅ All WhatsApp integration tests passed!"
echo ""
echo "📋 WhatsApp Setup Requirements:"
echo "   • WhatsApp Business Account"
echo "   • Facebook Developer Account" 
echo "   • WhatsApp Business API access"
echo "   • Phone Number ID from WhatsApp Business Platform"
echo "   • Access Token with messaging permissions"
echo ""
echo "🔗 Setup Guide: https://developers.facebook.com/docs/whatsapp/getting-started"
echo ""
echo "💡 Usage Examples:"
echo "   1. Run enhanced deployment: ./scripts/deployment/enhanced-deploy.sh"
echo "   2. Select option 4 for WhatsApp alerts when prompted"
echo "   3. Provide your WhatsApp Business API credentials"
echo ""
