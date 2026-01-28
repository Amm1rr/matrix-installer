#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="ansible-synapse"
ADDON_NAME_MENU="Install Synapse (Ansible with Private Key)"
ADDON_VERSION="0.1.0"
ADDON_ORDER="30"
ADDON_DESCRIPTION="Self-contained Ansible module for Synapse homeserver installation"
ADDON_AUTHOR="Matrix Installer"
ADDON_HIDDEN="false" # Hide this addon from the menu

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

# ===========================================
# CONFIGURATION
# ===========================================

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="$(pwd)"
PLAYBOOK_DIR="${WORKING_DIR}/matrix-docker-ansible-deploy"
LOG_FILE="${WORKING_DIR}/ansible-synapse.log"

# Default configuration values
DEFAULT_HOMESERVER_IMPL="synapse"
DEFAULT_IPV6_ENABLED="true"
DEFAULT_ELEMENT_ENABLED="true"

# Ansible settings
ANSIBLE_MIN_VERSION="2.15.1"
MATRIX_PLAYBOOK_REPO_URL="https://github.com/spantaleev/matrix-docker-ansible-deploy.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===========================================
# ENVIRONMENT VARIABLES FROM matrix-installer.sh
# ===========================================

# Expected from matrix-installer.sh:
# - SERVER_NAME: Matrix server identity (IP or domain)
# - SSL_CERT: Full chain certificate path
# - SSL_KEY: Private key path
# - ROOT_CA: Root Key certificate path
# - CERTS_DIR: Certificate directory
# - WORKING_DIR: Working directory

# ===========================================
# GLOBAL VARIABLES
# ===========================================

OS_TYPE=""
OS_DISTRO=""
HAS_ANSIBLE=false
HAS_GIT=false
HAS_PYTHON=false

INSTALLATION_MODE="local"
SERVER_IP=""
SERVER_IS_IP=""

MATRIX_SECRET=""
POSTGRES_PASSWORD=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""

IPV6_ENABLED=""
ELEMENT_ENABLED=""

HOST_VARS_DIR=""
VARS_YML_PATH=""
INVENTORY_PATH=""

# Certificate paths (for standalone mode)
STANDALONE_CERTS_DIR=""

# ===========================================
# HELPER FUNCTIONS
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

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$msg_type] $message" >> "$LOG_FILE"
}

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

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    while true; do
        local default_display
        if [[ "$default" == "y" ]]; then
            default_display="Y/n"
        else
            default_display="y/N"
        fi

        read -rp "$prompt [$default_display]: " answer

        if [[ -z "$answer" ]]; then
            answer="$default"
        fi

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
                echo "Please answer yes or no."
                ;;
        esac
    done
}

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

is_ip_address() {
    local input="$1"

    if [[ "$input" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($input)
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done
        return 0
    fi

    if [[ "$input" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$input" == *:* ]]; then
        return 0
    fi

    return 1
}

cd_playbook_and_setup_direnv() {
    cd "$PLAYBOOK_DIR" || return 1

    if [[ -f ".envrc" ]] && command -v direnv &> /dev/null; then
        if direnv status . 2>/dev/null | grep -q "Blocked"; then
            print_message "info" "Approving .envrc for direnv..."
            direnv allow . 2>/dev/null || true
        fi
    fi

    return 0
}

# ===========================================
# ENVIRONMENT VARIABLES CHECK (STANDALONE SUPPORT)
# ===========================================

check_environment_variables() {
    print_message "info" "Checking environment variables..."

    local missing=()
    [[ -z "${SERVER_NAME:-}" ]] && missing+=("SERVER_NAME")
    [[ -z "${SSL_CERT:-}" ]] && missing+=("SSL_CERT")
    [[ -z "${SSL_KEY:-}" ]] && missing+=("SSL_KEY")
    [[ -z "${ROOT_CA:-}" ]] && missing+=("ROOT_CA")

    # If no variables missing, just verify files exist and return
    if [[ ${#missing[@]} -eq 0 ]]; then
        # Verify certificate files exist
        if [[ ! -f "$SSL_CERT" ]]; then
            print_message "error" "SSL certificate file not found: $SSL_CERT"
            exit 1
        fi
        if [[ ! -f "$SSL_KEY" ]]; then
            print_message "error" "SSL key file not found: $SSL_KEY"
            exit 1
        fi
        if [[ ! -f "$ROOT_CA" ]]; then
            print_message "error" "Root CA file not found: $ROOT_CA"
            exit 1
        fi

        # Derive CERTS_DIR from certificate paths
        CERTS_DIR="$(dirname "$SSL_CERT")"
        while [[ "$CERTS_DIR" != "/" && ! -d "$CERTS_DIR/certs" && "$(basename "$CERTS_DIR")" != "certs" ]]; do
            CERTS_DIR="$(dirname "$CERTS_DIR")"
        done
        if [[ "$(basename "$CERTS_DIR")" != "certs" ]]; then
            CERTS_DIR="$(dirname "$SSL_CERT")"
        fi

        return 0
    fi

    # ============================================
    # STANDALONE MODE: Prompt for certificates
    # ============================================

    print_message "warning" "Running in standalone mode (not from matrix-installer.sh)"
    echo ""
    echo "Provide certificates directory, and I'll search for:"
    echo "  - cert-full-chain.pem (server certificate chain)"
    echo "  - server.crt (server certificate)"
    echo "  - server.key (server private key)"
    echo "  - rootCA.crt (Root CA certificate)"
    echo "  - rootCA.key (Root CA private key)"
    echo ""

    local found_cert=""
    local found_key=""
    local found_ca=""
    local found_ca_key=""

    # Prompt for certificates directory
    local certs_dir
    while true; do
        certs_dir="$(prompt_user "Certificates directory (or press Enter for individual paths)" "")"

        if [[ -z "$certs_dir" ]]; then
            # User wants to provide individual paths
            break
        fi

        if [[ ! -d "$certs_dir" ]]; then
            print_message "error" "Directory not found: $certs_dir"
            continue
        fi

        # Search for certificate files in the provided directory
        [[ -f "$certs_dir/cert-full-chain.pem" ]] && found_cert="$certs_dir/cert-full-chain.pem"
        [[ -z "$found_cert" && -f "$certs_dir/server.crt" ]] && found_cert="$certs_dir/server.crt"
        [[ -f "$certs_dir/server.key" ]] && found_key="$certs_dir/server.key"

        # Search for Root CA files (in provided directory, then up to 2 levels up)
        if [[ ! -f "$certs_dir/rootCA.crt" ]]; then
            # Try parent directory
            local parent_dir="$(dirname "$certs_dir")"
            [[ -f "$parent_dir/rootCA.crt" ]] && found_ca="$parent_dir/rootCA.crt"

            # Try grandparent directory (2 levels up)
            if [[ -z "$found_ca" ]]; then
                local grandparent_dir="$(dirname "$parent_dir")"
                [[ -f "$grandparent_dir/rootCA.crt" ]] && found_ca="$grandparent_dir/rootCA.crt"
            fi
        else
            found_ca="$certs_dir/rootCA.crt"
        fi

        if [[ ! -f "$certs_dir/rootCA.key" ]]; then
            # Try parent directory
            local parent_dir="$(dirname "$certs_dir")"
            [[ -f "$parent_dir/rootCA.key" ]] && found_ca_key="$parent_dir/rootCA.key"

            # Try grandparent directory (2 levels up)
            if [[ -z "$found_ca_key" ]]; then
                local grandparent_dir="$(dirname "$parent_dir")"
                [[ -f "$grandparent_dir/rootCA.key" ]] && found_ca_key="$grandparent_dir/rootCA.key"
            fi
        else
            found_ca_key="$certs_dir/rootCA.key"
        fi

        # Check what we found
        local missing_files=()
        [[ -z "$found_cert" ]] && missing_files+=("cert-full-chain.pem or server.crt")
        [[ -z "$found_key" ]] && missing_files+=("server.key")
        [[ -z "$found_ca" ]] && missing_files+=("rootCA.crt")
        [[ -z "$found_ca_key" ]] && missing_files+=("rootCA.key")

        if [[ ${#missing_files[@]} -eq 0 ]]; then
            # Found all files
            print_message "success" "All certificate files found!"
            break
        fi

        print_message "warning" "Missing files: ${missing_files[*]}"
        if [[ "$(prompt_yes_no "Try a different directory?" "y")" == "yes" ]]; then
            continue
        fi

        # Fall through to individual prompts
        break
    done

    # ============================================
    # FALLBACK: Prompt for individual paths
    # ============================================

    if [[ -z "$found_cert" ]]; then
        while [[ ! -f "$found_cert" ]]; do
            found_cert="$(prompt_user "Path to server certificate (cert-full-chain.pem or server.crt)")"
            if [[ ! -f "$found_cert" ]]; then
                print_message "error" "File not found: $found_cert"
            fi
        done
    fi

    if [[ -z "$found_key" ]]; then
        while [[ ! -f "$found_key" ]]; do
            found_key="$(prompt_user "Path to server private key (server.key)")"
            if [[ ! -f "$found_key" ]]; then
                print_message "error" "File not found: $found_key"
            fi
        done
    fi

    if [[ -z "$found_ca" ]]; then
        while [[ ! -f "$found_ca" ]]; do
            found_ca="$(prompt_user "Path to Root CA certificate (rootCA.crt)")"
            if [[ ! -f "$found_ca" ]]; then
                print_message "error" "File not found: $found_ca"
            fi
        done
    fi

    if [[ -z "$found_ca_key" ]]; then
        while [[ ! -f "$found_ca_key" ]]; do
            found_ca_key="$(prompt_user "Path to Root CA private key (rootCA.key)")"
            if [[ ! -f "$found_ca_key" ]]; then
                print_message "error" "File not found: $found_ca_key"
            fi
        done
    fi

    # Export the found paths
    export SERVER_NAME="${SERVER_NAME:-$(prompt_user "Server name (IP or domain)")}"
    export SSL_CERT="$found_cert"
    export SSL_KEY="$found_key"
    export ROOT_CA="$found_ca"

    # Derive CERTS_DIR from certificate paths
    STANDALONE_CERTS_DIR="$(dirname "$found_cert")"
    export CERTS_DIR="$STANDALONE_CERTS_DIR"
    export ROOT_CA_DIR="$(dirname "$found_ca")"
    export WORKING_DIR="${WORKING_DIR:-$(pwd)}"

    print_message "success" "Environment variables configured:"
    echo "  SERVER_NAME=$SERVER_NAME"
    echo "  SSL_CERT=$SSL_CERT"
    echo "  SSL_KEY=$SSL_KEY"
    echo "  ROOT_CA=$ROOT_CA"
    echo ""

    return 0
}

# ===========================================
# OS DETECTION HELPER
# ===========================================

# Get OS family: "arch", "debian", or "unknown"
# Usage: get_os_family "local" or get_os_family "remote" "$target"
get_os_family() {
    local mode="$1"
    local target="${2:-}"

    if [[ "$mode" == "local" ]]; then
        # Local OS detection
        if [[ -f /etc/arch-release ]]; then
            echo "arch"
        elif [[ -f /etc/debian_version ]]; then
            echo "debian"
        elif [[ -f /etc/os-release ]]; then
            # Check if ID is debian or ubuntu
            source /etc/os-release
            if [[ "${ID:-}" =~ ^(debian|ubuntu)$ ]]; then
                echo "debian"
            else
                echo "unknown"
            fi
        else
            echo "unknown"
        fi
    else
        # Remote OS detection via ansible
        # Check for Arch Linux first, then Debian-based
        local result
        result=$(ansible -i inventory/hosts "$target" -m shell \
            -a 'test -f /etc/arch-release && echo arch' \
            2>/dev/null | grep -v "$target |" | grep -v "WARNING" | head -n1 | tr -d ' \n\r')

        if [[ -z "$result" ]]; then
            result=$(ansible -i inventory/hosts "$target" -m shell \
                -a 'test -f /etc/debian_version && echo debian' \
                2>/dev/null | grep -v "$target |" | grep -v "WARNING" | head -n1 | tr -d ' \n\r')
        fi

        echo "${result:-unknown}"
    fi
}

detect_os() {
    print_message "info" "Detecting operating system..."

    if [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] || [[ -n "${CYGWIN_PREFIX:-}" ]]; then
        OS_TYPE="windows"
        print_message "info" "Detected: Windows (MSYS/MinGW/Cygwin)"
        return 0
    fi

    if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
        OS_TYPE="wsl"
        print_message "info" "Detected: Windows Subsystem for Linux (WSL)"
        return 0
    fi

    local uname_str
    uname_str="$(uname)"

    case "$uname_str" in
        Linux*)
            OS_TYPE="linux"
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

check_prerequisites() {
    print_message "info" "Checking prerequisites..."

    if command -v ansible &> /dev/null; then
        HAS_ANSIBLE=true
        local ansible_version
        ansible_version="$(ansible --version 2>&1 | head -n1 | awk '{print $2}')"
        print_message "success" "Ansible is installed: $ansible_version"
    else
        HAS_ANSIBLE=false
        print_message "warning" "Ansible is not installed"
    fi

    if command -v git &> /dev/null; then
        HAS_GIT=true
        print_message "success" "Git is installed"
    else
        HAS_GIT=false
        print_message "warning" "Git is not installed"
    fi

    if command -v python3 &> /dev/null; then
        HAS_PYTHON=true
        print_message "success" "Python3 is installed"
    else
        HAS_PYTHON=false
        print_message "warning" "Python3 is not installed"
    fi

    return 0
}

install_ansible() {
    if [[ "$HAS_ANSIBLE" == true ]]; then
        print_message "info" "Ansible is already installed, skipping..."
        return 0
    fi

    print_message "info" "Installing Ansible..."

    case "$OS_TYPE" in
        windows|wsl)
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
                    return 1
                    ;;
            esac
            ;;

        darwin)
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

    if command -v ansible &> /dev/null; then
        print_message "success" "Ansible has been installed successfully"
        HAS_ANSIBLE=true
        return 0
    else
        print_message "error" "Failed to install Ansible"
        return 1
    fi
}

ensure_playbook_exists() {
    print_message "info" "Checking playbook..."

    if [[ -d "$PLAYBOOK_DIR" ]]; then
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

    print_message "info" "Cloning Matrix Ansible Playbook..."

    if git clone "$MATRIX_PLAYBOOK_REPO_URL" "$PLAYBOOK_DIR" >> "$LOG_FILE" 2>&1; then
        print_message "success" "Playbook cloned successfully"
        return 0
    else
        print_message "error" "Failed to clone playbook"
        return 1
    fi
}

install_ansible_roles() {
    print_message "info" "Installing Ansible roles..."

    cd_playbook_and_setup_direnv || return 1

    if ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force >> "$LOG_FILE" 2>&1; then
        print_message "success" "Ansible roles installed successfully"
        return 0
    else
        print_message "error" "Failed to install Ansible roles"
        return 1
    fi
}

# ===========================================
# CONFIGURATION FUNCTIONS
# ===========================================

configure_inventory() {
    local server_ip="$1"

    print_message "info" "Configuring inventory..."

    local inventory_file="${PLAYBOOK_DIR}/inventory/hosts"
    local inventory_dir
    inventory_dir="$(dirname "$inventory_file")"

    if [[ -f "$inventory_file" ]]; then
        rm -f "$inventory_file"
    fi

    mkdir -p "$inventory_dir"

    cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by ansible-synapse addon on $(date)

[matrix_servers]
${server_ip} ansible_connection=local
EOF
    print_message "success" "Inventory configured for local installation"

    INVENTORY_PATH="$inventory_file"
    return 0
}

configure_vars_yml() {
    local server_ip="$1"
    local ipv6_enabled="$2"
    local element_enabled="$3"

    print_message "info" "Configuring vars.yml..."

    HOST_VARS_DIR="${PLAYBOOK_DIR}/inventory/host_vars/${server_ip}"

    if [[ -d "$HOST_VARS_DIR" ]]; then
        rm -rf "$HOST_VARS_DIR"
    fi

    mkdir -p "$HOST_VARS_DIR"

    VARS_YML_PATH="${HOST_VARS_DIR}/vars.yml"

    if [[ -z "$MATRIX_SECRET" ]]; then
        MATRIX_SECRET="$(generate_password 64)"
    fi
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD="$(generate_password 32)"
    fi

    cat > "$VARS_YML_PATH" <<EOF
# ===========================================
# Matrix Ansible Playbook Configuration
# Generated by ansible-synapse addon on $(date)
# ===========================================

# Basic Settings
matrix_domain: "${server_ip}"
matrix_server_fqn_matrix: "${server_ip}"
matrix_homeserver_implementation: "${DEFAULT_HOMESERVER_IMPL}"
matrix_homeserver_generic_secret_key: '${MATRIX_SECRET}'
matrix_playbook_reverse_proxy_type: playbook-managed-traefik
devture_systemd_docker_base_ipv6_enabled: ${ipv6_enabled}
postgres_connection_password: '${POSTGRES_PASSWORD}'

# Element Web Client
matrix_client_element_enabled: ${element_enabled}
matrix_server_fqn_element: "${server_ip}"
matrix_synapse_container_labels_public_client_root_enabled: false

# Federation Configuration
EOF

    if [[ "$SERVER_IS_IP" == "true" ]]; then
        cat >> "$VARS_YML_PATH" <<EOF
# IP-based federation configuration
matrix_synapse_federation_enabled: true
matrix_synapse_federation_ip_range_blacklist: []
matrix_synapse_configuration_extension_yaml: |
  federation_verify_certificates: false
  suppress_key_server_warning: true
  report_stats: false
  key_server:
    accept_keys_insecurely: true
  trusted_key_servers: []

EOF
    else
        cat >> "$VARS_YML_PATH" <<EOF
# Domain-based federation configuration
matrix_synapse_federation_enabled: true

EOF
    fi

    cat >> "$VARS_YML_PATH" <<EOF
# SSL/TLS Configuration
traefik_config_certificatesResolvers_acme_enabled: false
traefik_ssl_dir_enabled: true

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

# SSL Files (from environment variables set by matrix-installer.sh)
aux_file_definitions:
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: ${SSL_KEY}
    mode: "0600"

  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: ${SSL_CERT}
    mode: "0644"
EOF

    print_message "success" "vars.yml created successfully"
    return 0
}

create_traefik_directories() {
    local mode="$1"

    print_message "info" "Creating Traefik directories..."

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    ansible -i inventory/hosts "$target" -m shell \
        -a "mkdir -p /matrix/traefik/ssl /matrix/traefik/config" \
        --become >> "$LOG_FILE" 2>&1

    ansible -i inventory/hosts "$target" -m shell \
        -a "chown -R matrix:matrix /matrix/ || true" \
        --become >> "$LOG_FILE" 2>&1

    print_message "success" "Traefik directories created"
    return 0
}

configure_firewall() {
    local mode="$1"

    print_message "info" "Configuring firewall for Matrix ports..."

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    local detect_output
    detect_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "command -v ufw && echo 'ufw' || (command -v firewall-cmd && echo 'firewalld') || (iptables -nL >/dev/null 2>&1 && echo 'iptables') || echo 'none'" \
        --become 2>/dev/null | grep -v "$target |" | head -n1)

    local firewall_type
    firewall_type=$(echo "$detect_output" | tr -d ' \n\r')

    case "$firewall_type" in
        ufw)
            ansible -i inventory/hosts "$target" -m shell \
                -a "ufw allow 443/tcp && ufw allow 8448/tcp" \
                --become >> "$LOG_FILE" 2>&1
            print_message "success" "UFW rules added for ports 443, 8448"
            ;;
        firewalld)
            ansible -i inventory/hosts "$target" -m shell \
                -a "firewall-cmd --permanent --add-service=https && firewall-cmd --permanent --add-port=8448/tcp && firewall-cmd --reload" \
                --become >> "$LOG_FILE" 2>&1
            print_message "success" "firewalld rules added for ports 443, 8448"
            ;;
        iptables)
            ansible -i inventory/hosts "$target" -m shell \
                -a "iptables -I INPUT -p tcp --dport 443 -j ACCEPT && iptables -I INPUT -p tcp --dport 8448 -j ACCEPT" \
                --become >> "$LOG_FILE" 2>&1
            print_message "success" "iptables rules added for ports 443, 8448"
            ;;
        *)
            print_message "warning" "No firewall detected"
            ;;
    esac

    return 0
}

install_root_ca_on_system() {
    local mode="$1"

    print_message "info" "Installing Root Key in system trust store..."

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    # Detect OS family using the helper function
    local os_family
    os_family="$(get_os_family "remote" "$target")"

    print_message "info" "Detected OS family: $os_family"

    case "$os_family" in
        arch)
            # Arch/Manjaro: use /etc/ca-certificates/trust-source/anchors/
            ansible -i inventory/hosts "$target" -m copy \
                -a "src=${ROOT_CA} dest=/etc/ca-certificates/trust-source/anchors/matrix-root-ca.crt mode=0644" \
                --become >> "$LOG_FILE" 2>&1

            ansible -i inventory/hosts "$target" -m command \
                -a "trust extract-compat" \
                --become >> "$LOG_FILE" 2>&1
            ;;
        debian)
            # Debian/Ubuntu: use /usr/local/share/ca-certificates/
            ansible -i inventory/hosts "$target" -m copy \
                -a "src=${ROOT_CA} dest=/usr/local/share/ca-certificates/matrix-root-ca.crt mode=0644" \
                --become >> "$LOG_FILE" 2>&1

            ansible -i inventory/hosts "$target" -m command \
                -a "update-ca-certificates" \
                --become >> "$LOG_FILE" 2>&1
            ;;
        *)
            print_message "warning" "Unknown OS family ($os_family), trying Debian method..."
            ansible -i inventory/hosts "$target" -m copy \
                -a "src=${ROOT_CA} dest=/usr/local/share/ca-certificates/matrix-root-ca.crt mode=0644" \
                --become >> "$LOG_FILE" 2>&1

            ansible -i inventory/hosts "$target" -m command \
                -a "update-ca-certificates" \
                --become >> "$LOG_FILE" 2>&1 || true
            ;;
    esac

    print_message "success" "Root Key installed in system trust store"
    return 0
}

cleanup_existing_postgres_data() {
    local mode="$1"

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    print_message "info" "Checking for existing PostgreSQL data..."

    local check_output
    check_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "test -d /matrix/postgres && echo 'EXISTS' || echo 'NOT_FOUND'" \
        --become 2>/dev/null | grep -v "$target |")

    if [[ "$check_output" != *"EXISTS"* ]]; then
        print_message "info" "No existing PostgreSQL data found"
        return 0
    fi

    print_message "warning" "Removing existing PostgreSQL data..."

    ansible -i inventory/hosts "$target" -m shell \
        -a "rm -rf /matrix/postgres" \
        --become >> "$LOG_FILE" 2>&1

    print_message "success" "PostgreSQL data removed"
    return 0
}

cleanup_matrix_services() {
    local mode="$1"

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    print_message "info" "Stopping existing Matrix services..."

    ansible -i inventory/hosts "$target" -m shell \
        -a "systemctl stop matrix-*.service 2>/dev/null || true" \
        --become >> "$LOG_FILE" 2>&1

    ansible -i inventory/hosts "$target" -m shell \
        -a 'docker ps -a --format "{{"{{"}}.Names{{"}}"}}" | grep "^matrix-" | xargs -r docker rm -f 2>/dev/null || true' \
        --become >> "$LOG_FILE" 2>&1

    print_message "success" "Matrix services cleaned up"
    return 0
}

# ===========================================
# SYGNAPSE SIGNING KEY GENERATION
# ===========================================

cleanup_incorrect_signing_key() {
    local mode="$1"

    local signing_key_path="/matrix/synapse/config/${SERVER_NAME}.signing.key"

    cd_playbook_and_setup_direnv || return 1

    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    # Check if signing key exists and has incorrect format (RSA key instead of ed25519)
    local check_output
    check_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "test -f '$signing_key_path' && head -n1 '$signing_key_path' || echo 'NOT_FOUND'" \
        --become 2>/dev/null | grep -v "$target |" | grep -v "WARNING")

    if [[ "$check_output" == *"NOT_FOUND"* ]]; then
        print_message "info" "No existing signing key (playbook will generate it)"
        return 0
    fi

    # Check if it has incorrect format (RSA PEM format)
    if [[ "$check_output" == *"BEGIN PRIVATE KEY"* ]] || [[ "$check_output" == *"BEGIN RSA"* ]]; then
        print_message "warning" "Removing incorrectly formatted signing key..."
        ansible -i inventory/hosts "$target" -m shell \
            -a "rm -f '$signing_key_path'" \
            --become >> "$LOG_FILE" 2>&1
        print_message "success" "Incorrect signing key removed (playbook will generate correct one)"
        return 0
    fi

    print_message "info" "Signing key already exists in correct format"
    return 0
}

run_playbook() {
    local tags="${1:-install-all,ensure-matrix-users-created,start}"

    print_message "info" "Running Ansible playbook..."
    print_message "warning" "This may take 10-20 minutes, please be patient..."

    cd_playbook_and_setup_direnv || return 1

    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    if ansible-playbook -i inventory/hosts setup.yml --tags="$tags" 2>&1 | tee -a "$LOG_FILE"; then
        print_message "success" "Playbook executed successfully"
        return 0
    else
        print_message "error" "Playbook execution failed"
        return 1
    fi
}

create_admin_user() {
    local username="$1"
    local password="$2"

    print_message "info" "Creating admin user..."

    cd_playbook_and_setup_direnv || return 1

    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    local output
    output=$(ansible-playbook -i inventory/hosts setup.yml \
        --extra-vars="username=${username} password=${password} admin=yes" \
        --tags=register-user 2>&1 | tee -a "$LOG_FILE")
    local exit_code=$?

    if echo "$output" | grep -q "User ID already taken"; then
        print_message "warning" "Admin user '$username' already exists"
        return 0
    fi

    if [[ $exit_code -eq 0 ]] && ! echo "$output" | grep -q "failed=[1-9]"; then
        print_message "success" "Admin user created successfully"
        return 0
    fi

    print_message "error" "Failed to create admin user"
    return 1
}

print_summary() {
    echo ""
    echo -e "${GREEN}========================================
ANSIBLE-SYNAPSE INSTALLATION COMPLETE
========================================${NC}"

    echo -e "${BLUE}Server Information:${NC}
  - IP/Domain: ${SERVER_IP}
"

    echo -e "${BLUE}Admin User:${NC}
  - Username: ${ADMIN_USERNAME}
  - Password: ${ADMIN_PASSWORD}
"

    echo -e "${BLUE}Access URLs:${NC}
  - Matrix API: https://${SERVER_IP}/_matrix/client/versions
  - Element Web: https://${SERVER_IP}/
"

    echo -e "${GREEN}========================================${NC}
"
}

# ===========================================
# HELPER: Run command with sudo
# ===========================================

run_sudo_command() {
    local cmd="$1"
    local silent="${2:-false}"

    if [[ "$silent" == "true" ]]; then
        sudo sh -c "$cmd" 2>/dev/null
    else
        sudo sh -c "$cmd" 2>&1
    fi
}

# Try command without sudo first, fall back to sudo if needed
try_command() {
    local cmd="$1"
    local silent="${2:-false}"

    if [[ "$silent" == "true" ]]; then
        sh -c "$cmd" 2>/dev/null || sudo sh -c "$cmd" 2>/dev/null
    else
        sh -c "$cmd" 2>&1 || sudo sh -c "$cmd" 2>&1
    fi
}

# ===========================================
# STATUS CHECK
# ===========================================

check_status() {
    print_message "info" "Checking Matrix status..."

    # Collect all information first (try without sudo first)
    local containers
    local services
    local matrix_dir
    local volumes
    local container_count=0
    local service_count=0

    # Check /matrix directory first (no sudo needed for basic check)
    if [[ -d "/matrix" ]]; then
        matrix_dir="EXISTS"
    else
        matrix_dir="NOT_FOUND"
    fi

    # Only check Docker/systemd if /matrix exists
    if [[ "$matrix_dir" == "EXISTS" ]]; then
        containers=$(try_command "docker ps --format '{{.Names}}' | grep '^matrix-' || echo ''" true)
        container_count=$(echo "$containers" | grep -c "^matrix-" || true)

        services=$(try_command "systemctl list-units --type=service --state=running --all 2>/dev/null | grep '^matrix-' | wc -l" true)
        service_count=$(echo "$services" | tr -d ' ')

        volumes=$(try_command "docker volume ls -q 2>/dev/null | grep '^matrix' || echo ''" true)
    fi

    # Determine overall status
    local status=""
    local status_color=""
    local status_details=""

    if [[ "$matrix_dir" != "EXISTS" ]]; then
        status="NOT INSTALLED"
        status_color="${RED}"
        status_details="No Matrix installation found"
    elif [[ $container_count -eq 0 ]]; then
        status="INSTALLED (NOT RUNNING)"
        status_color="${YELLOW}"
        status_details="/matrix exists but no containers running"
    elif [[ $container_count -gt 0 ]]; then
        status="RUNNING"
        status_color="${GREEN}"
        status_details="$container_count container(s) running"
    fi

    # Show summary at top
    echo ""
    echo -e "╔══════════════════════════════════════════════════════════╗"
    echo -e "║                 Matrix Installation Status               ║"
    echo -e "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${status_color}  ${status}${NC}"
    echo -e "${status_color}  ${status_details}${NC}"

    # Only show details if Matrix is installed (directory exists)
    if [[ "$matrix_dir" == "EXISTS" ]]; then
        echo ""
        echo -e "${BLUE}=== Docker Containers ===${NC}"

        if [[ $container_count -eq 0 ]]; then
            print_message "warning" "No Matrix containers running"
        else
            try_command "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'matrix|NAMES'" || true
        fi

        echo ""
        echo -e "${BLUE}=== Systemd Services ===${NC}"

        if [[ $service_count -eq 0 ]] || [[ "$service_count" == "0" ]]; then
            print_message "warning" "No Matrix systemd services found"
        else
            try_command "systemctl is-active 'matrix-*' 2>/dev/null || true" | while read -r line; do
                if [[ -n "$line" ]]; then
                    echo "  $line"
                fi
            done
        fi

        echo ""
        echo -e "${BLUE}=== Directory & Files ===${NC}"

        print_message "success" "/matrix directory exists"
        echo ""
        echo "  Directory structure:"
        try_command "ls -lh /matrix/ 2>/dev/null | head -20" || true

        echo ""
        echo -e "${BLUE}=== Docker Volumes ===${NC}"

        if [[ -z "$volumes" ]]; then
            print_message "warning" "No Matrix volumes found"
        else
            try_command "docker volume ls | grep matrix" || true
        fi
    fi

    echo ""
    print_message "success" "Status check completed"
}

# ===========================================
# UNINSTALLATION
# ===========================================

uninstall_matrix() {
    print_message "warning" "This will:"
    echo "  - Stop all Matrix services"
    echo "  - Remove Matrix Docker containers, volumes, and networks"
    echo "  - Remove systemd services (all types)"
    echo "  - Delete /matrix directory"
    echo "  - Remove firewall rules (optional)"
    echo ""

    if [[ "$(prompt_yes_no "Continue with uninstall?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop Matrix services (including timers and sockets)
    print_message "info" "Stopping Matrix services..."
    run_sudo_command "systemctl stop 'matrix-*' 2>/dev/null || true" >> "$LOG_FILE" 2>&1

    # Remove containers
    print_message "info" "Removing Matrix containers..."
    run_sudo_command "docker ps -a --format '{{.Names}}' | grep '^matrix-' | xargs -r docker rm -f 2>/dev/null || true" >> "$LOG_FILE" 2>&1

    # Remove volumes
    print_message "info" "Removing Matrix volumes..."
    run_sudo_command "docker volume ls -q | grep '^matrix' | xargs -r docker volume rm -f 2>/dev/null || true" >> "$LOG_FILE" 2>&1

    # Remove networks
    print_message "info" "Removing Matrix Docker networks..."
    run_sudo_command "docker network ls --format '{{.Name}}' | grep '^matrix' | xargs -r docker network rm 2>/dev/null || true" >> "$LOG_FILE" 2>&1

    # Remove systemd services (all types: service, timer, socket, etc.)
    print_message "info" "Removing systemd services..."
    run_sudo_command "rm -f /etc/systemd/system/matrix-*.* && systemctl daemon-reload && systemctl reset-failed 2>/dev/null || true" >> "$LOG_FILE" 2>&1

    # Remove /matrix directory
    print_message "info" "Removing /matrix directory..."
    run_sudo_command "rm -rf /matrix" >> "$LOG_FILE" 2>&1

    # Ask about firewall rules
    echo ""
    if [[ "$(prompt_yes_no "Remove firewall rules for Matrix ports?" "y")" == "yes" ]]; then
        print_message "info" "Detecting firewall..."

        local firewall_output
        firewall_output=$(run_sudo_command "command -v ufw && echo 'ufw' || (command -v firewall-cmd && echo 'firewalld') || (iptables -nL >/dev/null 2>&1 && echo 'iptables') || echo 'none'" true)

        local firewall_type
        firewall_type=$(echo "$firewall_output" | tr -d ' \n\r')

        case "$firewall_type" in
            ufw)
                print_message "info" "Removing UFW rules..."
                run_sudo_command "ufw delete allow 443/tcp && ufw delete allow 8448/tcp" >> "$LOG_FILE" 2>&1
                print_message "success" "UFW rules removed"
                ;;
            firewalld)
                print_message "info" "Removing firewalld rules..."
                run_sudo_command "firewall-cmd --permanent --remove-service=https && firewall-cmd --permanent --remove-port=8448/tcp && firewall-cmd --reload" >> "$LOG_FILE" 2>&1
                print_message "success" "firewalld rules removed"
                ;;
            iptables)
                print_message "warning" "iptables rules not removed (manual cleanup required)"
                ;;
            *)
                print_message "info" "No firewall detected"
                ;;
        esac
    fi

    print_message "success" "Uninstall completed"
}

# ===========================================
# INSTALLATION FUNCTION
# ===========================================

install_matrix() {
    # Check prerequisites before installation
    print_message "info" "Checking prerequisites..."
    check_prerequisites

    # ============================================
    # COLLECT SERVER INFO
    # ============================================

    # Detect server IP
    print_message "info" "Detecting server IP..."
    SERVER_IP="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)"
    fi
    # Prompt with detected IP as default
    SERVER_IP="$(prompt_user "Enter server IP address or domain" "$SERVER_IP")"

    # Update SERVER_IS_IP based on final SERVER_IP
    if is_ip_address "$SERVER_IP"; then
        SERVER_IS_IP="true"
    fi

    # ============================================
    # CONFIGURATION
    # ============================================

    print_message "info" "=== Configuration ==="

    IPV6_ENABLED="true"
    ELEMENT_ENABLED="true"

    print_message "info" "Create admin user:"
    ADMIN_USERNAME="$(prompt_user "Username" "admin")"
    ADMIN_PASSWORD="$(prompt_user "Password" "$(generate_password 16)")"

    # ============================================
    # INSTALLATION
    # ============================================

    print_message "info" "=== Installing Prerequisites ==="

    if [[ "$HAS_ANSIBLE" == false ]]; then
        install_ansible || exit 1
    fi

    print_message "info" "=== Setting Up Playbook ==="

    ensure_playbook_exists || exit 1
    install_ansible_roles || exit 1

    print_message "info" "=== Configuring ==="

    configure_inventory "$SERVER_IP" "$INSTALLATION_MODE" || exit 1
    configure_vars_yml "$SERVER_IP" "$IPV6_ENABLED" "$ELEMENT_ENABLED" || exit 1
    create_traefik_directories "$INSTALLATION_MODE" || exit 1
    configure_firewall "$INSTALLATION_MODE"
    install_root_ca_on_system "$INSTALLATION_MODE"

    print_message "info" "=== Pre-installation Cleanup ==="

    cleanup_existing_postgres_data "$INSTALLATION_MODE"
    cleanup_matrix_services "$INSTALLATION_MODE"

    print_message "info" "=== Cleaning Up Signing Key ==="

    # Remove incorrect signing key if exists (let playbook generate it correctly)
    cleanup_incorrect_signing_key "$INSTALLATION_MODE"

    print_message "info" "=== Running Installation ==="

    run_playbook "install-all,start" || exit 1

    print_message "info" "=== Creating Admin User ==="

    create_admin_user "$ADMIN_USERNAME" "$ADMIN_PASSWORD"

    print_summary
    print_message "success" "ansible-synapse installation completed!"
}

# ===========================================
# MAIN MENU
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "ansible-synapse addon log - $(date)" > "$LOG_FILE"

    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     Private-Key Ansible-Synapse Addon Installer         ║
║                       Version 1.0.0                      ║
║                                                          ║
║       Ansible installer with Private Key SSL             ║
║              (Root Key from matrix-installer.sh)         ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # Check environment variables (supports standalone mode)
    check_environment_variables || exit 1

    SERVER_IP="$SERVER_NAME"
    SERVER_IS_IP="false"
    if is_ip_address "$SERVER_IP"; then
        SERVER_IS_IP="true"
    fi

    print_message "info" "=== Environment Detection ==="

    detect_os || exit 1

    # ============================================
    # INSTALLATION MODE SELECTION
    # ============================================

    # Always use local mode (This Is Server)
    INSTALLATION_MODE="local"
    print_message "info" "Local installation mode selected"

    # ============================================
    # MAIN MENU LOOP
    # ============================================

    while true; do
        cat <<'EOF'

Select an option:

  1) Install Matrix
  2) Check Status
  3) Uninstall Matrix
  -----------------
  0) Exit

EOF

        read -rp "Enter your choice (1-3, 0=Exit): " menu_choice

        case "$menu_choice" in
            1)
                install_matrix
                break
                ;;
            2)
                check_status
                ;;
            3)
                uninstall_matrix
                ;;
            0)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1-3 or 0."
                ;;
        esac
    done
}

# ===========================================
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
