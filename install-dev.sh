#!/bin/bash

# ===========================================
# Matrix Ansible Playbook Auto-Installer
# Version: 1.0.0
# Description: Automated installation script for Matrix Synapse using Ansible
# ===========================================

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Catch errors in pipes

# ===========================================
# CONFIGURATION SECTION
# All user-modifiable settings are here
# ===========================================

# Path configuration (all paths relative to current working directory)
WORKING_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="${WORKING_DIR}/matrix-docker-ansible-deploy"
CA_DIR="${WORKING_DIR}/matrix-ca"
LOG_FILE="${WORKING_DIR}/install.log"

# Default configuration values
DEFAULT_HOMESERVER_IMPL="synapse"
DEFAULT_IPV6_ENABLED="true"
DEFAULT_ELEMENT_ENABLED="true"
DEFAULT_SSH_USER="admin"
DEFAULT_SSH_PORT="22"

# SSL Certificate settings
SSL_COUNTRY="IR"
SSL_STATE="Tehran"
SSL_CITY="Tehran"
SSL_ORG="MatrixCA"
SSL_OU="IT"
SSL_CERT_DAYS=365
SSL_CA_DAYS=3650

# Ansible settings
ANSIBLE_MIN_VERSION="2.15.1"
MATRIX_PLAYBOOK_REPO_URL="https://github.com/spantaleev/matrix-docker-ansible-deploy.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===========================================
# GLOBAL VARIABLES
# Runtime variables (set during execution)
# ===========================================

OS_TYPE=""              # linux, darwin, windows
OS_DISTRO=""            # ubuntu, debian, arch, manjaro, centos, etc.
HAS_ANSIBLE=false       # true if ansible is installed
HAS_GIT=false           # true if git is installed
HAS_PYTHON=false        # true if python3 is installed
HAS_DOCKER=false        # true if docker is installed

# User inputs
INSTALLATION_MODE=""    # "local" or "remote"
SERVER_IP=""            # IP address or domain (for Matrix)
SERVER_USER=""          # SSH username
SERVER_PORT=""          # SSH port
SSH_HOST=""             # SSH host (for ansible_host, defaults to SERVER_IP)
USE_SSH_KEY=""          # "yes" or "no"
SSH_KEY_PATH=""         # Path to SSH key
SSH_PASSWORD=""         # SSH password (if using password auth)
SUDO_PASSWORD=""        # Sudo password (for become)

# Generated values
MATRIX_SECRET=""        # Generated secret key
POSTGRES_PASSWORD=""    # Generated postgres password
ADMIN_USERNAME=""       # Admin username
ADMIN_PASSWORD=""       # Admin password

# Configuration options
IPV6_ENABLED=""         # "true" or "false"
ELEMENT_ENABLED=""      # "true" or "false"
SSL_OPTION=""           # "1" (new Root CA) or "2" (use existing Root CA)

# Paths
HOST_VARS_DIR=""        # Path to host_vars directory
VARS_YML_PATH=""        # Path to vars.yml
INVENTORY_PATH=""       # Path to inventory/hosts
SSL_KEY_PATH=""         # Path to SSL private key
SSL_CERT_PATH=""        # Path to SSL certificate
SSL_CA_PATH=""          # Path to Root CA certificate
EXISTING_ROOT_CA_DIR="" # Path to existing Root CA (for loading)

# ===========================================
# HELPER FUNCTIONS
# ===========================================

# ===========================================
# FUNCTION: cd_playbook_and_setup_direnv
# Description: Change to playbook directory and handle direnv
# Usage: cd_playbook_and_setup_direnv
# ===========================================
cd_playbook_and_setup_direnv() {
    cd "$PLAYBOOK_DIR" || return 1

    # Check if direnv needs to be allowed (for .envrc with nix-shell)
    if [[ -f ".envrc" ]] && command -v direnv &> /dev/null; then
        if direnv status . 2>/dev/null | grep -q "Blocked"; then
            print_message "info" "Approving .envrc for direnv..."
            direnv allow . 2>/dev/null || true
        fi
    fi

    return 0
}

# ===========================================
# FUNCTION: print_message
# Description: Print colored messages to stdout
# Arguments:
#   $1 - Message type: info, success, warning, error
#   $2 - Message content
# ===========================================
print_message() {
    local msg_type="$1"
    local message="$2"

    case "$msg_type" in
        "info")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        *)
            echo "$message"
            ;;
    esac

    # Also log to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$msg_type] $message" >> "$LOG_FILE"
}

# ===========================================
# FUNCTION: detect_os
# Description: Detect the operating system
# Sets global variables: OS_TYPE, OS_DISTRO
# ===========================================
detect_os() {
    print_message "info" "Detecting operating system..."

    # Detect if running on Windows (MSYS/MinGW/Cygwin/WSL)
    if [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] || [[ -n "${CYGWIN_PREFIX:-}" ]]; then
        OS_TYPE="windows"
        print_message "info" "Detected: Windows (MSYS/MinGW/Cygwin)"
        return 0
    fi

    # Check if WSL
    if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
        OS_TYPE="wsl"
        print_message "info" "Detected: Windows Subsystem for Linux (WSL)"
        return 0
    fi

    # Detect Unix-like systems
    local uname_str
    uname_str="$(uname)"

    case "$uname_str" in
        Linux*)
            OS_TYPE="linux"
            # Detect Linux distribution
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                OS_DISTRO="${ID:-unknown}"
                print_message "info" "Detected: Linux ($OS_DISTRO)"
            elif [[ -f /etc/arch-release ]]; then
                OS_DISTRO="arch"
                print_message "info" "Detected: Linux (Arch)"
            elif [[ -f /etc/debian_version ]]; then
                OS_DISTRO="debian"
                print_message "info" "Detected: Linux (Debian)"
            else
                OS_DISTRO="unknown"
                print_message "warning" "Could not detect Linux distribution"
            fi
            ;;
        Darwin*)
            OS_TYPE="darwin"
            print_message "info" "Detected: macOS"
            ;;
        *)
            OS_TYPE="unknown"
            print_message "error" "Unknown operating system: $uname_str"
            return 1
            ;;
    esac

    return 0
}

# ===========================================
# FUNCTION: check_prerequisites
# Description: Check if required tools are installed
# Sets global variables: HAS_ANSIBLE, HAS_GIT, HAS_PYTHON, HAS_DOCKER
# ===========================================
check_prerequisites() {
    print_message "info" "Checking prerequisites..."

    # Check Ansible
    if command -v ansible &> /dev/null; then
        HAS_ANSIBLE=true
        local ansible_version
        ansible_version="$(ansible --version 2>&1 | head -n1 | awk '{print $2}')"
        print_message "success" "Ansible is installed: $ansible_version"
    else
        HAS_ANSIBLE=false
        print_message "warning" "Ansible is not installed"
    fi

    # Check Git
    if command -v git &> /dev/null; then
        HAS_GIT=true
        print_message "success" "Git is installed"
    else
        HAS_GIT=false
        print_message "warning" "Git is not installed"
    fi

    # Check Python
    if command -v python3 &> /dev/null; then
        HAS_PYTHON=true
        print_message "success" "Python3 is installed"
    else
        HAS_PYTHON=false
        print_message "warning" "Python3 is not installed"
    fi

    # Check Docker (only for local installation)
    if [[ "$INSTALLATION_MODE" == "local" ]]; then
        if command -v docker &> /dev/null; then
            HAS_DOCKER=true
            print_message "success" "Docker is installed"
        else
            HAS_DOCKER=false
            print_message "warning" "Docker is not installed (will be installed by playbook)"
        fi
    fi

    return 0
}

# ===========================================
# FUNCTION: install_ansible
# Description: Install Ansible based on detected OS
# ===========================================
install_ansible() {
    if [[ "$HAS_ANSIBLE" == true ]]; then
        print_message "info" "Ansible is already installed, skipping..."
        return 0
    fi

    print_message "info" "Installing Ansible..."

    case "$OS_TYPE" in
        windows|wsl)
            # For Windows/WSL, use pip
            if [[ "$HAS_PYTHON" == false ]]; then
                print_message "error" "Python3 is required for Ansible installation on Windows"
                return 1
            fi
            pip install ansible
            ;;

        linux)
            case "$OS_DISTRO" in
                ubuntu|debian)
                    sudo apt-get update
                    sudo apt-get install -y ansible git python3-pip
                    ;;
                arch|manjaro)
                    sudo pacman -S --noconfirm ansible git python3
                    ;;
                fedora|rhel|centos)
                    sudo dnf install -y ansible git python3
                    ;;
                *)
                    print_message "error" "Unsupported Linux distribution: $OS_DISTRO"
                    print_message "info" "Please install Ansible manually: https://docs.ansible.com/ansible/latest/installation_guide/index.html"
                    return 1
                    ;;
            esac
            ;;

        darwin)
            # For macOS, use Homebrew
            if ! command -v brew &> /dev/null; then
                print_message "error" "Homebrew is not installed. Please install it first: https://brew.sh/"
                return 1
            fi
            brew install ansible git python3
            ;;

        *)
            print_message "error" "Unsupported operating system: $OS_TYPE"
            return 1
            ;;
    esac

    # Verify installation
    if command -v ansible &> /dev/null; then
        print_message "success" "Ansible has been installed successfully"
        HAS_ANSIBLE=true
        return 0
    else
        print_message "error" "Failed to install Ansible"
        return 1
    fi
}

# ===========================================
# FUNCTION: ensure_playbook_exists
# Description: Check if playbook exists, clone if not
# ===========================================
ensure_playbook_exists() {
    print_message "info" "Checking playbook..."

    if [[ -d "$PLAYBOOK_DIR" ]]; then
        # Check if it's a valid git repository
        if [[ -d "$PLAYBOOK_DIR/.git" ]]; then
            print_message "success" "Playbook already exists"
            return 0
        else
            print_message "warning" "Playbook directory exists but is not a git repository"
            if [[ "$(prompt_yes_no "Remove and re-clone from GitHub?" "n")" == "yes" ]]; then
                rm -rf "$PLAYBOOK_DIR"
            else
                print_message "info" "Using existing directory"
                return 0
            fi
        fi
    fi

    # Clone the playbook
    print_message "info" "Cloning Matrix Ansible Playbook..."

    if git clone "$MATRIX_PLAYBOOK_REPO_URL" "$PLAYBOOK_DIR" >> "$LOG_FILE" 2>&1; then
        print_message "success" "Playbook cloned successfully"
        return 0
    else
        print_message "error" "Failed to clone playbook"
        print_message "info" "Check log file for details: $LOG_FILE"
        return 1
    fi
}

# ===========================================
# FUNCTION: generate_password
# Description: Generate a strong random password
# Arguments:
#   $1 - Length of password (default: 32)
# Output: Generated password
# ===========================================
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# ===========================================
# FUNCTION: create_root_ca
# Description: Create a new Root CA certificate
# Sets global variable: SSL_CA_PATH
# ===========================================
create_root_ca() {
    print_message "info" "Generating new Root CA..."

    # Create CA directory
    mkdir -p "$CA_DIR"
    cd "$CA_DIR" || return 1

    # Generate Root CA private key
    print_message "info" "Generating Root CA private key..."
    openssl genrsa -out rootCA.key 4096 2>/dev/null

    # Generate Root CA certificate
    print_message "info" "Generating Root CA certificate..."
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=Matrix Root CA" \
        -out rootCA.crt 2>/dev/null

    SSL_CA_PATH="${CA_DIR}/rootCA.crt"

    print_message "success" "Root CA created"
    print_message "info" "  - Root CA key: ${CA_DIR}/rootCA.key"
    print_message "info" "  - Root CA cert: ${CA_DIR}/rootCA.crt"

    return 0
}

# ===========================================
# FUNCTION: create_ssl_certificates
# Description: Create self-signed SSL certificates for the server
# Arguments:
#   $1 - Server IP address or domain
#   $2 - SSL option: "1" (new Root CA) or "2" (use existing Root CA)
# Sets global variables: SSL_KEY_PATH, SSL_CERT_PATH, SSL_CA_PATH
# ===========================================
create_ssl_certificates() {
    local server_ip="$1"
    local ssl_option="${2:-1}"

    print_message "info" "Creating self-signed SSL certificates..."

    # Create CA directory
    mkdir -p "$CA_DIR"
    cd "$CA_DIR" || return 1

    # Handle Root CA based on ssl_option
    if [[ "$ssl_option" == "1" ]]; then
        # Create new Root CA in matrix-ca
        create_root_ca || return 1
    elif [[ "$ssl_option" == "2" ]]; then
        # Use existing Root CA from script directory
        if [[ -n "$EXISTING_ROOT_CA_DIR" ]] && [[ -f "${EXISTING_ROOT_CA_DIR}/rootCA.key" ]] && [[ -f "${EXISTING_ROOT_CA_DIR}/rootCA.crt" ]]; then
            print_message "success" "Using existing Root CA from script directory"
            print_message "info" "  - Root CA key: ${EXISTING_ROOT_CA_DIR}/rootCA.key"
            print_message "info" "  - Root CA cert: ${EXISTING_ROOT_CA_DIR}/rootCA.crt"

            # Copy existing Root CA to matrix-ca for consistency
            cp "${EXISTING_ROOT_CA_DIR}/rootCA.key" "${CA_DIR}/rootCA.key"
            cp "${EXISTING_ROOT_CA_DIR}/rootCA.crt" "${CA_DIR}/rootCA.crt"

            # Also copy .srl if it exists
            if [[ -f "${EXISTING_ROOT_CA_DIR}/rootCA.srl" ]]; then
                cp "${EXISTING_ROOT_CA_DIR}/rootCA.srl" "${CA_DIR}/rootCA.srl"
            fi

            print_message "info" "  - Copied to: ${CA_DIR}/"
            SSL_CA_PATH="${CA_DIR}/rootCA.crt"
        else
            print_message "error" "Root CA not found at ${EXISTING_ROOT_CA_DIR:-SCRIPT_DIR}"
            print_message "info" "Please choose option 1 to create a new Root CA"
            return 1
        fi
    fi

    # Generate Server certificate
    print_message "info" "Generating server certificate for $server_ip..."

    # Generate Server private key
    openssl genrsa -out "server-${server_ip}.key" 4096 2>/dev/null

    # Generate CSR (Certificate Signing Request)
    openssl req -new -key "server-${server_ip}.key" -out "server-${server_ip}.csr" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=Matrix/OU=Server/CN=${server_ip}" \
        2>/dev/null

    # Create config file for Subject Alternative Names (SAN)
    cat > "server-${server_ip}.cnf" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
DNS.2 = localhost
IP.1 = ${server_ip}
IP.2 = 127.0.0.1
EOF

    # Sign the certificate with Root CA
    openssl x509 -req -in "server-${server_ip}.csr" -CA rootCA.crt -CAkey rootCA.key \
        -CAcreateserial -out "server-${server_ip}.crt" -days "$SSL_CERT_DAYS" -sha256 \
        -extfile "server-${server_ip}.cnf" 2>/dev/null

    # Create full-chain certificate
    cat "server-${server_ip}.crt" rootCA.crt > cert-full-chain.pem

    # Set global variables for SSL paths
    SSL_KEY_PATH="${CA_DIR}/server-${server_ip}.key"
    SSL_CERT_PATH="${CA_DIR}/cert-full-chain.pem"

    print_message "success" "SSL certificates created successfully"
    print_message "info" "  - Private key: $SSL_KEY_PATH"
    print_message "info" "  - Certificate: $SSL_CERT_PATH"
    print_message "info" "  - Root CA: $SSL_CA_PATH"

    return 0
}

# ===========================================
# FUNCTION: configure_inventory
# Description: Create or update the inventory/hosts file
# Arguments:
#   $1 - Server IP address
#   $2 - Installation mode: "local" or "remote"
# ===========================================
configure_inventory() {
    local server_ip="$1"
    local mode="$2"

    print_message "info" "Configuring inventory..."

    local inventory_file="${PLAYBOOK_DIR}/inventory/hosts"
    local inventory_dir
    inventory_dir="$(dirname "$inventory_file")"

    # Create inventory directory if it doesn't exist
    mkdir -p "$inventory_dir"

    # Create hosts file
    if [[ "$mode" == "local" ]]; then
        # Local installation (ansible_connection=local)
        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by install.sh on $(date)

[matrix_servers]
${server_ip} ansible_connection=local
EOF
        print_message "success" "Inventory configured for local installation"
    else
        # Remote installation (SSH)
        local ansible_user="${SERVER_USER:-$DEFAULT_SSH_USER}"
        local ansible_port="${SERVER_PORT:-22}"
        local ansible_host="${SSH_HOST:-$server_ip}"

        # Build inventory with SSH auth settings
        local inventory_vars="ansible_host=${ansible_host} ansible_ssh_user=${ansible_user} ansible_port=${ansible_port} ansible_become=true ansible_become_user=root"

        # Add SSH key if specified
        if [[ "$USE_SSH_KEY" == "yes" ]] && [[ -n "$SSH_KEY_PATH" ]]; then
            inventory_vars="${inventory_vars} ansible_ssh_private_key_file=${SSH_KEY_PATH}"
            print_message "info" "  - SSH Key: $SSH_KEY_PATH"
        fi

        # Add SSH password if specified (WARNING: stored in plaintext!)
        if [[ -n "$SSH_PASSWORD" ]]; then
            inventory_vars="${inventory_vars} ansible_ssh_pass='${SSH_PASSWORD}'"
            print_message "warning" "  - SSH Password: *** (stored in plaintext)"
        fi

        # Add sudo password if specified (WARNING: stored in plaintext!)
        if [[ -n "$SUDO_PASSWORD" ]]; then
            inventory_vars="${inventory_vars} ansible_become_pass='${SUDO_PASSWORD}'"
            print_message "warning" "  - Sudo Password: *** (stored in plaintext)"
        fi

        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by install.sh on $(date)

[matrix_servers]
${server_ip} ${inventory_vars}
EOF
        print_message "success" "Inventory configured for remote installation"
        print_message "info" "  - Server (Matrix): $server_ip"
        print_message "info" "  - SSH Host: $ansible_host"
        print_message "info" "  - SSH User: $ansible_user"
        print_message "info" "  - SSH Port: $ansible_port"
    fi

    INVENTORY_PATH="$inventory_file"
    return 0
}

# ===========================================
# FUNCTION: configure_vars_yml
# Description: Create the vars.yml configuration file
# Arguments:
#   $1 - Server IP address
#   $2 - Enable IPv6: "true" or "false"
#   $3 - Enable Element: "true" or "false"
# ===========================================
configure_vars_yml() {
    local server_ip="$1"
    local ipv6_enabled="$2"
    local element_enabled="$3"

    print_message "info" "Configuring vars.yml..."

    # Create host_vars directory
    HOST_VARS_DIR="${PLAYBOOK_DIR}/inventory/host_vars/${server_ip}"
    mkdir -p "$HOST_VARS_DIR"

    VARS_YML_PATH="${HOST_VARS_DIR}/vars.yml"

    # Generate secrets if not already generated
    if [[ -z "$MATRIX_SECRET" ]]; then
        MATRIX_SECRET="$(generate_password 64)"
    fi
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD="$(generate_password 32)"
    fi

    # Create vars.yml file
    cat > "$VARS_YML_PATH" <<EOF
# ===========================================
# Matrix Ansible Playbook Configuration
# Generated by install.sh on $(date)
# ===========================================

# -------------------------------------------
# Basic Settings
# -------------------------------------------

# The bare domain name which represents your Matrix identity
matrix_domain: "${server_ip}"

# The Matrix server FQN
matrix_server_fqn_matrix: "${server_ip}"

# Homeserver implementation (synapse, dendrite, conduit, conduwuit, continuwuity)
matrix_homeserver_implementation: "${DEFAULT_HOMESERVER_IMPL}"

# A secret key used for generating various other secrets
matrix_homeserver_generic_secret_key: '${MATRIX_SECRET}'

# Reverse proxy type
matrix_playbook_reverse_proxy_type: playbook-managed-traefik

# IPv6 support
devture_systemd_docker_base_ipv6_enabled: ${ipv6_enabled}

# Postgres password
postgres_connection_password: '${POSTGRES_PASSWORD}'

# -------------------------------------------
# Element Web Client
# -------------------------------------------

matrix_client_element_enabled: ${element_enabled}
matrix_server_fqn_element: "${server_ip}"

# Important: Disable redirect when using IP instead of domain
matrix_synapse_container_labels_public_client_root_enabled: false

# -------------------------------------------
# SSL/TLS Configuration (Self-signed)
# -------------------------------------------

# Disable ACME/Let's Encrypt
traefik_config_certificatesResolvers_acme_enabled: false

# Enable SSL directory
traefik_ssl_dir_enabled: true

# TLS configuration for Traefik
traefik_provider_configuration_extension_yaml: |
  tls:
    certificates:
      - certFile: /ssl/cert.pem
        keyFile: /ssl/privkey.pem
    stores:
      default:
        defaultCertificate:
          certFile: /ssl/cert.pem
          keyFile: /ssl/privkey.pem

# -------------------------------------------
# SSL Files
# -------------------------------------------

aux_file_definitions:
  # Private key
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: ${SSL_KEY_PATH}
    mode: "0600"

  # Full chain certificate (server cert + root CA)
  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: ${SSL_CERT_PATH}
    mode: "0644"
EOF

    print_message "success" "vars.yml created successfully"
    print_message "info" "  - Location: $VARS_YML_PATH"

    return 0
}

# ===========================================
# FUNCTION: create_traefik_directories
# Description: Create Traefik directories manually (workaround for playbook bug)
# Arguments:
#   $1 - Installation mode: "local" or "remote"
# ===========================================
create_traefik_directories() {
    local mode="$1"

    print_message "info" "Creating Traefik directories (workaround for playbook bug)..."

    if [[ "$mode" == "local" ]]; then
        # Create directories locally using ansible (avoids sudo password prompt)
        cd_playbook_and_setup_direnv || return 1

        # Set environment variables for ansible password authentication
        if [[ -n "$SSH_PASSWORD" ]]; then
            export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
        fi
        if [[ -n "$SUDO_PASSWORD" ]]; then
            export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"
        fi

        if ! ansible -i inventory/hosts "$SERVER_IP" -m shell \
            -a "mkdir -p /matrix/traefik/ssl /matrix/traefik/config" \
            --become 2>/dev/null; then
            print_message "error" "Failed to create directories via ansible"
            print_message "info" "Please check:"
            print_message "info" "  - User has sudo permissions"
            print_message "info" "  - Sudo password is correct (if required)"
            return 1
        fi

        if ! ansible -i inventory/hosts "$SERVER_IP" -m shell \
            -a "chown -R matrix:matrix /matrix/ || true" \
            --become 2>/dev/null; then
            print_message "warning" "Failed to set ownership, but directories created"
        fi

        print_message "success" "Traefik directories created locally"
    else
        # Create directories on remote server using ansible ad-hoc command
        cd_playbook_and_setup_direnv || return 1

        # Set environment variables for ansible password authentication
        if [[ -n "$SSH_PASSWORD" ]]; then
            export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
        fi
        if [[ -n "$SUDO_PASSWORD" ]]; then
            export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"
        fi

        if ! ansible -i inventory/hosts all -m shell -a "mkdir -p /matrix/traefik/ssl /matrix/traefik/config" --become 2>/dev/null; then
            print_message "error" "Failed to create directories via ansible"
            print_message "info" "Please check:"
            print_message "info" "  - SSH connection to server"
            print_message "info" "  - SSH keys are properly configured"
            print_message "info" "  - User has sudo permissions"
            return 1
        fi

        if ! ansible -i inventory/hosts all -m shell -a "chown -R matrix:matrix /matrix/ || true" --become 2>/dev/null; then
            print_message "warning" "Failed to set ownership, but directories created"
        fi

        print_message "success" "Traefik directories created on remote server"
    fi

    return 0
}

# ===========================================
# FUNCTION: install_ansible_roles
# Description: Install Ansible roles from requirements.yml
# ===========================================
install_ansible_roles() {
    print_message "info" "Installing Ansible roles..."

    cd_playbook_and_setup_direnv || return 1

    if ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force >> "$LOG_FILE" 2>&1; then
        print_message "success" "Ansible roles installed successfully"
        return 0
    else
        print_message "error" "Failed to install Ansible roles"
        print_message "info" "Check log file for details: $LOG_FILE"
        return 1
    fi
}

# ===========================================
# FUNCTION: run_playbook
# Description: Run the Ansible playbook for installation
# Arguments:
#   $1 - Tags to run (default: install-all,ensure-matrix-users-created,start)
# ===========================================
run_playbook() {
    local tags="${1:-install-all,ensure-matrix-users-created,start}"

    print_message "info" "Running Ansible playbook..."
    print_message "warning" "This may take 10-20 minutes, please be patient..."

    cd_playbook_and_setup_direnv || return 1

    # Set locale for consistent output
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    # Run playbook with live output (also save to log)
    if ansible-playbook -i inventory/hosts setup.yml --tags="$tags" 2>&1 | tee -a "$LOG_FILE"; then
        print_message "success" "Playbook executed successfully"
        return 0
    else
        print_message "error" "Playbook execution failed"
        print_message "info" "Check log file for details: $LOG_FILE"
        return 1
    fi
}

# ===========================================
# FUNCTION: create_admin_user
# Description: Create the admin user for Matrix
# Arguments:
#   $1 - Username
#   $2 - Password
# ===========================================
create_admin_user() {
    local username="$1"
    local password="$2"

    print_message "info" "Creating admin user..."

    cd_playbook_and_setup_direnv || return 1

    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    # Run playbook and capture output (also save to log file)
    local output
    output=$(ansible-playbook -i inventory/hosts setup.yml \
        --extra-vars="username=${username} password=${password} admin=yes" \
        --tags=register-user 2>&1 | tee -a "$LOG_FILE")
    local exit_code=$?

    # Check if user already exists (not a fatal error)
    if echo "$output" | grep -q "User ID already taken"; then
        print_message "warning" "Admin user '$username' already exists (skipping creation)"
        print_message "info" "  - Username: $username"
        return 0
    fi

    # Check for successful execution (exit code 0 AND no failures)
    if [[ $exit_code -eq 0 ]] && ! echo "$output" | grep -q "failed=[1-9]"; then
        print_message "success" "Admin user created successfully"
        print_message "info" "  - Username: $username"
        return 0
    fi

    # Actual failure
    print_message "error" "Failed to create admin user"
    print_message "info" "You can create it manually later"
    return 1
}

# ===========================================
# FUNCTION: cleanup_existing_postgres_data
# Description: Remove existing PostgreSQL data to prevent password mismatch
# Arguments:
#   $1 - Installation mode: "local" or "remote"
# ===========================================
cleanup_existing_postgres_data() {
    local mode="$1"

    cd_playbook_and_setup_direnv || return 1

    # Set environment variables for ansible password authentication
    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
    if [[ -n "$SUDO_PASSWORD" ]]; then
        export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"
    fi

    # Determine target (use SERVER_IP for local, 'all' for remote)
    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    # Check if postgres data directory exists
    print_message "info" "Checking for existing PostgreSQL data..."

    local check_output
    check_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "test -d /matrix/postgres && echo 'EXISTS' || echo 'NOT_FOUND'" \
        --become 2>/dev/null | grep -v "$target |")

    if [[ "$check_output" != *"EXISTS"* ]]; then
        print_message "info" "No existing PostgreSQL data found (clean installation)"
        return 0
    fi

    # PostgreSQL data exists - warn user and ask for confirmation
    echo ""
    print_message "warning" "Existing PostgreSQL data found on target server!"
    print_message "warning" "This will cause installation to fail due to password mismatch."
    print_message "info" "The existing data must be removed before installation."
    echo ""
    print_message "info" "WARNING: This will DELETE all existing Matrix database data!"
    print_message "info" "Including: users, messages, rooms, settings"

    if [[ "$(prompt_yes_no "Delete existing PostgreSQL data and continue?" "n")" != "yes" ]]; then
        print_message "info" "Installation cancelled by user"
        exit 0
    fi

    # Remove postgres data
    print_message "info" "Removing existing PostgreSQL data..."

    if ansible -i inventory/hosts "$target" -m shell \
        -a "rm -rf /matrix/postgres" \
        --become 2>/dev/null; then
        print_message "success" "PostgreSQL data removed successfully"
        return 0
    else
        print_message "error" "Failed to remove PostgreSQL data"
        return 1
    fi
}

# ===========================================
# FUNCTION: cleanup_matrix_services
# Description: Aggressively stop and remove all Matrix services and containers
# Arguments:
#   $1 - Installation mode: "local" or "remote"
# ===========================================
cleanup_matrix_services() {
    local mode="$1"

    cd_playbook_and_setup_direnv || return 1

    # Set environment variables for ansible password authentication
    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
    if [[ -n "$SUDO_PASSWORD" ]]; then
        export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"
    fi

    # Determine target (use SERVER_IP for local, 'all' for remote)
    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    # Check if any Matrix services exist
    print_message "info" "Checking for existing Matrix services..."

    local check_output
    check_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "systemctl list-units --all | grep -E 'matrix-.*\.service' | grep -v 'not found'" \
        --become 2>/dev/null | grep -v "$target |")

    if [[ -z "$check_output" ]] && [[ "$check_output" != *"matrix-"* ]]; then
        print_message "info" "No existing Matrix services found"
        return 0
    fi

    # Matrix services exist - warn user
    echo ""
    print_message "warning" "Existing Matrix services detected!"
    print_message "info" "The following services will be STOPPED and DISABLED:"
    echo "$check_output" | grep -oE "matrix-[^ ]+" | sort -u | while read -r svc; do
        print_message "info" "  - $svc"
    done
    echo ""

    # Also check for Docker containers
    local docker_check
    docker_check=$(ansible -i inventory/hosts "$target" -m shell \
        -a 'docker ps -a --format "{{"{{"}}.Names{{"}}"}}" 2>/dev/null | grep "^matrix-" || true' \
        --become 2>/dev/null | grep -v "$target |")

    if [[ -n "$docker_check" ]]; then
        print_message "warning" "Existing Matrix Docker containers detected:"
        echo "$docker_check" | while read -r container; do
            print_message "info" "  - $container"
        done
        echo ""
    fi

    print_message "warning" "This will STOP and DISABLE all Matrix services and REMOVE containers!"
    print_message "info" "Data in /matrix/postgres has already been cleaned separately."

    if [[ "$(prompt_yes_no "Stop and remove all Matrix services and containers?" "y")" != "yes" ]]; then
        print_message "info" "Cleanup cancelled by user"
        return 1
    fi

    # Stop and disable all Matrix services
    print_message "info" "Stopping Matrix services..."

    ansible -i inventory/hosts "$target" -m shell \
        -a "systemctl stop matrix-*.service 2>/dev/null || true" \
        --become 2>/dev/null

    ansible -i inventory/hosts "$target" -m shell \
        -a "systemctl disable matrix-*.service 2>/dev/null || true" \
        --become 2>/dev/null

    print_message "success" "Matrix services stopped and disabled"

    # Remove Docker containers
    print_message "info" "Removing Matrix Docker containers..."

    ansible -i inventory/hosts "$target" -m shell \
        -a 'docker ps -a --format "{{"{{"}}.Names{{"}}"}}" | grep "^matrix-" | xargs -r docker rm -f 2>/dev/null || true' \
        --become 2>/dev/null

    print_message "success" "Matrix Docker containers removed"

    # Optional: Remove Docker volumes (more aggressive)
    print_message "info" "Checking for Matrix Docker volumes..."

    local volumes_output
    volumes_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a 'docker volume ls --format "{{"{{"}}.Name{{"}}"}}" 2>/dev/null | grep "^matrix-" || true' \
        --become 2>/dev/null | grep -v "$target |")

    if [[ -n "$volumes_output" ]]; then
        print_message "warning" "Matrix Docker volumes found:"
        echo "$volumes_output" | while read -r vol; do
            print_message "info" "  - $vol"
        done
        echo ""

        if [[ "$(prompt_yes_no "Remove Matrix Docker volumes as well? This may delete additional data." "n")" == "yes" ]]; then
            ansible -i inventory/hosts "$target" -m shell \
                -a 'docker volume ls --format "{{"{{"}}.Name{{"}}"}}" | grep "^matrix-" | xargs -r docker volume rm -f 2>/dev/null || true' \
                --become 2>/dev/null
            print_message "success" "Matrix Docker volumes removed"
        fi
    fi

    print_message "success" "Matrix services cleanup completed"
    return 0
}

# ===========================================
# FUNCTION: prompt_user
# Description: Prompt user for input with a default value
# Arguments:
#   $1 - Prompt message
#   $2 - Default value (optional)
# Output: User input or default value
# ===========================================
prompt_user() {
    local prompt="$1"
    local default="${2:-}"

    if [[ -n "$default" ]]; then
        prompt="$prompt [$default]"
    fi

    read -rp "$prompt: " input

    if [[ -z "$input" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$input"
    fi
}

# ===========================================
# FUNCTION: prompt_yes_no
# Description: Prompt user for yes/no confirmation
# Arguments:
#   $1 - Prompt message
#   $2 - Default value: "y" or "n" (default: "n")
# Output: "yes" or "no"
# ===========================================
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    # Always show y/n/Default
    while true; do
        read -rp "$prompt [y/n/Default]: " answer

        # If empty (Enter pressed), return default
        if [[ -z "$answer" ]]; then
            if [[ "$default" == "y" ]] || [[ "$default" == "yes" ]] || [[ "$default" == "true" ]]; then
                echo "yes"
                return 0
            else
                echo "no"
                return 0
            fi
        fi

        # Otherwise check the answer
        case "$answer" in
            y|Y|yes|YES)
                echo "yes"
                return 0
                ;;
            n|N|no|NO)
                echo "no"
                return 0
                ;;
            *)
                echo "Please answer yes, no, or press Enter for default."
                ;;
        esac
    done
}

# ===========================================
# FUNCTION: prompt_ssl_option
# Description: Prompt user for SSL certificate option
# Arguments:
#   $1 - Default value: "1" or "2" (default: "1")
# Output: "1" or "2"
# ===========================================
prompt_ssl_option() {
    local default="${1:-1}"

    # Check if Root CA exists in script directory (for loading existing)
    local has_root_ca=false
    if [[ -f "${SCRIPT_DIR}/rootCA.key" ]] && [[ -f "${SCRIPT_DIR}/rootCA.crt" ]]; then
        has_root_ca=true
    fi

    # Display menu to stderr so it shows even when output is captured
    if [[ "$has_root_ca" == true ]]; then
        echo >&2 ""
        # Using echo -e for colors
        echo >&2 -e "${BLUE}Select SSL certificate option:${NC}"
        echo >&2 ""
        echo >&2 "  1) Create new Root CA + Server certificate"
        echo >&2 "     - Generates: rootCA.key, rootCA.crt, server cert"

        # Check if there's also one in matrix-ca
        if [[ -f "${CA_DIR}/rootCA.key" ]] && [[ -f "${CA_DIR}/rootCA.crt" ]]; then
            echo >&2 -e "     - ${YELLOW}Warning: Existing Root CA in matrix-ca will be overwritten!${NC}"
        fi

        echo >&2 ""
        echo >&2 "  2) Use existing Root CA + Create Server certificate"
        echo >&2 "     - Reuses Root CA from: $SCRIPT_DIR"
        echo >&2 "     - Generates new server certificate"
        echo >&2 ""

        while true; do
            read -rp "Enter your choice (1 or 2) [Default: 1]: " choice

            if [[ -z "$choice" ]]; then
                echo "$default"
                # Also output the existing root ca dir path
                echo "$SCRIPT_DIR"
                return 0
            fi

            case "$choice" in
                1|2)
                    echo "$choice"
                    # Also output the existing root ca dir path
                    echo "$SCRIPT_DIR"
                    return 0
                    ;;
                *)
                    echo "Invalid choice. Please enter 1 or 2."
                    ;;
            esac
        done
    else
        # No Root CA exists, only option is to create new one
        echo >&2 ""
        echo >&2 -e "${BLUE}SSL Certificate Configuration:${NC}"
        echo >&2 ""
        echo >&2 "  1) Create new Root CA + Server certificate"
        echo >&2 "     - Generates: rootCA.key, rootCA.crt, server cert"
        echo >&2 "     - Files will be created in: $CA_DIR"
        echo >&2 ""

        # No choice needed, return 1 automatically
        echo "1"
        echo ""
        return 0
    fi
}

# ===========================================
# FUNCTION: print_summary
# Description: Print installation summary
# ===========================================
print_summary() {
    echo ""
    echo -e "${GREEN}========================================
MATRIX INSTALLATION COMPLETE
========================================${NC}"

    echo -e "${BLUE}Server Information:${NC}
  - IP/Domain: ${SERVER_IP}
  - Installation Mode: ${INSTALLATION_MODE}
"

    echo -e "${BLUE}Admin User:${NC}
  - Username: ${ADMIN_USERNAME}
  - Password: ${ADMIN_PASSWORD}
"

    echo -e "${BLUE}Access URLs:${NC}
  - Matrix API: https://${SERVER_IP}/_matrix/client/versions
  - Element Web: https://${SERVER_IP}/
"

    echo -e "${BLUE}Important Files:${NC}
  - Vars YAML: ${VARS_YML_PATH}
  - Inventory: ${INVENTORY_PATH}
  - SSL Cert: ${SSL_CERT_PATH}
  - Root CA: ${SSL_CA_PATH}
"

    echo -e "${BLUE}Next Steps:${NC}
  1. Access https://${SERVER_IP}/ in your browser
  2. Log in with your admin credentials
"

    echo -e "${YELLOW}Note:${NC} Save this information securely!
"

    echo -e "${GREEN}========================================${NC}
"
    echo "Log file: $LOG_FILE"
    echo ""
}

# ===========================================
# FUNCTION: main
# Description: Main execution flow
# ===========================================
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Matrix Ansible Playbook Installation Log - $(date)" > "$LOG_FILE"

    # Print banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     Matrix Ansible Playbook Auto-Installer v1.0.0       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # ============================================
    # PHASE 1: Environment Detection
    # ============================================
    print_message "info" "=== PHASE 1: Environment Detection ==="

    detect_os || exit 1
    check_prerequisites

    # ============================================
    # PHASE 2: User Inputs (Collect all information first)
    # ============================================
    print_message "info" "=== PHASE 2: User Inputs ==="

    # Installation Mode
    cat <<'EOF'

Select installation mode:

  1) This Is Server
     - Install Matrix on THIS machine
     - Ansible will run locally (ansible_connection=local)

  2) Remote VPS
     - Install Matrix on a remote server via SSH
     - You need SSH access to the server

  3) Generate a new Root Key
     - Only create Root CA certificate
     - Can be used for multiple Matrix servers later

EOF

    while true; do
        read -rp "Enter your choice (1, 2 or 3): " choice

        case "$choice" in
            1)
                INSTALLATION_MODE="local"
                print_message "info" "Local installation mode selected"
                echo ""
                # Detect server IP (works on both Arch and Debian/Ubuntu)
                # Method 1: Get IP via default route (most reliable)
                SERVER_IP="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
                # Method 2: Fallback - first non-loopback IPv4
                if [[ -z "$SERVER_IP" ]]; then
                    SERVER_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)"
                fi
                if [[ -z "$SERVER_IP" ]]; then
                    print_message "warning" "Could not auto-detect IP address"
                    SERVER_IP="$(prompt_user "Enter server IP address")"
                else
                    echo ""
                    echo "Detected IP addresses:"
                    ip -br addr 2>/dev/null || ifconfig 2>/dev/null | grep "inet "
                    echo ""
                    if [[ "$(prompt_yes_no "Use '$SERVER_IP' as server IP?" "y")" == "yes" ]]; then
                        print_message "info" "Server IP: $SERVER_IP"
                    else
                        SERVER_IP="$(prompt_user "Enter server IP address")"
                        print_message "info" "Server IP: $SERVER_IP"
                    fi
                fi

                # Sudo password setup
                echo ""
                if [[ "$(prompt_yes_no "Does your user need sudo password?" "y")" == "yes" ]]; then
                    SUDO_PASSWORD="$(prompt_user "Sudo password")"
                    print_message "info" "Sudo password will be used"
                else
                    SUDO_PASSWORD=""
                    print_message "info" "Assuming passwordless sudo"
                fi

                print_message "info" "Target server: localhost (Matrix on $SERVER_IP)"
                break
                ;;
            2)
                INSTALLATION_MODE="remote"
                print_message "info" "Remote installation mode selected"
                # Get server details
                SERVER_IP="$(prompt_user "Enter server IP address or domain")"
                SERVER_USER="$(prompt_user "SSH username" "$DEFAULT_SSH_USER")"
                SSH_HOST="$(prompt_user "SSH host" "$SERVER_IP")"
                SERVER_PORT="$(prompt_user "SSH port" "22")"

                # SSH Authentication setup
                echo ""
                print_message "info" "SSH Authentication:"
                if [[ "$(prompt_yes_no "Use custom SSH key?" "n")" == "yes" ]]; then
                    SSH_KEY_PATH="$(prompt_user "SSH key path" "$HOME/.ssh/id_rsa")"
                    if [[ ! -f "$SSH_KEY_PATH" ]]; then
                        print_message "warning" "SSH key not found at $SSH_KEY_PATH"
                        if [[ "$(prompt_yes_no "Continue anyway?" "n")" != "yes" ]]; then
                            print_message "info" "Please specify a valid SSH key path"
                            exit 1
                        fi
                    fi
                    USE_SSH_KEY="yes"
                    print_message "info" "Using SSH key: $SSH_KEY_PATH"
                else
                    # Ask about password authentication
                    if [[ "$(prompt_yes_no "Use password authentication?" "n")" == "yes" ]]; then
                        USE_SSH_KEY="no"
                        SSH_PASSWORD="$(prompt_user "SSH password")"
                        print_message "info" "Password authentication will be used"
                    else
                        USE_SSH_KEY="no"
                        SSH_PASSWORD=""
                        print_message "info" "Using default SSH agent or keys"
                    fi
                fi

                # Sudo password setup
                echo ""
                if [[ "$(prompt_yes_no "Does ${SERVER_USER} need sudo password?" "y")" == "yes" ]]; then
                    SUDO_PASSWORD="$(prompt_user "Sudo password")"
                    print_message "info" "Sudo password will be used"
                else
                    SUDO_PASSWORD=""
                    print_message "info" "Assuming passwordless sudo"
                fi

                print_message "info" "Target server: ${SERVER_USER}@${SSH_HOST}:${SERVER_PORT} → Matrix on ${SERVER_IP}"
                break
                ;;
            3)
                INSTALLATION_MODE="generate-root-ca"
                print_message "info" "Generate Root CA mode selected"
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2 or 3."
                ;;
        esac
    done

    # ============================================
    # Branch based on installation mode
    # ============================================
    if [[ "$INSTALLATION_MODE" == "generate-root-ca" ]]; then
        # ============================================
        # MODE: Generate Root CA only
        # ============================================
        print_message "info" "=== Root CA Generation ==="

        create_root_ca || exit 1

        # Summary for Root CA generation
        echo ""
        print_message "info" "=== Root CA Summary ==="
        echo ""
        echo "  Mode:              Generate Root CA"
        echo "  Root CA Key:       ${CA_DIR}/rootCA.key"
        echo "  Root CA Cert:      ${CA_DIR}/rootCA.crt"
        echo ""
        print_message "success" "Root CA generation completed!"
        print_message "info" "You can now use this Root CA for Matrix installations."
        exit 0
    fi

    # ============================================
    # MODE: Matrix Installation (local or remote)
    # ============================================

    # Configuration
    echo ""
    print_message "info" "Configuration options:"

    ipv6_answer="$(prompt_yes_no "Enable IPv6 support?" "$DEFAULT_IPV6_ENABLED")"
    IPV6_ENABLED="$([ "$ipv6_answer" == "yes" ] && echo "true" || echo "false")"

    element_answer="$(prompt_yes_no "Enable Element Web?" "$DEFAULT_ELEMENT_ENABLED")"
    ELEMENT_ENABLED="$([ "$element_answer" == "yes" ] && echo "true" || echo "false")"

    # Admin user
    echo ""
    print_message "info" "Create admin user:"
    ADMIN_USERNAME="$(prompt_user "Username" "admin")"
    ADMIN_PASSWORD="$(prompt_user "Password" "$(generate_password 16)")"

    # SSL Certificates
    echo ""
    SSL_OUTPUT="$(prompt_ssl_option "1")"
    SSL_OPTION="$(echo "$SSL_OUTPUT" | head -n1)"
    EXISTING_ROOT_CA_DIR="$(echo "$SSL_OUTPUT" | tail -n1)"

    # Summary of inputs
    echo ""
    print_message "info" "=== Installation Summary ==="
    echo ""
    echo "  Server IP:         $SERVER_IP"
    echo "  Installation Mode: $INSTALLATION_MODE"
    if [[ "$INSTALLATION_MODE" == "remote" ]]; then
        echo "  SSH Host:          ${SSH_HOST:-$SERVER_IP}"
        echo "  SSH Port:          $SERVER_PORT"
        echo "  SSH User:          $SERVER_USER"
    fi
    echo "  IPv6:              $IPV6_ENABLED"
    echo "  Element Web:       $ELEMENT_ENABLED"
    echo "  Admin Username:    $ADMIN_USERNAME"
    if [[ "$SSL_OPTION" == "1" ]]; then
        echo "  SSL Option:        Create new Root CA"
    else
        echo "  SSL Option:        Use existing Root CA"
    fi
    echo ""

    if [[ "$(prompt_yes_no "Proceed with installation?" "y")" != "yes" ]]; then
        print_message "info" "Installation cancelled by user"
        exit 0
    fi

    # ============================================
    # PHASE 3: Install Prerequisites
    # ============================================
    print_message "info" "=== PHASE 3: Install Prerequisites ==="

    if [[ "$HAS_ANSIBLE" == false ]]; then
        print_message "warning" "Ansible is not installed, installing..."
        install_ansible || exit 1
    else
        print_message "success" "Ansible is already installed"
    fi

    # ============================================
    # PHASE 4: Ensure Playbook
    # ============================================
    print_message "info" "=== PHASE 4: Ensure Playbook ==="

    ensure_playbook_exists || exit 1

    # ============================================
    # PHASE 5: SSL Certificates
    # ============================================
    print_message "info" "=== PHASE 5: SSL Certificates ==="

    create_ssl_certificates "$SERVER_IP" "$SSL_OPTION" || exit 1

    # ============================================
    # PHASE 6: Configure Playbook
    # ============================================
    print_message "info" "=== PHASE 6: Configure Playbook ==="

    configure_inventory "$SERVER_IP" "$INSTALLATION_MODE" || exit 1
    configure_vars_yml "$SERVER_IP" "$IPV6_ENABLED" "$ELEMENT_ENABLED" || exit 1
    create_traefik_directories "$INSTALLATION_MODE" || exit 1

    # ============================================
    # PHASE 7: Install Ansible Roles
    # ============================================
    print_message "info" "=== PHASE 7: Install Ansible Roles ==="

    install_ansible_roles || exit 1

    # ============================================
    # PHASE 8: Pre-flight Check
    # ============================================
    print_message "info" "=== PHASE 8: Pre-flight Check ==="

    print_message "info" "Running pre-flight check..."
    cd_playbook_and_setup_direnv || exit 1
    export LC_ALL=C.UTF-8 LANG=C.UTF-8
    if ansible-playbook -i inventory/hosts setup.yml --tags=check-all >> "$LOG_FILE" 2>&1; then
        print_message "success" "Pre-flight check passed"
    else
        print_message "warning" "Pre-flight check found some issues"
        if [[ "$(prompt_yes_no "Continue anyway?" "n")" == "no" ]]; then
            print_message "error" "Installation cancelled"
            exit 1
        fi
    fi

    # ============================================
    # PHASE 8.5: Final Confirmation
    # ============================================
    print_message "info" "=== PHASE 8.5: Final Confirmation ==="

    echo ""
    print_message "info" "All configurations have been applied and pre-flight check passed."
    print_message "warning" "Installation will take 10-20 minutes."

    if [[ "$(prompt_yes_no "Start installation now?" "y")" != "yes" ]]; then
        print_message "info" "Installation cancelled by user"
        print_message "info" "All configurations are in place."
        print_message "info" "You can run the installation manually:"
        print_message "info" "  cd $PLAYBOOK_DIR"
        print_message "info" "  ansible-playbook -i inventory/hosts setup.yml --tags=install-all,start"
        print_message "info" ""
        print_message "info" "Or create admin user:"
        print_message "info" "  cd $PLAYBOOK_DIR"
        print_message "info" "  ansible-playbook -i inventory/hosts setup.yml --extra-vars=\"username=<user> password=<pass> admin=yes\" --tags=register-user"
        exit 0
    fi

    # ============================================
    # PHASE 8.6: Cleanup Existing Data (if any)
    # ============================================
    print_message "info" "=== PHASE 8.6: Cleanup Existing Data ==="

    if ! cleanup_existing_postgres_data "$INSTALLATION_MODE"; then
        print_message "error" "Failed to cleanup existing data"
        print_message "info" "Please manually remove /matrix/postgres on the target server"
        exit 1
    fi

    # ============================================
    # PHASE 8.7: Cleanup Matrix Services (if any)
    # ============================================
    print_message "info" "=== PHASE 8.7: Cleanup Matrix Services ==="

    if ! cleanup_matrix_services "$INSTALLATION_MODE"; then
        print_message "warning" "Matrix services cleanup was cancelled or failed"
        print_message "info" "Installation will continue, but may encounter issues"
    fi

    # ============================================
    # PHASE 9: Run Installation
    # ============================================
    print_message "info" "=== PHASE 9: Installation ==="

    run_playbook "install-all,ensure-matrix-users-created,start" || exit 1

    # ============================================
    # PHASE 10: Create Admin User
    # ============================================
    print_message "info" "=== PHASE 10: Create Admin User ==="

    if ! create_admin_user "$ADMIN_USERNAME" "$ADMIN_PASSWORD"; then
        print_message "warning" "Admin user creation failed, but installation is complete"
        print_message "info" "You can create the admin user manually later"
    fi

    # ============================================
    # PHASE 11: Summary
    # ============================================
    print_summary

    print_message "success" "Installation completed successfully!"
}

# ============================================
# SCRIPT ENTRY POINT
# ============================================
main "$@"
