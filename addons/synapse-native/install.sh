#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="synapse-native"
ADDON_NAME_MENU="Install Synapse Native (System Packages)"
ADDON_VERSION="1.0.0"
ADDON_ORDER="60"
ADDON_DESCRIPTION="Native package-based Synapse installer for Ubuntu/Debian/Arch"
ADDON_AUTHOR="Matrix Installer"
ADDON_HIDDEN="false"

# ===========================================
# CONFIGURATION
# ===========================================
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="${WORKING_DIR:-$(pwd)}"
LOG_FILE="${WORKING_DIR}/synapse-native.log"
MATRIX_BASE="/opt/matrix-synapse"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# OS Detection Result
DETECTED_OS=""

# Database credentials
POSTGRES_PASSWORD=""
REGISTRATION_SHARED_SECRET=""

# Installation options
INSTALL_ELEMENT_WEB=true
INSTALL_SYNAPSE_ADMIN=false
ENABLE_REGISTRATION=true

set -e
set -u
set -o pipefail

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
    openssl rand -base64 48 | tr -d '/+' | cut -c1-"$length"
}

# ===========================================
# OS DETECTION
# ===========================================

detect_os() {
    print_message "info" "Detecting operating system..."

    unset ID ID_LIKE
    [[ -f /etc/os-release ]] && source /etc/os-release

    case "$ID" in
        arch|artix|garuda|manjaro)
            DETECTED_OS="arch"
            print_message "success" "Detected Arch-based Linux"
            ;;
        ubuntu|debian)
            DETECTED_OS="ubuntu"
            print_message "success" "Detected Ubuntu/Debian"
            ;;
        *)
            if [[ "${ID_LIKE:-}" == *"ubuntu"* ]] || [[ "${ID_LIKE:-}" == *"debian"* ]]; then
                DETECTED_OS="ubuntu"
                print_message "success" "Detected Ubuntu/Debian-like system"
            else
                print_message "error" "Unsupported operating system: $ID"
                print_message "error" "This addon supports Ubuntu, Debian, and Arch-based distributions"
                return 1
            fi
            ;;
    esac

    return 0
}

# ===========================================
# OS-SPECIFIC GETTERS
# ===========================================

get_synapse_service_name() {
    case "$DETECTED_OS" in
        ubuntu) echo "matrix-synapse" ;;
        arch) echo "synapse" ;;
        *) echo "synapse" ;;
    esac
}

get_synapse_user() {
    case "$DETECTED_OS" in
        ubuntu) echo "matrix-synapse" ;;
        arch) echo "synapse" ;;
        *) echo "synapse" ;;
    esac
}

get_synapse_group() {
    case "$DETECTED_OS" in
        ubuntu) echo "matrix-synapse" ;;
        arch) echo "synapse" ;;
        *) echo "synapse" ;;
    esac
}

get_web_user() {
    case "$DETECTED_OS" in
        ubuntu) echo "www-data" ;;
        arch) echo "http" ;;
        *) echo "www-data" ;;
    esac
}

get_synapse_config_dir() {
    echo "/etc/synapse"
}

get_synapse_data_dir() {
    echo "/var/lib/synapse"
}

# ===========================================
# PREREQUISITES CHECK
# ===========================================

check_prerequisites() {
    print_message "info" "Checking prerequisites..."

    local missing=()

    # Check systemd
    if ! command -v systemctl &> /dev/null; then
        missing+=("systemd")
    else
        print_message "success" "systemd is available"
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    else
        print_message "success" "curl is installed"
    fi

    # Check openssl
    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    else
        print_message "success" "openssl is installed"
    fi

    # Check for sudo
    if ! command -v sudo &> /dev/null; then
        missing+=("sudo")
    else
        print_message "success" "sudo is installed"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "error" "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Install missing packages:"
        echo "  Ubuntu/Debian: sudo apt-get install -y curl openssl sudo"
        echo "  Arch/Manjaro:  sudo pacman -S curl openssl sudo"
        return 1
    fi

    # Check if we have sudo privileges
    if ! sudo -v &> /dev/null; then
        print_message "error" "This script requires sudo privileges"
        return 1
    fi

    return 0
}

# ===========================================
# ENVIRONMENT VARIABLES SETUP
# ===========================================

check_environment_variables() {
    print_message "info" "Checking environment variables..."

    # Check if running from matrix-installer.sh
    if [[ -n "${SERVER_NAME:-}" ]] && [[ -n "${SSL_CERT:-}" ]] && [[ -n "${SSL_KEY:-}" ]]; then
        print_message "success" "Running from matrix-installer.sh mode"
        print_message "info" "Server: $SERVER_NAME"
        print_message "info" "Certificate: $SSL_CERT"
        print_message "info" "Private Key: $SSL_KEY"

        # Set defaults for optional variables
        WORKING_DIR="${WORKING_DIR:-$(pwd)}"
        CERTS_DIR="${CERTS_DIR:-$(dirname "$SSL_CERT")}"
        ROOT_CA="${ROOT_CA:-}"
        return 0
    fi

    # Standalone mode - prompt for configuration
    print_message "info" "Running in standalone mode"
    echo ""
    echo "=== Synapse Native Configuration ==="
    echo ""

    # Prompt for server name
    SERVER_NAME="$(prompt_user "Server name (IP or domain)" "$(hostname -I | awk '{print $1}')")"

    # Prompt for SSL certificate paths
    echo ""
    echo "SSL Certificate Configuration"
    echo "----------------------------"
    echo "You need to provide SSL certificates for Synapse."
    echo ""
    echo "Options:"
    echo "  1) Use existing certificates"
    echo "  2) Generate self-signed certificate (for testing)"
    echo ""

    read -rp "Choose option [1/2]: " ssl_option

    if [[ "$ssl_option" == "2" ]]; then
        # Generate self-signed certificate
        print_message "info" "Generating self-signed certificate..."
        local cert_dir="/etc/synapse"
        sudo mkdir -p "$cert_dir"

        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${cert_dir}/${SERVER_NAME}.key" \
            -out "${cert_dir}/${SERVER_NAME}.crt" \
            -subj "/CN=${SERVER_NAME}" 2>/dev/null

        SSL_CERT="${cert_dir}/${SERVER_NAME}.crt"
        SSL_KEY="${cert_dir}/${SERVER_NAME}.key"
        CERTS_DIR="$cert_dir"
        ROOT_CA=""

        print_message "success" "Self-signed certificate generated"
    else
        # Use existing certificates
        SSL_CERT="$(prompt_user "Path to SSL certificate file")"
        SSL_KEY="$(prompt_user "Path to SSL private key file")"
        CERTS_DIR="$(dirname "$SSL_CERT")"

        # Validate files exist
        if [[ ! -f "$SSL_CERT" ]]; then
            print_message "error" "Certificate file not found: $SSL_CERT"
            return 1
        fi

        if [[ ! -f "$SSL_KEY" ]]; then
            print_message "error" "Private key file not found: $SSL_KEY"
            return 1
        fi

        # Check for Root CA
        ROOT_CA="$(prompt_user "Path to Root CA certificate (optional, press Enter to skip)")"
        if [[ -z "$ROOT_CA" ]] || [[ ! -f "$ROOT_CA" ]]; then
            ROOT_CA=""
        fi
    fi

    WORKING_DIR="$(pwd)"
    print_message "success" "Configuration complete"

    return 0
}

# ===========================================
# INSTALLATION FUNCTIONS
# ===========================================

install_postgresql() {
    print_message "info" "Installing PostgreSQL..."

    case "$DETECTED_OS" in
        ubuntu)
            sudo apt-get update -qq
            sudo apt-get install -y postgresql postgresql-contrib python3-psycopg2
            ;;
        arch)
            sudo pacman -S --noconfirm postgresql python-psycopg2
            ;;
    esac

    print_message "success" "PostgreSQL installed"

    # Initialize database if needed (Arch)
    if [[ "$DETECTED_OS" == "arch" ]]; then
        if [[ ! -d /var/lib/postgres/data ]]; then
            print_message "info" "Initializing PostgreSQL database..."
            sudo -u postgres mkdir -p /var/lib/postgres/data
            sudo -u postgres /usr/bin/initdb -D /var/lib/postgres/data
        fi
    fi

    # Enable and start PostgreSQL
    print_message "info" "Starting PostgreSQL service..."
    sudo systemctl enable postgresql
    sudo systemctl start postgresql

    # Wait for PostgreSQL to be ready
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if sudo -u postgres psql -c "SELECT 1" &> /dev/null; then
            print_message "success" "PostgreSQL is running"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    print_message "error" "PostgreSQL failed to start"
    return 1
}

setup_synapse_user_and_db() {
    print_message "info" "Setting up Synapse database user and database..."

    local db_user="synapse"
    local db_name="synapsedb"
    POSTGRES_PASSWORD="$(generate_password 32)"

    # Create user and database
    case "$DETECTED_OS" in
        ubuntu|arch)
            sudo -u postgres createuser "$db_user" 2>/dev/null || true
            sudo -u postgres psql -c "ALTER USER $db_user PASSWORD '$POSTGRES_PASSWORD';"
            sudo -u postgres createdb -O "$db_user" "$db_name" 2>/dev/null || {
                print_message "warning" "Database may already exist, continuing..."
            }
            ;;
    esac

    print_message "success" "Database configured"
}

install_synapse_package() {
    print_message "info" "Installing Synapse package..."

    case "$DETECTED_OS" in
        ubuntu)
            # Add Matrix.org repository
            print_message "info" "Adding Matrix.org package repository..."

            if [[ ! -f /usr/share/keyrings/matrix-org-archive-keyring.gpg ]]; then
                sudo wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg \
                    https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
            fi

            echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] \
                https://packages.matrix.org/debian/ debian main" | \
                sudo tee /etc/apt/sources.list.d/matrix-org.list > /dev/null

            sudo apt-get update -qq
            sudo apt-get install -y matrix-synapse
            ;;
        arch)
            sudo pacman -S --noconfirm synapse python-setuptools
            ;;
    esac

    print_message "success" "Synapse package installed"
}

configure_synapse() {
    print_message "info" "Configuring Synapse..."

    local config_dir="$(get_synapse_config_dir)"
    local config_file="${config_dir}/homeserver.yaml"
    local synapse_user="$(get_synapse_user)"
    local synapse_group="$(get_synapse_group)"

    # Generate registration shared secret
    REGISTRATION_SHARED_SECRET="$(generate_password 32)"

    # Create config directory
    sudo mkdir -p "$config_dir"

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        sudo cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"
        print_message "info" "Backed up existing configuration"
    fi

    # Generate new config
    sudo tee "$config_file" > /dev/null <<EOF
# Matrix Synapse Configuration
# Generated by synapse-native addon

server_name: "${SERVER_NAME}"
pid_file: /var/lib/synapse/homeserver.pid
listeners:
  - port: 8448
    tls: true
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapsedb
    host: localhost
    cp_min: 5
    cp_max: 10

tls_certificate_path: \${config_dir}/${SERVER_NAME}.crt
tls_private_key_path: \${config_dir}/${SERVER_NAME}.key

# Federation settings for Root Key
federation_verify_certificates: false
trust_signed_third_party_certificates: false

# Registration
enable_registration: ${ENABLE_REGISTRATION}
registration_shared_secret: "${REGISTRATION_SHARED_SECRET}"

# Report stats
report_stats: false

# Logging
log_config: "/etc/synapse/${SERVER_NAME}.log.config"
EOF

    # Create log config
    sudo tee "${config_dir}/${SERVER_NAME}.log.config" > /dev/null <<EOF
version: 1

formatters:
  precise:
    format: '[%(asctime)s] %(levelname)s %(name)s - %(message)s'

handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
    level: INFO

  file:
    class: logging.handlers.RotatingFileHandler
    formatter: precise
    filename: /var/log/synapse/homeserver.log
    maxBytes: 10485760
    backupCount: 10

root:
    level: INFO
    handlers: [console, file]

disable_existing_loggers: false
EOF

    # Set permissions
    sudo chmod 640 "$config_file"
    sudo chmod 640 "${config_dir}/${SERVER_NAME}.log.config"
    sudo chown "${synapse_user}:${synapse_group}" "$config_file"
    sudo chown "${synapse_user}:${synapse_group}" "${config_dir}/${SERVER_NAME}.log.config"

    # Create log directory
    sudo mkdir -p /var/log/synapse
    sudo chown "${synapse_user}:${synapse_group}" /var/log/synapse

    print_message "success" "Synapse configured"
}

setup_root_ca_certificates() {
    [[ -z "${ROOT_CA:-}" ]] && return 0

    print_message "info" "Installing Root Key in system trust store..."

    case "$DETECTED_OS" in
        ubuntu)
            # Copy to Debian trust store
            sudo mkdir -p /usr/local/share/ca-certificates
            sudo cp "$ROOT_CA" /usr/local/share/ca-certificates/matrix-root-ca.crt
            sudo update-ca-certificates
            ;;
        arch)
            # Copy to Arch trust store
            sudo mkdir -p /etc/ca-certificates/trust-source/anchors
            sudo cp "$ROOT_CA" /etc/ca-certificates/trust-source/anchors/matrix-root-ca.crt
            sudo trust extract-compat
            ;;
    esac

    print_message "success" "Root Key installed in system trust store"
}

configure_synapse_tls() {
    print_message "info" "Configuring TLS certificates for Synapse..."

    local config_dir="$(get_synapse_config_dir)"
    local synapse_user="$(get_synapse_user)"
    local synapse_group="$(get_synapse_group)"

    # Copy certificates
    sudo cp "$SSL_CERT" "${config_dir}/${SERVER_NAME}.crt"
    sudo cp "$SSL_KEY" "${config_dir}/${SERVER_NAME}.key"

    # Set permissions
    sudo chmod 644 "${config_dir}/${SERVER_NAME}.crt"
    sudo chmod 600 "${config_dir}/${SERVER_NAME}.key"
    sudo chown "${synapse_user}:${synapse_group}" "${config_dir}/${SERVER_NAME}".{crt,key}

    print_message "success" "TLS certificates configured"
}

install_element_web() {
    print_message "info" "Installing Element Web from GitHub..."

    local install_dir="/var/www/element"
    local web_user="$(get_web_user)"

    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/element-hq/element-web/releases/latest | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    [[ -z "$latest_version" ]] && latest_version="v1.11.93"

    print_message "info" "Downloading Element Web ${latest_version}..."

    local download_url="https://github.com/element-hq/element-web/releases/download/${latest_version}/element-web-${latest_version}.tar.gz"

    sudo mkdir -p "$install_dir"

    # Download and extract
    cd /tmp
    curl -fL "$download_url" -o element-web.tar.gz
    sudo tar -xzf element-web.tar.gz -C "$install_dir" --strip-components=1
    rm -f element-web.tar.gz

    # Configure
    sudo tee "${install_dir}/config.json" > /dev/null <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${SERVER_NAME}",
            "server_name": "${SERVER_NAME}"
        }
    },
    "disable_custom_urls": true,
    "brand": "Element",
    "showLabsSettings": false,
    "piwik": false,
    "enableMetrics": false
}
EOF

    # Set ownership
    sudo chown -R "${web_user}:${web_user}" "$install_dir"

    print_message "success" "Element Web installed to $install_dir"
}

install_synapse_admin() {
    print_message "info" "Installing Synapse Admin from GitHub..."

    local install_dir="/var/www/synapse-admin"
    local web_user="$(get_web_user)"

    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/Awesome-Technologies/synapse-admin/releases/latest | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    [[ -z "$latest_version" ]] && latest_version="v0.10.2"

    print_message "info" "Downloading Synapse Admin ${latest_version}..."

    local download_url="https://github.com/Awesome-Technologies/synapse-admin/releases/download/${latest_version}/synapse-admin-${latest_version}.tar.gz"

    sudo mkdir -p "$install_dir"

    # Download and extract
    cd /tmp
    curl -fL "$download_url" -o synapse-admin.tar.gz
    sudo tar -xzf synapse-admin.tar.gz -C "$install_dir" --strip-components=1
    rm -f synapse-admin.tar.gz

    # Set ownership
    sudo chown -R "${web_user}:${web_user}" "$install_dir"

    print_message "success" "Synapse Admin installed to $install_dir"
}

enable_and_start_services() {
    local synapse_service="$(get_synapse_service_name)"

    print_message "info" "Enabling and starting services..."

    # Enable services
    sudo systemctl enable postgresql
    sudo systemctl enable "$synapse_service"

    # Start/restart services
    sudo systemctl restart postgresql
    sleep 3
    sudo systemctl restart "$synapse_service"

    # Wait for synapse to be ready
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if sudo systemctl is-active --quiet "$synapse_service"; then
            print_message "success" "Synapse is running"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    print_message "warning" "Synapse may not be fully started yet. Check with: sudo systemctl status $synapse_service"
}

create_admin_user() {
    local username="${1:-admin}"
    local password="${2:-$(generate_password 16)}"

    print_message "info" "Creating admin user: $username"

    local synapse_service="$(get_synapse_service_name)"

    # Wait for synapse to be ready
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if sudo -u "$(get_synapse_user)" register_new_matrix_user \
            --server "$SERVER_NAME:8448" \
            --user "$username" \
            --password "$password" \
            --admin \
            --no-progress 2>&1; then

            # Save credentials
            cat > "${WORKING_DIR}/synapse-credentials.txt" <<EOF
Synapse Admin User Credentials
==============================
Server: https://${SERVER_NAME}:8448
Username: ${username}
Password: ${password}
EOF

            chmod 600 "${WORKING_DIR}/synapse-credentials.txt"
            print_message "success" "Admin user created. Credentials saved to synapse-credentials.txt"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    print_message "warning" "Failed to create admin user automatically"
    print_message "info" "Create manually with: sudo -u $(get_synapse_user) register_new_matrix_user --server $SERVER_NAME:8448 --admin"
    return 1
}

# ===========================================
# MAIN INSTALLATION FUNCTION
# ===========================================

install_synapse() {
    print_message "info" "Starting Synapse installation..."

    # Check for existing installation
    local synapse_service="$(get_synapse_service_name)"
    if systemctl is-enabled --quiet "$synapse_service" 2>/dev/null; then
        print_message "error" "Synapse is already installed"
        print_message "info" "Use 'Check Status' or 'Uninstall' options"
        return 1
    fi

    # Installation prompts
    echo ""
    echo "=== Synapse Configuration ==="
    echo ""

    SERVER_NAME="$(prompt_user "Server name" "${SERVER_NAME:-$(hostname -I | awk '{print $1}')}")"

    if [[ "$(prompt_yes_no "Enable user registration?" "y")" == "yes" ]]; then
        ENABLE_REGISTRATION=true
    else
        ENABLE_REGISTRATION=false
    fi

    if [[ "$(prompt_yes_no "Install Element Web?" "y")" == "yes" ]]; then
        INSTALL_ELEMENT_WEB=true
    else
        INSTALL_ELEMENT_WEB=false
    fi

    if [[ "$(prompt_yes_no "Install Synapse Admin?" "n")" == "yes" ]]; then
        INSTALL_SYNAPSE_ADMIN=true
    else
        INSTALL_SYNAPSE_ADMIN=false
    fi

    local admin_username="$(prompt_user "Admin username" "admin")"

    echo ""
    echo "Configuration Summary:"
    echo "  Server: $SERVER_NAME"
    echo "  Registration: $ENABLE_REGISTRATION"
    echo "  Element Web: $INSTALL_ELEMENT_WEB"
    echo "  Synapse Admin: $INSTALL_SYNAPSE_ADMIN"
    echo "  Admin: $admin_username"
    echo ""

    if [[ "$(prompt_yes_no "Continue with installation?" "y")" != "yes" ]]; then
        print_message "info" "Installation cancelled"
        return 0
    fi

    # Installation steps
    install_postgresql || return 1
    setup_synapse_user_and_db || return 1
    install_synapse_package || return 1
    configure_synapse || return 1
    setup_root_ca_certificates || return 0
    configure_synapse_tls || return 1

    if [[ "$INSTALL_ELEMENT_WEB" == true ]]; then
        install_element_web || print_message "warning" "Element Web installation failed"
    fi

    if [[ "$INSTALL_SYNAPSE_ADMIN" == true ]]; then
        install_synapse_admin || print_message "warning" "Synapse Admin installation failed"
    fi

    enable_and_start_services || return 1

    # Create admin user
    echo ""
    if [[ "$(prompt_yes_no "Create admin user now?" "y")" == "yes" ]]; then
        create_admin_user "$admin_username" || true
    else
        print_message "info" "You can create an admin user later with the 'Create Admin User' option"
    fi

    # Print summary
    echo ""
    echo "=========================================="
    print_message "success" "Synapse installation completed!"
    echo "=========================================="
    echo ""
    echo "Services:"
    echo "  - PostgreSQL: sudo systemctl status postgresql"
    echo "  - Synapse: sudo systemctl status $synapse_service"
    echo ""
    echo "Access:"
    echo "  - Synapse: https://${SERVER_NAME}:8448"
    if [[ "$INSTALL_ELEMENT_WEB" == true ]]; then
        echo "  - Element Web: http://${SERVER_NAME}/element (requires web server configuration)"
    fi
    if [[ "$INSTALL_SYNAPSE_ADMIN" == true ]]; then
        echo "  - Synapse Admin: http://${SERVER_NAME}/synapse-admin (requires web server configuration)"
    fi
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""

    return 0
}

# ===========================================
# STATUS FUNCTION
# ===========================================

check_status() {
    local synapse_service="$(get_synapse_service_name)"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Synapse Installation Status                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # OS detection
    echo "OS: $DETECTED_OS"
    echo ""

    # Synapse service
    if sudo systemctl is-active --quiet "$synapse_service" 2>/dev/null; then
        echo -e "${GREEN}✓ Synapse: RUNNING${NC}"
    else
        echo -e "${RED}✗ Synapse: NOT RUNNING${NC}"
    fi

    if sudo systemctl is-enabled --quiet "$synapse_service" 2>/dev/null; then
        echo "  Service: Enabled on boot"
    else
        echo "  Service: Not enabled on boot"
    fi

    echo ""

    # PostgreSQL service
    if sudo systemctl is-active --quiet postgresql 2>/dev/null; then
        echo -e "${GREEN}✓ PostgreSQL: RUNNING${NC}"
    else
        echo -e "${RED}✗ PostgreSQL: NOT RUNNING${NC}"
    fi

    echo ""

    # Connection test
    if sudo systemctl is-active --quiet "$synapse_service" 2>/dev/null; then
        echo "Testing connection to $SERVER_NAME:8448..."
        if curl -fsS -k "https://${SERVER_NAME}:8448/_matrix/client/versions" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Synapse API is accessible${NC}"
        else
            echo -e "${YELLOW}⚠ Cannot connect to Synapse API${NC}"
        fi
    fi

    echo ""

    # Element Web
    if [[ -d "/var/www/element" ]]; then
        echo -e "${GREEN}✓ Element Web: Installed at /var/www/element${NC}"
    else
        echo -e "${YELLOW}⚠ Element Web: Not installed${NC}"
    fi

    # Synapse Admin
    if [[ -d "/var/www/synapse-admin" ]]; then
        echo -e "${GREEN}✓ Synapse Admin: Installed at /var/www/synapse-admin${NC}"
    else
        echo -e "${YELLOW}⚠ Synapse Admin: Not installed${NC}"
    fi

    echo ""
}

# ===========================================
# ADMIN USER CREATION
# ===========================================

menu_create_admin_user() {
    echo ""
    echo "=== Create Admin User ==="
    echo ""

    local username="$(prompt_user "Admin username" "admin")"
    local password=""
    local confirm_password=""

    while true; do
        password="$(prompt_user "Admin password (press Enter for auto-generated)")"
        if [[ -z "$password" ]]; then
            password="$(generate_password 16)"
            print_message "info" "Auto-generated password: $password"
            break
        fi

        confirm_password="$(prompt_user "Confirm password")"
        if [[ "$password" == "$confirm_password" ]]; then
            break
        fi
        print_message "error" "Passwords do not match"
    done

    create_admin_user "$username" "$password"
}

# ===========================================
# UNINSTALL FUNCTION
# ===========================================

uninstall_synapse() {
    local synapse_service="$(get_synapse_service_name)"

    print_message "warning" "This will remove Synapse and all data"
    echo ""

    if [[ "$(prompt_yes_no "Continue with uninstall?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop services
    print_message "info" "Stopping services..."
    sudo systemctl stop "$synapse_service" 2>/dev/null || true
    sudo systemctl stop postgresql 2>/dev/null || true

    # Remove packages
    print_message "info" "Removing packages..."
    case "$DETECTED_OS" in
        ubuntu)
            sudo apt-get remove --purge -y matrix-synapse postgresql python3-psycopg2 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rns --noconfirm synapse postgresql python-psycopg2 2>/dev/null || true
            ;;
    esac

    # Remove configs and data
    print_message "info" "Removing configuration and data..."
    sudo rm -rf /etc/synapse
    sudo rm -rf /var/lib/synapse
    sudo rm -rf /var/lib/postgresql
    sudo rm -rf /var/www/element
    sudo rm -rf /var/www/synapse-admin
    sudo rm -rf /var/log/synapse

    # Remove Matrix.org repo (Ubuntu)
    if [[ "$DETECTED_OS" == "ubuntu" ]]; then
        sudo rm -f /etc/apt/sources.list.d/matrix-org.list
        sudo rm -f /usr/share/keyrings/matrix-org-archive-keyring.gpg
    fi

    # Remove users
    print_message "info" "Removing users..."
    local synapse_user="$(get_synapse_user)"
    sudo userdel "$synapse_user" 2>/dev/null || true

    print_message "success" "Uninstall completed"
}

# ===========================================
# MAIN MENU
# ===========================================

show_menu() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Synapse Native Installer                        ║"
    echo "║              Version ${ADDON_VERSION}                               ║"
    echo "║                                                          ║"
    echo "║       Native package-based Matrix homeserver             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Select an option:"
    echo ""
    echo "  1) Install Matrix Synapse"
    echo "  2) Check Status"
    echo "  3) Create Admin User"
    echo "  4) Uninstall Matrix"
    echo "  -----------------"
    echo "  0) Exit"
    echo ""
}

main() {
    # Detect OS
    detect_os || exit 1

    # Check prerequisites
    check_prerequisites || exit 1

    # Check environment variables (handles both modes)
    check_environment_variables || exit 1

    # Main menu loop
    while true; do
        show_menu
        read -rp "Enter your choice: " choice

        case "$choice" in
            1|install)
                install_synapse
                ;;
            2|status)
                check_status
                ;;
            3|admin)
                menu_create_admin_user
                ;;
            4|uninstall)
                uninstall_synapse
                ;;
            0|exit|q)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                print_message "error" "Invalid option: $choice"
                ;;
        esac
    done
}

# Run main function
main "$@"
