#!/bin/bash

# ===========================================
# Matrix Installer - Private Key Matrix Installation System
# ===========================================

# Application Metadata
MATRIX_PLUS_NAME="Matrix Installer"
MATRIX_PLUS_VERSION="0.1.0"
MATRIX_PLUS_DESCRIPTION="Federation Key Manager"
MATRIX_PLUS_BUILD_DATE="$(date +%Y-%m-%d)"

set -e
set -u
set -o pipefail

# ===========================================
# CONFIGURATION
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
WORKING_DIR="$(pwd)"
CERTS_DIR="${WORKING_DIR}/certs"
ADDONS_DIR="${WORKING_DIR}/addons"
LOG_FILE="${WORKING_DIR}/matrix-installer.log"

# SSL Certificate settings
SSL_COUNTRY="IR"
SSL_STATE="Tehran"
SSL_CITY="Tehran"
SSL_ORG="MatrixIR"
SSL_OU="IT"
SSL_CERT_DAYS=365
SSL_CA_DAYS=3650

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Menu separator (U+2500 BOX DRAWINGS LIGHT HORIZONTAL) - aligned with header box width (54)
MENU_SEPARATOR="──────────────────────────────────────────────────────────"

# ===========================================
# GLOBAL VARIABLES
# ===========================================

ROOT_CA_DETECTED=""
ROOT_CA_SOURCE_PATH=""
SERVER_NAME=""
ACTIVE_SERVER=""  # Currently selected server for addon installation
ACTIVE_ROOT_CA_DIR=""  # Currently active Root CA directory
SELECTED_ROOT_CA_BASE=""  # Selected Root CA base name from files next to script

# Menu choice constants (for user input handling)
MENU_CHOICE_BACK="0"
MENU_CHOICE_NEW="N"

# Menu return codes
MENU_RETURN_SUCCESS=0
MENU_RETURN_NEW=1
MENU_RETURN_BACK=3

# ===========================================
# HELPER FUNCTIONS
# ===========================================

# Check if menu choice is special (back, new, etc.)
# Returns: 0=back, 1=new, 2=numeric
check_menu_choice_type() {
    local choice="$1"

    # Empty input = Back
    if [[ -z "$choice" ]]; then
        return 0
    fi

    # Back option
    if [[ "$choice" == "$MENU_CHOICE_BACK" ]]; then
        return 0
    fi

    # New option (case-insensitive)
    if [[ "$choice" == "$MENU_CHOICE_NEW" ]] || [[ "$choice" == "${MENU_CHOICE_NEW,,}" ]]; then
        return 1
    fi

    # Check if numeric
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        return 2
    fi

    # Invalid
    return 255
}

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

    read -rp "$prompt: " input || true

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

        read -rp "$prompt [$default_display]: " answer || true

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

# Get detected local IP address
get_detected_ip() {
    local ip=""
    ip="$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
    if [[ -z "$ip" ]]; then
        ip="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)"
    fi
    echo "$ip"
}

# Print styled menu header
print_menu_header() {
    local title="$1"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"

    local box_width=58
    local title_padding=$(( (box_width - ${#title}) / 2 ))
    printf "║%*s%s%*s║\n" $title_padding "" "$title" $((box_width - title_padding - ${#title})) ""

    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
}

# Prompt for Root Key configuration (returns: org|country|state|city|days)
prompt_root_ca_config() {
    local org_input
    local country_input
    local state_input
    local city_input
    local days_input

    echo "" >&2
    echo "=== Root Key Configuration ===" >&2
    echo "Press Enter for default values" >&2

    org_input="$(prompt_user "Organization" "$SSL_ORG")"

    # Validate country code (2 characters)
    while true; do
        country_input="$(prompt_user "Country Code (2 letters)" "$SSL_COUNTRY")"
        if [[ ${#country_input} -eq 2 ]]; then
            break
        fi
        echo "Country code must be exactly 2 letters (e.g., IR, US, DE)" >&2
    done

    state_input="$(prompt_user "State/Province" "$SSL_STATE")"
    city_input="$(prompt_user "City" "$SSL_CITY")"
    days_input="$(prompt_user "Validity in days" "$SSL_CA_DAYS")"

    # Validate days is a number
    if [[ ! "$days_input" =~ ^[0-9]+$ ]]; then
        echo "Invalid days value, using default: $SSL_CA_DAYS" >&2
        days_input="$SSL_CA_DAYS"
    fi

    # Display summary
    echo "" >&2
    echo "  Organization:  $org_input" >&2
    echo "  Country:       $country_input" >&2
    echo "  State:         $state_input" >&2
    echo "  City:          $city_input" >&2
    echo "  Validity:      $days_input days" >&2
    echo "" >&2

    # Output as pipe-delimited for parsing (to stdout only)
    echo "${org_input}|${country_input}|${state_input}|${city_input}|${days_input}"
}

# Create Root Key from menu (handles config prompt and creation)
create_root_ca_from_menu() {
    echo ""
    if [[ "$(prompt_yes_no "This will create a new Root Key directory. Continue?" "y")" != "yes" ]]; then
        return 0
    fi

    # Get configuration
    local config
    config="$(prompt_root_ca_config)" || true

    # Parse config safely
    local org_input country_input state_input city_input days_input
    org_input="$(echo "$config" | cut -d'|' -f1)"
    country_input="$(echo "$config" | cut -d'|' -f2)"
    state_input="$(echo "$config" | cut -d'|' -f3)"
    city_input="$(echo "$config" | cut -d'|' -f4)"
    days_input="$(echo "$config" | cut -d'|' -f5)"

    # Save and restore globals
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

    if [[ "$(prompt_yes_no "Create Root Key with these settings?" "y")" == "yes" ]]; then
        ssl_manager_create_root_ca "$org_input"
    fi

    # Restore defaults
    SSL_ORG="$old_org"
    SSL_COUNTRY="$old_country"
    SSL_STATE="$old_state"
    SSL_CITY="$old_city"
    SSL_CA_DAYS="$old_days"
}

# ===========================================
# ROOT KEY HELPER FUNCTIONS
# ===========================================

get_active_root_ca_dir() {
    echo "$ACTIVE_ROOT_CA_DIR"
}

set_active_root_ca() {
    local root_ca_dir="$1"
    ACTIVE_ROOT_CA_DIR="$root_ca_dir"
}

list_root_cas() {
    local root_cas=()

    # Check all subdirectories in certs/
    for dir in "${CERTS_DIR}"/*/; do
        if [[ -d "$dir" ]]; then
            local root_ca_name
            root_ca_name="$(basename "$dir")"

            # Skip if not a Root CA directory (must have rootCA.key)
            if [[ -f "${dir}/rootCA.key" ]] && [[ -f "${dir}/rootCA.crt" ]]; then
                root_cas+=("$root_ca_name")
            fi
        fi
    done

    # Return list (only if we have Root CAs)
    if [[ ${#root_cas[@]} -gt 0 ]]; then
        printf '%s\n' "${root_cas[@]}"
    fi
}

detect_root_ca_files_next_to_script() {
    local found_pairs=()

    # Find all .key/.crt pairs in SCRIPT_DIR
    for key_file in "${SCRIPT_DIR}"/*.key; do
        if [[ -f "$key_file" ]]; then
            local base_name
            base_name="$(basename "$key_file" .key)"
            local cert_file="${SCRIPT_DIR}/${base_name}.crt"

            # Check if matching .crt exists
            if [[ -f "$cert_file" ]]; then
                found_pairs+=("$base_name")
            fi
        fi
    done

    # Return list
    if [[ ${#found_pairs[@]} -gt 0 ]]; then
        printf '%s\n' "${found_pairs[@]}"
    fi
}

# ===========================================
# SERVER CERTIFICATE HELPER FUNCTIONS
# ===========================================

get_server_cert_dir() {
    local server_name="$1"
    local root_ca_dir="${2:-${ACTIVE_ROOT_CA_DIR}}"

    if [[ -z "$root_ca_dir" ]]; then
        echo "${CERTS_DIR}/${server_name}"
        return
    fi

    echo "${root_ca_dir}/servers/${server_name}"
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
    local root_ca_dir="${1:-${ACTIVE_ROOT_CA_DIR}}"

    if [[ -z "$root_ca_dir" ]] || [[ ! -d "$root_ca_dir/servers" ]]; then
        return
    fi

    # Check all subdirectories in active Root CA's servers/ directory
    for dir in "${root_ca_dir}/servers"/*/; do
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
    local root_ca_dir="${1:-${ACTIVE_ROOT_CA_DIR}}"
    local root_ca_cert="${root_ca_dir}/rootCA.crt"

    if [[ ! -f "$root_ca_cert" ]]; then
        return 1
    fi

    # Get Subject (CN)
    local subject
    subject=$(openssl x509 -in "$root_ca_cert" -noout -subject 2>/dev/null | grep -o 'CN=[^,]*' | cut -d'=' -f2)

    # Default subject if not found
    if [[ -z "$subject" ]]; then
        subject="Matrix Root Key"
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

    # Detect Root CA files next to ${SCRIPT_NAME}
    detect_root_ca_files
}

detect_root_ca_files() {
    ROOT_CA_DETECTED="false"
    ROOT_CA_SOURCE_PATH=""
    ROOT_CA_FILES=()  # Array to store found Root CA file names

    # Find all .key/.crt pairs next to ${SCRIPT_NAME}
    mapfile -t ROOT_CA_FILES < <(detect_root_ca_files_next_to_script)

    if [[ ${#ROOT_CA_FILES[@]} -gt 0 ]]; then
        ROOT_CA_DETECTED="true"
        ROOT_CA_SOURCE_PATH="$SCRIPT_DIR"
    fi
}

prompt_select_root_ca_from_files() {
    local found_files=("$@")

    if [[ ${#found_files[@]} -eq 0 ]]; then
        return 1
    fi

    echo ""
    print_message "info" "Multiple Root Key files found next to script:"
    echo ""

    # Display each Root Key file
    local index=1
    for base_name in "${found_files[@]}"; do
        echo "  $index) ${base_name}.key"
        ((index++))
    done

    echo "  $MENU_SEPARATOR"
    echo "  $index) Skip and use Root Keys from certs/"
    echo "  0) Back to previous menu"
    echo ""

    while true; do
        read -rp "Select which Root Key to use (0-$index): " choice || true

        # Handle empty input (Enter) as Skip
        if [[ -z "$choice" ]]; then
            SELECTED_ROOT_CA_BASE=""
            return 1  # Skip
        fi

        # Check choice type
        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back
                return $MENU_RETURN_BACK
                ;;
            1)  # New - not applicable here
                print_message "error" "Invalid choice"
                ;;
            2)  # Numeric - validate range
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -lt $index ]]; then
                    SELECTED_ROOT_CA_BASE="${found_files[$((choice-1))]}"
                    return 0
                elif [[ "$choice" -eq $index ]]; then
                    SELECTED_ROOT_CA_BASE=""
                    return 1  # Skip
                fi
                ;;
        esac

        # Invalid choice
        print_message "error" "Invalid choice"
    done
}

prompt_use_existing_root_ca() {
    if [[ "$ROOT_CA_DETECTED" != "true" ]]; then
        return 1
    fi

    local selected_base=""

    # If multiple Root CA files found, prompt for selection
    if [[ ${#ROOT_CA_FILES[@]} -gt 1 ]]; then
        local select_result
        prompt_select_root_ca_from_files "${ROOT_CA_FILES[@]}" || select_result=$?
        select_result="${select_result:-0}"
        selected_base="$SELECTED_ROOT_CA_BASE"
        if [[ $select_result -eq 3 ]]; then
            # Back to previous menu - skip and show certs menu
            print_message "info" "Skipping Root Key files next to script"
            return 1
        fi
        if [[ -z "$selected_base" ]]; then
            print_message "info" "Skipping Root Key files next to script"
            return 1
        fi
    elif [[ ${#ROOT_CA_FILES[@]} -eq 1 ]]; then
        selected_base="${ROOT_CA_FILES[0]}"
        echo ""
        print_message "info" "Root Key found at: ${ROOT_CA_SOURCE_PATH}/${selected_base}.{key,crt}"
        if [[ "$(prompt_yes_no "Use this Root Key for ${MATRIX_PLUS_NAME}?" "n")" != "yes" ]]; then
            return 1
        fi
    else
        return 1
    fi

    # Get Root Key directory name from user (use selected_base as default)
    local root_ca_name=""
    while true; do
        root_ca_name="$(prompt_user "Enter a name for this Root Key directory (e.g., IP or domain)" "$selected_base")"
        if [[ -n "$root_ca_name" ]]; then
            break
        fi
        echo "Root Key name cannot be empty."
    done

    local new_root_ca_dir="${CERTS_DIR}/${root_ca_name}"

    # Check if directory already exists
    if [[ -d "$new_root_ca_dir" ]]; then
        print_message "warning" "Directory ${root_ca_name} already exists!"
        if [[ "$(prompt_yes_no "Backup existing and create new?" "y")" == "yes" ]]; then
            local backup_name="${root_ca_name}.backup-$(date +%Y%m%d-%H%M%S)"
            mv "$new_root_ca_dir" "${CERTS_DIR}/${backup_name}"
            print_message "info" "Backed up to: ${backup_name}"
        else
            print_message "info" "Skipped copying Root Key"
            return 1
        fi
    fi

    # Create new Root Key directory structure
    mkdir -p "$new_root_ca_dir/servers"

    # Copy Root Key files
    cp "${ROOT_CA_SOURCE_PATH}/${selected_base}.key" "${new_root_ca_dir}/rootCA.key"
    cp "${ROOT_CA_SOURCE_PATH}/${selected_base}.crt" "${new_root_ca_dir}/rootCA.crt"

    # Copy .srl if exists
    if [[ -f "${ROOT_CA_SOURCE_PATH}/${selected_base}.srl" ]]; then
        cp "${ROOT_CA_SOURCE_PATH}/${selected_base}.srl" "${new_root_ca_dir}/rootCA.srl"
    fi

    chmod 600 "${new_root_ca_dir}/rootCA.key"
    chmod 644 "${new_root_ca_dir}/rootCA.crt"

    # Set as active Root CA
    ACTIVE_ROOT_CA_DIR="$new_root_ca_dir"

    print_message "success" "Root Key copied to: ${new_root_ca_dir}"
    return 0
}

prompt_select_root_ca_from_certs() {
    local root_cas=("$@")

    if [[ ${#root_cas[@]} -eq 0 ]]; then
        return 1
    fi

    # If only one Root Key, auto-select it
    if [[ ${#root_cas[@]} -eq 1 ]]; then
        local root_ca_name="${root_cas[0]}"
        ACTIVE_ROOT_CA_DIR="${CERTS_DIR}/${root_ca_name}"
        return 0
    fi

    echo ""
    echo "  === Root Key Selection ==="
    echo "  Root Key signs all server certificates for federation."
    echo "  Choose one below or create a new one."
    echo ""

    # Display each Root Key with info
    local index=1
    for root_ca_name in "${root_cas[@]}"; do
        local root_ca_dir="${CERTS_DIR}/${root_ca_name}"
        local root_ca_cert="${root_ca_dir}/rootCA.crt"

        # Get certificate info
        local subject="Unknown"
        local expiry="Unknown"
        local days="Unknown"

        if [[ -f "$root_ca_cert" ]]; then
            subject=$(openssl x509 -in "$root_ca_cert" -noout -subject 2>/dev/null | grep -o 'CN=[^,]*' | cut -d'=' -f2)
            subject="${subject:-${root_ca_name}}"

            local expiry_date
            expiry_date=$(openssl x509 -in "$root_ca_cert" -noout -enddate 2>/dev/null | cut -d'=' -f2)

            if command -v date &> /dev/null && [[ -n "$expiry_date" ]]; then
                local expiry_epoch
                expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
                if [[ -n "$expiry_epoch" ]]; then
                    local current_epoch
                    current_epoch=$(date +%s)
                    local seconds_diff=$((expiry_epoch - current_epoch))
                    if [[ $seconds_diff -gt 0 ]]; then
                        days=$((seconds_diff / 86400))
                        expiry=$(date -d "$expiry_date" "+%Y-%m-%d" 2>/dev/null || echo "$expiry_date")
                    else
                        days="expired"
                    fi
                fi
            fi
        fi

        # Format: align columns nicely
        local num_display="$index)"
        local name_display="${root_ca_name}"
        local subject_display="Subject: ${subject}"
        local days_display="Exp: ${days} days"

        printf "  %-2s  %-12s  %-20s  %-12s\n" "$num_display" "$name_display" "$subject_display" "$days_display"
        ((index++))
    done

    echo "  $MENU_SEPARATOR"
    echo "  N) Create new Root Key    0) Back"
    echo ""

    while true; do
        read -rp "Select [1-$((index-1)), N=New, 0=Back]: " choice || true

        # Check choice type
        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back
                return $MENU_RETURN_BACK
                ;;
            1)  # New
                return $MENU_RETURN_NEW
                ;;
            2)  # Numeric - validate range
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#root_cas[@]} ]]; then
                    local selected_root_ca="${root_cas[$((choice-1))]}"
                    ACTIVE_ROOT_CA_DIR="${CERTS_DIR}/${selected_root_ca}"
                    print_message "success" "Selected Root Key: ${selected_root_ca}"
                    return 0
                fi
                ;;&
        esac

        # If we reach here, choice was invalid
        print_message "error" "Invalid choice"
    done
}

ssl_manager_create_root_ca() {
    local root_ca_name="${1:-}"

    print_message "info" "Creating new Root Key..."

    # Determine default name for Root Key directory
    local default_name="$root_ca_name"
    if [[ -z "$default_name" ]]; then
        # Detect local IP for default suggestion
        default_name="$(get_detected_ip)"
    fi

    # Get Root Key directory name (use provided name or detected IP as default)
    while true; do
        local prompt_text="Enter a name for the Root Key directory (e.g., IP or domain)"
        if [[ -n "$default_name" ]]; then
            root_ca_name="$(prompt_user "$prompt_text" "$default_name")"
        else
            root_ca_name="$(prompt_user "$prompt_text")"
        fi

        if [[ -n "$root_ca_name" ]]; then
            break
        fi
        echo "Root Key name cannot be empty."
    done

    local new_root_ca_dir="${CERTS_DIR}/${root_ca_name}"

    # Check if directory already exists
    if [[ -d "$new_root_ca_dir" ]]; then
        print_message "warning" "Root Key directory already exists: ${root_ca_name}"
        if [[ "$(prompt_yes_no "Backup existing and create new Root Key?" "y")" == "yes" ]]; then
            local backup_name="${root_ca_name}.backup-$(date +%Y%m%d-%H%M%S)"
            mv "$new_root_ca_dir" "${CERTS_DIR}/${backup_name}"
            print_message "info" "Backed up to: ${backup_name}"
        else
            print_message "info" "Root Key creation cancelled"
            return 1
        fi
    fi

    # Create new Root Key directory structure
    mkdir -p "$new_root_ca_dir/servers"

    cd "$new_root_ca_dir" || return 1

    # Generate Root CA private key
    openssl genrsa -out rootCA.key 4096 2>/dev/null
    chmod 600 rootCA.key

    # Generate Root CA certificate with v3_ca extensions
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=${SSL_ORG}" \
        -out rootCA.crt 2>/dev/null

    chmod 644 rootCA.crt

    # Set as active Root Key
    ACTIVE_ROOT_CA_DIR="$new_root_ca_dir"

    print_message "success" "Root Key created (valid for $SSL_CA_DAYS days)"

    # Show Root Key summary
    echo ""
    echo "=== Root Key Files ==="
    echo "  Root Key directory:    ${new_root_ca_dir}"
    echo "  Root Key certificate:   ${new_root_ca_dir}/rootCA.crt"
    echo "  Root Key private key:   ${new_root_ca_dir}/rootCA.key"
    echo "  Servers directory:     ${new_root_ca_dir}/servers/"
    echo ""

    cd "$WORKING_DIR"
    return 0
}

ssl_manager_generate_server_cert() {
    local server_name="$1"
    local root_ca_dir="${2:-${ACTIVE_ROOT_CA_DIR}}"

    # Check if Root Key is set
    if [[ -z "$root_ca_dir" ]]; then
        print_message "error" "No active Root Key. Please select or create a Root Key first."
        return 1
    fi

    print_message "info" "Generating server certificate for: $server_name"
    print_message "info" "Using Root Key: $(basename "$root_ca_dir")"

    # Check Root Key exists
    if [[ ! -f "${root_ca_dir}/rootCA.key" ]] || [[ ! -f "${root_ca_dir}/rootCA.crt" ]]; then
        print_message "error" "Root Key not found in ${root_ca_dir}"
        return 1
    fi

    # Create server subdirectory under active Root CA
    local server_cert_dir
    server_cert_dir="${root_ca_dir}/servers/${server_name}"
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
        -CA "${root_ca_dir}/rootCA.crt" -CAkey "${root_ca_dir}/rootCA.key" \
        -CAcreateserial -out server.crt \
        -days "$SSL_CERT_DAYS" -sha256 \
        -extensions v3_req -extfile openssl.cnf 2>/dev/null

    # Create full chain
    cat server.crt "${root_ca_dir}/rootCA.crt" > cert-full-chain.pem
    chmod 644 server.crt cert-full-chain.pem

    # Cleanup
    rm -f server.csr openssl.cnf

    # Set as active server
    ACTIVE_SERVER="$server_name"

    print_message "success" "Server certificate created for: $server_name"

    # Show certificate summary
    echo ""
    echo "=== Certificate Files ==="
    echo "  Root Key directory:     ${root_ca_dir}"
    echo "  Server cert directory: ${server_cert_dir}"
    echo "  Private key:          ${server_cert_dir}/server.key"
    echo "  Full chain cert:      ${server_cert_dir}/cert-full-chain.pem"
    echo "  Server cert:          ${server_cert_dir}/server.crt"
    echo ""
    echo "  Root Key:              ${root_ca_dir}/rootCA.crt"
    echo "  Root Key key:          ${root_ca_dir}/rootCA.key"
    echo ""

    cd "$WORKING_DIR"
    return 0
}

# ===========================================
# ENVIRONMENT PROVIDER MODULE
# ===========================================

env_provider_export_for_addon() {
    local server_name="$1"
    local root_ca_dir="${2:-${ACTIVE_ROOT_CA_DIR}}"

    # Check if Root Key is set
    if [[ -z "$root_ca_dir" ]]; then
        print_message "error" "No active Root Key. Cannot export environment."
        return 1
    fi

    # Get server certificate directory
    local server_cert_dir
    server_cert_dir="${root_ca_dir}/servers/${server_name}"

    # Check certificates exist
    if [[ ! -f "${server_cert_dir}/server.key" ]] || [[ ! -f "${server_cert_dir}/cert-full-chain.pem" ]] || [[ ! -f "${root_ca_dir}/rootCA.crt" ]]; then
        print_message "error" "SSL certificates not found for server: $server_name"
        print_message "error" "Expected location: ${server_cert_dir}"
        return 1
    fi

    # Export environment variables for addon
    export SERVER_NAME="$server_name"
    export SSL_CERT="${server_cert_dir}/cert-full-chain.pem"
    export SSL_KEY="${server_cert_dir}/server.key"
    export ROOT_CA="${root_ca_dir}/rootCA.crt"
    export ROOT_CA_DIR="$root_ca_dir"
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
    for dir in addons/*/; do
        if [[ -f "${dir}install.sh" ]]; then
            # Check if addon is hidden (only include if NOT hidden)
            if ! grep -q "^ADDON_HIDDEN=\"true\"" "${dir}install.sh" 2>/dev/null; then
                found_addons+=("${dir%/}")
            fi
        fi
    done

    # Sort addons by ADDON_ORDER (default to 999 if not set)
    local sorted_addons=()
    while IFS= read -r addon; do
        sorted_addons+=("$addon")
    done < <(for addon in "${found_addons[@]}"; do
        local order
        order=$(grep "^ADDON_ORDER=" "$addon/install.sh" 2>/dev/null | cut -d'=' -f2 | tr -d '" ')
        echo "${order:-999} $addon"
    done | sort -n | cut -d' ' -f2-)

    # Return sorted list
    printf '%s\n' "${sorted_addons[@]}"
    return 0
}

addon_loader_get_name() {
    local addon_dir="$1"
    local addon_install="${addon_dir}/install.sh"

    if [[ -f "$addon_install" ]]; then
        local name
        # First check for ADDON_NAME_MENU (menu display name)
        name=$(grep "^ADDON_NAME_MENU=" "$addon_install" | cut -d'=' -f2)
        # Remove quotes if present
        name="${name%\"}"
        name="${name#\"}"

        # If ADDON_NAME_MENU not found, fall back to ADDON_NAME
        if [[ -z "$name" ]]; then
            name=$(grep "^ADDON_NAME=" "$addon_install" | cut -d'=' -f2)
            # Remove quotes if present
            name="${name%\"}"
            name="${name#\"}"
        fi

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

menu_with_root_key() {
    # Get addons list
    local addons
    mapfile -t addons < <(addon_loader_get_list)

    # Get available Root Keys
    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
    local num_root_cas=${#FOUND_ROOT_CAS[@]}

    while true; do
        # Build menu dynamically with addons
        local addon_index_start=2
        local last_addon_index=$((addon_index_start + ${#addons[@]} - 1))
        local switch_ca_option="S"
        local new_ca_option="N"
        local exit_option=0

        echo ""
        echo "  === Main Menu ==="
        echo ""

        # Get and display Root Key info
        local ca_info
        ca_info=$(get_root_ca_info "$ACTIVE_ROOT_CA_DIR" 2>/dev/null)

        if [[ -n "$ca_info" ]]; then
            # Parse the info line by line
            local ca_subject="Matrix Root Key"
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

            echo -e "  Root Key: ${BLUE}$(basename "$ACTIVE_ROOT_CA_DIR")${NC} | Exp: $ca_days days | $ca_country"
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
                echo "  $addon_num) $addon_name"
            done
        fi

        echo ""
        echo "  $MENU_SEPARATOR"

        # Build footer options
        if [[ $num_root_cas -gt 1 ]]; then
            echo -e "  ${BLUE}S) Switch${NC}    N) New Root Key    0) Exit"
        else
            echo "  N) New Root Key    0) Exit"
        fi
        echo ""

        # Build prompt text based on available options
        if [[ $num_root_cas -gt 1 ]]; then
            read -rp "Enter your choice (1-${last_addon_index}, S=Switch, N=New, 0=Exit): " choice || true
        else
            read -rp "Enter your choice (1-${last_addon_index}, N=New, 0=Exit): " choice || true
        fi

        case "$choice" in
            1)
                # Generate server certificate
                echo ""

                local detected_ip
                detected_ip="$(get_detected_ip)"
                local server_input

                while true; do
                    if [[ -n "$detected_ip" ]]; then
                        server_input="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
                    else
                        server_input="$(prompt_user "Enter server IP address or domain" "")"
                    fi

                    # Clean input (remove control characters)
                    server_input="$(echo "$server_input" | tr -d '[:cntrl:]')"

                    if [[ -n "$server_input" ]]; then
                        break
                    fi
                    echo "Server name cannot be empty. Please try again."
                done

                # Show summary and confirm
                echo ""
                echo "  === Certificate Summary ==="
                echo ""
                echo -e "  Root Key:      ${BLUE}$(basename "$ACTIVE_ROOT_CA_DIR")${NC}"

                local server_type="Domain"
                if is_ip_address "$server_input"; then
                    server_type="IP Address"
                fi

                echo "  Server:        $server_input"
                echo "  Type:          $server_type"
                echo "  Certificate:   ${ACTIVE_ROOT_CA_DIR}/servers/${server_input}/"
                echo "  Validity:      $SSL_CERT_DAYS days"
                echo ""

                if [[ "$(prompt_yes_no "Generate certificate now?" "y")" == "yes" ]]; then
                    SERVER_NAME="$server_input"
                    ssl_manager_generate_server_cert "$SERVER_NAME"
                else
                    print_message "info" "Certificate generation cancelled"
                fi
                ;;
            [Ss])
                if [[ $num_root_cas -gt 1 ]]; then
                    echo ""
                    local select_result
                    prompt_select_root_ca_from_certs "${FOUND_ROOT_CAS[@]}" || select_result=$?
                    select_result="${select_result:-0}"
                    if [[ $select_result -eq 0 ]]; then
                        print_message "success" "Switched to Root Key: $(basename "$ACTIVE_ROOT_CA_DIR")"
                        mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                        num_root_cas=${#FOUND_ROOT_CAS[@]}
                    elif [[ $select_result -eq 1 ]]; then
                        # User chose to create new Root Key
                        create_root_ca_from_menu
                        mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                        num_root_cas=${#FOUND_ROOT_CAS[@]}
                    fi
                    # If return code 3 (Back), just continue to re-display menu
                else
                    # Only one Root Key, create new
                    create_root_ca_from_menu
                    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                    num_root_cas=${#FOUND_ROOT_CAS[@]}
                fi
                ;;
            [Nn])
                create_root_ca_from_menu
                mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                num_root_cas=${#FOUND_ROOT_CAS[@]}
                ;;
            0)
                print_message "info" "Exiting..."
                exit 0
                ;;
            *)
                # Check if it's an addon choice (must be numeric first)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge $addon_index_start ]] && [[ "$choice" -le $last_addon_index ]]; then
                    local selected_addon="${addons[$((choice - addon_index_start))]}"
                    # Run addon with error handling - return to menu on failure
                    set +e
                    menu_run_addon "$selected_addon"
                    local addon_result=$?
                    set -e
                    # If addon returned 1 (error), just continue to re-display menu
                else
                    print_message "error" "Invalid choice"
                fi
                ;;
        esac
    done
}

menu_without_root_key() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║             ${MATRIX_PLUS_NAME} - Main Menu              ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo -e "Root Key: ${ORANGE}Not Available${NC}"
        echo ""
        echo "  1) Generate new Root Key"
        echo "  2) Exit"
        echo ""

        read -rp "Enter your choice (1-2): " choice || true

        case "$choice" in
            1)
                if [[ "$(prompt_yes_no "This will create a new Root Key directory. Continue?" "y")" != "yes" ]]; then
                    continue
                fi

                local config
                config="$(prompt_root_ca_config)" || true

                # Parse config safely
                local org_input country_input state_input city_input days_input
                org_input="$(echo "$config" | cut -d'|' -f1)"
                country_input="$(echo "$config" | cut -d'|' -f2)"
                state_input="$(echo "$config" | cut -d'|' -f3)"
                city_input="$(echo "$config" | cut -d'|' -f4)"
                days_input="$(echo "$config" | cut -d'|' -f5)"

                # Save and restore globals
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

                if [[ "$(prompt_yes_no "Create Root Key with these settings?" "y")" == "yes" ]]; then
                    if ssl_manager_create_root_ca "$org_input"; then
                        print_message "success" "Root Key created. Switching to main menu..."
                        SSL_ORG="$old_org"
                        SSL_COUNTRY="$old_country"
                        SSL_STATE="$old_state"
                        SSL_CITY="$old_city"
                        SSL_CA_DAYS="$old_days"
                        menu_with_root_key
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

        local detected_ip
        detected_ip="$(get_detected_ip)"
        local new_server

        if [[ -n "$detected_ip" ]]; then
            new_server="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
        else
            while true; do
                new_server="$(prompt_user "Enter server IP address or domain" "")"
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

        read -rp "Select server (1-$index): " choice || true

        # Check choice type first
        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back - not applicable in this menu
                print_message "error" "Invalid choice"
                return 1
                ;;
            1)  # New - check for special value
                # In this menu, the "new" option is the index value (not N)
                if [[ "$choice" == "$MENU_CHOICE_NEW" ]] || [[ "$choice" == "${MENU_CHOICE_NEW,,}" ]]; then
                    print_message "error" "Invalid choice"
                    return 1
                fi
                ;;&
            2)  # Numeric
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -lt $index ]]; then
                    selected_server="${servers[$((choice-1))]}"
                elif [[ "$choice" -eq $index ]]; then
                    # Create new certificate
                    local new_server
                    local detected_ip
                    detected_ip="$(get_detected_ip)"

                    while true; do
                        new_server="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
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
                ;;
        esac
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

    # Return to menu after addon completes (don't exit)
    # Addons no longer take full control - user can return to main menu
}

# ===========================================
# INITIALIZATION FUNCTION
# ===========================================

initialize() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "${MATRIX_PLUS_NAME} Log - $(date)" > "$LOG_FILE"

    # Print banner (dynamic)
    local title="${MATRIX_PLUS_NAME} - ${MATRIX_PLUS_DESCRIPTION}"
    local version="Version ${MATRIX_PLUS_VERSION}"
    local build="Build: ${MATRIX_PLUS_BUILD_DATE}"
    local box_width=58

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"

    # Center title
    local title_padding=$(( (box_width - ${#title}) / 2 ))
    printf "║%*s%s%*s║\n" $title_padding "" "$title" $((box_width - title_padding - ${#title})) ""

    # Center version
    local version_padding=$(( (box_width - ${#version}) / 2 ))
    printf "║%*s%s%*s║\n" $version_padding "" "$version" $((box_width - version_padding - ${#version})) ""

    # Center build
    local build_padding=$(( (box_width - ${#build}) / 2 ))
    printf "║%*s%s%*s║\n" $build_padding "" "$build" $((box_width - build_padding - ${#build})) ""

    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Initialize SSL Manager
    ssl_manager_init
}

# ===========================================
# NEW ROOT CA CREATION FUNCTION
# ===========================================
# MAIN FUNCTION
# ===========================================

main() {
    # Initialize: show banner and detect Root CA files
    initialize

    # Step 1: Handle Root CA files next to script (if any)
    if [[ "$ROOT_CA_DETECTED" == "true" ]]; then
        if prompt_use_existing_root_ca; then
            # Root CA copied successfully, continue to certs/ menu
            :
        fi
    fi

    # Step 2: Discover Root CAs in certs/ and show appropriate menu
    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)

    if [[ ${#FOUND_ROOT_CAS[@]} -gt 0 ]]; then
        # Has Root CAs - may need to select one
        if [[ ${#FOUND_ROOT_CAS[@]} -eq 1 ]] && [[ -z "$ACTIVE_ROOT_CA_DIR" ]]; then
            # Auto-select single Root CA
            ACTIVE_ROOT_CA_DIR="${CERTS_DIR}/${FOUND_ROOT_CAS[0]}"
        elif [[ -z "$ACTIVE_ROOT_CA_DIR" ]]; then
            # Multiple Root CAs and none selected - prompt user
            local select_result
            prompt_select_root_ca_from_certs "${FOUND_ROOT_CAS[@]}" || select_result=$?
            select_result="${select_result:-0}"
            if [[ $select_result -eq 1 ]]; then
                # User chose to create new Root Key
                create_root_ca_from_menu
                mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
            fi
            # If return code 0 (auto-selected) or 3 (Back), just continue to menu_with_root_key
        fi
        menu_with_root_key
    else
        # No Root Keys found
        menu_without_root_key
    fi
}

# ===========================================
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
