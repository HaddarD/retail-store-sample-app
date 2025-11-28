#!/bin/bash

################################################################################
# Display Application URLs
# Shows all important URLs and credentials for the project
################################################################################

# Load deployment info
if [ -f deployment-info.txt ]; then
    source deployment-info.txt
else
    echo "❌ deployment-info.txt not found!"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "  YOUR APPLICATION URLS"
echo "════════════════════════════════════════════════════"
echo ""
echo "🛒 Retail Store App: http://${MASTER_PUBLIC_IP}:30080"
echo ""
echo "🔧 ArgoCD Dashboard: https://${MASTER_PUBLIC_IP}:30090"
echo "   Username: admin"
echo "   Password: ${ARGOCD_ADMIN_PASSWORD:-<not set - check deployment-info.txt>}"
echo ""
echo "════════════════════════════════════════════════════"
echo ""