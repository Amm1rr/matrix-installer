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
# ENVIRONMENT VARIABLES FROM matrix-installer.sh
# ===========================================
# These variables are exported by matrix-installer.sh before running this addon:
#
# SERVER_NAME="172.19.39.69"                                  # Server IP or domain name
# SSL_CERT="/path/to/certs/172.19.39.69/cert-full-chain.pem"  # Full chain certificate
# SSL_KEY="/path/to/certs/172.19.39.69/server.key"            # SSL private key
# ROOT_CA="/path/to/certs/rootCA.crt"                         # Root Key certificate
# CERTS_DIR="/path/to/certs"                                  # Certificates directory
# WORKING_DIR="/path/to/script"                               # Script working directory
# ===========================================

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
GRAY='\033[0;90m'
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

    # Create user and database with C collation (required by Synapse)
    case "$DETECTED_OS" in
        ubuntu|arch)
            # Drop database if it exists (to recreate with correct collation)
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS $db_name;" 2>/dev/null || true

            # Create user
            sudo -u postgres createuser "$db_user" 2>/dev/null || true
            sudo -u postgres psql -c "ALTER USER $db_user PASSWORD '$POSTGRES_PASSWORD';"

            # Create database with C collation (Synapse requirement)
            sudo -u postgres createdb --locale=C --encoding=UTF8 --template=template0 -O "$db_user" "$db_name"
            ;;
    esac

    print_message "success" "Database configured"
}

# Create systemd service file for pip-installed Synapse
create_synapse_systemd_service() {
    print_message "info" "Creating systemd service for Synapse..."

    local service_file="/etc/systemd/system/matrix-synapse.service"
    local synapse_user="matrix-synapse"
    local synapse_venv="/opt/synapse-venv"

    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Matrix Synapse homeserver
After=network.target postgresql.service

[Service]
Type=notify
NotifyAccess=all
User=$synapse_user
Group=$synapse_user
WorkingDirectory=/var/lib/synapse
ExecStart=$synapse_venv/bin/python -m synapse.app.homeserver --config-path=/etc/synapse/homeserver.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=3
Environment="PYTHONUNBUFFERED=1"
Environment="PATH=$synapse_venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    print_message "success" "Systemd service created"
}

install_synapse_package() {
    print_message "info" "Installing Synapse package..."

    case "$DETECTED_OS" in
        ubuntu)
            # Install Synapse using pip in virtual environment
            # Ubuntu 24.04+ has PEP 668 which requires venv for system-wide pip installs
            print_message "info" "Installing Synapse via pip in virtual environment..."

            local synapse_venv="/opt/synapse-venv"
            local venv_exists=false
            local synapse_installed=false

            # Check if venv already exists and has synapse installed
            if [[ -d "$synapse_venv" ]]; then
                print_message "info" "Found existing virtual environment at $synapse_venv"
                venv_exists=true

                # Check if synapse is already installed in the venv
                if "$synapse_venv/bin/python" -c "import synapse; print(synapse.__version__)" 2>/dev/null; then
                    local installed_version=$("$synapse_venv/bin/python" -c "import synapse; print(synapse.__version__)" 2>/dev/null)
                    print_message "success" "Synapse $installed_version already installed in venv"
                    print_message "info" "Skipping download, using existing installation..."
                    synapse_installed=true
                else
                    print_message "warning" "Venv exists but Synapse not properly installed"
                    print_message "info" "Will reinstall Synapse in existing venv..."
                fi
            fi

            # Install build dependencies
            sudo apt-get update -qq
            sudo apt-get install -y python3-venv libssl-dev python3-dev \
                libxml2-dev libpq-dev libffi-dev python3-setuptools build-essential

            # Create virtual environment if it doesn't exist
            if [[ "$venv_exists" == "false" ]]; then
                print_message "info" "Creating virtual environment at $synapse_venv..."
                sudo python3 -m venv "$synapse_venv" || {
                    print_message "error" "Failed to create virtual environment"
                    return 1
                }
            fi

            # Install synapse in virtual environment (only if not already installed)
            if [[ "$synapse_installed" == "false" ]]; then
                print_message "info" "Installing matrix-synapse in virtual environment..."
                sudo "$synapse_venv/bin/pip" install --upgrade "matrix-synapse[all]" || {
                    print_message "error" "Failed to install matrix-synapse"
                    return 1
                }
                print_message "success" "Synapse installed successfully"
            fi

            # Create synapse user manually (since we're using pip)
            if ! id "matrix-synapse" &>/dev/null; then
                print_message "info" "Creating synapse user..."
                sudo useradd --system --home /var/lib/synapse --create-home \
                    --shell /usr/sbin/nologin matrix-synapse || {
                    print_message "error" "Failed to create synapse user"
                    return 1
                }
            fi

            # Ensure the synapse directories exist with proper permissions
            print_message "info" "Creating synapse directories..."
            sudo mkdir -p /var/lib/synapse /var/log/synapse /etc/synapse
            sudo chown -R matrix-synapse:matrix-synapse /var/lib/synapse /var/log/synapse /etc/synapse
            sudo chmod 750 /var/lib/synapse /var/log/synapse
            sudo chmod 755 /etc/synapse

            # Create systemd service file for venv-installed synapse
            create_synapse_systemd_service

            # Verify synapse installation
            if ! sudo -u matrix-synapse "$synapse_venv/bin/python" -c "import synapse" 2>/dev/null; then
                print_message "error" "Synapse installation verification failed"
                return 1
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm synapse python-setuptools || {
                print_message "error" "Failed to install synapse package"
                return 1
            }
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
  - port: 8008
    tls: false
    type: http
    x_forwarded: false
    bind_addresses: ['::1', '127.0.0.1']
    resources:
      - names: [client]
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

tls_certificate_path: "${config_dir}/${SERVER_NAME}.crt"
tls_private_key_path: "${config_dir}/${SERVER_NAME}.key"

# Federation settings for Root Key
federation_verify_certificates: false

# Trusted key servers
trusted_key_servers:
  - server_name: "matrix.org"
    accept_keys_insecurely: true

# Suppress key server warning when using custom certificates
suppress_key_server_warning: true

# Registration
enable_registration: ${ENABLE_REGISTRATION}
enable_registration_without_verification: true
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
            # Install ca-certificates package if needed
            if ! dpkg -l | grep -q "^ii.*ca-certificates"; then
                print_message "info" "Installing ca-certificates package..."
                sudo apt-get install -y ca-certificates
            fi

            # Copy to Debian trust store
            sudo mkdir -p /usr/local/share/ca-certificates
            sudo cp "$ROOT_CA" /usr/local/share/ca-certificates/matrix-root-ca.crt

            # Use full path to avoid PATH issues
            if [[ -x /usr/sbin/update-ca-certificates ]]; then
                sudo /usr/sbin/update-ca-certificates
            else
                print_message "warning" "update-ca-certificates not found, Root Key may not be fully trusted"
            fi
            ;;
        arch)
            # Install ca-certificates package if needed
            if ! pacman -Q ca-certificates &>/dev/null; then
                print_message "info" "Installing ca-certificates package..."
                sudo pacman -S --noconfirm ca-certificates
            fi

            # Copy to Arch trust store
            sudo mkdir -p /etc/ca-certificates/trust-source/anchors
            sudo cp "$ROOT_CA" /etc/ca-certificates/trust-source/anchors/matrix-root-ca.crt

            # Use full path to avoid PATH issues
            if [[ -x /usr/bin/trust ]]; then
                sudo /usr/bin/trust extract-compat
            else
                print_message "warning" "trust command not found, Root Key may not be fully trusted"
            fi
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

    # Get latest version with fallback
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/element-hq/element-web/releases/latest 2>/dev/null | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)

    # Use a known working version if API fails
    [[ -z "$latest_version" ]] && latest_version="v1.12.9"

    print_message "info" "Downloading Element Web ${latest_version}..."

    sudo mkdir -p "$install_dir"
    cd /tmp

    # Correct URL format: element-v<version>.tar.gz (not element-web-v<version>.tar.gz)
    local download_urls=(
        "https://github.com/element-hq/element-web/releases/download/${latest_version}/element-${latest_version}.tar.gz"
        "https://github.com/element-hq/element-web/releases/download/${latest_version}/element-web-${latest_version}.tar.gz"
    )

    local downloaded=false
    local url_used=""

    for url in "${download_urls[@]}"; do
        if curl -fL "$url" -o element-web.tar.gz 2>/dev/null; then
            downloaded=true
            url_used="$url"
            break
        fi
    done

    if [[ "$downloaded" == "false" ]]; then
        print_message "warning" "Failed to download Element Web"
        print_message "info" "You can install Element Web manually from: https://github.com/element-hq/element-web"
        print_message "info" "Or use the release URL directly and extract to $install_dir"
        return 1
    fi

    print_message "info" "Downloaded from: $url_used"

    # Extract and install
    if sudo tar -xzf element-web.tar.gz -C "$install_dir" --strip-components=1 2>/dev/null; then
        rm -f element-web.tar.gz
    else
        # Try without strip-components
        rm -rf "$install_dir"/*
        sudo tar -xzf element-web.tar.gz -C "$install_dir" 2>/dev/null
        rm -f element-web.tar.gz

        # If extraction created a subdirectory, move files up
        local subdir
        subdir=$(sudo find "$install_dir" -maxdepth 1 -type d \( -name "element-*" -o -name "element" \) 2>/dev/null | head -1)
        if [[ -n "$subdir" ]]; then
            sudo mv "${subdir}"/* "$install_dir"/ 2>/dev/null || true
            sudo rmdir "$subdir" 2>/dev/null || true
        fi
    fi

    # Check if files were extracted
    if [[ ! -f "${install_dir}/index.html" ]]; then
        print_message "warning" "Element Web installation incomplete - index.html not found"
        return 1
    fi

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

    # Get latest version with fallback
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/Awesome-Technologies/synapse-admin/releases/latest 2>/dev/null | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)

    # Use a known working version if API fails
    [[ -z "$latest_version" ]] && latest_version="v0.10.2"

    print_message "info" "Downloading Synapse Admin ${latest_version}..."

    sudo mkdir -p "$install_dir"
    cd /tmp

    # Try different download URL formats
    local download_urls=(
        "https://github.com/Awesome-Technologies/synapse-admin/releases/download/${latest_version}/synapse-admin-${latest_version}.tar.gz"
        "https://github.com/Awesome-Technologies/synapse-admin/releases/download/${latest_version}/synapse-admin.tar.gz"
        "https://github.com/Awesome-Technologies/synapse-admin/archive/refs/tags/${latest_version}.tar.gz"
    )

    local downloaded=false
    for url in "${download_urls[@]}"; do
        if curl -fL "$url" -o synapse-admin.tar.gz 2>/dev/null; then
            downloaded=true
            print_message "info" "Downloaded from: $url"
            break
        fi
    done

    if [[ "$downloaded" == "false" ]]; then
        print_message "warning" "Failed to download Synapse Admin. Skipping..."
        rm -f synapse-admin.tar.gz
        return 1
    fi

    # Extract and install
    if sudo tar -xzf synapse-admin.tar.gz -C "$install_dir" --strip-components=1 2>/dev/null; then
        rm -f synapse-admin.tar.gz
    else
        # Try without strip-components
        rm -rf "$install_dir"/*
        sudo tar -xzf synapse-admin.tar.gz -C "$install_dir" 2>/dev/null
        rm -f synapse-admin.tar.gz

        # If extraction created a subdirectory, move files up
        local subdir
        subdir=$(sudo find "$install_dir" -maxdepth 1 -type d -name "synapse-admin*" 2>/dev/null | head -1)
        if [[ -n "$subdir" ]]; then
            sudo mv "${subdir}"/* "$install_dir"/ 2>/dev/null
            sudo rmdir "$subdir" 2>/dev/null
        fi
    fi

    # Check if files were extracted
    if [[ ! -f "${install_dir}/index.html" ]]; then
        print_message "warning" "Synapse Admin files not found. Installation may be incomplete."
        return 1
    fi

    # Set ownership
    sudo chown -R "${web_user}:${web_user}" "$install_dir"

    print_message "success" "Synapse Admin installed to $install_dir"
}

# ===========================================
# NGINX INSTALLATION
# ===========================================

install_nginx() {
    print_message "info" "Installing nginx web server..."

    case "$DETECTED_OS" in
        ubuntu)
            sudo apt-get update -qq
            sudo apt-get install -y nginx
            ;;
        arch)
            sudo pacman -S --noconfirm nginx
            ;;
    esac

    print_message "success" "nginx installed"
}

configure_nginx() {
    print_message "info" "Configuring nginx for Element Web and Synapse Admin..."

    local web_user="$(get_web_user)"
    local nginx_config="/etc/nginx/sites-available/matrix"
    local synapse_venv="/opt/synapse-venv"

    # Create directory for SSL if needed
    sudo mkdir -p /etc/nginx/ssl
    sudo chown root:root /etc/nginx/ssl
    sudo chmod 755 /etc/nginx/ssl

    # Copy SSL certificates for nginx (same as Synapse)
    if [[ -f "$SSL_CERT" ]] && [[ -f "$SSL_KEY" ]]; then
        sudo cp "$SSL_CERT" /etc/nginx/ssl/synapse.crt
        sudo cp "$SSL_KEY" /etc/nginx/ssl/synapse.key
        # Set ownership and permissions for SSL certificates
        # The certificate can be world-readable, but the key must be protected
        sudo chown root:root /etc/nginx/ssl/synapse.crt
        sudo chown root:root /etc/nginx/ssl/synapse.key
        sudo chmod 644 /etc/nginx/ssl/synapse.crt
        sudo chmod 640 /etc/nginx/ssl/synapse.key
        # Add web user to ssl-cert group for key access (Ubuntu)
        if [[ "$DETECTED_OS" == "ubuntu" ]] && id -g ssl-cert 2>/dev/null; then
            sudo usermod -aG ssl-cert "$web_user" 2>/dev/null || true
            sudo chown root:ssl-cert /etc/nginx/ssl/synapse.key
            sudo chmod 640 /etc/nginx/ssl/synapse.key
        fi
    fi

    # Remove default site if enabled
    sudo rm -f /etc/nginx/sites-enabled/default

    # Create nginx configuration
    sudo tee "$nginx_config" > /dev/null <<EOF
# Matrix Server Configuration
# Generated by synapse-native addon

# Redirect HTTP to HTTPS (optional - comment out if not wanted)
server {
    listen 80;
    server_name ${SERVER_NAME};

    # Uncomment to redirect all HTTP to HTTPS
    # return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${SERVER_NAME};

    ssl_certificate /etc/nginx/ssl/synapse.crt;
    ssl_certificate_key /etc/nginx/ssl/synapse.key;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Element Web
    location /element {
        alias /var/www/element;
        try_files \$uri \$uri/ /element/index.html;
    }

    # Synapse Admin
    location /synapse-admin {
        alias /var/www/synapse-admin;
        try_files \$uri \$uri/ /synapse-admin/index.html;
    }

    # Synapse Client API (reverse proxy)
    location /_matrix {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Synapse Federation API (reverse proxy)
    location /_synapse {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
    }
}
EOF

    # Enable site
    sudo ln -sf "$nginx_config" /etc/nginx/sites-enabled/

    # Test configuration
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        print_message "success" "nginx configuration is valid"
    else
        print_message "error" "nginx configuration test failed"
        return 1
    fi

    # Enable nginx (will be started in enable_and_start_services after synapse is running)
    sudo systemctl enable nginx

    print_message "success" "nginx configured"
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

    # Try to start synapse
    sudo systemctl restart "$synapse_service" 2>&1

    # Start nginx if installed
    if [[ "$INSTALL_NGINX" == true ]]; then
        sudo systemctl restart nginx 2>&1 || print_message "warning" "nginx failed to start"
    fi

    # Wait a bit and check if service is running
    sleep 5

    if sudo systemctl is-active --quiet "$synapse_service"; then
        print_message "success" "Synapse is running"
    else
        # Service failed to start - get detailed error
        print_message "error" "Synapse service failed to start"
        echo ""
        echo "Service status:"
        sudo systemctl status "$synapse_service" --no-pager -l 2>&1 | head -20 || true
        echo ""
        echo "Recent logs:"
        sudo journalctl -u "$synapse_service" -n 30 --no-pager 2>&1 || true
        echo ""

        return 1
    fi

    # Check nginx status if installed
    if [[ "$INSTALL_NGINX" == true ]]; then
        if sudo systemctl is-active --quiet nginx; then
            print_message "success" "nginx is running"
        else
            print_message "warning" "nginx is not running"
            echo ""
            echo "nginx status:"
            sudo systemctl status nginx --no-pager -l 2>&1 | head -20 || true
            echo ""
            echo "nginx error log:"
            sudo tail -30 /var/log/nginx/error.log 2>/dev/null || true
            echo ""
        fi
    fi

    return 0
}

create_admin_user() {
    local username="${1:-admin}"
    local password="${2:-$(generate_password 16)}"

    # Redirect all output to stderr except the final password echo
    print_message "info" "Creating admin user: $username" >&2

    local synapse_user="$(get_synapse_user)"
    local synapse_venv="/opt/synapse-venv"
    local register_cmd="$synapse_venv/bin/register_new_matrix_user"
    local config_file="/etc/synapse/homeserver.yaml"

    # Check if synapse user exists
    if ! id "$synapse_user" &>/dev/null; then
        print_message "error" "Synapse user '$synapse_user' does not exist" >&2
        print_message "info" "Install Synapse first" >&2
        return 1
    fi

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        print_message "error" "Config file not found: $config_file" >&2
        return 1
    fi

    # Check if register command exists
    if [[ ! -x "$register_cmd" ]]; then
        print_message "error" "register_new_matrix_user not found at $register_cmd" >&2
        return 1
    fi

    # Create admin user using -c flag with config file
    # Suppress all output from the register command
    if sudo -u "$synapse_user" PATH="$synapse_venv/bin:$PATH" "$register_cmd" \
        -c "$config_file" \
        -u "$username" \
        -p "$password" \
        -a >/dev/null 2>&1; then

        # Save credentials (append if file exists)
        local cred_file="${WORKING_DIR}/synapse-credentials.txt"

        if [[ -f "$cred_file" ]]; then
            # File exists, append new user
            echo "" >> "$cred_file"
            echo "────────────────────────────────────────────────────────────" >> "$cred_file"
            echo "Synapse Admin User Credentials" >> "$cred_file"
            echo "==============================" >> "$cred_file"
            echo "Server: https://${SERVER_NAME}:8448" >> "$cred_file"
            echo "Username: ${username}" >> "$cred_file"
            echo "Password: ${password}" >> "$cred_file"
        else
            # File doesn't exist, create new
            cat > "$cred_file" <<EOF
Synapse Admin User Credentials
==============================
Server: https://${SERVER_NAME}:8448
Username: ${username}
Password: ${password}
EOF
        fi

        chmod 600 "$cred_file"
        print_message "success" "Admin user created. Credentials saved to synapse-credentials.txt" >&2
        # Echo password for capture by caller (ONLY to stdout)
        echo "$password"
        return 0
    else
        print_message "warning" "Failed to create admin user" >&2
        print_message "info" "Create manually with:" >&2
        print_message "info" "  sudo -u $synapse_user $register_cmd -c $config_file -a" >&2
        return 0
    fi
}

# ===========================================
# PORT 443 CHECK FUNCTION
# ===========================================

check_port_443() {
    print_message "info" "Checking if port 443 is available..."

    # Check if port 443 is in use
    local port_info
    port_info=$(sudo ss -tlnp 2>/dev/null | grep ":443 " || true)

    if [[ -z "$port_info" ]]; then
        print_message "success" "Port 443 is available"
        return 0
    fi

    # Port is in use - extract process info
    local process_name
    local process_pid
    process_name=$(echo "$port_info" | head -1 | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
    process_pid=$(echo "$port_info" | head -1 | grep -oP 'users:\(\K[^)]+' | grep -oP 'pid=\K[0-9]+' | head -1)

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    PORT 443 ALREADY IN USE                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    print_message "error" "Port 443 is already in use by: ${process_name:-unknown} (PID: ${process_pid:-unknown})"
    echo ""
    echo "To free the port, run one of these commands:"
    echo ""

    # Show specific commands based on the process
    if [[ "$process_name" == "docker-proxy" ]]; then
        echo "  • Stop Docker service:"
        echo "      sudo systemctl stop docker"
        echo ""
        echo "  • Or stop specific container:"
        echo "      docker ps"
        echo "      docker stop <container_name>"
        echo ""
    elif [[ "$process_name" == "nginx" ]]; then
        echo "  • Stop nginx service:"
        echo "      sudo systemctl stop nginx"
        echo ""
    elif [[ "$process_name" == "apache2" ]]; then
        echo "  • Stop Apache service:"
        echo "      sudo systemctl stop apache2"
        echo ""
    else
        echo "  • Stop the service using port 443:"
        echo "      sudo kill ${process_pid:-<PID>}"
        echo ""
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""

    # Loop until port is free or user cancels
    while true; do
        echo "Options:"
        echo "  1) Check port again"
        echo "  0) Cancel installation"
        echo ""
        read -rp "Enter your choice: " choice

        case "$choice" in
            1|check)
                echo ""
                print_message "info" "Checking port 443 again..."
                port_info=$(sudo ss -tlnp 2>/dev/null | grep ":443 " || true)
                if [[ -z "$port_info" ]]; then
                    print_message "success" "Port 443 is now available"
                    echo ""
                    return 0
                else
                    process_name=$(echo "$port_info" | head -1 | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
                    process_pid=$(echo "$port_info" | head -1 | grep -oP 'users:\(\K[^)]+' | grep -oP 'pid=\K[0-9]+' | head -1)
                    print_message "error" "Port 443 is still in use by: ${process_name:-unknown} (PID: ${process_pid:-unknown})"
                    echo ""
                fi
                ;;
            0|cancel|exit|q)
                echo ""
                print_message "info" "Installation cancelled"
                return 1
                ;;
            *)
                print_message "error" "Invalid option: $choice"
                ;;
        esac
    done
}

# ===========================================
# INSTALLATION SUMMARY
# ===========================================

print_installation_summary() {
    local synapse_service="$(get_synapse_service_name)"
    local admin_username="${1:-}"
    local admin_created="${2:-false}"
    local admin_password="${3:-}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Synapse Installation Completed!                 ║"
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

    # nginx service
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "${GREEN}✓ nginx: RUNNING${NC}"
        else
            echo -e "${RED}✗ nginx: NOT RUNNING${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ nginx: Not installed${NC}"
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
        echo ""
    fi

    # Element Web
    if [[ -d "/var/www/element" ]]; then
        echo -e "${GREEN}✓ Element Web: Installed${NC}"
    else
        echo -e "${YELLOW}⚠ Element Web: Not installed${NC}"
    fi

    # Synapse Admin
    if [[ -d "/var/www/synapse-admin" ]]; then
        echo -e "${GREEN}✓ Synapse Admin: Installed${NC}"
    else
        echo -e "${YELLOW}⚠ Synapse Admin: Not installed${NC}"
    fi

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo ""

    # Access URLs
    echo -e "${BLUE}Access URLs:${NC}"
    echo -e "  ${GREEN}➜${NC} Synapse:       https://${SERVER_NAME}:8448"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        if [[ -d "/var/www/element" ]]; then
            echo -e "  ${GREEN}➜${NC} Element Web:   https://${SERVER_NAME}/element"
        fi
        if [[ -d "/var/www/synapse-admin" ]]; then
            echo -e "  ${GREEN}➜${NC} Synapse Admin: https://${SERVER_NAME}/synapse-admin"
        fi
    fi

    echo ""

    # Admin user info
    if [[ "$admin_created" == "true" ]] && [[ -n "$admin_username" ]]; then
        echo -e "${BLUE}Admin User:${NC}"
        echo -e "  ${YELLOW}➜${NC} Username:      ${admin_username}"
        echo -e "  ${YELLOW}➜${NC} Password:      ${admin_password}"
        echo -e "  ${YELLOW}➜${NC} Credentials:   ${WORKING_DIR}/synapse-credentials.txt"
        echo ""
    fi

    # Service management commands
    echo -e "${BLUE}Service Management:${NC}"
    echo -e "  ${GRAY}➜${NC} sudo systemctl status postgresql"
    echo -e "  ${GRAY}➜${NC} sudo systemctl status ${synapse_service}"
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        echo -e "  ${GRAY}➜${NC} sudo systemctl status nginx"
    fi

    echo ""

    # Log file
    echo -e "${BLUE}Log file:${NC} ${GRAY}${LOG_FILE}${NC}"
    echo ""
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

    # Ask about nginx (only if Element Web is being installed)
    INSTALL_NGINX=false
    if [[ "$INSTALL_ELEMENT_WEB" == true ]]; then
        if [[ "$(prompt_yes_no "Install nginx for Element/Synapse Admin?" "y")" == "yes" ]]; then
            INSTALL_NGINX=true
        fi
    fi

    # Check port 443 if nginx is being installed
    if [[ "$INSTALL_NGINX" == true ]]; then
        check_port_443 || return 1
    fi

    local admin_username="$(prompt_user "Admin username" "admin")"

    echo ""
    echo "Configuration Summary:"
    echo "  Server: $SERVER_NAME"
    echo "  Registration: $ENABLE_REGISTRATION"
    echo "  Element Web: $INSTALL_ELEMENT_WEB"
    echo "  Synapse Admin: $INSTALL_SYNAPSE_ADMIN"
    echo "  nginx: $INSTALL_NGINX"
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

    # Install nginx (after web files are in place)
    if [[ "$INSTALL_NGINX" == true ]]; then
        install_nginx || print_message "warning" "nginx installation failed"
        configure_nginx || print_message "warning" "nginx configuration failed"
    fi

    enable_and_start_services || return 1

    # Create admin user
    local admin_created=false
    local admin_password=""
    echo ""
    if [[ "$(prompt_yes_no "Create admin user now?" "y")" == "yes" ]]; then
        admin_password=$(create_admin_user "$admin_username")
        if [[ $? -eq 0 && -n "$admin_password" ]]; then
            admin_created=true
        fi
    else
        print_message "info" "You can create an admin user later with the 'Create Admin User' option"
    fi

    # Print installation summary
    print_installation_summary "$admin_username" "$admin_created" "$admin_password"

    return 0
}

# ===========================================
# STATUS FUNCTION
# ===========================================

check_status() {
    local synapse_service="$(get_synapse_service_name)"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Synapse Installation Status                 ║"
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

    # nginx web server
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "${GREEN}✓ nginx: RUNNING${NC}"
        else
            echo -e "${RED}✗ nginx: NOT RUNNING${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ nginx: Not installed${NC}"
    fi

    echo ""

    # Port status check
    echo "────────────────────────────────────────────────────────────"
    echo ""
    echo "Port Status:"
    echo ""

    # Check port 8448 (Synapse TLS)
    local port_8448_info=$(sudo ss -tlnp 2>/dev/null | grep ":8448 " || true)
    if [[ -n "$port_8448_info" ]]; then
        local process_8448=$(echo "$port_8448_info" | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
        echo -e "${GREEN}✓ Port 8448 (Synapse TLS): In use by ${process_8448:-synapse}${NC}"
    else
        echo -e "${YELLOW}⚠ Port 8448 (Synapse TLS): Not listening${NC}"
    fi

    # Check port 8008 (Synapse HTTP/Admin API)
    local port_8008_info=$(sudo ss -tlnp 2>/dev/null | grep ":8008 " || true)
    if [[ -n "$port_8008_info" ]]; then
        local process_8008=$(echo "$port_8008_info" | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
        echo -e "${GREEN}✓ Port 8008 (Admin API): In use by ${process_8008:-synapse}${NC}"
    else
        echo -e "${YELLOW}⚠ Port 8008 (Admin API): Not listening${NC}"
    fi

    # Check port 443 (nginx HTTPS)
    local port_443_info=$(sudo ss -tlnp 2>/dev/null | grep ":443 " || true)
    if [[ -n "$port_443_info" ]]; then
        local process_443=$(echo "$port_443_info" | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
        echo -e "${GREEN}✓ Port 443 (HTTPS): In use by ${process_443:-nginx}${NC}"
    else
        echo -e "${YELLOW}⚠ Port 443 (HTTPS): Not listening${NC}"
    fi

    # Check port 5432 (PostgreSQL)
    local port_5432_info=$(sudo ss -tlnp 2>/dev/null | grep ":5432 " || true)
    if [[ -n "$port_5432_info" ]]; then
        local process_5432=$(echo "$port_5432_info" | grep -oP 'users:\(\K[^)]+' | grep -oP '"\K[^"]+' | head -1)
        echo -e "${GREEN}✓ Port 5432 (PostgreSQL): In use by ${process_5432:-postgres}${NC}"
    else
        echo -e "${YELLOW}⚠ Port 5432 (PostgreSQL): Not listening${NC}"
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

# ===========================================
# UNINSTALL OPTIONS
# ===========================================

show_uninstall_menu() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Uninstall Options                           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Select uninstall level:"
    echo ""
    echo "  1) Remove Synapse only (Recommended)"
    echo "     - Remove Synapse configs, data, and service"
    echo "     - Keep PostgreSQL database and nginx"
    echo "     - Safe if other services use PostgreSQL"
    echo ""
    echo "  2) Remove Synapse + Database"
    echo "     - Remove Synapse configs, data, service, and database"
    echo "     - Keep PostgreSQL package and nginx"
    echo ""
    echo "  3) Complete Removal (Advanced)"
    echo "     - Remove everything including PostgreSQL and nginx"
    echo "     - WARNING: May affect other services!"
    echo ""
    echo "  0) Cancel"
    echo ""
}

uninstall_synapse() {
    local synapse_service="$(get_synapse_service_name)"
    local synapse_user="$(get_synapse_user)"

    # Check for any traces of Synapse installation (full or partial)
    local has_synapse=false
    local has_postgresql=false
    local has_element=false
    local has_synapse_admin=false
    local has_configs=false
    local has_nginx=false

    # Check Synapse installation (venv or service)
    if systemctl list-unit-files 2>/dev/null | grep -q "^${synapse_service}\.service"; then
        has_synapse=true
    fi
    # Check for venv installation
    if [[ -d "/opt/synapse-venv" ]] || [[ -d "/opt/synapse" ]]; then
        has_synapse=true
    fi

    case "$DETECTED_OS" in
        ubuntu)
            if dpkg -l 2>/dev/null | grep -q "^ii.*postgresql"; then
                has_postgresql=true
            fi
            ;;
        arch)
            if pacman -Q postgresql &>/dev/null; then
                has_postgresql=true
            fi
            ;;
    esac

    # Check for PostgreSQL via service
    if systemctl list-unit-files 2>/dev/null | grep -q "^postgresql.service"; then
        has_postgresql=true
    fi

    # Check for Element Web
    if [[ -d "/var/www/element" ]]; then
        has_element=true
    fi

    # Check for Synapse Admin
    if [[ -d "/var/www/synapse-admin" ]]; then
        has_synapse_admin=true
    fi

    # Check for Synapse configs
    if [[ -d "/etc/synapse" ]] || [[ -d "/var/lib/synapse" ]]; then
        has_configs=true
    fi

    # Check for nginx
    if systemctl list-unit-files 2>/dev/null | grep -q "^nginx.service"; then
        has_nginx=true
    elif [[ -f "/etc/nginx/sites-available/matrix" ]]; then
        has_nginx=true
    fi

    # If nothing is found, return
    if [[ "$has_synapse" == "false" ]] && [[ "$has_postgresql" == "false" ]] && \
       [[ "$has_element" == "false" ]] && [[ "$has_synapse_admin" == "false" ]] && \
       [[ "$has_configs" == "false" ]] && [[ "${has_nginx:-false}" == "false" ]]; then
        print_message "warning" "Matrix is not installed"
        return 0
    fi

    # Show what was found
    print_message "info" "Found traces of Matrix installation:"
    [[ "$has_synapse" == "true" ]] && echo "  - Synapse (venv/service)"
    [[ "$has_postgresql" == "true" ]] && echo "  - PostgreSQL"
    [[ "$has_element" == "true" ]] && echo "  - Element Web"
    [[ "$has_synapse_admin" == "true" ]] && echo "  - Synapse Admin"
    [[ "$has_configs" == "true" ]] && echo "  - Synapse configs/data"
    [[ "${has_nginx:-false}" == "true" ]] && echo "  - nginx web server"
    echo ""

    show_uninstall_menu
    read -rp "Enter your choice: " choice

    case "$choice" in
        1)
            uninstall_synapse_only "$synapse_service" "$synapse_user"
            ;;
        2)
            uninstall_with_database "$synapse_service" "$synapse_user"
            ;;
        3)
            uninstall_complete "$synapse_service" "$synapse_user"
            ;;
        0|q|exit)
            print_message "info" "Uninstall cancelled"
            return 0
            ;;
        *)
            print_message "error" "Invalid option"
            return 0
            ;;
    esac
}

# Remove Synapse only (keep PostgreSQL and system packages)
uninstall_synapse_only() {
    local synapse_service="$1"
    local synapse_user="$2"
    local remove_venv=false

    # Ask about removing virtual environment (only if it exists)
    if [[ -d "/opt/synapse-venv" ]]; then
        echo ""
        echo "Found virtual environment at /opt/synapse-venv (~500MB)"
        echo "Keeping it will make next installation faster."
        echo ""
        if [[ "$(prompt_yes_no "Remove virtual environment?" "n")" == "yes" ]]; then
            remove_venv=true
        fi
    fi

    # Show warning and ask for confirmation
    echo ""
    print_message "warning" "This will remove Synapse configuration and data"
    print_message "info" "PostgreSQL and nginx will be kept"
    echo ""

    if [[ "$(prompt_yes_no "Continue?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop Synapse service
    print_message "info" "Stopping Synapse service..."
    sudo systemctl stop "$synapse_service" 2>/dev/null || true
    sudo systemctl disable "$synapse_service" 2>/dev/null || true

    # Remove Synapse virtual environment if requested
    if [[ "$remove_venv" == "true" ]]; then
        print_message "info" "Removing Synapse virtual environment..."
        sudo rm -rf /opt/synapse-venv
    elif [[ -d "/opt/synapse-venv" ]]; then
        print_message "info" "Keeping virtual environment for faster reinstall"
    fi

    # Remove old synapse directory if exists
    if [[ -d "/opt/synapse" ]]; then
        print_message "info" "Removing old Synapse directory..."
        sudo rm -rf /opt/synapse
    fi

    # Remove systemd service file
    sudo rm -f /etc/systemd/system/matrix-synapse.service
    sudo systemctl daemon-reload 2>/dev/null || true

    # Remove Synapse configs and data
    print_message "info" "Removing Synapse configuration and data..."
    sudo rm -rf /etc/synapse
    sudo rm -rf /var/lib/synapse
    sudo rm -rf /var/log/synapse

    # Remove web files
    sudo rm -rf /var/www/element
    sudo rm -rf /var/www/synapse-admin

    # Remove nginx configuration and package
    print_message "info" "Removing nginx..."
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl disable nginx 2>/dev/null || true
    sudo rm -f /etc/nginx/sites-enabled/matrix
    sudo rm -f /etc/nginx/sites-available/matrix
    sudo rm -rf /etc/nginx/ssl

    # Ask about removing nginx package
    if [[ "$(prompt_yes_no "Remove nginx package?" "n")" == "yes" ]]; then
        case "$DETECTED_OS" in
            ubuntu)
                sudo apt-get remove --purge -y nginx 2>/dev/null || true
                ;;
            arch)
                sudo pacman -Rns --noconfirm nginx 2>/dev/null || true
                ;;
        esac
    fi

    print_message "success" "Synapse removed (PostgreSQL kept intact)"
}

# Remove Synapse + Database (keep PostgreSQL package)
uninstall_with_database() {
    local synapse_service="$1"
    local synapse_user="$2"

    print_message "warning" "This will remove Synapse and its database"
    print_message "info" "PostgreSQL package and nginx will be kept"
    echo ""

    if [[ "$(prompt_yes_no "Continue?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # First do synapse-only uninstall
    uninstall_synapse_only "$synapse_service" "$synapse_user"

    # Remove Synapse database and user
    print_message "info" "Removing Synapse database and user..."

    # Drop database
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS synapsedb;" 2>/dev/null || true

    # Drop user
    sudo -u postgres psql -c "DROP USER IF EXISTS synapse;" 2>/dev/null || true

    print_message "success" "Synapse and database removed (PostgreSQL package kept)"
}

# Complete removal (including PostgreSQL package)
uninstall_complete() {
    local synapse_service="$1"
    local synapse_user="$2"

    print_message "warning" "========================================"
    print_message "warning" "DANGER: Complete Removal"
    print_message "warning" "========================================"
    print_message "warning" "This will remove:"
    print_message "warning" "  - Synapse package and configs"
    print_message "warning" "  - Synapse database"
    print_message "warning" "  - PostgreSQL package and ALL databases"
    print_message "warning" "  - All data in /var/lib/postgresql"
    print_message "warning" ""
    print_message "warning" "If other services use PostgreSQL, they will break!"
    echo ""

    local confirm
    confirm="$(prompt_user "Type 'COMPLETE' to confirm")"

    if [[ "$confirm" != "COMPLETE" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop services
    print_message "info" "Stopping services..."
    sudo systemctl stop "$synapse_service" 2>/dev/null || true
    sudo systemctl disable "$synapse_service" 2>/dev/null || true
    sudo systemctl stop postgresql 2>/dev/null || true
    sudo systemctl disable postgresql 2>/dev/null || true

    # Remove Synapse virtual environment
    if [[ -d "/opt/synapse-venv" ]]; then
        print_message "info" "Removing Synapse virtual environment..."
        sudo rm -rf /opt/synapse-venv
    fi

    # Remove old synapse directory if exists
    if [[ -d "/opt/synapse" ]]; then
        sudo rm -rf /opt/synapse
    fi

    # Remove systemd service file
    sudo rm -f /etc/systemd/system/matrix-synapse.service
    sudo systemctl daemon-reload 2>/dev/null || true

    # Remove all data
    print_message "info" "Removing all data..."
    sudo rm -rf /etc/synapse
    sudo rm -rf /var/lib/synapse
    sudo rm -rf /var/lib/postgresql
    sudo rm -rf /var/www/element
    sudo rm -rf /var/www/synapse-admin
    sudo rm -rf /var/log/synapse

    # Remove PostgreSQL package
    print_message "info" "Removing PostgreSQL package..."
    case "$DETECTED_OS" in
        ubuntu)
            sudo apt-get remove --purge -y postgresql postgresql-contrib 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rns --noconfirm postgresql 2>/dev/null || true
            ;;
    esac

    # Remove system user
    print_message "info" "Removing system user..."
    sudo userdel "$synapse_user" 2>/dev/null || true

    print_message "success" "Complete removal finished"
    print_message "warning" "PostgreSQL package has been removed"
    print_message "info" "You may need to reinstall PostgreSQL if needed"
}

# ===========================================
# MAIN MENU
# ===========================================

show_menu() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Synapse Native Installer                       ║"
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
