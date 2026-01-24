#!/bin/bash

# ===========================================
# Matrix Plus - Modular Matrix Installation System
# Version: 1.0.0
# Description: Orchestrator for modular Matrix homeserver installation
# ===========================================

set -e
set -u
set -o pipefail

# ===========================================
# CONFIGURATION
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="$(pwd)"
CERTS_DIR="${WORKING_DIR}/certs"
ADDONS_DIR="${WORKING_DIR}"
LOG_FILE="${WORKING_DIR}/main.log"

# SSL Certificate settings
SSL_COUNTRY="IR"
SSL_STATE="Tehran"
SSL_CITY="Tehran"
SSL_ORG="MatrixCA"
SSL_OU="IT"
SSL_CERT_DAYS=365
SSL_CA_DAYS=3650

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===========================================
# GLOBAL VARIABLES
# ===========================================

ROOT_CA_DETECTED=""
ROOT_CA_SOURCE_PATH=""
SERVER_NAME=""
ACTIVE_SERVER=""  # Currently selected server for addon installation

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
# SERVER CERTIFICATE HELPER FUNCTIONS
# ===========================================

get_server_cert_dir() {
    local server_name="$1"
    echo "${CERTS_DIR}/${server_name}"
}

server_has_certs() {
    local server_name="$1"
    local cert_dir
    cert_dir="$(get_server_cert_dir "$server_name")"

    [[ -f "${cert_dir}/server.key" ]] && \
    [[ -f "${cert_dir}/cert-full-chain.pem" ]] && \
    [[ -f "${cert_dir}/server.crt" ]]
}

list_servers_with_certs() {
    local servers=()

    # Check all subdirectories in certs/
    for dir in "${CERTS_DIR}"/*/; do
        if [[ -d "$dir" ]]; then
            local server_name
            server_name="$(basename "$dir")"

            # Skip if it's not a server cert dir (must have server.key)
            if [[ -f "${dir}/server.key" ]]; then
                servers+=("$server_name")
            fi
        fi
    done

    # Return list
    printf '%s\n' "${servers[@]}"
}

# ===========================================
# SSL MANAGER MODULE
# ===========================================

ssl_manager_init() {
    print_message "info" "Initializing SSL Manager..."

    # Create certs directory
    mkdir -p "$CERTS_DIR"

    # Detect Root CA next to main.sh
    detect_root_ca

    print_message "info" "SSL Manager initialized"
}

detect_root_ca() {
    ROOT_CA_DETECTED="false"
    ROOT_CA_SOURCE_PATH=""

    # Check for Root CA next to main.sh
    if [[ -f "${SCRIPT_DIR}/rootCA.key" ]] && [[ -f "${SCRIPT_DIR}/rootCA.crt" ]]; then
        ROOT_CA_DETECTED="true"
        ROOT_CA_SOURCE_PATH="$SCRIPT_DIR"
        print_message "info" "Root CA detected next to main.sh"
    fi

    # Also check in certs/ for existing Root CA
    if [[ -f "${CERTS_DIR}/rootCA.key" ]] && [[ -f "${CERTS_DIR}/rootCA.crt" ]]; then
        print_message "info" "Root CA already exists in certs/"
    fi
}

prompt_use_existing_root_ca() {
    if [[ "$ROOT_CA_DETECTED" != "true" ]]; then
        return 1
    fi

    echo ""
    print_message "info" "Root CA found at: ${ROOT_CA_SOURCE_PATH}"
    if [[ "$(prompt_yes_no "Use this Root CA for Matrix Plus?" "n")" == "yes" ]]; then
        # Copy to certs/
        cp "${ROOT_CA_SOURCE_PATH}/rootCA.key" "${CERTS_DIR}/rootCA.key"
        cp "${ROOT_CA_SOURCE_PATH}/rootCA.crt" "${CERTS_DIR}/rootCA.crt"

        # Copy .srl if exists
        if [[ -f "${ROOT_CA_SOURCE_PATH}/rootCA.srl" ]]; then
            cp "${ROOT_CA_SOURCE_PATH}/rootCA.srl" "${CERTS_DIR}/rootCA.srl"
        fi

        chmod 600 "${CERTS_DIR}/rootCA.key"
        chmod 644 "${CERTS_DIR}/rootCA.crt"

        print_message "success" "Root CA copied to certs/"
        return 0
    fi

    return 1
}

ssl_manager_create_root_ca() {
    print_message "info" "Creating new Root CA..."

    # Warn if overwriting
    if [[ -f "${CERTS_DIR}/rootCA.key" ]] || [[ -f "${CERTS_DIR}/rootCA.crt" ]]; then
        print_message "warning" "Existing Root CA found in certs/"
        if [[ "$(prompt_yes_no "Overwrite existing Root CA?" "n")" != "yes" ]]; then
            print_message "info" "Root CA creation cancelled"
            return 1
        fi
        rm -f "${CERTS_DIR}/rootCA.key" "${CERTS_DIR}/rootCA.crt" "${CERTS_DIR}/rootCA.srl"
    fi

    cd "$CERTS_DIR" || return 1

    # Generate Root CA private key
    print_message "info" "Generating Root CA private key..."
    openssl genrsa -out rootCA.key 4096 2>/dev/null
    chmod 600 rootCA.key

    # Generate Root CA certificate with v3_ca extensions
    print_message "info" "Generating Root CA certificate..."
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=Matrix Root CA" \
        -out rootCA.crt 2>/dev/null

    chmod 644 rootCA.crt

    print_message "success" "Root CA created"
    print_message "info" "  - Root CA key: ${CERTS_DIR}/rootCA.key"
    print_message "info" "  - Root CA cert: ${CERTS_DIR}/rootCA.crt"
    print_message "info" "  - Valid for: $SSL_CA_DAYS days"

    cd "$WORKING_DIR"
    return 0
}

ssl_manager_generate_server_cert() {
    local server_name="$1"

    print_message "info" "Generating server certificate for: $server_name"

    # Check Root CA exists
    if [[ ! -f "${CERTS_DIR}/rootCA.key" ]] || [[ ! -f "${CERTS_DIR}/rootCA.crt" ]]; then
        print_message "error" "Root CA not found. Please create Root CA first."
        return 1
    fi

    # Create server subdirectory
    local server_cert_dir
    server_cert_dir="$(get_server_cert_dir "$server_name")"
    mkdir -p "$server_cert_dir"

    # Check if certs already exist for this server
    if [[ -f "${server_cert_dir}/server.key" ]] || [[ -f "${server_cert_dir}/cert-full-chain.pem" ]]; then
        print_message "warning" "Certificates already exist for server: $server_name"
        if [[ "$(prompt_yes_no "Overwrite existing certificates?" "n")" != "yes" ]]; then
            print_message "info" "Certificate generation cancelled"
            return 1
        fi
        rm -f "${server_cert_dir}/server.key" "${server_cert_dir}/server.crt" "${server_cert_dir}/cert-full-chain.pem"
    fi

    cd "$server_cert_dir" || return 1

    # Determine domain and IP for SAN
    local cert_domain="$server_name"
    local cert_ip="$server_name"

    if is_ip_address "$server_name"; then
        cert_domain="matrix.local"
        cert_ip="$server_name"
    else
        cert_domain="$server_name"
        cert_ip=""
    fi

    # Create OpenSSL config with SAN
    cat > openssl.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = ${SSL_COUNTRY}
ST = ${SSL_STATE}
L = ${SSL_CITY}
O = Matrix
OU = Server
CN = ${server_name}

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${cert_domain}
DNS.2 = matrix.local
DNS.3 = localhost
EOF

    # Add IP to SAN if it's an IP address
    if [[ -n "$cert_ip" ]]; then
        echo "IP.1 = ${cert_ip}" >> openssl.cnf
        echo "IP.2 = 127.0.0.1" >> openssl.cnf
    fi

    # Generate server private key
    openssl genrsa -out server.key 4096 2>/dev/null
    chmod 600 server.key

    # Generate CSR
    openssl req -new -key server.key -out server.csr -config openssl.cnf 2>/dev/null

    # Sign with Root CA
    openssl x509 -req -in server.csr \
        -CA "${CERTS_DIR}/rootCA.crt" -CAkey "${CERTS_DIR}/rootCA.key" \
        -CAcreateserial -out server.crt \
        -days "$SSL_CERT_DAYS" -sha256 \
        -extensions v3_req -extfile openssl.cnf 2>/dev/null

    # Create full chain
    cat server.crt "${CERTS_DIR}/rootCA.crt" > cert-full-chain.pem
    chmod 644 server.crt cert-full-chain.pem

    # Cleanup
    rm -f server.csr openssl.cnf

    # Set as active server
    ACTIVE_SERVER="$server_name"

    print_message "success" "Server certificate created"
    print_message "info" "  - Server: $server_name"
    print_message "info" "  - Private key: ${server_cert_dir}/server.key"
    print_message "info" "  - Certificate: ${server_cert_dir}/server.crt"
    print_message "info" "  - Full chain: ${server_cert_dir}/cert-full-chain.pem"
    print_message "info" "  - SAN includes: ${cert_domain}, matrix.local, localhost${cert_ip:+, ${cert_ip}, 127.0.0.1}"

    cd "$WORKING_DIR"
    return 0
}

# ===========================================
# ENVIRONMENT PROVIDER MODULE
# ===========================================

env_provider_export_for_addon() {
    local server_name="$1"

    # Get server certificate directory
    local server_cert_dir
    server_cert_dir="$(get_server_cert_dir "$server_name")"

    # Check certificates exist
    if [[ ! -f "${server_cert_dir}/server.key" ]] || [[ ! -f "${server_cert_dir}/cert-full-chain.pem" ]] || [[ ! -f "${CERTS_DIR}/rootCA.crt" ]]; then
        print_message "error" "SSL certificates not found for server: $server_name"
        return 1
    fi

    # Export environment variables for addon
    export SERVER_NAME="$server_name"
    export SSL_CERT="${server_cert_dir}/cert-full-chain.pem"
    export SSL_KEY="${server_cert_dir}/server.key"
    export ROOT_CA="${CERTS_DIR}/rootCA.crt"
    export CERTS_DIR="$CERTS_DIR"
    export WORKING_DIR="$WORKING_DIR"

    print_message "info" "Environment variables set for addon"
    print_message "info" "  - SERVER_NAME: $SERVER_NAME"
    print_message "info" "  - SSL_CERT: $SSL_CERT"
    print_message "info" "  - SSL_KEY: $SSL_KEY"
    print_message "info" "  - ROOT_CA: $ROOT_CA"

    return 0
}

# ===========================================
# ADDON LOADER MODULE
# ===========================================

addon_loader_get_list() {
    local found_addons=()

    # Find all directories containing install.sh
    for dir in */; do
        if [[ -f "${dir}install.sh" ]] && [[ -f "${dir}addon.manifest" ]]; then
            found_addons+=("${dir%/}")
        fi
    done

    # Return list
    printf '%s\n' "${found_addons[@]}"
    return 0
}

addon_loader_get_name() {
    local addon_dir="$1"

    if [[ -f "${addon_dir}/addon.manifest" ]]; then
        local name
        name=$(grep "^NAME=" "${addon_dir}/addon.manifest" | cut -d'=' -f2)
        # Remove quotes if present
        name="${name%\"}"
        name="${name#\"}"
        echo "$name"
    else
        echo "$addon_dir"
    fi
}

addon_loader_run() {
    local addon_dir="$1"
    local addon_install="${addon_dir}/install.sh"

    if [[ ! -f "$addon_install" ]]; then
        print_message "error" "Addon install script not found: $addon_install"
        return 1
    fi

    print_message "info" "Running addon: $addon_dir"

    # Make executable
    chmod +x "$addon_install"

    # Run with environment variables
    if bash "$addon_install"; then
        print_message "success" "Addon completed: $addon_dir"
        return 0
    else
        print_message "error" "Addon failed: $addon_dir"
        return 1
    fi
}

addon_loader_validate() {
    local addon_dir="$1"

    # Check for install.sh
    if [[ ! -f "${addon_dir}/install.sh" ]]; then
        print_message "error" "Missing install.sh in addon: $addon_dir"
        return 1
    fi

    # Check for manifest (optional but recommended)
    if [[ -f "${addon_dir}/addon.manifest" ]]; then
        print_message "info" "Addon manifest found"
    fi

    return 0
}

# ===========================================
# MENU SYSTEM
# ===========================================

menu_with_root_ca() {
    # Get addons list
    local addons
    mapfile -t addons < <(addon_loader_get_list)

    while true; do
        # Build menu dynamically with addons
        local addon_index_start=3
        local last_addon_index=$((addon_index_start + ${#addons[@]} - 1))
        local exit_option=$((last_addon_index + 1))

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                  Matrix Plus - Main Menu                ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Root CA: Available"
        echo ""
        echo "  1) Generate server certificate for Synapse"
        echo "  2) Generate new Root CA (overwrite existing)"

        # Add addon options to menu
        if [[ ${#addons[@]} -gt 0 ]]; then
            for i in "${!addons[@]}"; do
                local addon_num=$((i + addon_index_start))
                local addon_name
                addon_name="$(addon_loader_get_name "${addons[$i]}")"
                echo "  $addon_num) $addon_name"
            done
        fi

        echo "  $exit_option) Exit"
        echo ""

        read -rp "Enter your choice (1-$exit_option): " choice

        case "$choice" in
            1)
                # Generate server certificate
                echo ""
                SERVER_NAME="$(prompt_user "Enter server IP address or domain")"
                ssl_manager_generate_server_cert "$SERVER_NAME"
                ;;
            2)
                # Generate new Root CA
                echo ""
                if [[ "$(prompt_yes_no "This will overwrite the existing Root CA. Continue?" "n")" == "yes" ]]; then
                    ssl_manager_create_root_ca
                fi
                ;;
            $exit_option)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                # Check if it's an addon choice
                if [[ "$choice" -ge $addon_index_start ]] && [[ "$choice" -le $last_addon_index ]]; then
                    local selected_addon="${addons[$((choice - addon_index_start))]}"
                    menu_run_addon "$selected_addon"
                else
                    print_message "error" "Invalid choice"
                fi
                ;;
        esac
    done
}

menu_without_root_ca() {
    while true; do
        cat <<'EOF'

╔══════════════════════════════════════════════════════════╗
║                  Matrix Plus - Main Menu                ║
╚══════════════════════════════════════════════════════════╝

Root CA: Not Available

  1) Generate new Root CA
  2) Exit

EOF

        read -rp "Enter your choice (1-2): " choice

        case "$choice" in
            1)
                if ssl_manager_create_root_ca; then
                    # Root CA created successfully, switch to main menu
                    print_message "success" "Root CA created. Switching to main menu..."
                    echo ""
                    menu_with_root_ca
                    return
                fi
                ;;
            2)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                print_message "error" "Invalid choice"
                ;;
        esac
    done
}

menu_run_addon() {
    local selected_addon="$1"

    # Validate addon
    if ! addon_loader_validate "$selected_addon"; then
        return 1
    fi

    # Get list of servers with certificates
    local servers
    mapfile -t servers < <(list_servers_with_certs)

    local selected_server=""

    if [[ ${#servers[@]} -eq 0 ]]; then
        # No servers with certificates
        print_message "warning" "No server certificates found!"
        echo ""
        echo "You need to generate a server certificate before installing an addon."
        echo ""

        local new_server
        new_server="$(prompt_user "Enter server IP address or domain")"

        if [[ "$(prompt_yes_no "Generate server certificate for $new_server now?" "y")" == "yes" ]]; then
            if ! ssl_manager_generate_server_cert "$new_server"; then
                print_message "error" "Failed to generate server certificate"
                return 1
            fi
            selected_server="$new_server"
        else
            print_message "info" "Addon installation cancelled"
            return 0
        fi
    elif [[ ${#servers[@]} -eq 1 ]]; then
        # Only one server, use it
        selected_server="${servers[0]}"
        print_message "info" "Using existing certificate for: $selected_server"
    else
        # Multiple servers, let user choose
        echo ""
        print_message "info" "Servers with available certificates:"
        local index=1
        for server in "${servers[@]}"; do
            echo "  $index) $server"
            ((index++))
        done
        echo "  $index) Create new server certificate"
        echo ""

        read -rp "Select server (1-$index): " choice

        if [[ "$choice" -ge 1 ]] && [[ "$choice" -lt $index ]]; then
            selected_server="${servers[$((choice-1))]}"
        elif [[ "$choice" -eq $index ]]; then
            # Create new certificate
            local new_server
            new_server="$(prompt_user "Enter server IP address or domain")"

            if ! ssl_manager_generate_server_cert "$new_server"; then
                print_message "error" "Failed to generate server certificate"
                return 1
            fi
            selected_server="$new_server"
        else
            print_message "error" "Invalid choice"
            return 1
        fi
    fi

    # Set active server
    SERVER_NAME="$selected_server"
    ACTIVE_SERVER="$selected_server"

    # Export environment for addon
    if ! env_provider_export_for_addon "$SERVER_NAME"; then
        return 1
    fi

    # Run addon
    addon_loader_run "$selected_addon"
}

# ===========================================
# MAIN FUNCTION
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Matrix Plus Log - $(date)" > "$LOG_FILE"

    # Print banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║              Matrix Plus - Modular Installer            ║
║                      Version 1.0.0                       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # Initialize SSL Manager
    ssl_manager_init

    # Check for Root CA next to main.sh and prompt user
    if [[ "$ROOT_CA_DETECTED" == "true" ]]; then
        if prompt_use_existing_root_ca; then
            # Root CA copied successfully
            :
        fi
    fi

    # Show appropriate menu based on Root CA availability
    if [[ -f "${CERTS_DIR}/rootCA.crt" ]]; then
        menu_with_root_ca
    else
        menu_without_root_ca
    fi
}

# ===========================================
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
