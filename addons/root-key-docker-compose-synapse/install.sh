#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="private-key-docker-compose-synapse"
ADDON_NAME_MENU="Install Docker Compose Synapse (With Key SSL)"
ADDON_VERSION="0.1.0"
ADDON_DESCRIPTION="Docker Compose installer with Private Key SSL (Root Key)"
ADDON_AUTHOR="Matrix Installer"

# ===========================================
# ENVIRONMENT VARIABLES FROM MAIN.SH
# ===========================================
# These variables are exported by main.sh before running this addon:
#
# SERVER_NAME="172.19.39.69"                    # Server IP or domain name
# SSL_CERT="/path/to/certs/172.19.39.69/cert-full-chain.pem"  # Full chain certificate
# SSL_KEY="/path/to/certs/172.19.39.69/server.key"            # SSL private key
# ROOT_CA="/path/to/certs/rootCA.crt"                       # Root Key certificate
# CERTS_DIR="/path/to/certs"                                # Certificates directory
# WORKING_DIR="/path/to/script"                              # Script working directory
# ===========================================

# ===========================================
# CONFIGURATION
# ===========================================
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="${WORKING_DIR:-$(pwd)}"
LOG_FILE="${WORKING_DIR}/private-key-docker-compose-synapse.log"
MATRIX_BASE="/opt/matrix"
SSL_DIR="${MATRIX_BASE}/ssl"

# Default configuration values
DEFAULT_MAX_REG="5"
DEFAULT_ENABLE_REG="true"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

rand_secret() {
    openssl rand -base64 32 | tr -d '/+' | cut -c1-32
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

# ===========================================
# PREREQUISITES CHECK
# ===========================================

check_port_conflicts() {
    print_message "info" "Checking for port conflicts..."

    local required_ports=("443" "80" "8080")
    local conflicts=()
    local conflicting_containers=()
    local containers_using_port
    local container
    local port
    local item
    local existing
    local duplicate
    local already_tracked
    local unique_conflicts
    local conflict

    for port in "${required_ports[@]}"; do
        # Check if any container is using this port
        containers_using_port=$(docker ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null | grep -E "0.0.0.0:${port}->" | awk '{print $1}') || true

        if [[ -n "$containers_using_port" ]]; then
            while IFS= read -r container; do
                if [[ -n "$container" ]]; then
                    conflicts+=("$container (port $port)")
                    # Track unique container names
                    already_tracked=0
                    for existing in "${conflicting_containers[@]}"; do
                        if [[ "$existing" == "$container" ]]; then
                            already_tracked=1
                            break
                        fi
                    done
                    if [[ $already_tracked -eq 0 ]]; then
                        conflicting_containers+=("$container")
                    fi
                fi
            done <<< "$containers_using_port"
        fi
    done

    # Remove duplicates from display list
    unique_conflicts=()
    for item in "${conflicts[@]}"; do
        duplicate=0
        for existing in "${unique_conflicts[@]}"; do
            if [[ "$item" == "$existing" ]]; then
                duplicate=1
                break
            fi
        done
        if [[ $duplicate -eq 0 ]]; then
            unique_conflicts+=("$item")
        fi
    done

    if [[ ${#unique_conflicts[@]} -gt 0 ]]; then
        print_message "warning" "Port conflicts detected!"
        echo ""
        echo "The following containers are using ports required by this installation:"
        for conflict in "${unique_conflicts[@]}"; do
            echo "  - $conflict"
        done
        echo ""
        echo "Required ports: 443 (HTTPS), 80 (HTTP), 8080 (Traefik Dashboard)"
        echo ""

        if [[ "$(prompt_yes_no "Stop and remove conflicting containers automatically?" "y")" == "yes" ]]; then
            print_message "info" "Stopping conflicting containers..."
            for container in "${conflicting_containers[@]}"; do
                docker stop "$container" 2>/dev/null && echo "  Stopped: $container" || echo "  Failed to stop: $container"
            done

            print_message "info" "Removing conflicting containers..."
            for container in "${conflicting_containers[@]}"; do
                docker rm "$container" 2>/dev/null && echo "  Removed: $container" || echo "  Failed to remove: $container"
            done

            print_message "success" "Conflicting containers removed"
            echo ""
            return 0
        else
            print_message "info" "Installation cancelled by user"
            echo "Please stop the conflicting containers manually:"
            echo "  docker stop <container-name>"
            echo "  docker rm <container-name>"
            echo ""
            return 2  # Return 2 to indicate user cancelled (return to menu)
        fi
    fi

    print_message "success" "No port conflicts detected"
    return 0
}

check_prerequisites() {
    print_message "info" "Checking prerequisites..."

    local missing=()

    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    else
        print_message "success" "Docker is installed"
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
    else
        print_message "success" "Docker Compose is installed"
    fi

    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    else
        print_message "success" "openssl is installed"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "error" "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Install missing packages:"
        echo "  Ubuntu/Debian: sudo apt-get install -y docker.io docker-compose openssl"
        echo "  Arch/Manjaro:  sudo pacman -S docker docker-compose openssl"
        return 1
    fi

    return 0
}

check_environment_variables() {
    print_message "info" "Checking environment variables..."

    local missing=()

    if [[ -z "${SERVER_NAME:-}" ]]; then
        missing+=("SERVER_NAME")
    fi

    if [[ -z "${SSL_CERT:-}" ]]; then
        missing+=("SSL_CERT")
    fi

    if [[ -z "${SSL_KEY:-}" ]]; then
        missing+=("SSL_KEY")
    fi

    if [[ -z "${ROOT_CA:-}" ]]; then
        missing+=("ROOT_CA")
    fi

    if [[ -z "${CERTS_DIR:-}" ]]; then
        missing+=("CERTS_DIR")
    fi

    if [[ -z "${WORKING_DIR:-}" ]]; then
        missing+=("WORKING_DIR")
    fi

    # Standalone mode: prompt for missing variables
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "warning" "Running in standalone mode (not from main.sh)"
        echo ""
        echo "This addon requires the following information to continue:"
        echo ""

        # Prompt for missing variables
        for var in "${missing[@]}"; do
            case "$var" in
                SERVER_NAME)
                    local default_server="172.19.39.69"
                    SERVER_NAME="$(prompt_user "Server name or IP address" "$default_server")"
                    export SERVER_NAME
                    ;;
                SSL_CERT)
                    echo "  SSL_CERT: Full certificate chain (.pem file)"
                    SSL_CERT="$(prompt_user "  Path to SSL certificate" "/path/to/cert-full-chain.pem")"
                    export SSL_CERT
                    ;;
                SSL_KEY)
                    echo "  SSL_KEY: SSL private key file"
                    SSL_KEY="$(prompt_user "  Path to SSL private key" "/path/to/server.key")"
                    export SSL_KEY
                    ;;
                ROOT_CA)
                    echo "  ROOT_CA: Root CA certificate file"
                    ROOT_CA="$(prompt_user "  Path to Root CA certificate" "/path/to/rootCA.crt")"
                    export ROOT_CA
                    ;;
                CERTS_DIR)
                    # Derive from SSL_CERT path
                    if [[ -n "$SSL_CERT" ]]; then
                        CERTS_DIR="$(dirname "$(dirname "$SSL_CERT")")"
                    else
                        CERTS_DIR="$(prompt_user "  Certificates directory" "/path/to/certs")"
                    fi
                    export CERTS_DIR
                    ;;
                WORKING_DIR)
                    # Default to current directory or parent of certs
                    if [[ -n "${CERTS_DIR:-}" ]]; then
                        WORKING_DIR="$(dirname "$CERTS_DIR")"
                    else
                        WORKING_DIR="$(pwd)"
                    fi
                    export WORKING_DIR
                    ;;
            esac
        done
        echo ""
    fi

    # Verify certificate files exist
    if [[ ! -f "$SSL_CERT" ]]; then
        print_message "error" "SSL certificate not found: $SSL_CERT"
        return 1
    fi

    if [[ ! -f "$SSL_KEY" ]]; then
        print_message "error" "SSL private key not found: $SSL_KEY"
        return 1
    fi

    if [[ ! -f "$ROOT_CA" ]]; then
        print_message "error" "Root Key certificate not found: $ROOT_CA"
        return 1
    fi

    print_message "success" "All environment variables verified"
    print_message "info" "  SERVER_NAME: ${SERVER_NAME}"
    print_message "info" "  SSL_CERT: ${SSL_CERT}"
    print_message "info" "  SSL_KEY: ${SSL_KEY}"
    print_message "info" "  ROOT_CA: ${ROOT_CA}"

    return 0
}

# ===========================================
# CONFIGURATION
# ===========================================

configure_registration() {
    # Skip prompting if re-executed with sudo (variables already set)
    if [[ "${REEXECED:-}" == "1" && -n "${MAX_REG_DEFAULT:-}" && -n "${ENABLE_REGISTRATION:-}" ]]; then
        # Only generate secrets if not already set
        REGISTRATION_SHARED_SECRET="${REGISTRATION_SHARED_SECRET:-$(rand_secret)}"
        POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand_secret)}"
        ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(rand_secret)}"
        MACAROON_SECRET_KEY="${MACAROON_SECRET_KEY:-$(rand_secret)}"
        FORM_SECRET="${FORM_SECRET:-$(rand_secret)}"
        DOMAIN="${DOMAIN:-$SERVER_NAME}"
        return 0
    fi

    echo ""
    echo "========================================"
    echo "       Registration Configuration"
    echo "========================================"
    echo ""

    MAX_REG_DEFAULT="$(prompt_user "Max registrations per invite" "$DEFAULT_MAX_REG")"

    if [[ "$(prompt_yes_no "Enable user registration?" "y")" == "yes" ]]; then
        ENABLE_REGISTRATION="true"
    else
        ENABLE_REGISTRATION="false"
    fi

    # Security secrets (auto-generated)
    REGISTRATION_SHARED_SECRET="$(rand_secret)"
    POSTGRES_PASSWORD="$(rand_secret)"
    ADMIN_PASSWORD="$(rand_secret)"
    MACAROON_SECRET_KEY="$(rand_secret)"
    FORM_SECRET="$(rand_secret)"

    # Domain is SERVER_NAME from main.sh
    DOMAIN="$SERVER_NAME"

    echo ""
    print_message "info" "Configuration Summary:"
    echo "  Server: ${DOMAIN}"
    echo "  Max registrations: ${MAX_REG_DEFAULT}"
    echo "  Registration enabled: ${ENABLE_REGISTRATION}"
    echo ""
}

# ===========================================
# INSTALLATION
# ===========================================

install_matrix() {
    print_message "info" "Starting installation..."

    # Check prerequisites
    check_prerequisites || exit 1

    # Root privilege check - FIRST, before anything else
    # This ensures we have sudo access before prompting for any inputs
    if [[ $EUID -ne 0 ]]; then
        print_message "warning" "This installation requires root privileges"
        if [[ "$(prompt_yes_no "Continue with sudo?" "y")" != "yes" ]]; then
            print_message "info" "Installation cancelled"
            exit 0
        fi

        # Save configuration to temp file for sudo execution
        # Note: Variables may be empty in standalone mode, will be prompted after re-exec
        local temp_config="/tmp/matrix-install-$$-config.sh"
        cat > "$temp_config" <<EOF
export SERVER_NAME="${SERVER_NAME:-}"
export SSL_CERT="${SSL_CERT:-}"
export SSL_KEY="${SSL_KEY:-}"
export ROOT_CA="${ROOT_CA:-}"
export CERTS_DIR="${CERTS_DIR:-}"
export WORKING_DIR="${WORKING_DIR:-}"
export REEXECED="1"
EOF

        print_message "info" "Restarting with sudo..."
        # Use absolute path since sudo changes working directory
        local script_path="$ADDON_DIR/install.sh"
        exec sudo bash -c "source '$temp_config' && bash '$script_path' && rm -f '$temp_config'"
    fi

    # Load config if re-executed
    if [[ "${REEXECED:-}" == "1" ]]; then
        # Variables are already exported by the source command in exec
        :
    fi

    # Check environment variables (prompts in standalone mode, uses main.sh vars otherwise)
    # This happens AFTER sudo re-exec, so all prompts are in the sudo context
    check_environment_variables || exit 1

    # Configure registration (happens after env vars are set)
    configure_registration

    # Check for port conflicts - now with sudo access for complete container visibility
    set +e
    check_port_conflicts
    local port_check_result=$?

    if [[ $port_check_result -eq 2 ]]; then
        # User cancelled, return 2 to stay in menu (don't re-enable set -e before return!)
        return 2
    elif [[ $port_check_result -ne 0 ]]; then
        set -e
        exit 1
    fi

    # Re-enable set -e after handling all cases
    set -e

    # Check if already installed
    if [[ -d "$MATRIX_BASE" ]]; then
        print_message "warning" "Installation directory already exists: ${MATRIX_BASE}"
        if [[ "$(prompt_yes_no "Remove existing installation and continue?" "n")" != "yes" ]]; then
            print_message "info" "Installation cancelled"
            exit 0
        fi
        print_message "info" "Removing existing installation..."
        cd "$MATRIX_BASE" 2>/dev/null && docker compose down --remove-orphans 2>/dev/null || true
        rm -rf "$MATRIX_BASE"
    fi

    # Create directory structure
    print_message "info" "Creating directory structure..."
    mkdir -p "${MATRIX_BASE}/data/"{synapse,postgres,traefik,element,well-known/matrix}
    mkdir -p "${SSL_DIR}"

    # Copy SSL certificates
    print_message "info" "Copying SSL certificates..."
    cp "$SSL_CERT" "${SSL_DIR}/cert-full-chain.pem"
    cp "$SSL_KEY" "${SSL_DIR}/server.key"
    cp "$ROOT_CA" "${SSL_DIR}/rootCA.crt"

    chmod 644 "${SSL_DIR}/cert-full-chain.pem"
    chmod 644 "${SSL_DIR}/rootCA.crt"
    chmod 600 "${SSL_DIR}/server.key"

    # Generate Element config.json
    print_message "info" "Generating Element configuration..."
    cat > "${MATRIX_BASE}/data/element/config.json" <<EOF
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://${DOMAIN}",
      "server_name": "${DOMAIN}"
    }
  },
  "brand": "Element",
  "showLabsSettings": true,
  "default_country_code": "IR",
  " PIE_enabled": true
}
EOF

    # Generate docker-compose.yml
    print_message "info" "Generating docker-compose.yml..."
    cat > "${MATRIX_BASE}/docker-compose.yml" <<EOF
networks: {matrix: {}}
services:
  traefik:
    image: traefik:v3.6
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.file.filename=/etc/traefik/tls.yaml"
      - "--entrypoints.websecure.address=:443"
      - "--api.insecure=true"
    ports: ["443:443", "8080:8080"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock:ro", "./ssl:/ssl:ro", "./traefik-config:/etc/traefik:ro"]
    networks: [matrix]

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=synapsedb
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=-E UTF8 --locale=C
    volumes: ["./data/postgres:/var/lib/postgresql/data"]
    networks: [matrix]

  synapse:
    image: ghcr.io/matrix-org/synapse:latest
    depends_on: [postgres]
    volumes: ["./data/synapse:/data"]
    environment:
      SYNAPSE_SERVER_NAME: ${DOMAIN}
      SYNAPSE_REPORT_STATS: "no"
      SYNAPSE_HTTP_BIND_PORT: "8008"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.synapse.rule=Host(\`${DOMAIN}\`) && (PathPrefix(\`/_matrix\`) || PathPrefix(\`/_synapse\`))"
      - "traefik.http.routers.synapse.entrypoints=websecure"
      - "traefik.http.routers.synapse.tls=true"
    networks: [matrix]

  synapse-admin:
    image: awesometechnologies/synapse-admin:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.synadmin.rule=Host(\`${DOMAIN}\`) && PathPrefix(\`/admin\`)"
      - "traefik.http.routers.synadmin.entrypoints=websecure"
      - "traefik.http.routers.synadmin.tls=true"
    networks: [matrix]

  element:
    image: vectorim/element-web:latest
    volumes: ["./data/element/config.json:/app/config.json:ro"]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.element.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.element.entrypoints=websecure"
      - "traefik.http.routers.element.tls=true"
      - "traefik.http.services.element.loadbalancer.server.port=80"
    networks: [matrix]
EOF

    # Configure Traefik with static SSL
    print_message "info" "Configuring Traefik with static SSL certificates..."
    mkdir -p "${MATRIX_BASE}/traefik-config"

    cat > "${MATRIX_BASE}/traefik-config/tls.yaml" <<EOF
tls:
  certificates:
    - certFile: /ssl/cert-full-chain.pem
      keyFile: /ssl/server.key
  stores:
    default:
      defaultCertificate:
        certFile: /ssl/cert-full-chain.pem
        keyFile: /ssl/server.key
EOF

    # Update docker-compose.yml to include Traefik config
    print_message "info" "Updating docker-compose.yml with TLS configuration..."
    sed -i '/--api.insecure=true/a\      - "--providers.file.filename=/etc/traefik/tls.yaml"' "${MATRIX_BASE}/docker-compose.yml"
    sed -i 's|"./ssl:/ssl:ro"|"./ssl:/ssl:ro", "./traefik-config:/etc/traefik:ro"|' "${MATRIX_BASE}/docker-compose.yml"

    # Cleanup any stuck containers
    print_message "info" "Cleaning up old containers..."
    cd "$MATRIX_BASE"
    docker compose down --remove-orphans 2>/dev/null || true

    # Initialize Synapse
    print_message "info" "Initializing Synapse..."

    # Create synapse data directory
    mkdir -p data/synapse

    # Note: Synapse automatically generates the signing key on first startup
    # at: /data/${DOMAIN}.signing.key

    # Create minimal homeserver.yaml manually
    print_message "info" "Creating homeserver configuration..."
    cat > data/synapse/homeserver.yaml <<EOF
# Configuration file for Synapse
server_name: "${DOMAIN}"
pid_file: /data/homeserver.pid
listeners:
  - port: 8008
    tls: false
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
    host: postgres
  allow_unsafe_locale: true
media_store_path: /data/media_store
registration_shared_secret: "${REGISTRATION_SHARED_SECRET}"
report_stats: false
macaroon_secret_key: "${MACAROON_SECRET_KEY}"
form_secret: "${FORM_SECRET}"
signing_key_path: "/data/${DOMAIN}.signing.key"
EOF

    # Fix ownership of synapse data files (synapse runs as UID 991)
    chown -R 991:991 data/synapse/

    # Handle IP-based server configuration
    if is_ip_address "$DOMAIN"; then
        print_message "info" "Configuring for IP-based server..."
        cat >> data/synapse/homeserver.yaml <<EOF

# IP-based configuration
federation_verify_certificates: false
suppress_key_server_warning: true
report_stats: false
key_server:
  accept_keys_insecurely: true
trusted_key_servers: []
EOF
    fi

    # Add registration settings
    cat >> data/synapse/homeserver.yaml <<EOF
enable_registration: ${ENABLE_REGISTRATION}
enable_registration_without_verification: true
EOF

    # Fix ownership again after modifications
    chown -R 991:991 data/synapse/

    # Start services
    print_message "info" "Starting services..."
    docker compose up -d

    # Wait for services to be ready - with health check
    print_message "info" "Waiting for Synapse to be ready..."
    local max_wait=60
    local waited=0
    local synapse_ready=false

    while [[ $waited -lt $max_wait ]]; do
        # Check if synapse is responding
        if docker compose exec -T synapse synapsectl status &>/dev/null || \
           docker compose exec -T synapse curl -s http://localhost:8008/health &>/dev/null; then
            synapse_ready=true
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""

    if [[ "$synapse_ready" == "false" ]]; then
        print_message "warning" "Synapse may not be fully ready, attempting to create admin user anyway..."
    else
        print_message "success" "Synapse is ready!"
    fi

    # Create Admin User
    print_message "info" "Creating admin user..."

    # Wait a bit more for database migrations
    sleep 5

    # Use < /dev/null to prevent stdin blocking, and capture stderr to handle existing user
    if docker compose exec -T synapse register_new_matrix_user -u admin -p "${ADMIN_PASSWORD}" -a -c /data/homeserver.yaml < /dev/null 2>&1; then
        print_message "success" "Admin user created successfully"
    else
        print_message "warning" "Admin user may already exist or creation failed."
        echo "  You can create it manually:"
        echo "  docker compose exec synapse register_new_matrix_user -u admin -p YOUR_PASSWORD -a -c /data/homeserver.yaml"
    fi

    # Print summary
    print_summary
}

# ===========================================
# UNINSTALLATION
# ===========================================

uninstall_matrix() {
    print_message "warning" "This will:"
    echo "  - Stop all Matrix containers"
    echo "  - Remove containers and volumes"
    echo "  - Delete ${MATRIX_BASE} directory"
    echo ""

    if [[ "$(prompt_yes_no "Continue with uninstall?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    if [[ ! -d "$MATRIX_BASE" ]]; then
        print_message "warning" "Matrix is not installed"
        return 0
    fi

    cd "$MATRIX_BASE" || { print_message "error" "Cannot access ${MATRIX_BASE}"; return 1; }

    print_message "info" "Stopping and removing containers..."
    docker compose down -v 2>/dev/null || true

    cd /
    print_message "info" "Removing installation directory..."

    # Check if we need sudo
    if [[ $EUID -ne 0 ]]; then
        print_message "info" "Using sudo to remove files..."
        sudo rm -rf "$MATRIX_BASE"
    else
        rm -rf "$MATRIX_BASE"
    fi

    print_message "success" "Uninstall completed"
}

# ===========================================
# STATUS CHECK
# ===========================================

check_status() {
    print_message "info" "Checking Matrix status..."

    if [[ ! -d "$MATRIX_BASE" ]]; then
        print_message "warning" "Matrix is not installed"
        return 0
    fi

    # Check if docker-compose.yml exists
    if [[ ! -f "$MATRIX_BASE/docker-compose.yml" ]]; then
        print_message "warning" "Matrix is not properly installed (docker-compose.yml not found)"
        print_message "info" "You may need to reinstall or clean up the directory: sudo rm -rf $MATRIX_BASE"
        return 0
    fi

    cd "$MATRIX_BASE" || return 1

    echo ""
    docker compose ps 2>/dev/null
    echo ""

    if docker compose ps 2>/dev/null | grep -q "Up"; then
        print_message "success" "Matrix services are running"
    else
        print_message "warning" "Matrix services are not running"
    fi
}

# ===========================================
# PRINT SUMMARY
# ===========================================

print_summary() {
    echo ""
    echo -e "${GREEN}========================================
PRIVATE-KEY-DOCKER-COMPOSE-SYNAPSE INSTALLATION COMPLETE
========================================${NC}"

    echo -e "${BLUE}Server Information:${NC}
  - Server: ${DOMAIN}
  - Installation: Docker Compose with Private Key SSL
"

    echo -e "${BLUE}Admin User:${NC}
  - Username: admin
  - Password: ${ADMIN_PASSWORD}
"

    echo -e "${BLUE}Access URLs:${NC}
  - Element Web: https://${DOMAIN}
  - Admin UI: https://${DOMAIN}/admin
  - Traefik Dashboard: http://${DOMAIN}:8080
"

    echo -e "${BLUE}Registration:${NC}
  - Shared Secret: ${REGISTRATION_SHARED_SECRET}
  - Max Per Invite: ${MAX_REG_DEFAULT}
  - Enabled: ${ENABLE_REGISTRATION}
"

    echo -e "${BLUE}SSL Certificates:${NC}
  - Certificate: ${SSL_DIR}/cert-full-chain.pem
  - Private Key: ${SSL_DIR}/server.key
  - Root Key: ${SSL_DIR}/rootCA.crt
"

    echo -e "${BLUE}Docker Compose:${NC}
  - Location: ${MATRIX_BASE}
  - Control: cd ${MATRIX_BASE} && docker compose [up|down|logs]
"

    echo -e "${GREEN}========================================${NC}"
}

# ===========================================
# MAIN MENU
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "private-key-docker-compose-synapse addon log - $(date)" > "$LOG_FILE"

    # Check if re-executed with sudo - skip menu and install directly
    if [[ "${REEXECED:-}" == "1" ]]; then
        print_message "info" "Continuing installation with root privileges..."
        # Variables are already exported, run installation directly
        install_matrix "$@"
        return $?
    fi

    # Banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     Private-Key Docker-Compose-Synapse Addon Installer  ║
║                       Version 1.0.0                      ║
║                                                          ║
║       Docker Compose installer with Private Key SSL      ║
║              (Root Key from main.sh)                     ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # Note: Environment variable check moved to check_environment_variables()
    # to support both main.sh and standalone modes

    # Main menu loop
    while true; do
        cat <<'EOF'


Select an option:

  1) Install Matrix
  2) Uninstall Matrix
  3) Check Status
  4) Exit

EOF

        read -rp "Enter your choice (1-4): " choice

        case "$choice" in
            1)
                set +e
                install_matrix "$@"
                install_result=$?
                set -e
                # Only break on success (0) or error (1), not on user cancel (2)
                if [[ $install_result -ne 2 ]]; then
                    break
                fi
                ;;
            2)
                uninstall_matrix
                ;;
            3)
                check_status
                ;;
            4)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# ===========================================
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
