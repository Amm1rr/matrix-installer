#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="zanjir-synapse"
ADDON_NAME_MENU="Install Zanjir Synapse (Private Key+Dendrite+nginx)"
ADDON_VERSION="1.0.0"
ADDON_ORDER="40"
ADDON_DESCRIPTION="Matrix server using Dendrite with Element Web and nginx"
ADDON_AUTHOR="Matrix Installer"

# ===========================================
# ENVIRONMENT VARIABLES FROM MAIN.SH
# ===========================================
# These variables are exported by main.sh before running this addon:
#
# SERVER_NAME="172.19.39.69"                    # Server IP or domain name
# SSL_CERT="/path/to/certs/172.19.39.69/cert-full-chain.pem"  # Full chain certificate
# SSL_KEY="/path/to/certs/172.19.39.69/server.key"            # SSL private key
# ROOT_CA="/path/to/certs/172.19.39.69/rootCA.crt"            # Root Key certificate
# CERTS_DIR="/path/to/certs"                                # Certificates directory
# WORKING_DIR="/path/to/script"                              # Script working directory
# ===========================================

# ===========================================
# CONFIGURATION
# ===========================================
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="${WORKING_DIR:-$(pwd)}"
LOG_FILE="${WORKING_DIR}/zanjir-synapse.log"
MATRIX_BASE="/opt/zanjir-synapse"
SSL_DIR="${MATRIX_BASE}/ssl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values for optional features (must be before set -u)
: "${ENABLE_FEDERATION:=false}"
: "${ENABLE_FARSI_UI:=true}"
: "${ENABLE_REGISTRATION:=false}"
: "${ENABLE_DOCKER_MIRRORS:=false}"
: "${REEXECED:=0}"
: "${STANDALONE_MODE:=false}"
: "${UNINSTALL_MODE:=0}"
: "${ADMIN_USERNAME:=admin}"
: "${ADMIN_PASSWORD:=}"

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
        "info")    echo -e "${BLUE}[INFO]${NC} $message" ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "warning") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "error")   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
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

json_array_from_csv() {
    local csv=$1
    python3 - "$csv" <<'PY'
import json, sys
csv = sys.argv[1]
parts = [p.strip() for p in csv.replace(";", ",").split(",")]
parts = [p for p in parts if p]
print(json.dumps(parts))
PY
}

# ===========================================
# DUAL-MODE DETECTION
# ===========================================

check_environment_variables() {
    print_message "info" "Checking environment variables..."

    # Check for missing variables
    local missing=()
    [[ -z "${SERVER_NAME:-}" ]] && missing+=("SERVER_NAME")
    [[ -z "${SSL_CERT:-}" ]] && missing+=("SSL_CERT")
    [[ -z "${SSL_KEY:-}" ]] && missing+=("SSL_KEY")
    [[ -z "${ROOT_CA:-}" ]] && missing+=("ROOT_CA")

    # If no variables missing, just verify and return
    if [[ ${#missing[@]} -eq 0 ]]; then
        # Set CERTS_DIR and WORKING_DIR if not set
        [[ -z "${CERTS_DIR:-}" ]] && export CERTS_DIR="$(dirname "$(dirname "$SSL_CERT")")"
        [[ -z "${WORKING_DIR:-}" ]] && export WORKING_DIR="$(dirname "$CERTS_DIR")"
        WORKING_DIR="${WORKING_DIR:-$(pwd)}"
        LOG_FILE="${WORKING_DIR}/zanjir-synapse.log"

        # Verify files exist
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

        STANDALONE_MODE=false
        print_message "success" "Running in addon mode (using main.sh certificates)"
        print_message "info" "  SERVER_NAME: ${SERVER_NAME}"
        print_message "info" "  SSL_CERT: ${SSL_CERT}"
        print_message "info" "  SSL_KEY: ${SSL_KEY}"
        print_message "info" "  ROOT_CA: ${ROOT_CA}"
        return 0
    fi

    # Standalone mode: prompt for missing variables
    STANDALONE_MODE=true
    print_message "warning" "Running in standalone mode (not from main.sh)"
    echo ""
    echo "This addon can run standalone, but requires SSL certificates."
    echo ""

    # First, prompt for SERVER_NAME if needed
    if [[ " ${missing[*]} " =~ " SERVER_NAME " ]]; then
        local default_server="172.19.39.69"
        SERVER_NAME="$(prompt_user "Server name or IP address" "$default_server")"
        export SERVER_NAME
        # Remove from missing array
        missing=("${missing[@]/SERVER_NAME}")
    fi

    # Check if certificate files are needed
    local need_certs=false
    [[ " ${missing[*]} " =~ " SSL_CERT " ]] && need_certs=true
    [[ " ${missing[@]} " =~ " SSL_KEY " ]] && need_certs=true
    [[ " ${missing[@]} " =~ " ROOT_CA " ]] && need_certs=true

    if [[ "$need_certs" == "true" ]]; then
        echo ""
        echo "Provide certificates directory, and I'll search for:"
        echo "  - cert-full-chain.pem (server certificate chain)"
        echo "  - server.crt (server certificate)"
        echo "  - server.key (server private key)"
        echo "  - rootCA.crt (Root CA certificate)"
        echo ""

        local certs_dir
        certs_dir="$(prompt_user "Certificates directory (or press Enter for individual paths)" "")"

        if [[ -n "$certs_dir" && -d "$certs_dir" ]]; then
            # Search for files
            local found_cert=""
            local found_key=""
            local found_ca=""

            # Search for server certificate
            [[ -f "$certs_dir/cert-full-chain.pem" ]] && found_cert="$certs_dir/cert-full-chain.pem"
            [[ -z "$found_cert" && -f "$certs_dir/server.crt" ]] && found_cert="$certs_dir/server.crt"

            # Search for server private key
            [[ -f "$certs_dir/server.key" ]] && found_key="$certs_dir/server.key"

            # Search for Root CA files
            if [[ ! -f "$certs_dir/rootCA.crt" ]]; then
                local parent_dir="$(dirname "$certs_dir")"
                [[ -f "$parent_dir/rootCA.crt" ]] && found_ca="$parent_dir/rootCA.crt"

                if [[ -z "$found_ca" ]]; then
                    local grandparent_dir="$(dirname "$parent_dir")"
                    [[ -f "$grandparent_dir/rootCA.crt" ]] && found_ca="$grandparent_dir/rootCA.crt"
                fi
            else
                found_ca="$certs_dir/rootCA.crt"
            fi

            # Report findings
            [[ -n "$found_cert" ]] && print_message "success" "Found certificate: $found_cert"
            [[ -n "$found_key" ]] && print_message "success" "Found private key: $found_key"
            [[ -n "$found_ca" ]] && print_message "success" "Found Root CA: $found_ca"

            echo ""

            # Set found variables
            [[ -n "$found_cert" ]] && SSL_CERT="$found_cert" && export SSL_CERT
            [[ -n "$found_key" ]] && SSL_KEY="$found_key" && export SSL_KEY
            [[ -n "$found_ca" ]] && ROOT_CA="$found_ca" && export ROOT_CA

            # Check for missing files and prompt
            local missing_files=()
            [[ -z "$SSL_CERT" ]] && missing_files+=("SSL_CERT")
            [[ -z "$SSL_KEY" ]] && missing_files+=("SSL_KEY")
            [[ -z "$ROOT_CA" ]] && missing_files+=("ROOT_CA")

            if [[ ${#missing_files[@]} -gt 0 ]]; then
                print_message "info" "Some files were not found. Please provide paths:"
                echo ""

                [[ " ${missing_files[*]} " =~ " SSL_CERT " ]] && {
                    SSL_CERT="$(prompt_user "  Path to SSL certificate" "/path/to/cert-full-chain.pem")"
                    export SSL_CERT
                }

                [[ " ${missing_files[*]} " =~ " SSL_KEY " ]] && {
                    SSL_KEY="$(prompt_user "  Path to SSL private key" "/path/to/server.key")"
                    export SSL_KEY
                }

                [[ " ${missing_files[*]} " =~ " ROOT_CA " ]] && {
                    ROOT_CA="$(prompt_user "  Path to Root CA certificate" "/path/to/rootCA.crt")"
                    export ROOT_CA
                }
            fi
        else
            # No directory provided, prompt for all
            echo "Please provide individual file paths:"
            echo ""

            [[ -z "$SSL_CERT" ]] && {
                SSL_CERT="$(prompt_user "  Path to SSL certificate" "/path/to/cert-full-chain.pem")"
                export SSL_CERT
            }

            [[ -z "$SSL_KEY" ]] && {
                SSL_KEY="$(prompt_user "  Path to SSL private key" "/path/to/server.key")"
                export SSL_KEY
            }

            [[ -z "$ROOT_CA" ]] && {
                ROOT_CA="$(prompt_user "  Path to Root CA certificate" "/path/to/rootCA.crt")"
                export ROOT_CA
            }
        fi
    fi

    # Set CERTS_DIR and WORKING_DIR if not set
    [[ -z "${CERTS_DIR:-}" ]] && export CERTS_DIR="$(dirname "$(dirname "$SSL_CERT")")"
    [[ -z "${WORKING_DIR:-}" ]] && export WORKING_DIR="$(dirname "$CERTS_DIR")"
    WORKING_DIR="${WORKING_DIR:-$(pwd)}"
    LOG_FILE="${WORKING_DIR}/zanjir-synapse.log"

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

    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    else
        print_message "success" "openssl is installed"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "error" "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Install missing packages:"
        echo "  Ubuntu/Debian: sudo apt-get install -y docker.io docker-compose-plugin openssl"
        echo "  Arch/Manjaro:  sudo pacman -S docker docker-compose openssl"
        return 1
    fi

    return 0
}

is_dockerhub_restriction_error() {
    local text=$1
    echo "$text" | grep -Eqi '403 Forbidden|export control regulations|Since Docker is a US company'
}

configure_docker_registry_mirrors() {
    local mirrors_csv=$1
    if [ -z "$mirrors_csv" ]; then
        return 1
    fi

    local mirrors_json
    if command -v python3 &>/dev/null; then
        mirrors_json=$(json_array_from_csv "$mirrors_csv")
    else
        local cleaned
        cleaned=$(echo "$mirrors_csv" | tr ';' ',' | tr -s ' ')
        local IFS=','
        read -ra _parts <<<"$cleaned"
        local json="["
        local first=1
        for p in "${_parts[@]}"; do
            p=$(echo "$p" | xargs)
            [ -z "$p" ] && continue
            if [ "$first" -eq 0 ]; then
                json+=","
            fi
            first=0
            json+="\"$p\""
        done
        json+="]"
        mirrors_json="$json"
    fi

    print_message "info" "Configuring Docker registry mirrors..."
    mkdir -p /etc/docker

    local daemon_file="/etc/docker/daemon.json"
    if [ -f "$daemon_file" ]; then
        cp -a "$daemon_file" "${daemon_file}.bak.$(date +%s)" 2>/dev/null || true
    fi

    if command -v python3 &>/dev/null; then
        python3 - "$daemon_file" "$mirrors_json" <<'PY'
import json, sys, pathlib, re

daemon_file = pathlib.Path(sys.argv[1])
mirrors = json.loads(sys.argv[2])

data = {}
if daemon_file.exists():
    try:
        raw = daemon_file.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        data = {}

def insecure_from_url(url: str) -> str:
    url = re.sub(r"^https?://", "", url)
    url = url.split("/", 1)[0]
    return url

data["registry-mirrors"] = mirrors
data["insecure-registries"] = sorted({insecure_from_url(u) for u in mirrors})

daemon_file.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    else
        cat >"$daemon_file" <<EOF
{
  "registry-mirrors": $mirrors_json,
  "insecure-registries": $(echo "$mirrors_json" | sed -E 's#https?://##g;s#/[^"]*##g')
}
EOF
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart docker
    print_message "success" "Docker mirrors configured."
}

ensure_docker_registry_access() {
    local mirrors_csv="${DOCKER_REGISTRY_MIRRORS:-${DOCKER_REGISTRY_MIRROR:-}}"
    if [ -n "$mirrors_csv" ]; then
        configure_docker_registry_mirrors "$mirrors_csv" || true
        return 0
    fi

    local probe_image="${DOCKER_PROBE_IMAGE:-hello-world:latest}"

    set +e
    local pull_output
    pull_output=$(docker pull "$probe_image" 2>&1)
    local pull_exit=$?
    set -e

    if [ "$pull_exit" -eq 0 ]; then
        return 0
    fi

    if ! is_dockerhub_restriction_error "$pull_output"; then
        print_message "warning" "Docker pull failed (not a sanctions-style 403). Continuing..."
        return 0
    fi

    print_message "warning" "Docker Hub appears restricted. Applying mirrors..."

    local default_mirrors="https://docker.arvancloud.ir,https://registry.docker.ir,https://docker.iranserver.com,https://mirror-docker.runflare.com"
    configure_docker_registry_mirrors "$default_mirrors"
}

docker_pull_with_mirror_fallback() {
    local image=$1

    set +e
    local out
    out=$(docker pull "$image" 2>&1)
    local code=$?
    set -e

    if [ "$code" -eq 0 ]; then
        return 0
    fi

    if is_dockerhub_restriction_error "$out"; then
        ensure_docker_registry_access
        docker pull "$image"
        return $?
    fi

    echo "$out" >&2
    return "$code"
}

# ===========================================
# OPTIONAL FEATURES PROMPT
# ===========================================

prompt_optional_features() {
    echo ""
    echo "========================================"
    echo "       Optional Features"
    echo "========================================"
    echo ""

    # Docker registry mirrors (for Iran)
    if [[ "$(prompt_yes_no "Enable Docker registry mirrors for Iran?" "n")" == "yes" ]]; then
        ENABLE_DOCKER_MIRRORS=true
        DOCKER_MIRRORS="https://docker.arvancloud.ir,https://registry.docker.ir,https://docker.iranserver.com,https://mirror-docker.runflare.com"
        print_message "info" "Docker mirrors will be configured"
    else
        ENABLE_DOCKER_MIRRORS=false
        DOCKER_MIRRORS=""
    fi

    # Farsi UI
    if [[ "$(prompt_yes_no "Enable Farsi (Persian) language UI?" "y")" == "yes" ]]; then
        ENABLE_FARSI_UI=true
        print_message "info" "Farsi UI will be enabled"
    else
        ENABLE_FARSI_UI=false
    fi

    # Federation
    if [[ "$(prompt_yes_no "Enable Matrix federation?" "n")" == "yes" ]]; then
        ENABLE_FEDERATION=true
        print_message "info" "Federation will be enabled"
    else
        ENABLE_FEDERATION=false
        print_message "info" "Federation disabled (isolated server)"
    fi

    # Registration
    if [[ "$(prompt_yes_no "Enable user registration?" "n")" == "yes" ]]; then
        ENABLE_REGISTRATION=true
        print_message "info" "Registration will be enabled"
    else
        ENABLE_REGISTRATION=false
        print_message "info" "Registration disabled (admin only)"
    fi

    # Admin User
    echo ""
    echo "========================================"
    echo "       Admin User Configuration"
    echo "========================================"
    echo ""

    ADMIN_USERNAME="$(prompt_user "Admin username" "admin")"

    # Generate a random password as default
    local default_password
    default_password=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)

    # Password validation - Dendrite only checks minimum length (8 characters)
    while true; do
        ADMIN_PASSWORD="$(prompt_user "Admin password (min 8 characters)" "$default_password")"

        if [[ ${#ADMIN_PASSWORD} -ge 8 ]]; then
            break
        fi

        echo ""
        print_message "warning" "Password must be at least 8 characters"
        echo ""
    done

    print_message "info" "Admin user will be created after installation"
    print_message "info" "  - Username: $ADMIN_USERNAME"
    echo ""
}

# ===========================================
# CONFIGURATION
# ===========================================

generate_secrets() {
    print_message "info" "Generating security keys..."
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
    REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
    print_message "success" "Keys generated."
}

create_env_file() {
    print_message "info" "Creating .env file..."

    cat > "${MATRIX_BASE}/.env" <<EOF
DOMAIN=${SERVER_NAME}
SERVER_ADDRESS=${SERVER_NAME}
PROTOCOL=https
REGISTRATION_SHARED_SECRET=${REGISTRATION_SECRET}
POSTGRES_USER=dendrite
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=dendrite
POSTGRES_IMAGE=postgres:15-alpine
DENDRITE_IMAGE=matrixdotorg/dendrite-monolith:latest
ELEMENT_IMAGE=vectorim/element-web:v1.11.50
ELEMENT_COPY_IMAGE=vectorim/element-web:v1.11.50
EOF

    chmod 600 "${MATRIX_BASE}/.env"
    print_message "success" ".env file created."
}

setup_nginx_conf() {
    print_message "info" "Setting up nginx configuration..."

    if [[ "$ENABLE_FEDERATION" == "true" ]]; then
        print_message "info" "Using main.sh Root Key SSL certificates (federation enabled)"
    else
        print_message "info" "Using main.sh certificates (isolated mode)"
    fi

    mkdir -p "${MATRIX_BASE}/nginx"

    cat > "${MATRIX_BASE}/nginx/nginx.conf" <<EOF
# Zanjir - nginx Configuration
# Using main.sh Root Key SSL certificates for federation support

worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    # Upstream Matrix server
    upstream dendrite {
        server dendrite:8008;
    }

    # HTTP redirect to HTTPS
    server {
        listen 80;
        server_name ${SERVER_NAME};
        return 301 https://\$host\$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name ${SERVER_NAME};

        # SSL certificates from main.sh
        ssl_certificate /etc/nginx/ssl/cert-full-chain.pem;
        ssl_certificate_key /etc/nginx/ssl/server.key;

        # SSL settings
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        # Security headers
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy strict-origin-when-cross-origin always;

        # Matrix .well-known endpoints
        location /.well-known/matrix/server {
            default_type application/json;
            return 200 '{"m.server": "${SERVER_NAME}:443"}';
        }

        location /.well-known/matrix/client {
            default_type application/json;
            add_header Access-Control-Allow-Origin * always;
            return 200 '{"m.homeserver": {"base_url": "https://${SERVER_NAME}"}, "m.identity_server": {"base_url": "https://vector.im"}}';
        }

        # Matrix Client-Server API
        location /_matrix/ {
            proxy_pass http://dendrite;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Matrix Federation API
        location /_dendrite/ {
            proxy_pass http://dendrite;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Mobile guide
        location /mobile_guide {
            alias /srv/element/mobile_guide;
            try_files \$uri /mobile_guide/index.html =404;
        }

        # Welcome page
        location = /welcome {
            alias /srv/element/welcome.html;
        }

        location = /welcome.html {
            alias /srv/element/welcome.html;
        }

        # Element App
        location /app/ {
            alias /srv/element/;
            try_files \$uri \$uri/ /app/index.html =404;
        }

        # Element Web (default)
        location / {
            alias /srv/element/;
            try_files \$uri \$uri/ /index.html =404;
        }
    }
}
EOF

    chmod 644 "${MATRIX_BASE}/nginx/nginx.conf"
    print_message "success" "nginx configuration created."
}

update_dendrite_config() {
    print_message "info" "Configuring Dendrite..."

    # Read template from addon and create configured version
    local template_file="${ADDON_DIR}/dendrite/dendrite.yaml"
    local output_file="${MATRIX_BASE}/dendrite/dendrite.yaml"

    # Create output directory
    mkdir -p "${MATRIX_BASE}/dendrite"

    # Replace placeholders with actual values
    sed "s|\${DOMAIN}|${SERVER_NAME}|g" "$template_file" | \
    sed "s|\${POSTGRES_USER}|dendrite|g" | \
    sed "s|\${POSTGRES_PASSWORD}|${POSTGRES_PASSWORD}|g" | \
    sed "s|\${POSTGRES_DB}|dendrite|g" | \
    sed "s|\${REGISTRATION_SHARED_SECRET}|${REGISTRATION_SECRET}|g" \
    > "$output_file"

    # Handle federation setting directly
    if [[ "$ENABLE_FEDERATION" == "true" ]]; then
        sed -i 's/disable_federation: true/disable_federation: false/g' "$output_file"
    fi

    # Handle registration setting
    if [[ "$ENABLE_REGISTRATION" == "true" ]]; then
        sed -i 's/registration_disabled: true/registration_disabled: false/g' "$output_file"
        sed -i 's/guests_disabled: true/guests_disabled: false/g' "$output_file"
    fi

    # Handle search language for Farsi
    if [[ "$ENABLE_FARSI_UI" == "true" ]]; then
        sed -i 's/language: "en"/language: "fa"/g' "$output_file"
    fi

    print_message "success" "Dendrite configured."
}

update_element_config() {
    print_message "info" "Configuring Element..."

    local template_file="${ADDON_DIR}/config/element-config.json"
    local output_file="${MATRIX_BASE}/config/element-config.json"

    mkdir -p "${MATRIX_BASE}/config"

    # Determine registration feature value
    local registration_feature
    if [[ "$ENABLE_REGISTRATION" == "true" ]]; then
        registration_feature="true"
    else
        registration_feature="false"
    fi

    # Replace domain placeholder, language settings, and registration feature
    sed "s|__DOMAIN_PLACEHOLDER__|${SERVER_NAME}|g" "$template_file" | \
    sed "s|\"language\": \"fa\"|\"language\": \"$( [[ "$ENABLE_FARSI_UI" == "true" ]] && echo "fa" || echo "en" )\"|g" | \
    sed "s|\"UIFeature.registration\": false|\"UIFeature.registration\": ${registration_feature}|g" \
    > "$output_file"

    print_message "success" "Element configured."
}

copy_certificates() {
    print_message "info" "Copying SSL certificates for nginx..."
    mkdir -p "${SSL_DIR}"

    cp "$SSL_CERT" "${SSL_DIR}/cert-full-chain.pem"
    cp "$SSL_KEY" "${SSL_DIR}/server.key"
    cp "$ROOT_CA" "${SSL_DIR}/rootCA.crt"

    chmod 644 "${SSL_DIR}/cert-full-chain.pem"
    chmod 644 "${SSL_DIR}/rootCA.crt"
    chmod 600 "${SSL_DIR}/server.key"

    print_message "success" "SSL certificates copied."
}

copy_config_files() {
    print_message "info" "Copying configuration files..."

    # Copy all config files from addon
    cp "${ADDON_DIR}/config/welcome.html" "${MATRIX_BASE}/config/"
    cp "${ADDON_DIR}/config/mobile_guide.html" "${MATRIX_BASE}/config/"
    cp "${ADDON_DIR}/config/custom.css" "${MATRIX_BASE}/config/"
    cp "${ADDON_DIR}/config/logo.webp" "${MATRIX_BASE}/config/" 2>/dev/null || true

    print_message "success" "Configuration files copied."
}

generate_matrix_key() {
    print_message "info" "Generating Matrix signing key..."

    if [[ -f "${MATRIX_BASE}/dendrite/matrix_key.pem" ]]; then
        print_message "warning" "Matrix key already exists."
        return 0
    fi

    load_env_if_exists

    local dendrite_image="${DENDRITE_IMAGE:-matrixdotorg/dendrite-monolith:latest}"

    # Apply Docker mirrors if enabled
    if [[ "$ENABLE_DOCKER_MIRRORS" == "true" ]]; then
        ensure_docker_registry_access
    fi

    print_message "info" "Pulling Dendrite image..."
    docker_pull_with_mirror_fallback "$dendrite_image"

    print_message "info" "Generating key..."
    docker run --rm \
        --entrypoint /usr/bin/generate-keys \
        -v "${MATRIX_BASE}/dendrite:/etc/dendrite" \
        "$dendrite_image" \
        --private-key /etc/dendrite/matrix_key.pem

    if [[ -f "${MATRIX_BASE}/dendrite/matrix_key.pem" ]]; then
        chmod 600 "${MATRIX_BASE}/dendrite/matrix_key.pem"
        print_message "success" "Matrix key generated."
    else
        print_message "error" "Failed to generate Matrix key!"
        return 1
    fi
}

load_env_if_exists() {
    if [[ -f "${MATRIX_BASE}/.env" ]]; then
        set -a
        . "${MATRIX_BASE}/.env"
        set +a
    fi
}

start_services() {
    print_message "info" "Starting services..."

    cd "$MATRIX_BASE"

    # Create docker-compose.yml FIRST before any docker compose commands
    update_docker_compose

    # Apply Docker mirrors if enabled
    if [[ "$ENABLE_DOCKER_MIRRORS" == "true" ]]; then
        ensure_docker_registry_access
    fi

    print_message "info" "Pulling Docker images..."

    set +e
    local pull_out
    pull_out=$(docker compose pull 2>&1)
    local pull_code=$?
    set -e

    if [[ $pull_code -ne 0 ]]; then
        if is_dockerhub_restriction_error "$pull_out"; then
            ensure_docker_registry_access
            docker compose pull
        else
            echo "$pull_out" >&2
            return $pull_code
        fi
    fi

    print_message "info" "Copying Element files..."
    docker compose run --rm element-copy

    print_message "info" "Starting services..."
    docker compose up -d postgres

    print_message "info" "Waiting for PostgreSQL to be ready..."
    sleep 10

    docker compose up -d dendrite element nginx

    print_message "info" "Waiting for services to start..."
    sleep 5

    print_message "success" "Services started!"
}

update_docker_compose() {
    print_message "info" "Updating docker-compose.yml..."

    cat > "${MATRIX_BASE}/docker-compose.yml" <<EOF
# Zanjir - Docker Compose Configuration
# Self-hosted Matrix server with Dendrite, Element Web, and nginx
# Web Server: nginx
# Federation: \${ENABLE_FEDERATION}

services:
  # PostgreSQL Database
  postgres:
    image: \${POSTGRES_IMAGE:-postgres:15-alpine}
    container_name: zanjir-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER:-dendrite}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB:-dendrite}
    volumes:
      - zanjir-postgres-data:/var/lib/postgresql/data
    networks:
      - zanjir-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-dendrite}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Dendrite Matrix Homeserver
  dendrite:
    image: \${DENDRITE_IMAGE:-matrixdotorg/dendrite-monolith:latest}
    container_name: zanjir-dendrite
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DOMAIN: \${DOMAIN}
      POSTGRES_USER: \${POSTGRES_USER:-dendrite}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB:-dendrite}
      REGISTRATION_SHARED_SECRET: \${REGISTRATION_SHARED_SECRET}
    volumes:
      - ./dendrite/dendrite.yaml:/etc/dendrite/dendrite.yaml:ro
      - ./dendrite/matrix_key.pem:/etc/dendrite/matrix_key.pem:ro
      - zanjir-dendrite-media:/var/dendrite/media
      - zanjir-dendrite-jetstream:/var/dendrite/jetstream
      - zanjir-dendrite-search:/var/dendrite/searchindex
    networks:
      - zanjir-network
$( [[ "$ENABLE_REGISTRATION" == "true" ]] && echo "    command: --config /etc/dendrite/dendrite.yaml --really-enable-open-registration" || echo "    command: --config /etc/dendrite/dendrite.yaml" )

  # Element Web Client
  element:
    image: \${ELEMENT_IMAGE:-vectorim/element-web:v1.11.50}
    container_name: zanjir-element
    restart: unless-stopped
    volumes:
      - ./config/element-config.json:/app/config.json:ro
      - ./config/welcome.html:/app/welcome.html:ro
    networks:
      - zanjir-network

  # nginx Reverse Proxy with main.sh SSL
  nginx:
    image: nginx:alpine
    container_name: zanjir-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - zanjir-web-data:/data
      # Mount Element Web files for serving
      - zanjir-element-web:/srv/element:ro
    networks:
      - zanjir-network
    depends_on:
      - dendrite
      - element

  # Utility container to copy Element Web files
  element-copy:
    image: \${ELEMENT_COPY_IMAGE:-vectorim/element-web:v1.11.50}
    container_name: zanjir-element-copy
    user: root
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        cp -r /app/* /srv/element/
        cp /config/config.json /srv/element/config.json
        cp /config/welcome.html /srv/element/welcome.html
        cp /config/logo.webp /srv/element/logo.webp 2>/dev/null || true
        cp /config/custom.css /srv/element/themes/custom.css 2>/dev/null || true
        mkdir -p /srv/element/mobile_guide
        cp /config/mobile_guide.html /srv/element/mobile_guide/index.html
        echo "Element Web files copied successfully"
    volumes:
      - zanjir-element-web:/srv/element
      - ./config/element-config.json:/config/config.json:ro
      - ./config/welcome.html:/config/welcome.html:ro
      - ./config/logo.webp:/config/logo.webp:ro
      - ./config/custom.css:/config/custom.css:ro
      - ./config/mobile_guide.html:/config/mobile_guide.html:ro
    networks:
      - zanjir-network

networks:
  zanjir-network:
    driver: bridge

volumes:
  zanjir-postgres-data:
    name: zanjir-postgres-data
  zanjir-dendrite-media:
    name: zanjir-dendrite-media
  zanjir-dendrite-jetstream:
    name: zanjir-dendrite-jetstream
  zanjir-dendrite-search:
    name: zanjir-dendrite-search
  zanjir-web-data:
    name: zanjir-web-data
  zanjir-element-web:
    name: zanjir-element-web
EOF
}

check_services() {
    print_message "info" "Checking service status..."
    cd "$MATRIX_BASE"
    docker compose ps
}

create_admin_user() {
    print_message "info" "Creating admin user..."

    # Wait for Dendrite to be fully ready
    print_message "info" "Waiting for Dendrite to be ready..."
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if docker exec zanjir-dendrite /usr/bin/create-account --help >/dev/null 2>&1; then
            break
        fi
        sleep 1
        ((waited++))
    done

    # Create admin user (password was pre-validated)
    local output
    output=$(docker exec zanjir-dendrite /usr/bin/create-account \
        --config /etc/dendrite/dendrite.yaml \
        --username "$ADMIN_USERNAME" \
        --password "$ADMIN_PASSWORD" \
        --admin 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_message "success" "Admin user created successfully"
        print_message "info" "  - Username: $ADMIN_USERNAME"
        return 0
    fi

    # Check if user already exists (not a fatal error)
    if echo "$output" | grep -qi "already exists"; then
        print_message "warning" "Admin user already exists"
        print_message "info" "  - Username: $ADMIN_USERNAME"
        return 0
    fi

    # Other error
    print_message "error" "Failed to create admin user"
    print_message "info" "Error: $output"
    print_message "info" "You can create it manually:"
    echo "  docker exec -it zanjir-dendrite /usr/bin/create-account \\"
    echo "    --config /etc/dendrite/dendrite.yaml \\"
    echo "    --username $ADMIN_USERNAME \\"
    echo "    --password PASSWORD \\"
    echo "    --admin"
    return 1
}

# ===========================================
# INSTALLATION
# ===========================================

install_matrix() {
    print_message "info" "Starting installation..."

    # Check if Matrix is already installed
    if [[ -d "$MATRIX_BASE" && -f "$MATRIX_BASE/docker-compose.yml" ]]; then
        # Check if containers are running
        local running_count
        running_count=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -c "^zanjir-" || echo "0")
        running_count=$(echo "$running_count" | tr -d '[:space:]')

        if [[ "$running_count" -gt 0 ]]; then
            echo ""
            print_message "warning" "Matrix is already installed and running!"
            echo ""
            echo "  Installation directory: ${MATRIX_BASE}"
            echo "  Running containers: ${running_count}"
            echo ""
            print_message "info" "Please use option 2 (Uninstall Matrix) from the main menu first."
            echo ""
            return 2
        fi
    fi

    # Prompt for optional features BEFORE sudo re-exec (so user can choose)
    if [[ "${REEXECED:-}" != "1" ]]; then
        prompt_optional_features
    fi

    # Root privilege check
    if [[ $EUID -ne 0 ]]; then
        print_message "warning" "This installation requires root privileges"
        if [[ "$(prompt_yes_no "Continue with sudo?" "y")" != "yes" ]]; then
            print_message "info" "Installation cancelled"
            exit 0
        fi

        # Save configuration to temp file for sudo execution
        local temp_config="/tmp/zanjir-install-$$-config.sh"
        cat > "$temp_config" <<EOF
export SERVER_NAME="${SERVER_NAME:-}"
export SSL_CERT="${SSL_CERT:-}"
export SSL_KEY="${SSL_KEY:-}"
export ROOT_CA="${ROOT_CA:-}"
export CERTS_DIR="${CERTS_DIR:-}"
export WORKING_DIR="${WORKING_DIR:-}"
export REEXECED="1"
export ENABLE_FEDERATION="${ENABLE_FEDERATION:-false}"
export ENABLE_FARSI_UI="${ENABLE_FARSI_UI:-true}"
export ENABLE_REGISTRATION="${ENABLE_REGISTRATION:-false}"
export ENABLE_DOCKER_MIRRORS="${ENABLE_DOCKER_MIRRORS:-false}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
EOF

        print_message "info" "Restarting with sudo..."
        local script_path="$ADDON_DIR/install.sh"
        exec sudo bash -c "source '$temp_config' && bash '$script_path' && rm -f '$temp_config'"
    fi

    # Check prerequisites
    check_prerequisites || exit 3

    # Check environment variables
    check_environment_variables || exit 4

    # Clean up any old Zanjir containers that might conflict
    print_message "info" "Checking for conflicting containers..."
    local conflicting_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep -E "^zanjir-(postgres|dendrite|caddy|element)" || true)
    if [[ -n "$conflicting_containers" ]]; then
        print_message "warning" "Found old Zanjir containers that conflict with this installation:"
        echo "$conflicting_containers" | sed 's/^/  - /'
        if [[ "$(prompt_yes_no "Remove old Zanjir containers?" "y")" == "yes" ]]; then
            print_message "info" "Removing old Zanjir containers..."
            echo "$conflicting_containers" | xargs -r docker rm -f 2>/dev/null || true
        fi
    fi

    # Generate secrets
    generate_secrets

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
    mkdir -p "${MATRIX_BASE}/"{config,dendrite,ssl}

    # Copy certificates
    copy_certificates

    # Copy config files
    copy_config_files

    # Create .env file
    create_env_file

    # Setup web server configuration
    setup_nginx_conf

    # Update Dendrite config
    update_dendrite_config

    # Update Element config
    update_element_config

    # Generate Matrix key
    generate_matrix_key

    # Start services
    start_services

    # Check services
    check_services

    # Create admin user
    create_admin_user

    # Print summary
    print_summary
}

# ===========================================
# UNINSTALLATION
# ===========================================

uninstall_matrix() {
    # Root privilege check - re-exec with sudo if needed
    if [[ $EUID -ne 0 ]]; then
        print_message "warning" "Uninstallation requires root privileges"
        if [[ "$(prompt_yes_no "Continue with sudo?" "y")" != "yes" ]]; then
            print_message "info" "Uninstall cancelled"
            return 0
        fi

        local script_path="$ADDON_DIR/install.sh"
        print_message "info" "Restarting with sudo..."
        exec sudo bash -c "export UNINSTALL_MODE=1; bash '$script_path'"
    fi

    print_message "warning" "This will:"
    echo "  - Stop all Zanjir Synapse containers"
    echo "  - Remove all Zanjir containers (both old and new)"
    echo "  - Remove all Zanjir volumes"
    echo "  - Delete ${MATRIX_BASE} directory"
    echo ""

    if [[ "$(prompt_yes_no "Continue with uninstall?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop and remove new zanjir-synapse containers (if docker-compose.yml exists)
    if [[ -d "$MATRIX_BASE" && -f "$MATRIX_BASE/docker-compose.yml" ]]; then
        cd "$MATRIX_BASE" || { print_message "error" "Cannot access ${MATRIX_BASE}"; return 1; }
        print_message "info" "Stopping and removing zanjir-synapse containers..."
        docker compose down -v 2>/dev/null || true
    fi

    # Remove old zanjir containers (from original Zanjir installation)
    print_message "info" "Checking for old Zanjir containers..."
    local old_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^zanjir-" | grep -v "^zanjir-synapse-" || true)
    if [[ -n "$old_containers" ]]; then
        print_message "info" "Removing old Zanjir containers..."
        echo "$old_containers" | xargs -r docker rm -f 2>/dev/null || true
    fi

    # Remove old zanjir volumes
    print_message "info" "Checking for old Zanjir volumes..."
    local old_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep "^zanjir-" | grep -v "^zanjir-synapse-" || true)
    if [[ -n "$old_volumes" ]]; then
        print_message "info" "Removing old Zanjir volumes..."
        echo "$old_volumes" | xargs -r docker volume rm 2>/dev/null || true
    fi

    # Remove installation directory
    if [[ -d "$MATRIX_BASE" ]]; then
        cd "/"
        print_message "info" "Removing installation directory..."
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

    if [[ ! -f "$MATRIX_BASE/docker-compose.yml" ]]; then
        print_message "warning" "Matrix is not properly installed (docker-compose.yml not found)"
        print_message "info" "Directory exists at: ${MATRIX_BASE}"
        return 0
    fi

    print_message "success" "Matrix is installed at: ${MATRIX_BASE}"
    echo ""

    # Show all running Docker containers
    print_message "info" "All running Docker containers:"
    echo ""

    local running_containers
    running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)

    if [[ -n "$running_containers" ]]; then
        echo "$running_containers"
        echo ""
        local total_running
        total_running=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
        print_message "success" "Total running containers: ${total_running}"
    else
        print_message "warning" "No containers are currently running"
        print_message "info" "Docker might not be running - check with: systemctl status docker"
    fi
    echo ""

    # Check Matrix-specific containers
    print_message "info" "Matrix containers status:"
    echo ""

    # Count running Matrix containers by name
    local matrix_running_count
    matrix_running_count=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -c "^zanjir-" || echo "0")
    matrix_running_count=$(echo "$matrix_running_count" | tr -d '[:space:]')

    if [[ "$matrix_running_count" -gt 0 ]]; then
        # Show Matrix container details
        docker ps --filter "name=zanjir-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
        echo ""
        print_message "success" "Matrix services are running (${matrix_running_count} containers active)"
    else
        print_message "warning" "Matrix services are not running"
        print_message "info" "Start them with: cd ${MATRIX_BASE} && docker compose up -d"
    fi
    echo ""

    # Try docker compose ps for detailed status
    local current_dir="$(pwd)"
    if cd "$MATRIX_BASE" 2>/dev/null; then
        local compose_output
        compose_output=$(docker compose ps 2>&1)
        local compose_exit=$?

        if [[ $compose_exit -eq 0 && -n "$compose_output" ]]; then
            print_message "info" "Docker Compose detailed status:"
            echo "$compose_output"
        fi

        cd "$current_dir" 2>/dev/null || true
    fi
}

# ===========================================
# PRINT SUMMARY
# ===========================================

print_summary() {
    echo ""
    echo -e "${GREEN}========================================
ZANJIR-SYNAPSE INSTALLATION COMPLETE
========================================${NC}"

    echo -e "${CYAN}Admin Credentials:${NC}"
    echo "  Username: ${ADMIN_USERNAME:-admin}"
    echo "  Password: ${ADMIN_PASSWORD:-<not set>}"
    echo ""

    echo -e "${BLUE}Server Information:${NC}"
    echo "  - Server: ${SERVER_NAME}"
    echo "  - Web Server: nginx"
    if [[ "$ENABLE_FEDERATION" == "true" ]]; then
        echo "  - Installation: Docker Compose with nginx + main.sh Root Key SSL"
    else
        echo "  - Installation: Docker Compose with nginx + main.sh certificates (isolated)"
    fi
    echo "  - Mode: $( [[ "$STANDALONE_MODE" == "true" ]] && echo "Standalone" || echo "Addon (main.sh)" )"
    echo ""

    echo -e "${BLUE}Access URLs:${NC}"
    echo "  - Element Web: https://${SERVER_NAME}"
    echo "  - Mobile Guide: https://${SERVER_NAME}/mobile_guide"

    if [[ "$ENABLE_FEDERATION" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}  NOTE: Self-signed certificate (import Root CA to browser).${NC}"
    fi
    echo ""

    echo -e "${BLUE}Registration:${NC}"
    echo "  - Shared Secret: ${REGISTRATION_SECRET}"
    echo "  - Enabled: ${ENABLE_REGISTRATION:-false}"
    echo "  - Federation: ${ENABLE_FEDERATION:-false}"
    echo ""

    echo -e "${BLUE}Features:${NC}"
    echo "  - Farsi UI: ${ENABLE_FARSI_UI:-false}"
    echo "  - Docker Mirrors: ${ENABLE_DOCKER_MIRRORS:-false}"
    echo ""

    echo -e "${BLUE}SSL Configuration:${NC}"
    echo "  - Server: nginx"
    if [[ "$ENABLE_FEDERATION" == "true" ]]; then
        echo "  - Mode: main.sh Root Key (for federation)"
        echo "  - Certificate: ${SSL_DIR}/cert-full-chain.pem"
        echo "  - Private Key: ${SSL_DIR}/server.key"
        echo "  - Root CA: ${SSL_DIR}/rootCA.crt"
    else
        echo "  - Mode: main.sh certificates (isolated)"
        echo "  - Certificate: ${SSL_DIR}/cert-full-chain.pem"
    fi
    echo ""

    echo -e "${BLUE}Docker Compose:${NC}"
    echo "  - Location: ${MATRIX_BASE}"
    echo "  - Control: cd ${MATRIX_BASE} && docker compose [up|down|logs]"
    echo ""

    echo -e "${YELLOW}IMPORTANT:${NC} Save your admin credentials securely!"
    echo ""

    echo -e "${GREEN}========================================${NC}"
}

# ===========================================
# BANNER
# ===========================================

print_banner() {
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║           Zanjir Synapse (Dendrite) Addon               ║
║                       Version 1.0.0                      ║
║                                                          ║
║     Matrix server using Dendrite with Element Web       ║
║           and nginx with main.sh Root Key SSL           ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
}

# ===========================================
# MAIN MENU
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "zanjir-synapse addon log - $(date)" > "$LOG_FILE"

    # Check if re-executed with sudo for install - skip menu and install directly
    if [[ "${REEXECED:-}" == "1" ]]; then
        print_message "info" "Continuing installation with root privileges..."
        install_matrix "$@"
        return $?
    fi

    # Check if running in uninstall mode - skip menu and uninstall directly
    if [[ "${UNINSTALL_MODE:-}" == "1" ]]; then
        print_banner
        uninstall_matrix
        exit 0
    fi

    # Banner
    print_banner

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
                if [[ $install_result -ne 2 ]]; then
                    break
                fi
                ;;
            2)
                set +e
                uninstall_matrix
                set -e
                ;;
            3)
                set +e
                check_status
                set -e
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
