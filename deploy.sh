#!/bin/bash

# Pi-Swarm v2.0.0 - Main Deployment Script
# This script provides easy access to all deployment options

set -euo pipefail

echo "🚀 Pi-Swarm v2.0.0 - Docker Swarm Orchestration Platform"
echo "========================================================="
echo ""
echo "Please choose a deployment option:"
echo ""
echo "1. 🤖 Automated Deployment (Recommended for first-time users)"
echo "   • No user interaction required"
echo "   • Uses sensible defaults"
echo "   • Perfect for testing and CI/CD"
echo ""
echo "2. 🔧 Enhanced Interactive Deployment"
echo "   • Step-by-step configuration"
echo "   • Advanced options available"
echo "   • Better error handling and feedback"
echo ""
echo "3. 🎛️ Traditional Deployment"
echo "   • Full manual control"
echo "   • All enterprise features configurable"
echo "   • For experienced users"
echo ""
echo "4. 🧪 Validation Mode"
echo "   • Test without actual deployment"
echo "   • Validate configuration and connectivity"
echo "   • Perfect for troubleshooting"
echo ""
echo "5. 📊 Demo Mode"
echo "   • See all deployment options"
echo "   • Show project capabilities"
echo "   • Educational walkthrough"
echo ""

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo "🤖 Starting automated deployment..."
        exec ./scripts/deployment/automated-deploy.sh
        ;;
    2)
        echo "🔧 Starting enhanced interactive deployment..."
        exec ./scripts/deployment/enhanced-deploy.sh
        ;;
    3)
        echo "🎛️ Starting traditional deployment..."
        exec ./core/swarm-cluster.sh
        ;;
    4)
        echo "🧪 Running validation tests..."
        exec ./scripts/testing/final-validation-test.sh
        ;;
    5)
        echo "📊 Starting demo mode..."
        exec ./scripts/deployment/deployment-demo.sh
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again and choose 1-5."
        exit 1
        ;;
esac
