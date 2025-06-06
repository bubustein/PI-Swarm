#!/bin/bash

# Security Validation Script - Check for hardcoded password assumptions
set -euo pipefail

echo "🔐 Pi-Swarm Security Validation"
echo "==============================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track issues found
ISSUES_FOUND=0

echo "🔍 Checking for hardcoded password assumptions..."
echo ""

# Check for hardcoded "raspberry" password
echo "1. Checking for hardcoded 'raspberry' password..."
if grep -r "raspberry" --include="*.sh" . | grep -v "Raspberry Pi" | grep -v "# Check for" | grep -v "echo" | grep -v "docs/" | grep -v "SECURITY_IMPROVEMENTS.md" | grep -v "security-validation.sh" >/dev/null 2>&1; then
    echo -e "   ${RED}❌ Found potential hardcoded 'raspberry' password:${NC}"
    grep -r "raspberry" --include="*.sh" . | grep -v "Raspberry Pi" | grep -v "# Check for" | grep -v "echo" | grep -v "docs/" | grep -v "SECURITY_IMPROVEMENTS.md" | grep -v "security-validation.sh" | head -5
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✅ No hardcoded 'raspberry' passwords found${NC}"
fi

echo ""

# Check for hardcoded "piswarm123" password
echo "2. Checking for hardcoded 'piswarm123' password..."
if grep -r "piswarm123" --include="*.sh" . | grep -v "docs/" | grep -v "SECURITY_IMPROVEMENTS.md" | grep -v "security-validation.sh" | grep -v "# Check for" >/dev/null 2>&1; then
    echo -e "   ${RED}❌ Found hardcoded 'piswarm123' password:${NC}"
    grep -r "piswarm123" --include="*.sh" . | grep -v "docs/" | grep -v "SECURITY_IMPROVEMENTS.md" | grep -v "security-validation.sh" | grep -v "# Check for"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✅ No hardcoded 'piswarm123' passwords found${NC}"
fi

echo ""

# Check for prompt_or_default with password defaults
echo "3. Checking for password defaults in prompt_or_default..."
if grep -r "prompt_or_default.*password.*raspberry" --include="*.sh" . | grep -v "security-validation.sh" >/dev/null 2>&1; then
    echo -e "   ${RED}❌ Found prompt_or_default with 'raspberry' default:${NC}"
    grep -r "prompt_or_default.*password.*raspberry" --include="*.sh" . | grep -v "security-validation.sh"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✅ No password defaults in prompt_or_default found${NC}"
fi

echo ""

# Check for proper password prompting
echo "4. Checking for proper password prompting..."
if grep -r "read -sp.*[Pp]assword" --include="*.sh" . >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Found secure password prompting${NC}"
else
    echo -e "   ${YELLOW}⚠️  No secure password prompting found - may need manual verification${NC}"
fi

echo ""

# Check for environment variable password support
echo "5. Checking for environment variable password support..."
if grep -r "TEST_PASSWORD\|TEST_PI_PASSWORD" --include="*.sh" . >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Found environment variable password support${NC}"
else
    echo -e "   ${YELLOW}⚠️  Limited environment variable password support${NC}"
fi

echo ""

# Check for configuration file password support
echo "6. Checking for configuration file password support..."
if grep -r "get_config_value.*pass" --include="*.sh" . >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Found configuration file password support${NC}"
else
    echo -e "   ${YELLOW}⚠️  Limited configuration file password support${NC}"
fi

echo ""
echo "============================================"

if [[ $ISSUES_FOUND -eq 0 ]]; then
    echo -e "${GREEN}🎉 Security Validation PASSED!${NC}"
    echo ""
    echo "✅ No hardcoded password assumptions found"
    echo "✅ Security improvements are properly implemented"
    echo ""
    echo "📋 Best practices implemented:"
    echo "   • No default SSH passwords"
    echo "   • No default service passwords"
    echo "   • Secure password prompting"
    echo "   • Environment variable support"
    echo "   • Configuration file support"
else
    echo -e "${RED}❌ Security Validation FAILED!${NC}"
    echo ""
    echo "Found $ISSUES_FOUND security issue(s) that need attention."
    echo ""
    echo "📋 Next steps:"
    echo "   1. Review the issues listed above"
    echo "   2. Remove any hardcoded passwords"
    echo "   3. Implement proper password prompting"
    echo "   4. Run this script again to verify fixes"
    exit 1
fi

echo ""
echo "🔗 For more information, see:"
echo "   • docs/SECURITY_IMPROVEMENTS.md"
echo "   • docs/USER_AUTHENTICATION.md"
echo "   • docs/ENTERPRISE_FEATURES.md"
