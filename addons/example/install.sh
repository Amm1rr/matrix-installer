#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="example"
ADDON_NAME_MENU="Example Addon (NOT YET IMPLEMENTED)"
ADDON_VERSION="0.1.0"
ADDON_ORDER="60"
ADDON_DESCRIPTION="Placeholder for future Synapse deployment module (NOT YET IMPLEMENTED)"
ADDON_AUTHOR="Yours"
ADDON_HIDDEN="true" # Hide this addon from the menu

# ===========================================
# ENVIRONMENT VARIABLES FROM matrix-installer.sh
# ===========================================
# These variables are exported by matrix-installer.sh before running this addon:
#
# SERVER_NAME="172.19.39.69"                    # Server IP or domain name
# SSL_CERT="/path/to/certs/172.19.39.69/cert-full-chain.pem"  # Full chain certificate
# SSL_KEY="/path/to/certs/172.19.39.69/server.key"            # SSL private key
# ROOT_CA="/path/to/certs/rootCA.crt"                       # Root Key certificate
# CERTS_DIR="/path/to/certs"                                # Certificates directory
# WORKING_DIR="/path/to/script"                              # Script working directory
# ===========================================

set -e
set -u
set -o pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}[ERROR]${NC} example-addon is not yet implemented."
echo ""
echo "This is a placeholder for a future alternative deployment method"
echo "using the Example orchestration system."
echo ""

exit 1
