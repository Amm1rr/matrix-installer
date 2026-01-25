#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="zanjir-synapse"
ADDON_VERSION="0.1.0"
ADDON_DESCRIPTION="Placeholder for future Zanjir-based Synapse deployment module (NOT YET IMPLEMENTED)"
ADDON_AUTHOR="Matrix Plus Team"

# ===========================================
# ENVIRONMENT VARIABLES FROM MAIN.SH
# ===========================================
# These variables are exported by main.sh:
# SERVER_NAME - Matrix server identity (IP or domain)
# SSL_CERT - Full chain certificate path
# SSL_KEY - Private key path
# ROOT_CA - Root CA certificate path
# CERTS_DIR - Certificate directory
# WORKING_DIR - Working directory
# ===========================================

set -e
set -u
set -o pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}[ERROR]${NC} zanjir-synapse addon is not yet implemented."
echo ""
echo "This is a placeholder for a future alternative deployment method"
echo "using the Zanjir orchestration system."
echo ""
echo "Available addons:"
echo "  - ansible-synapse: Fully functional Ansible-based installation"
echo ""
echo "For now, please use the ansible-synapse addon instead."

exit 1
