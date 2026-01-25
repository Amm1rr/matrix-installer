#!/bin/bash

# این متغیرها در دسترس هستند
# SERVER_NAME="$server_name"                                                                      
# SSL_CERT="${server_cert_dir}/cert-full-chain.pem"                                               
# SSL_KEY="${server_cert_dir}/server.key"                                                         
# ROOT_CA="${CERTS_DIR}/rootCA.crt"                                                               
# CERTS_DIR="$CERTS_DIR"                                                                          
# WORKING_DIR="$WORKING_DIR"                                                                      

# در این ماژول، فقط از این ها استفاده شده است: 
# ${SSL_CERT}
# ${SSL_KEY}
# ${ROOT_CA}

# ===========================================
# ansible-synapse Addon
# Self-contained Ansible module for Synapse installation
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
DEFAULT_SSH_USER="admin"
DEFAULT_SSH_PORT="22"

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
# ENVIRONMENT VARIABLES FROM MAIN.SH
# ===========================================

# Expected from main.sh:
# - SERVER_NAME: Matrix server identity (IP or domain)
# - SSL_CERT: Full chain certificate path
# - SSL_KEY: Private key path
# - ROOT_CA: Root CA certificate path
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

INSTALLATION_MODE=""
SERVER_IP=""
SERVER_IS_IP=""
SERVER_USER=""
SERVER_PORT=""
SSH_HOST=""
USE_SSH_KEY=""
SSH_KEY_PATH=""
SSH_PASSWORD=""
SUDO_PASSWORD=""

MATRIX_SECRET=""
POSTGRES_PASSWORD=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""

IPV6_ENABLED=""
ELEMENT_ENABLED=""

HOST_VARS_DIR=""
VARS_YML_PATH=""
INVENTORY_PATH=""

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
        # Remote OS detection via ansible (no become needed for checking /etc files)
        ansible -i inventory/hosts "$target" -m shell \
            -a "if [[ -f /etc/arch-release ]]; then echo 'arch'; elif [[ -f /etc/debian_version ]]; then echo 'debian'; else echo 'unknown'; fi" \
            2>/dev/null | grep -v "$target |" | grep -v "WARNING" | head -n1 | tr -d ' \n\r'
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
    local mode="$2"

    print_message "info" "Configuring inventory..."

    local inventory_file="${PLAYBOOK_DIR}/inventory/hosts"
    local inventory_dir
    inventory_dir="$(dirname "$inventory_file")"

    if [[ -f "$inventory_file" ]]; then
        rm -f "$inventory_file"
    fi

    mkdir -p "$inventory_dir"

    if [[ "$mode" == "local" ]]; then
        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by ansible-synapse addon on $(date)

[matrix_servers]
${server_ip} ansible_connection=local
EOF
        print_message "success" "Inventory configured for local installation"
    else
        local ansible_user="${SERVER_USER:-$DEFAULT_SSH_USER}"
        local ansible_port="${SERVER_PORT:-22}"
        local ansible_host="${SSH_HOST:-$server_ip}"

        local inventory_vars="ansible_host=${ansible_host} ansible_ssh_user=${ansible_user} ansible_port=${ansible_port} ansible_become=true ansible_become_user=root"

        if [[ "$USE_SSH_KEY" == "yes" ]] && [[ -n "$SSH_KEY_PATH" ]]; then
            inventory_vars="${inventory_vars} ansible_ssh_private_key_file=${SSH_KEY_PATH}"
        fi

        if [[ -n "$SSH_PASSWORD" ]]; then
            inventory_vars="${inventory_vars} ansible_ssh_pass='${SSH_PASSWORD}'"
        fi

        if [[ -n "$SUDO_PASSWORD" ]]; then
            inventory_vars="${inventory_vars} ansible_become_pass='${SUDO_PASSWORD}'"
        fi

        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by ansible-synapse addon on $(date)

[matrix_servers]
${server_ip} ${inventory_vars}
EOF
        print_message "success" "Inventory configured for remote installation"
    fi

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

# SSL Files (from environment variables set by main.sh)
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

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
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

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
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

    print_message "info" "Installing Root CA in system trust store..."

    cd_playbook_and_setup_direnv || return 1

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
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

    print_message "success" "Root CA installed in system trust store"
    return 0
}

cleanup_existing_postgres_data() {
    local mode="$1"

    cd_playbook_and_setup_direnv || return 1

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
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

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
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

    if [[ -n "$SSH_PASSWORD" ]]; then
        export ANSIBLE_SSH_PASS="$SSH_PASSWORD"
    fi
    # Always export ANSIBLE_BECOME_PASS for local mode (supports passwordless sudo)
    export ANSIBLE_BECOME_PASS="$SUDO_PASSWORD"

    local target="$SERVER_IP"
    if [[ "$mode" == "remote" ]]; then
        target="all"
    fi

    # Check if signing key exists and has incorrect format (RSA key instead of ed25519)
    local check_output
    check_output=$(ansible -i inventory/hosts "$target" -m shell \
        -a "if [[ -f '$signing_key_path' ]]; then head -n1 '$signing_key_path'; else echo 'NOT_FOUND'; fi" \
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

    echo -e "${GREEN}========================================${NC}
"
}

# ===========================================
# MAIN INSTALLATION FUNCTION
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "ansible-synapse addon log - $(date)" > "$LOG_FILE"

    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║             ansible-synapse Addon Installer             ║
║                      Version 1.0.0                       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # Check environment variables from main.sh
    if [[ -z "${SERVER_NAME:-}" ]]; then
        print_message "error" "SERVER_NAME environment variable not set"
        print_message "info" "This addon must be run from main.sh"
        exit 1
    fi

    if [[ -z "${SSL_CERT:-}" ]] || [[ -z "${SSL_KEY:-}" ]] || [[ -z "${ROOT_CA:-}" ]]; then
        print_message "error" "SSL certificate environment variables not set"
        print_message "info" "Please generate server certificate from main.sh first"
        exit 1
    fi

    SERVER_IP="$SERVER_NAME"
    SERVER_IS_IP="false"
    if is_ip_address "$SERVER_IP"; then
        SERVER_IS_IP="true"
    fi

    print_message "info" "=== Environment Detection ==="

    detect_os || exit 1
    check_prerequisites

    # ============================================
    # INSTALLATION MODE SELECTION
    # ============================================

    cat <<'EOF'

Select installation mode:

  1) This Is Server
     - Install Matrix on THIS machine
     - Ansible will run locally (ansible_connection=local)

  2) Remote VPS (Beta)
     - Install Matrix on a remote server via SSH

EOF

    while true; do
        read -rp "Enter your choice (1 or 2): " choice

        case "$choice" in
            1)
                INSTALLATION_MODE="local"
                print_message "info" "Local installation mode selected"

                # Detect server IP
                SERVER_IP="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
                if [[ -z "$SERVER_IP" ]]; then
                    SERVER_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)"
                fi
                if [[ -z "$SERVER_IP" ]]; then
                    SERVER_IP="$(prompt_user "Enter server IP address")"
                else
                    print_message "info" "Detected IP: $SERVER_IP"
                    if [[ "$(prompt_yes_no "Use this IP?" "y")" != "yes" ]]; then
                        SERVER_IP="$(prompt_user "Enter server IP address or domain")"
                    fi
                fi

                SUDO_PASSWORD="$(prompt_user "Sudo password")"
                break
                ;;
            2)
                INSTALLATION_MODE="remote"
                print_message "info" "Remote installation mode selected"

                SERVER_IP="$(prompt_user "Enter server IP address or domain")"
                SERVER_USER="$(prompt_user "SSH username" "$DEFAULT_SSH_USER")"
                SSH_HOST="$(prompt_user "SSH host" "$SERVER_IP")"
                SERVER_PORT="$(prompt_user "SSH port" "22")"

                if [[ "$(prompt_yes_no "Use custom SSH key?" "n")" == "yes" ]]; then
                    SSH_KEY_PATH="$(prompt_user "SSH key path" "$HOME/.ssh/id_rsa")"
                    USE_SSH_KEY="yes"
                elif [[ "$(prompt_yes_no "Use password authentication?" "n")" == "yes" ]]; then
                    SSH_PASSWORD="$(prompt_user "SSH password")"
                    USE_SSH_KEY="no"
                else
                    USE_SSH_KEY="no"
                fi

                SUDO_PASSWORD="$(prompt_user "Sudo password")"
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

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
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
