#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="docker-compose-synapse"
ADDON_NAME_MENU="Install Docker Synapse (Let's Encrypt)"
ADDON_VERSION="0.1.0"
ADDON_ORDER="20"
ADDON_DESCRIPTION="Quick Docker Compose installer with Let's Encrypt SSL and DuckDNS"
ADDON_AUTHOR="Matrix Installer"

# ===========================================
# CONFIGURATION
# ===========================================
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="${WORKING_DIR:-$(pwd)}"
LOG_FILE="${WORKING_DIR}/docker-compose-synapse.log"
MATRIX_BASE="/opt/matrix"

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

# ===========================================
# PREREQUISITES CHECK
# ===========================================

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

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    else
        print_message "success" "curl is installed"
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
        echo "  Ubuntu/Debian: sudo apt-get install -y docker.io docker-compose curl openssl"
        echo "  Arch/Manjaro:  sudo pacman -S docker docker-compose curl openssl"
        return 1
    fi

    return 0
}

# ===========================================
# DUCKDNS CONFIGURATION
# ===========================================

validate_duckdns_token() {
    local token="$1"

    # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    if [[ "$token" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    fi
    return 1
}

validate_subdomain() {
    local subdomain="$1"

    # Alphanumeric with hyphens allowed
    if [[ "$subdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    fi
    return 1
}

configure_duckdns() {
    cat <<'EOF'
========================================
DuckDNS Configuration
========================================

This addon requires a DuckDNS account for automatic
Let's Encrypt SSL certificate generation.

Get your free token at: https://www.duckdns.org

Requirements:
- DuckDNS account and token
- Port 80 and 443 accessible from internet
- Domain propagation may take a few minutes

NOTE: This addon uses Let's Encrypt for automatic
SSL certificate management. It does NOT use the
custom Root Key certificates from main.sh.

========================================

EOF

    while true; do
        local token
        token="$(prompt_user "Enter your DuckDNS token")"

        if validate_duckdns_token "$token"; then
            DUCKDNS_TOKEN="$token"
            break
        else
            print_message "error" "Invalid token format. Expected UUID format (e.g., xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
        fi
    done

    while true; do
        local subdomain
        subdomain="$(prompt_user "Enter your DuckDNS subdomain")"

        if validate_subdomain "$subdomain"; then
            DOMAIN_SUB="$subdomain"
            break
        else
            print_message "error" "Invalid subdomain. Use alphanumeric characters and hyphens only (3-63 characters)"
        fi
    done

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

    # Get public IP
    print_message "info" "Detecting public IP..."
    PUBLIC_IP=$(curl -fsS https://api.ipify.org)
    print_message "success" "Public IP: ${PUBLIC_IP}"

    # Build domain
    CLEAN_HOST=$(echo "$DOMAIN_SUB" | sed 's/\.duckdns\.org//g' | tr '[:upper:]' '[:lower:]')
    DOMAIN="${CLEAN_HOST}.duckdns.org"
    EMAIL="admin@${DOMAIN}"

    echo ""
    print_message "info" "Configuration Summary:"
    echo "  Domain: ${DOMAIN}"
    echo "  Public IP: ${PUBLIC_IP}"
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

    # Configure DuckDNS
    configure_duckdns

    # Root privilege check
    if [[ $EUID -ne 0 ]]; then
        print_message "warning" "This installation requires root privileges"
        if [[ "$(prompt_yes_no "Continue with sudo?" "y")" != "yes" ]]; then
            print_message "info" "Installation cancelled"
            exit 0
        fi

        # Export configuration for sudo execution
        export DUCKDNS_TOKEN DOMAIN_SUB MAX_REG_DEFAULT ENABLE_REGISTRATION
        export REGISTRATION_SHARED_SECRET POSTGRES_PASSWORD ADMIN_PASSWORD
        export PUBLIC_IP CLEAN_HOST DOMAIN EMAIL

        print_message "info" "Restarting with sudo..."
        exec sudo bash "$0" "$@"
    fi

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

    # Update DuckDNS record
    print_message "info" "Updating DuckDNS record..."
    curl -s "https://www.duckdns.org/update?domains=${CLEAN_HOST}&token=${DUCKDNS_TOKEN}&ip=${PUBLIC_IP}"

    # Create directory structure
    print_message "info" "Creating directory structure..."
    mkdir -p "${MATRIX_BASE}/data/"{synapse,postgres,traefik,element,well-known/matrix}
    cd "$MATRIX_BASE"

    # Reset SSL data
    rm -f data/traefik/acme.json
    touch data/traefik/acme.json
    chmod 600 data/traefik/acme.json

    # Generate docker-compose.yml
    print_message "info" "Generating docker-compose.yml..."
    cat > docker-compose.yml <<EOF
networks: {matrix: {}}
services:
  traefik:
    image: traefik:v2.10
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--certificatesresolvers.le.acme.tlschallenge=true"
      - "--certificatesresolvers.le.acme.email=${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/acme.json"
    ports: ["80:80", "443:443"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock:ro", "./data/traefik/acme.json:/acme.json"]
    networks: [matrix]

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=synapsedb
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes: ["./data/postgres:/var/lib/postgresql/data"]
    networks: [matrix]

  synapse:
    image: ghcr.io/matrix-org/synapse:latest
    depends_on: [postgres]
    volumes: ["./data/synapse:/data"]
    environment:
      SYNAPSE_SERVER_NAME: ${DOMAIN}
      SYNAPSE_REPORT_STATS: "no"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.synapse.rule=Host(\`${DOMAIN}\`) && (PathPrefix(\`/_matrix\`) || PathPrefix(\`/_synapse\`))"
      - "traefik.http.routers.synapse.entrypoints=websecure"
      - "traefik.http.routers.synapse.tls.certresolver=le"
    networks: [matrix]

  synapse-admin:
    image: awesometechnologies/synapse-admin:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.synadmin.rule=Host(\`${DOMAIN}\`) && PathPrefix(\`/admin\`)"
      - "traefik.http.routers.synadmin.entrypoints=websecure"
      - "traefik.http.routers.synadmin.tls.certresolver=le"
    networks: [matrix]

  element:
    image: vectorim/element-web:latest
    volumes: ["./data/element/config.json:/usr/share/element/config.json"]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.element.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.element.entrypoints=websecure"
      - "traefik.http.routers.element.tls.certresolver=le"
    networks: [matrix]
EOF

    # Cleanup any stuck containers
    print_message "info" "Cleaning up old containers..."
    docker compose down --remove-orphans 2>/dev/null || true

    # Initialize Synapse
    print_message "info" "Initializing Synapse..."
    docker compose run --rm synapse generate || true

    # Write Homeserver Config
    print_message "info" "Configuring Synapse..."
    cat >> data/synapse/homeserver.yaml <<EOF
database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapsedb
    host: postgres
enable_registration: ${ENABLE_REGISTRATION}
registration_shared_secret: "${REGISTRATION_SHARED_SECRET}"
EOF

    # Start services
    print_message "info" "Starting services and generating SSL certificates..."
    print_message "warning" "This may take 1-2 minutes..."
    docker compose up -d

    # Wait for SSL certificate generation
    print_message "info" "Waiting for SSL certificate (approximately 45 seconds)..."
    sleep 45

    # Create Admin User
    print_message "info" "Creating admin user..."
    docker compose exec -T synapse register_new_matrix_user -u admin -p "${ADMIN_PASSWORD}" -a -c /data/homeserver.yaml || true

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
    rm -rf "$MATRIX_BASE"

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

    cd "$MATRIX_BASE" || return 1

    echo ""
    docker compose ps
    echo ""

    if docker compose ps | grep -q "Up"; then
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
DOCKER-COMPOSE-SYNAPSE INSTALLATION COMPLETE
========================================${NC}"

    echo -e "${BLUE}Server Information:${NC}
  - Domain: https://${DOMAIN}
  - Installation: Docker Compose
"

    echo -e "${BLUE}Admin User:${NC}
  - Username: admin
  - Password: ${ADMIN_PASSWORD}
"

    echo -e "${BLUE}Access URLs:${NC}
  - Element Web: https://${DOMAIN}
  - Admin UI: https://${DOMAIN}/admin
"

    echo -e "${BLUE}Registration:${NC}
  - Shared Secret: ${REGISTRATION_SHARED_SECRET}
  - Max Per Invite: ${MAX_REG_DEFAULT}
  - Enabled: ${ENABLE_REGISTRATION}
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
    echo "docker-compose-synapse addon log - $(date)" > "$LOG_FILE"

    # Banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║          docker-compose-synapse Addon Installer         ║
║                       Version 2.3.0                      ║
║                                                          ║
║       Quick Docker Compose installer with Let's Encrypt ║
║                 SSL and DuckDNS support                  ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

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
                install_matrix "$@"
                break
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
