#!/bin/bash

# ===========================================
# Matrix Plus - Private Key Matrix Installation System
# Version: 0.1.0
# Description:Matrix homeserver installation
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

    # Return list (only if we have servers)
    if [[ ${#servers[@]} -gt 0 ]]; then
        printf '%s\n' "${servers[@]}"
    fi
}

# ===========================================
# Root CA Information Functions
# ===========================================

get_root_ca_info() {
    local root_ca_cert="${CERTS_DIR}/rootCA.crt"

    if [[ ! -f "$root_ca_cert" ]]; then
        return 1
    fi

    # Get Subject (CN)
    local subject
    subject=$(openssl x509 -in "$root_ca_cert" -noout -subject 2>/dev/null | grep -o 'CN=[^,]*' | cut -d'=' -f2)

    # Default subject if not found
    if [[ -z "$subject" ]]; then
        subject="Matrix Root CA"
    fi

    # Get Country (C)
    local country
    country=$(openssl x509 -in "$root_ca_cert" -noout -subject 2>/dev/null | grep -o 'C=[^,]*' | cut -d'=' -f2)

    # Default country if not found
    if [[ -z "$country" ]]; then
        country="IR"
    fi

    # Get expiration date and calculate days remaining
    local expiry_date
    local expiry_epoch
    local days_remaining="unknown"
    local display_date

    expiry_date=$(openssl x509 -in "$root_ca_cert" -noout -enddate 2>/dev/null | cut -d'=' -f2)

    if command -v date &> /dev/null && [[ -n "$expiry_date" ]]; then
        # Try GNU date format
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        # If that fails, try BSD date
        if [[ -z "$expiry_epoch" ]]; then
            expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
        fi

        if [[ -n "$expiry_epoch" ]]; then
            local current_epoch
            current_epoch=$(date +%s)
            local seconds_diff=$((expiry_epoch - current_epoch))
            if [[ $seconds_diff -gt 0 ]]; then
                days_remaining=$((seconds_diff / 86400))
            else
                days_remaining="expired"
            fi
        fi

        display_date=$(date -d "$expiry_date" "+%Y-%m-%d" 2>/dev/null || echo "$expiry_date")
    fi

    # Output as formatted lines
    echo "SUBJECT=$subject"
    echo "COUNTRY=$country"
    echo "EXPIRY_DATE=$display_date"
    echo "DAYS_REMAINING=$days_remaining"

    return 0
}

# ===========================================
# SSL MANAGER MODULE
# ===========================================

ssl_manager_init() {
    # Create certs directory
    mkdir -p "$CERTS_DIR"

    # Detect Root CA next to main.sh
    detect_root_ca
}

detect_root_ca() {
    ROOT_CA_DETECTED="false"
    ROOT_CA_SOURCE_PATH=""

    # Check for Root CA next to main.sh
    if [[ -f "${SCRIPT_DIR}/rootCA.key" ]] && [[ -f "${SCRIPT_DIR}/rootCA.crt" ]]; then
        ROOT_CA_DETECTED="true"
        ROOT_CA_SOURCE_PATH="$SCRIPT_DIR"
    fi
}

prompt_use_existing_root_ca() {
    if [[ "$ROOT_CA_DETECTED" != "true" ]]; then
        return 1
    fi

    echo ""
    print_message "info" "Root CA found at: ${ROOT_CA_SOURCE_PATH}"
    if [[ "$(prompt_yes_no "Use this Root CA for Matrix Plus?" "n")" == "yes" ]]; then
        # Check if files already exist in certs/ and warn user
        if [[ -f "${CERTS_DIR}/rootCA.key" ]] || [[ -f "${CERTS_DIR}/rootCA.crt" ]]; then
            echo ""
            print_message "warning" "Root CA files already exist in certs/ directory!"
            print_message "warning" "They will be overwritten with files from: ${ROOT_CA_SOURCE_PATH}"
            echo ""
            if [[ "$(prompt_yes_no "Continue with overwrite?" "y")" != "yes" ]]; then
                print_message "info" "Skipped copying Root CA"
                return 1
            fi
        fi

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
        if [[ "$(prompt_yes_no "Overwrite existing Root CA?" "y")" != "yes" ]]; then
            return 1
        fi
        rm -f "${CERTS_DIR}/rootCA.key" "${CERTS_DIR}/rootCA.crt" "${CERTS_DIR}/rootCA.srl"
    fi

    cd "$CERTS_DIR" || return 1

    # Generate Root CA private key
    openssl genrsa -out rootCA.key 4096 2>/dev/null
    chmod 600 rootCA.key

    # Generate Root CA certificate with v3_ca extensions
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=${SSL_ORG}" \
        -out rootCA.crt 2>/dev/null

    chmod 644 rootCA.crt

    print_message "success" "Root CA created (valid for $SSL_CA_DAYS days)"

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
        if [[ "$(prompt_yes_no "Overwrite existing certificates?" "y")" != "yes" ]]; then
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

    print_message "success" "Server certificate created for: $server_name"

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

    return 0
}

# ===========================================
# ADDON LOADER MODULE
# ===========================================

addon_loader_get_list() {
    local found_addons=()

    # Find all directories containing install.sh
    for dir in */; do
        if [[ -f "${dir}install.sh" ]]; then
            found_addons+=("${dir%/}")
        fi
    done

    # Return list
    printf '%s\n' "${found_addons[@]}"
    return 0
}

addon_loader_get_name() {
    local addon_dir="$1"
    local addon_install="${addon_dir}/install.sh"

    if [[ -f "$addon_install" ]]; then
        local name
        name=$(grep "^ADDON_NAME=" "$addon_install" | cut -d'=' -f2)
        # Remove quotes if present
        name="${name%\"}"
        name="${name#\"}"
        echo "${name:-$addon_dir}"
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
    local addon_install="${addon_dir}/install.sh"

    # Check for install.sh
    if [[ ! -f "$addon_install" ]]; then
        return 1
    fi

    # Check for ADDON_NAME in first 15 lines (valid addon marker)
    if ! head -n 15 "$addon_install" | grep -q "^ADDON_NAME="; then
        return 1
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
        local addon_index_start=2
        local last_addon_index=$((addon_index_start + ${#addons[@]} - 1))
        local root_ca_option=8
        local exit_option=0

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                  Matrix Plus - Main Menu                 ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Root CA: Available"

        # Get and display Root CA info
        local ca_info
        ca_info=$(get_root_ca_info 2>/dev/null)

        if [[ -n "$ca_info" ]]; then
            # Parse the info line by line
            local ca_subject="Matrix Root CA"
            local ca_country="IR"
            local ca_expiry="unknown"
            local ca_days="unknown"

            while IFS= read -r line; do
                local key="${line%%=*}"
                local value="${line#*=}"
                case "$key" in
                    SUBJECT) ca_subject="$value" ;;
                    COUNTRY) ca_country="$value" ;;
                    EXPIRY_DATE) ca_expiry="$value" ;;
                    DAYS_REMAINING) ca_days="$value" ;;
                esac
            done <<< "$ca_info"

            echo "  | Subject: $ca_subject"
            echo "  | Expires: $ca_expiry (in $ca_days days)"
            echo "  | Country: $ca_country"
        fi

        echo ""
        echo "  1) Generate server certificate"
        echo ""

        # Add addon options to menu
        if [[ ${#addons[@]} -gt 0 ]]; then
            for i in "${!addons[@]}"; do
                local addon_num=$((i + addon_index_start))
                local addon_name
                addon_name="$(addon_loader_get_name "${addons[$i]}")"
                echo "  $addon_num) Install $addon_name"
            done
        fi

        echo ""
        echo "  ---------------------------"
        echo "  $root_ca_option) Generate new Root CA (overwrite existing)"
        echo "  $exit_option) Exit"
        echo ""

        read -rp "Enter your choice (0-8): " choice

        case "$choice" in
            1)
                # Generate server certificate
                echo ""
                local server_input
                # Loop until user enters a valid server name
                while true; do
                    server_input="$(prompt_user "Enter server IP address or domain")"
                    if [[ -n "$server_input" ]]; then
                        break
                    fi
                    echo "Server name cannot be empty. Please try again."
                done

                # Show summary and confirm
                echo ""
                echo "=== Certificate Summary ==="
                echo "  Server: $server_input"
                local server_type="Domain"
                if is_ip_address "$server_input"; then
                    server_type="IP Address"
                fi
                echo "  Type: $server_type"
                echo "  Certificate directory: certs/$server_input/"
                echo "  Validity: $SSL_CERT_DAYS days"
                echo ""

                if [[ "$(prompt_yes_no "Generate certificate now?" "y")" == "yes" ]]; then
                    SERVER_NAME="$server_input"
                    ssl_manager_generate_server_cert "$SERVER_NAME"
                else
                    print_message "info" "Certificate generation cancelled"
                fi
                ;;
            8)
                # Generate new Root CA
                echo ""
                if [[ "$(prompt_yes_no "This will overwrite the existing Root CA. Continue?" "y")" == "yes" ]]; then
                    echo ""
                    echo "=== Root CA Configuration ==="
                    echo "Press Enter for default values"

                    local org_input
                    local country_input
                    local state_input
                    local city_input
                    local days_input

                    org_input="$(prompt_user "Organization" "$SSL_ORG")"
                    # Validate country code (2 characters)
                    while true; do
                        country_input="$(prompt_user "Country Code (2 letters)" "$SSL_COUNTRY")"
                        if [[ ${#country_input} -eq 2 ]]; then
                            break
                        fi
                        echo "Country code must be exactly 2 letters (e.g., IR, US, DE)"
                    done
                    state_input="$(prompt_user "State/Province" "$SSL_STATE")"
                    city_input="$(prompt_user "City" "$SSL_CITY")"
                    days_input="$(prompt_user "Validity in days" "$SSL_CA_DAYS")"

                    # Validate days is a number
                    if [[ ! "$days_input" =~ ^[0-9]+$ ]]; then
                        echo "Invalid days value, using default: $SSL_CA_DAYS"
                        days_input="$SSL_CA_DAYS"
                    fi

                    # Update globals for this creation
                    local old_org="$SSL_ORG"
                    local old_country="$SSL_COUNTRY"
                    local old_state="$SSL_STATE"
                    local old_city="$SSL_CITY"
                    local old_days="$SSL_CA_DAYS"

                    SSL_ORG="$org_input"
                    SSL_COUNTRY="$country_input"
                    SSL_STATE="$state_input"
                    SSL_CITY="$city_input"
                    SSL_CA_DAYS="$days_input"

                    echo ""
                    echo "  Organization: $SSL_ORG"
                    echo "  Country: $SSL_COUNTRY"
                    echo "  State: $SSL_STATE"
                    echo "  City: $SSL_CITY"
                    echo "  Validity: $SSL_CA_DAYS days"
                    echo ""

                    if [[ "$(prompt_yes_no "Create Root CA with these settings?" "y")" == "yes" ]]; then
                        ssl_manager_create_root_ca
                    fi

                    # Restore defaults
                    SSL_ORG="$old_org"
                    SSL_COUNTRY="$old_country"
                    SSL_STATE="$old_state"
                    SSL_CITY="$old_city"
                    SSL_CA_DAYS="$old_days"
                fi
                ;;
            0)
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
║                  Matrix Plus - Main Menu                 ║
╚══════════════════════════════════════════════════════════╝

Root CA: Not Available

  1) Generate new Root CA
  2) Exit

EOF

        read -rp "Enter your choice (1-2): " choice

        case "$choice" in
            1)
                echo ""
                echo "=== Root CA Configuration ==="
                echo "Press Enter for default values"

                local org_input
                local country_input
                local state_input
                local city_input
                local days_input

                org_input="$(prompt_user "Organization" "$SSL_ORG")"
                # Validate country code (2 characters)
                while true; do
                    country_input="$(prompt_user "Country Code (2 letters)" "$SSL_COUNTRY")"
                    if [[ ${#country_input} -eq 2 ]]; then
                        break
                    fi
                    echo "Country code must be exactly 2 letters (e.g., IR, US, DE)"
                done
                state_input="$(prompt_user "State/Province" "$SSL_STATE")"
                city_input="$(prompt_user "City" "$SSL_CITY")"
                days_input="$(prompt_user "Validity in days" "$SSL_CA_DAYS")"

                # Validate days is a number
                if [[ ! "$days_input" =~ ^[0-9]+$ ]]; then
                    echo "Invalid days value, using default: $SSL_CA_DAYS"
                    days_input="$SSL_CA_DAYS"
                fi

                # Update globals for this creation
                local old_org="$SSL_ORG"
                local old_country="$SSL_COUNTRY"
                local old_state="$SSL_STATE"
                local old_city="$SSL_CITY"
                local old_days="$SSL_CA_DAYS"

                SSL_ORG="$org_input"
                SSL_COUNTRY="$country_input"
                SSL_STATE="$state_input"
                SSL_CITY="$city_input"
                SSL_CA_DAYS="$days_input"

                echo ""
                echo "  Organization: $SSL_ORG"
                echo "  Country: $SSL_COUNTRY"
                echo "  State: $SSL_STATE"
                echo "  City: $SSL_CITY"
                echo "  Validity: $SSL_CA_DAYS days"
                echo ""

                if [[ "$(prompt_yes_no "Create Root CA with these settings?" "y")" == "yes" ]]; then
                    if ssl_manager_create_root_ca; then
                        # Root CA created successfully, switch to main menu
                        print_message "success" "Root CA created. Switching to main menu..."
                        echo ""

                        # Restore defaults
                        SSL_ORG="$old_org"
                        SSL_COUNTRY="$old_country"
                        SSL_STATE="$old_state"
                        SSL_CITY="$old_city"
                        SSL_CA_DAYS="$old_days"

                        menu_with_root_ca
                        return
                    fi
                fi

                # Restore defaults on cancel
                SSL_ORG="$old_org"
                SSL_COUNTRY="$old_country"
                SSL_STATE="$old_state"
                SSL_CITY="$old_city"
                SSL_CA_DAYS="$old_days"
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

        # Detect local IP
        local detected_ip
        detected_ip="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
        if [[ -z "$detected_ip" ]]; then
            detected_ip="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)"
        fi

        local new_server
        if [[ -n "$detected_ip" ]]; then
            # Custom prompt: Enter/y = use detected IP, anything else = custom IP
            read -rp "Use [$detected_ip] for server certificate? [Y/n]: " server_choice
            if [[ -z "$server_choice" ]] || [[ "$server_choice" =~ ^[Yy] ]]; then
                new_server="$detected_ip"
            else
                new_server="$server_choice"
                # If user typed "n", prompt for IP
                if [[ "$new_server" =~ ^[Nn]$ ]]; then
                    while true; do
                        new_server="$(prompt_user "Enter server IP address or domain")"
                        if [[ -n "$new_server" ]]; then
                            break
                        fi
                        echo "Server name cannot be empty. Please try again."
                    done
                fi
            fi
        else
            # Loop until user enters a valid server name
            while true; do
                new_server="$(prompt_user "Enter server IP address or domain")"
                if [[ -n "$new_server" ]]; then
                    break
                fi
                echo "Server name cannot be empty. Please try again."
            done
        fi

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
            # Loop until user enters a valid server name
            while true; do
                new_server="$(prompt_user "Enter server IP address or domain")"
                if [[ -n "$new_server" ]]; then
                    break
                fi
                echo "Server name cannot be empty. Please try again."
            done

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
║              Matrix Plus - Private Key Installer         ║
║                      Version 0.1.0                       ║
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
