#!/bin/bash

# ===========================================
# Matrix Installer - Private Key Matrix Installation System
# ===========================================

# Application Metadata
MATRIX_PLUS_NAME="Matrix Installer"
MATRIX_PLUS_VERSION="0.1.0"
MATRIX_PLUS_DESCRIPTION="Federation Key Manager"
MATRIX_PLUS_BUILD="Alpha"

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
DETECTED_OS=""  # Detected OS: arch|ubuntu|debian|unknown
MISSING_DEPS=()  # Array of missing dependencies
OS_DIR="${SCRIPT_DIR}/os"  # Directory containing OS-specific modules
ACTIVE_OS_MODULE=""  # Currently active OS module

# Menu choice constants (for user input handling)
MENU_CHOICE_BACK="0"
MENU_CHOICE_NEW="N"

# Menu return codes
MENU_RETURN_SUCCESS=0
MENU_RETURN_NEW=1
MENU_RETURN_BACK=3
MENU_RETURN_EXPORT=4

# ===========================================
# PREREQUISITE CHECK FUNCTIONS
# ===========================================

# Detect the operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # Source os-release safely, capturing any errors
        source /etc/os-release 2>/dev/null || true
        local id="${ID:-}"
        local id_like="${ID_LIKE:-}"

        case "$id" in
            arch|artix|garuda|manjaro)
                DETECTED_OS="arch"
                return 0
                ;;
            ubuntu)
                DETECTED_OS="ubuntu"
                return 0
                ;;
            debian)
                DETECTED_OS="debian"
                return 0
                ;;
        esac

        # Check ID_LIKE for Ubuntu/Debian variants
        if [[ "$id_like" == *"ubuntu"* ]] || [[ "$id_like" == *"debian"* ]]; then
            DETECTED_OS="ubuntu"
            return 0
        fi
    fi

    DETECTED_OS="unknown"
    return 0  # Always return 0 to avoid script exit with set -e
}

# Check if a command exists (returns 0 if exists, 1 if not)
command_exists() {
    local cmd_path
    cmd_path="$(command -v "$1" 2>/dev/null)" || return 1

    # Additional check: verify the command is actually executable
    if [[ ! -x "$cmd_path" ]]; then
        return 1
    fi

    # For git, check if it's a stub (common on Debian/Ubuntu after apt remove)
    if [[ "$1" == "git" ]]; then
        # Check if git actually works by running it
        if git --version &>/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi

    return 0
}

# Check required dependencies (uses OS module's REQUIRED_COMMANDS) - Silent mode
check_dependencies() {
    MISSING_DEPS=()

    # Get required commands from OS module if available
    local required_commands=()
    if [[ -n "$ACTIVE_OS_MODULE" ]] && declare -p REQUIRED_COMMANDS >/dev/null 2>&1; then
        required_commands=("${REQUIRED_COMMANDS[@]}")
    else
        # Fallback to basic commands if no OS module loaded
        required_commands=("openssl" "ip")
    fi

    # Silent check - no output
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            MISSING_DEPS+=("$cmd")
        fi
    done

    # Return silently
    [[ ${#MISSING_DEPS[@]} -eq 0 ]]
}

# Display missing dependencies and prompt for installation
prompt_install_dependencies() {
    if [[ ${#MISSING_DEPS[@]} -eq 0 ]]; then
        return 0
    fi

    # Get required commands for display
    local required_commands=()
    if [[ -n "$ACTIVE_OS_MODULE" ]] && declare -p REQUIRED_COMMANDS >/dev/null 2>&1; then
        required_commands=("${REQUIRED_COMMANDS[@]}")
    else
        required_commands=("openssl" "ip")
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Missing Dependencies                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "The following required packages are missing:"
    echo ""
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Found:"
    echo ""
    for cmd in "${required_commands[@]}"; do
        if command_exists "$cmd"; then
            echo "  - $cmd"
        fi
    done
    echo ""
    echo "Detected OS: $DETECTED_OS"
    echo ""

    if [[ "$(prompt_yes_no "Install missing dependencies now?" "y")" != "yes" ]]; then
        print_message "error" "Cannot continue without required dependencies."
        exit 1
    fi

    install_dependencies
}

# Install missing dependencies using OS module (with built-in fallback)
install_dependencies() {
    print_message "info" "Installing dependencies..."

    # Try OS module first if available and complete
    if [[ -n "$ACTIVE_OS_MODULE" ]] && \
       declare -f get_package_for_command >/dev/null 2>&1 && \
       declare -f os_install_packages >/dev/null 2>&1; then

        # Map missing commands to package names using OS module
        local packages=()
        for cmd in "${MISSING_DEPS[@]}"; do
            local pkg
            pkg="$(get_package_for_command "$cmd")"
            packages+=("$pkg")
        done

        # Install packages using OS module's function
        if [[ ${#packages[@]} -gt 0 ]]; then
            print_message "info" "Installing: ${packages[*]}"
            if os_install_packages "${packages[@]}"; then
                print_message "success" "Dependencies installed successfully"
                return 0
            else
                print_message "error" "Failed to install dependencies"
                exit 1
            fi
        fi
        return 0
    fi

    # Fallback to built-in support
    print_message "info" "Using built-in package installation..."
    case "$DETECTED_OS" in
        ubuntu|debian)
            install_ubuntu_deps_fallback
            ;;
        arch)
            install_arch_deps_fallback
            ;;
        *)
            print_message "error" "Unsupported OS: $DETECTED_OS"
            print_message "info" "Please install manually: ${MISSING_DEPS[*]}"
            exit 1
            ;;
    esac
}

# ===========================================
# BUILT-IN FALLBACK FUNCTIONS
# ===========================================

# Built-in fallback for Ubuntu/Debian
install_ubuntu_deps_fallback() {
    local packages=()

    for dep in "${MISSING_DEPS[@]}"; do
        case "$dep" in
            git) packages+=("git-all") ;;
            openssl) packages+=("openssl") ;;
            ip) packages+=("iproute2") ;;
            *) packages+=("$dep") ;;
        esac
    done

    if [[ ${#packages[@]} -gt 0 ]]; then
        print_message "info" "Installing with apt-get: ${packages[*]}"
        if sudo apt-get update -qq && sudo apt-get install -y "${packages[@]}"; then
            print_message "success" "Dependencies installed successfully"
        else
            print_message "error" "Failed to install dependencies"
            exit 1
        fi
    fi
}

# Built-in fallback for Arch Linux
install_arch_deps_fallback() {
    local packages=()

    for dep in "${MISSING_DEPS[@]}"; do
        case "$dep" in
            git) packages+=("git") ;;
            openssl) packages+=("openssl") ;;
            ip) packages+=("iproute2") ;;
            *) packages+=("$dep") ;;
        esac
    done

    if [[ ${#packages[@]} -gt 0 ]]; then
        print_message "info" "Installing with pacman: ${packages[*]}"
        if sudo pacman -S --noconfirm "${packages[@]}"; then
            print_message "success" "Dependencies installed successfully"
        else
            print_message "error" "Failed to install dependencies"
            exit 1
        fi
    fi
}

# ===========================================
# OS MODULE SYSTEM
# ===========================================

# Detect and load the appropriate OS module
detect_os_module() {
    ACTIVE_OS_MODULE=""

    if [[ ! -d "$OS_DIR" ]]; then
        return 1
    fi

    # Find all .sh files in os/ directory
    for module_file in "${OS_DIR}"/*.sh; do
        if [[ -f "$module_file" ]]; then
            local module_name
            module_name="$(basename "$module_file" .sh)"

            # Test if this module matches the current OS (in subshell)
            if (
                source "$module_file" 2>/dev/null
                os_detect
            ) then
                # This module matches - load it for real
                source "$module_file"
                ACTIVE_OS_MODULE="$module_name"
                DETECTED_OS="$module_name"
                print_message "success" "Detected OS: $module_name"
                return 0
            fi
        fi
    done

    return 1
}

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

# Clear the terminal screen
clean_screen() {
    clear
}

# Truncate string to max length with ... in the middle
# Usage: truncate_string "string" "max_length"
# Examples:
#   "MatrixIR" "12" -> "MatrixIR"
#   "10.239.191.69" "12" -> "10.2...91.69"
#   "verylongname123" "15" -> "veryl...123"
truncate_string() {
    local str="$1"
    local max_len="$2"

    # If string is short enough, return as is
    if [[ ${#str} -le $max_len ]]; then
        echo "$str"
        return
    fi

    # Calculate how many chars to keep from start and end
    # Formula: start_chars = (max_len - 3) / 2
    #          end_chars = max_len - 3 - start_chars
    local start_chars=$(( (max_len - 3) / 2 ))
    local end_chars=$(( max_len - 3 - start_chars ))

    local first_part="${str:0:$start_chars}"
    local last_part="${str: -$end_chars}"
    echo "${first_part}...${last_part}"
}

# Print welcome header with title, version and build info
print_welcome_header() {
    local title="${MATRIX_PLUS_NAME} - ${MATRIX_PLUS_DESCRIPTION}"
    local version="Version ${MATRIX_PLUS_VERSION}"
    local build="Build: ${MATRIX_PLUS_BUILD}"
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
                echo "Please answer yes or no." >&2
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

# Pause and wait for user to press Enter
pause() {
    echo ""
    read -rp "Press Enter to continue..."
}

# Print styled menu header
print_menu_header() {
    local title="$1"
    local subtitle="${2:-}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"

    local box_width=58
    # Calculate visible width by removing ANSI color codes
    local title_no_color="${title//$'\033'[[0-9;]*m/}"
    local title_padding=$(( (box_width - ${#title_no_color}) / 2 ))

    # Use printf %b to interpret escape sequences
    printf "║%*s%b%*s║\n" $title_padding "" "$title" $((box_width - title_padding - ${#title_no_color})) ""

    # Print subtitle if provided
    if [[ -n "$subtitle" ]]; then
        local subtitle_no_color="${subtitle//$'\033'[[0-9;]*m/}"
        local subtitle_padding=$(( (box_width - ${#subtitle_no_color}) / 2 ))
        printf "║%*s%b%*s║\n" $subtitle_padding "" "$subtitle" $((box_width - subtitle_padding - ${#subtitle_no_color})) ""
    fi

    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
}

# Print styled menu footer with options
print_menu_footer() {
    local options="$1"  # Comma-separated options: "back,new,export,switch"
    local show_separator="${2:-true}"

    if [[ "$show_separator" == "true" ]]; then
        echo ""
        echo "  $MENU_SEPARATOR"
    fi

    echo ""

    # Build footer based on available options
    local footer_parts=()

    # Check for switch option (colored)
    if [[ "$options" == *"switch"* ]]; then
        footer_parts+=("${BLUE}S) Switch${NC}")
    fi

    # Check for export option
    if [[ "$options" == *"export"* ]]; then
        footer_parts+=("E) Export\\Import")
    fi

    # Check for new option
    if [[ "$options" == *"new"* ]]; then
        footer_parts+=("N) New Root Key")
    fi

    # Check for back option
    if [[ "$options" == *"back"* ]]; then
        footer_parts+=("Enter) Back")
    fi

    # Check for exit option
    if [[ "$options" == *"exit"* ]]; then
        footer_parts+=("Enter) Exit")
    fi

    # Join parts with "    " separator
    local footer_text=""
    local first=true
    for part in "${footer_parts[@]}"; do
        if [[ "$first" == "true" ]]; then
            footer_text="  $part"
            first=false
        else
            footer_text="${footer_text}    ${part}"
        fi
    done

    # Print footer with color expansion
    echo -e "$footer_text"
    echo ""
}

# Generic menu builder function
menu_show() {
    local title="$1"
    local -n items_array="$2"
    local options="${3:-}"
    local prompt_msg="${4:-}"
    local separator_after="${5:-}"  # Add blank line after this item index (1-based)

    # Display output goes to terminal (>&2), return value goes to stdout
    echo "" >&2

    # Print header if title provided
    if [[ -n "$title" ]]; then
        print_menu_header "$title" >&2
    fi

    # Display menu items
    local index=1
    for item in "${items_array[@]}"; do
        # Parse item: label|value|color|badge
        IFS='|' read -r label value color badge <<< "$item"

        # Build display line
        local display_line="  $index) ${label}"

        # Apply color if specified
        if [[ -n "$color" ]]; then
            display_line="  $index) ${color}${label}${NC}"
        fi

        # Add badge if specified
        if [[ -n "$badge" ]]; then
            display_line="${display_line} ${badge}"
        fi

        echo -e "$display_line" >&2

        # Add blank line after specified index
        if [[ -n "$separator_after" ]] && [[ "$index" == "$separator_after" ]]; then
            echo "" >&2
        fi

        ((index++))
    done

    # Print separator and footer if options provided
    if [[ -n "$options" ]]; then
        print_menu_footer "$options" "true" >&2
    else
        echo "" >&2
    fi

    # Build prompt message if not provided
    if [[ -z "$prompt_msg" ]]; then
        local last_index=$((index - 1))
        prompt_msg="Enter your choice (1-${last_index}"

        # Add special options to prompt
        if [[ "$options" == *"back"* ]] || [[ "$options" == *"exit"* ]]; then
            prompt_msg="${prompt_msg}, Enter=Back"
        fi
        if [[ "$options" == *"new"* ]]; then
            prompt_msg="${prompt_msg}, N=New"
        fi
        if [[ "$options" == *"export"* ]]; then
            prompt_msg="${prompt_msg}, E=Export"
        fi
        if [[ "$options" == *"switch"* ]]; then
            prompt_msg="${prompt_msg}, S=Switch"
        fi

        prompt_msg="${prompt_msg}): "
    fi

    # Read user choice
    while true; do
        read -rp "$prompt_msg" choice || true

        # Empty input is only "Back" if explicitly allowed in options
        if [[ -z "$choice" ]]; then
            if [[ "$options" == *"back"* ]] || [[ "$options" == *"exit"* ]]; then
                return $MENU_RETURN_BACK
            fi
            # Otherwise, re-prompt (don't treat empty as Back)
            continue
        fi

        # Check choice type
        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back (user entered 0)
                if [[ "$options" == *"back"* ]] || [[ "$options" == *"exit"* ]]; then
                    return $MENU_RETURN_BACK
                fi
                ;;
            1)  # New
                if [[ "$options" == *"new"* ]]; then
                    return $MENU_RETURN_NEW
                fi
                ;;
            2)  # Numeric - validate range
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le $((index - 1)) ]]; then
                    # Return the selected item's value
                    local selected_item="${items_array[$((choice - 1))]}"
                    IFS='|' read -r label item_value color badge <<< "$selected_item"
                    echo "$item_value"
                    return 0
                fi
                ;;
        esac

        # Check for Export option (special case - not in check_menu_choice_type)
        if [[ "$options" == *"export"* ]]; then
            if [[ "$choice" == "E" ]] || [[ "$choice" == "e" ]]; then
                return $MENU_RETURN_EXPORT
            fi
        fi

        # Check for Switch option (special case)
        if [[ "$options" == *"switch"* ]]; then
            if [[ "$choice" == "S" ]] || [[ "$choice" == "s" ]]; then
                echo "switch"
                return 0
            fi
        fi

        # Invalid choice
        print_message "error" "Invalid choice"
    done
}

# Unified summary display function
print_summary() {
    local title="$1"
    local -n sections_array="$2"

    # Calculate visible width by removing ANSI color codes
    local title_no_color="${title//$'\033'[[0-9;]*m/}"
    local title_width=${#title_no_color}
    local padding=$(( 54 - title_width ))
    local left_pad=$(( padding / 2 ))
    local right_pad=$(( padding - left_pad ))

    # Build padding strings
    local left_padding=""
    for ((i=0; i<left_pad; i++)); do left_padding+=" "; done
    local right_padding=""
    for ((i=0; i<right_pad; i++)); do right_padding+=" "; done

    echo ""
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo -e "  ║  ${left_padding}${title}${right_padding}║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Process each section
    local section_index=0
    local total_sections=${#sections_array[@]}

    for section in "${sections_array[@]}"; do
        IFS='|' read -r section_label item1 item2 item3 item4 item5 item6 <<< "$section"

        # Check if item1 contains a tree structure marker (| character indicates multi-line tree)
        if [[ -n "$item1" ]] && [[ "$item1" == *"|"*"|"* ]]; then
            # Parse item1 as a tree structure string with | as line separator
            echo -e "  ${BLUE}${section_label}:${NC}"
            echo "  |"

            # Split by | and print each line
            local IFS='|'
            read -ra tree_lines <<< "$item1"
            for line in "${tree_lines[@]}"; do
                # Trim leading whitespace
                line="${line#"${line%%[![:space:]]*}"}"
                if [[ -n "$line" ]]; then
                    echo -e "  $line"
                fi
            done
        elif [[ -n "$item2" ]]; then
            # Multi-item section with tree structure
            echo -e "  ${BLUE}${section_label}:${NC}"
            echo "  |"

            # Print first item
            if [[ -n "$item1" ]]; then
                echo -e "  +-- $item1"
            fi

            # Print middle items (if any)
            local item_count=2
            local item_var="item${item_count}"
            while [[ -n "${!item_var}" ]]; do
                local current_item="${!item_var}"
                ((item_count++))
                item_var="item${item_count}"

                # Check if this is the last item
                if [[ -z "${!item_var}" ]]; then
                    echo -e "  \`-- $current_item"
                else
                    echo -e "  +-- $current_item"
                fi
            done
        else
            # Simple section with single item
            echo -e "  ${BLUE}${section_label}:${NC}"
            if [[ -n "$item1" ]]; then
                echo -e "     $item1"
            fi
        fi

        ((section_index++)) || true
        if [[ $section_index -lt $total_sections ]]; then
            echo ""
        fi
    done

    echo ""
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
        # Pause to let user see the result
        pause
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

# Display Root CA information in specified format
display_root_ca_info() {
    local root_ca_dir="$1"
    local style="${2:-compact}"  # compact|detailed

    if [[ ! -f "${root_ca_dir}/rootCA.crt" ]]; then
        return 1
    fi

    # Get certificate info using existing function
    local ca_info
    ca_info=$(get_root_ca_info "$root_ca_dir" 2>/dev/null)

    if [[ -z "$ca_info" ]]; then
        return 1
    fi

    # Parse the info
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

    # Determine type (Full vs Imported)
    local ca_type_label="Full"
    local ca_type_color="${GREEN}"
    if is_root_ca_imported "$root_ca_dir"; then
        ca_type_label="Imported"
        ca_type_color="${ORANGE}"
    fi

    # Display based on style
    if [[ "$style" == "compact" ]]; then
        # Single-line compact format
        local ca_name
        ca_name="$(basename "$root_ca_dir")"
        echo -e "  Root Key: ${BLUE}${ca_name}${NC} | Subject: ${ca_subject} | ${ca_type_color}${ca_type_label}${NC} | Exp: ${ca_days} days | ${ca_country}"
    elif [[ "$style" == "detailed" ]]; then
        # Multi-line detailed format
        local ca_name
        ca_name="$(basename "$root_ca_dir")"
        # Truncate name to 12 chars max with ... in middle if needed
        local ca_name_display
        ca_name_display="$(truncate_string "$ca_name" 12)"
        printf "  %-2s  %-12s  %-20s  %-12s  ${ca_type_color}%-10s${NC}\n" "" "$ca_name_display" "Subject: ${ca_subject}" "Exp: ${ca_days} days" "$ca_type_label"
    fi

    return 0
}

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

            # Accept as Root CA directory if it has rootCA.crt
            # (with or without rootCA.key - we'll distinguish later)
            if [[ -f "${dir}/rootCA.crt" ]]; then
                root_cas+=("$root_ca_name")
            fi
        fi
    done

    # Return list (only if we have Root CAs)
    if [[ ${#root_cas[@]} -gt 0 ]]; then
        printf '%s\n' "${root_cas[@]}"
    fi
}

# Check if a Root CA is imported (read-only, without private key)
# Returns: 0 if imported (no key), 1 if full (has key)
is_root_ca_imported() {
    local root_ca_dir="$1"

    if [[ ! -f "${root_ca_dir}/rootCA.key" ]]; then
        return 0  # Imported (read-only)
    fi

    return 1  # Full (has private key)
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

# Prompt user to select a server from available certificates
prompt_select_server() {
    local allow_create="${1:-true}"
    local prompt_msg="${2:-Select a server}"

    # Get list of servers with certificates
    local servers
    mapfile -t servers < <(list_servers_with_certs)

    # No servers - auto-prompt for new server
    if [[ ${#servers[@]} -eq 0 ]]; then
        local detected_ip
        detected_ip="$(get_detected_ip)"
        local new_server

        while true; do
            if [[ -n "$detected_ip" ]]; then
                new_server="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
            else
                new_server="$(prompt_user "Enter server IP address or domain" "")"
            fi

            if [[ -n "$new_server" ]]; then
                break
            fi
            echo "Server name cannot be empty." >&2
        done

        # Generate certificate for new server (redirect logs to stderr to avoid capture)
        if ! ssl_manager_generate_server_cert "$new_server" >&2; then
            print_message "error" "Failed to generate server certificate" >&2
            echo "" >&2
            return 1
        fi

        echo "$new_server"
        return 0
    fi

    # Single server - auto-select
    if [[ ${#servers[@]} -eq 1 ]]; then
        echo "" >&2
        print_message "info" "Using existing certificate for: ${servers[0]}" >&2
        echo "${servers[0]}"
        return 0
    fi

    # Multiple servers - show selection menu
    echo "" >&2
    print_message "info" "Servers with available certificates:" >&2
    local index=1
    for server in "${servers[@]}"; do
        echo "  $index) $server" >&2
        ((index++))
    done

    # Add create new option if allowed
    if [[ "$allow_create" == "true" ]]; then
        echo "  $index) Create new server certificate" >&2
    fi

    echo "" >&2

    local max_index=$index
    if [[ "$allow_create" == "false" ]]; then
        ((max_index--))
    fi

    while true; do
        read -rp "Select server (1-$max_index): " choice || true

        # Check choice type
        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back
                echo "" >&2
                return 1
                ;;
            2)  # Numeric
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -lt $index ]]; then
                    # Selected existing server
                    echo "${servers[$((choice-1))]}"
                    return 0
                elif [[ "$choice" -eq $index ]] && [[ "$allow_create" == "true" ]]; then
                    # Create new certificate
                    local new_server
                    local detected_ip
                    detected_ip="$(get_detected_ip)"

                    while true; do
                        new_server="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
                        if [[ -n "$new_server" ]]; then
                            break
                        fi
                        echo "Server name cannot be empty." >&2
                    done

                    if ! ssl_manager_generate_server_cert "$new_server" >&2; then
                        print_message "error" "Failed to generate server certificate" >&2
                        echo "" >&2
                        return 1
                    fi

                    echo "$new_server"
                    return 0
                fi
                ;;
        esac

        print_message "error" "Invalid choice"
    done
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

# Set appropriate permissions on certificate files
set_cert_permissions() {
    local cert_dir="$1"
    local cert_type="${2:-auto}"  # auto|server|root_ca

    # Auto-detect certificate type if not specified
    if [[ "$cert_type" == "auto" ]]; then
        if [[ -f "${cert_dir}/rootCA.key" ]] || [[ -f "${cert_dir}/rootCA.crt" ]]; then
            cert_type="root_ca"
        elif [[ -f "${cert_dir}/server.key" ]] || [[ -d "${cert_dir}/servers" ]]; then
            cert_type="server"
        fi
    fi

    if [[ "$cert_type" == "root_ca" ]]; then
        # Root CA permissions
        if [[ -f "${cert_dir}/rootCA.key" ]]; then
            chmod 600 "${cert_dir}/rootCA.key"
        fi
        if [[ -f "${cert_dir}/rootCA.crt" ]]; then
            chmod 644 "${cert_dir}/rootCA.crt"
        fi
        if [[ -f "${cert_dir}/rootCA.srl" ]]; then
            chmod 644 "${cert_dir}/rootCA.srl"
        fi
    elif [[ "$cert_type" == "server" ]]; then
        # Server certificate permissions
        if [[ -f "${cert_dir}/server.key" ]]; then
            chmod 600 "${cert_dir}/server.key"
        fi
        if [[ -f "${cert_dir}/server.crt" ]]; then
            chmod 644 "${cert_dir}/server.crt"
        fi
        if [[ -f "${cert_dir}/cert-full-chain.pem" ]]; then
            chmod 644 "${cert_dir}/cert-full-chain.pem"
        fi
    fi
}

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

    # Build menu items dynamically
    local menu_items=()
    for base_name in "${found_files[@]}"; do
        menu_items+=("${base_name}.key|${base_name}|")
    done
    menu_items+=("Skip and use Root Keys from certs/|skip|")

    # Show menu and get selection
    local choice
    choice=$(menu_show "" menu_items "back" "")

    case "$choice" in
        skip|"")
            # Empty choice means Back or skip
            SELECTED_ROOT_CA_BASE=""
            return 1  # Skip
            ;;
        *)
            # Selected a file
            SELECTED_ROOT_CA_BASE="$choice"
            return 0
            ;;
    esac
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

    # Set permissions using helper function
    set_cert_permissions "$new_root_ca_dir" "root_ca"

    # Set as active Root CA
    ACTIVE_ROOT_CA_DIR="$new_root_ca_dir"

    print_message "success" "Root Key copied to: ${new_root_ca_dir}"
    return 0
}

# Show menu when no Root Keys exist (New/Export/Back options only)
prompt_root_ca_empty_menu() {
    echo ""
    echo "  === Root Key Selection ==="
    echo "  Root Key signs all server certificates for federation."
    echo "  Choose one below or create a new one."
    echo ""
    echo -e "  ${ORANGE}No Root Keys found${NC}"
    echo "  $MENU_SEPARATOR"
    echo "  N) Create new Root Key    E) Export\\Import    Enter) Back"
    echo ""

    while true; do
        read -rp "Select [N=New, E=Export, Enter=Back]: " choice || true

        if [[ "$choice" == "E" ]] || [[ "$choice" == "e" ]]; then
            clean_screen
            return $MENU_RETURN_EXPORT
        fi

        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back
                return $MENU_RETURN_BACK
                ;;
            1)  # New
                return $MENU_RETURN_NEW
                ;;
            *)
                print_message "error" "Invalid choice"
                ;;
        esac
    done
}

# Show menu when single Root Key is invalid (New/Export/Back options only)
prompt_root_ca_invalid_menu() {
    local root_ca_name="$1"

    print_message "error" "Imported Root Key has no server certificates"
    print_message "info" "The Root Key is incomplete (missing servers/ folder)"
    echo ""
    echo "  === Root Key Selection ==="
    echo -e "  ${ORANGE}1) ${root_ca_name} [Invalid - no server certificates]${NC}"
    echo "  $MENU_SEPARATOR"
    echo "  N) Create new Root Key    E) Export\\Import    Enter) Back"
    echo ""

    while true; do
        read -rp "Select [N=New, E=Export, Enter=Back]: " choice || true

        if [[ "$choice" == "E" ]] || [[ "$choice" == "e" ]]; then
            clean_screen
            return $MENU_RETURN_EXPORT
        fi

        check_menu_choice_type "$choice"
        local choice_type=$?

        case $choice_type in
            0)  # Back
                return $MENU_RETURN_BACK
                ;;
            1)  # New
                return $MENU_RETURN_NEW
                ;;
            *)
                print_message "error" "Invalid choice"
                ;;
        esac
    done
}

prompt_select_root_ca_from_certs() {
    local root_cas=("$@")

    if [[ ${#root_cas[@]} -eq 0 ]]; then
        prompt_root_ca_empty_menu
        return $?
    fi

    # If only one Root Key, check if valid before auto-selecting
    if [[ ${#root_cas[@]} -eq 1 ]]; then
        local root_ca_name="${root_cas[0]}"
        local root_ca_dir="${CERTS_DIR}/${root_ca_name}"

        # Validate imported Root Key has servers
        if is_root_ca_imported "$root_ca_dir"; then
            mapfile -t servers < <(list_servers_with_certs "$root_ca_dir")
            if [[ ${#servers[@]} -eq 0 ]]; then
                # Invalid single Root Key - show menu
                prompt_root_ca_invalid_menu "$root_ca_name"
                return $?
            fi
        fi

        ACTIVE_ROOT_CA_DIR="$root_ca_dir"
        return 0
    fi

    echo ""
    echo "  === Root Key Selection ==="
    echo "  Root Key signs all server certificates for federation."
    echo "  Choose one below or create a new one."
    echo ""

    # Display each Root Key with info, marking invalid ones
    local index=1
    local valid_indices=()
    for root_ca_name in "${root_cas[@]}"; do
        local root_ca_dir="${CERTS_DIR}/${root_ca_name}"
        local is_invalid=false

        # Check if imported Root Key has servers
        if is_root_ca_imported "$root_ca_dir"; then
            mapfile -t servers < <(list_servers_with_certs "$root_ca_dir")
            if [[ ${#servers[@]} -eq 0 ]]; then
                is_invalid=true
            fi
        fi

        # Get the detailed info line and add number prefix
        local info_output
        info_output=$(display_root_ca_info "$root_ca_dir" "detailed")

        if [[ "$is_invalid" == "true" ]]; then
            echo -e "  ${ORANGE}${index}) ${info_output} [Invalid - no server certificates]${NC}"
        else
            echo "  ${index}) ${info_output}"
            valid_indices+=("$index")
        fi
        ((index++))
    done

    echo "  $MENU_SEPARATOR"
    echo "  N) Create new Root Key    E) Export\\Import    Enter) Back"
    echo ""

    while true; do
        read -rp "Select [1-${#root_cas[@]}, N=New, E=Export, Enter=Back]: " choice || true

        # Check for Export option first (before check_menu_choice_type)
        if [[ "$choice" == "E" ]] || [[ "$choice" == "e" ]]; then
            clean_screen
            return $MENU_RETURN_EXPORT
        fi

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
                    local selected_dir="${CERTS_DIR}/${selected_root_ca}"

                    # Validate imported Root Key has servers
                    if is_root_ca_imported "$selected_dir"; then
                        mapfile -t servers < <(list_servers_with_certs "$selected_dir")
                        if [[ ${#servers[@]} -eq 0 ]]; then
                            print_message "error" "Cannot select incomplete imported Root Key"
                            print_message "info" "The Root Key has no server certificates"
                            print_message "info" "Please create a new Root Key or import a complete one"
                            pause
                            continue
                        fi
                    fi

                    ACTIVE_ROOT_CA_DIR="$selected_dir"
                    print_message "success" "Selected Root Key: ${selected_root_ca}"
                    clean_screen
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

    # Generate Root CA certificate with v3_ca extensions
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=${SSL_ORG}" \
        -out rootCA.crt 2>/dev/null

    # Set permissions using helper function
    set_cert_permissions "$new_root_ca_dir" "root_ca"

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
    if [[ ! -f "${root_ca_dir}/rootCA.key" ]]; then
        if [[ -f "${root_ca_dir}/rootCA.crt" ]]; then
            print_message "error" "Cannot generate certificates: Root Key private key is missing."
            print_message "info" "This appears to be an exported Root Key (certificate only)."
            print_message "info" "Use a Full Root Key with the private key to generate new server certificates."
        else
            print_message "error" "Root Key not found in ${root_ca_dir}"
        fi
        return 1
    fi

    if [[ ! -f "${root_ca_dir}/rootCA.crt" ]]; then
        print_message "error" "Root Key certificate not found in ${root_ca_dir}"
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

    # Set permissions using helper function
    set_cert_permissions "$server_cert_dir" "server"

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
        # Clear screen for clean menu display
        clean_screen

        # Display welcome header
        print_welcome_header

        # Build menu items dynamically
        local menu_items=()

        # Check if this is an exported Root CA
        local is_exported_ca=false
        if is_root_ca_imported "$ACTIVE_ROOT_CA_DIR"; then
            is_exported_ca=true
        fi

        # Add generate server certificate item
        if [[ "$is_exported_ca" == "true" ]]; then
            menu_items+=("Generate server certificate|generate||${ORANGE}[Unavailable]${NC}")
        else
            menu_items+=("Generate server certificate|generate|")
        fi

        # Add addon options to menu
        for addon in "${addons[@]}"; do
            local addon_name
            addon_name="$(addon_loader_get_name "$addon")"
            if [[ -n "$addon_name" ]]; then
                # Use addon path as value for identification
                menu_items+=("${addon_name}|${addon}|")
            fi
        done

        # Build options string
        local menu_options="new,export,exit"
        if [[ $num_root_cas -gt 1 ]]; then
            menu_options="switch,${menu_options}"
        fi

        # Display menu
        echo ""
        echo "  === Main Menu ==="
        echo ""

        # Display Root Key info using helper function
        display_root_ca_info "$ACTIVE_ROOT_CA_DIR" "compact"
        echo ""

        # Show menu and get selection
        local choice
        local prompt_text
        if [[ $num_root_cas -gt 1 ]]; then
            prompt_text="Enter your choice (1-${#menu_items[@]}, S=Switch, E=Export\\Import, N=New, 0=Exit): "
        else
            prompt_text="Enter your choice (1-${#menu_items[@]}, E=Export\\Import, N=New, 0=Exit): "
        fi

        # Display items manually since we need custom spacing
        local index=1
        for item in "${menu_items[@]}"; do
            IFS='|' read -r label value color badge <<< "$item"
            local display_line="  $index) ${label}"
            if [[ -n "$color" ]]; then
                display_line="  $index) ${color}${label}${NC}"
            fi
            if [[ -n "$badge" ]]; then
                display_line="${display_line} ${badge}"
            fi
            echo -e "$display_line"
            # Add blank line after first item (Generate server certificate)
            if [[ $index -eq 1 ]]; then
                echo ""
            fi
            ((index++))
        done

        echo ""
        echo "  $MENU_SEPARATOR"

        # Display footer
        if [[ $num_root_cas -gt 1 ]]; then
            echo ""
            echo -e "  ${BLUE}S) Switch${NC}    E) Export\\Import    N) New Root Key    0) Exit"
        else
            echo ""
            echo "  E) Export\\Import    N) New Root Key    0) Exit"
        fi
        echo ""

        read -rp "$prompt_text" choice || true

        # Handle special options first
        if [[ "$choice" == "switch" ]] || [[ "$choice" == "S" ]] || [[ "$choice" == "s" ]]; then
            if [[ $num_root_cas -gt 1 ]]; then
                clean_screen
                local select_result
                prompt_select_root_ca_from_certs "${FOUND_ROOT_CAS[@]}" || select_result=$?
                select_result="${select_result:-0}"
                if [[ $select_result -eq 0 ]]; then
                    print_message "success" "Switched to Root Key: $(basename "$ACTIVE_ROOT_CA_DIR")"
                    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                    num_root_cas=${#FOUND_ROOT_CAS[@]}
                elif [[ $select_result -eq 1 ]]; then
                    create_root_ca_from_menu
                    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
                    num_root_cas=${#FOUND_ROOT_CAS[@]}
                elif [[ $select_result -eq 4 ]]; then
                    export_menu
                fi
            fi
            continue
        fi

        if [[ "$choice" == "E" ]] || [[ "$choice" == "e" ]]; then
            export_menu
            continue
        fi

        if [[ "$choice" == "N" ]] || [[ "$choice" == "n" ]]; then
            create_root_ca_from_menu
            mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
            num_root_cas=${#FOUND_ROOT_CAS[@]}
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            print_message "info" "Exiting..."
            exit 0
        fi

        # Check if numeric
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#menu_items[@]} ]]; then
            local selected_item="${menu_items[$((choice-1))]}"
            IFS='|' read -r label item_value color badge <<< "$selected_item"

            if [[ "$item_value" == "generate" ]]; then
                # Generate server certificate
                echo ""

                if [[ "$is_exported_ca" == "true" ]]; then
                    print_message "info" "Cannot generate new server certificates with an exported Root Key."
                    print_message "info" "This Root Key was exported without the private key for security reasons."
                    echo ""
                    echo "  Imported Root Keys can only:"
                    echo "    - Install addons for existing servers"
                    echo "    - Export certificates for backup/transfer"
                    echo ""
                    echo "  To generate new server certificates, you need:"
                    echo "    - A Full Root Key (with private key)"
                    echo "    - Or create a new Root Key with option N"
                    echo ""
                    pause
                    continue
                fi

                local detected_ip
                detected_ip="$(get_detected_ip)"
                local server_input

                while true; do
                    if [[ -n "$detected_ip" ]]; then
                        server_input="$(prompt_user "Enter server IP address or domain" "$detected_ip")"
                    else
                        server_input="$(prompt_user "Enter server IP address or domain" "")"
                    fi

                    server_input="$(echo "$server_input" | tr -d '[:cntrl:]')"

                    if [[ -n "$server_input" ]]; then
                        break
                    fi
                    echo "Server name cannot be empty. Please try again."
                done

                # Show summary and confirm using print_summary
                local server_type="Domain"
                if is_ip_address "$server_input"; then
                    server_type="IP Address"
                fi

                local summary_sections=()
                summary_sections+=("Root Key|${BLUE}$(basename "$ACTIVE_ROOT_CA_DIR")${NC}")
                summary_sections+=("Server|${server_input}")
                summary_sections+=("Type|${server_type}")
                summary_sections+=("Certificate|${ACTIVE_ROOT_CA_DIR}/servers/${server_input}/")
                summary_sections+=("Validity|${SSL_CERT_DAYS} days")

                set +e
                print_summary "Certificate Summary" summary_sections
                set -e

                if [[ "$(prompt_yes_no "Generate certificate now?" "y")" == "yes" ]]; then
                    SERVER_NAME="$server_input"
                    ssl_manager_generate_server_cert "$SERVER_NAME" || true
                else
                    print_message "info" "Certificate generation cancelled"
                fi
                pause
                continue
            else
                # It's an addon
                set +e
                menu_run_addon "$item_value" || true
                set -e
                pause
                continue
            fi
        else
            print_message "error" "Invalid choice"
        fi
    done
}

menu_without_root_key() {
    while true; do
        echo ""
        print_menu_header "${MATRIX_PLUS_NAME} - Main Menu"
        echo ""
        echo -e "Root Key: ${ORANGE}Not Available${NC}"

        # Define menu items
        local menu_items=(
            "Generate new Root Key|generate|"
            "Export/Import|export_import|"
            "Exit|exit|"
        )

        # Show menu and get selection
        local choice
        choice=$(menu_show "" menu_items "" "Enter your choice (1-3): ")

        case "$choice" in
            generate)
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
            export_import)
                export_menu
                ;;
            exit)
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

    # Use prompt_select_server helper (with create option for addons)
    local selected_server
    selected_server=$(prompt_select_server true "Select server for addon installation")

    # Check if user cancelled or error occurred
    if [[ $? -ne 0 ]] || [[ -z "$selected_server" ]]; then
        return 1
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
# EXPORT MENU
# ===========================================

export_menu() {
    while true; do
        # Clear screen for clean menu display
        clean_screen

        # Define menu items
        local menu_items=(
            "Export Certificate|export|"
            "Import Certificate|import|"
            "Create Portable|portable||${ORANGE}[under development]${NC}"
        )

        # Show menu and get selection
        local choice
        choice=$(menu_show "Export/Import Menu" menu_items "back" "") || true

        # Empty choice means user pressed 0 or Enter for Back
        if [[ -z "$choice" ]]; then
            return 0
        fi

        # Handle the selection
        case "$choice" in
            export)
                export_certificate || true
                ;;
            import)
                import_certificate || true
                ;;
            portable)
                create_portable || true
                ;;
        esac
    done
}

export_certificate() {
    # Check if Root CA is selected
    if [[ -z "$ACTIVE_ROOT_CA_DIR" ]]; then
        print_message "error" "No Root Key selected."
        print_message "info" "Please select a Root Key from the main menu first."
        pause
        return 1
    fi

    # Get list of servers with certificates
    local servers
    mapfile -t servers < <(list_servers_with_certs)

    if [[ ${#servers[@]} -eq 0 ]]; then
        print_message "error" "No server certificates found to export."
        print_message "info" "Generate a server certificate first from the main menu."
        pause
        return 1
    fi

    # Use prompt_select_server helper (no create option for export)
    local selected_server
    selected_server=$(prompt_select_server false "Select server to export")

    # Check if user cancelled
    if [[ $? -ne 0 ]] || [[ -z "$selected_server" ]]; then
        print_message "info" "Export cancelled"
        pause
        return 0
    fi

    local server_dir="${ACTIVE_ROOT_CA_DIR}/servers/${selected_server}"

    # Prompt for destination folder
    echo ""
    local dest_dir
    dest_dir="$(prompt_user "Enter destination folder path" "$HOME/exports")"

    # Clean and validate destination path
    dest_dir="$(echo "$dest_dir" | tr -d '[:cntrl:]')"

    if [[ -z "$dest_dir" ]]; then
        print_message "error" "Destination path cannot be empty"
        pause
        return 1
    fi

    # Determine target directory
    local target_dir="$dest_dir"
    if [[ -d "$dest_dir" ]] && [[ -n "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
        # Directory exists and is not empty, create subfolder
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        target_dir="${dest_dir}/${selected_server}_${timestamp}"
    fi

    # Show summary using print_summary with tree structure
    local summary_sections=()

    # Build tree structure with proper line breaks
    local tree_root="${target_dir}/"
    local tree_line1="+-- servers/"
    local tree_line2="|   \`-- ${selected_server}/"
    local tree_line3="|       +-- server.key"
    local tree_line4="|       +-- server.crt"
    local tree_line5="|       \`-- cert-full-chain.pem"
    local tree_line6="\`-- rootCA.crt"

    # Combine tree lines with | separator for parsing
    local tree_structure="${tree_root}|${tree_line1}|${tree_line2}|${tree_line3}|${tree_line4}|${tree_line5}|${tree_line6}"

    summary_sections+=("Server certificate folder|${server_dir}/")
    summary_sections+=("Root CA certificate|${ACTIVE_ROOT_CA_DIR}/rootCA.crt")
    summary_sections+=("Target directory|${target_dir}/")
    summary_sections+=("Export structure|$tree_structure")

    print_summary "Export Summary" summary_sections

    if [[ "$(prompt_yes_no "Proceed with export?" "y")" != "yes" ]]; then
        print_message "info" "Export cancelled"
        pause
        return 0
    fi

    # Create target directory structure
    mkdir -p "${target_dir}/servers"

    # Copy server folder
    if ! cp -r "$server_dir" "${target_dir}/servers/${selected_server}"; then
        print_message "error" "Failed to copy server certificate folder"
        pause
        return 1
    fi

    # Copy Root CA certificate
    if ! cp "${ACTIVE_ROOT_CA_DIR}/rootCA.crt" "${target_dir}/rootCA.crt"; then
        print_message "error" "Failed to copy Root CA certificate"
        pause
        return 1
    fi

    # Set appropriate permissions using helper function
    set_cert_permissions "${target_dir}/servers/${selected_server}" "server"
    set_cert_permissions "${target_dir}" "root_ca"

    print_message "success" "Export completed successfully!"
    echo ""
    echo "  Exported files are in:"
    echo "    ${target_dir}/"
    echo ""

    pause
}

import_certificate() {
    local source_dir
    local root_ca_cert
    local servers_dir
    local found_servers=()

    # Loop until valid input is provided
    while true; do
        # Prompt for source folder path
        echo ""
        source_dir="$(prompt_user "Enter path to exported certificate folder (press Enter to cancel)" "")"

        # Clean input (remove control characters and trailing slash)
        source_dir="$(echo "$source_dir" | tr -d '[:cntrl:]')"
        source_dir="${source_dir%/}"  # Remove trailing slash if present

        if [[ -z "$source_dir" ]]; then
            print_message "info" "Import cancelled"
            return 0
        fi

        # Validate source folder exists
        if [[ ! -d "$source_dir" ]]; then
            print_message "error" "Source folder does not exist: $source_dir"
            continue
        fi

        # Validate exported folder structure
        root_ca_cert="${source_dir}/rootCA.crt"
        servers_dir="${source_dir}/servers"

        if [[ ! -f "$root_ca_cert" ]]; then
            print_message "error" "Invalid export folder: rootCA.crt not found"
            print_message "info" "Expected structure: <folder>/rootCA.crt"
            continue
        fi

        if [[ ! -d "$servers_dir" ]]; then
            print_message "error" "Invalid export folder: servers/ directory not found"
            print_message "info" "Expected structure: <folder>/servers/"
            continue
        fi

        # Check for at least one server folder with certificates
        found_servers=()
        for server_dir in "${servers_dir}"/*/; do
            if [[ -d "$server_dir" ]]; then
                if [[ -f "${server_dir}/server.key" ]] && \
                   [[ -f "${server_dir}/server.crt" ]] && \
                   [[ -f "${server_dir}/cert-full-chain.pem" ]]; then
                    found_servers+=("$(basename "$server_dir")")
                fi
            fi
        done

        if [[ ${#found_servers[@]} -eq 0 ]]; then
            print_message "error" "Invalid export folder: no valid server certificates found"
            print_message "info" "Expected: servers/<server>/server.key, server.crt, cert-full-chain.pem"
            continue
        fi

        # All validations passed, break the loop
        break
    done

    # Check if rootCA.key exists (Full Root CA)
    local has_root_ca_key=false
    if [[ -f "${source_dir}/rootCA.key" ]]; then
        has_root_ca_key=true
    fi

    # Prompt for Root CA folder name with smart suggestion
    local suggested_name
    suggested_name="$(basename "$source_dir")"
    local root_ca_name=""
    while true; do
        root_ca_name="$(prompt_user "Enter Root CA folder name" "$suggested_name")"
        root_ca_name="$(echo "$root_ca_name" | tr -d '[:cntrl:]')"
        if [[ -n "$root_ca_name" ]]; then
            break
        fi
        echo "Root CA name cannot be empty."
    done

    # Check if destination already exists
    local target_dir="${CERTS_DIR}/${root_ca_name}"
    while [[ -d "$target_dir" ]]; do
        print_message "warning" "Directory ${root_ca_name} already exists in certs/"
        root_ca_name=""
        while true; do
            root_ca_name="$(prompt_user "Enter a different Root CA folder name" "")"
            root_ca_name="$(echo "$root_ca_name" | tr -d '[:cntrl:]')"
            if [[ -n "$root_ca_name" ]]; then
                break
            fi
            echo "Root CA name cannot be empty."
        done
        target_dir="${CERTS_DIR}/${root_ca_name}"
    done

    # Show import summary using print_summary
    # Shorten source path for display
    local source_display="$source_dir"
    if [[ ${#source_display} -gt 50 ]]; then
        source_display="...${source_display: -47}"
    fi

    # Determine Root CA type display
    local root_ca_type=""
    if [[ "$has_root_ca_key" == "true" ]]; then
        root_ca_type="${GREEN}Full${NC} (with private key)"
    else
        root_ca_type="${ORANGE}Imported${NC} (certificate only)"
    fi

    local summary_sections=()

    # Add basic info
    summary_sections+=("Source|${source_display}/")
    summary_sections+=("Target|certs/$(basename "$target_dir")/")

    # Add Root CA info with tree structure
    local ca_cert_line="+- Certificate: [+] Present"
    local ca_key_line="\`- Private Key: "
    if [[ "$has_root_ca_key" == "true" ]]; then
        ca_key_line+="[+] Present"
    else
        ca_key_line+="[-] Normal"
    fi
    summary_sections+=("Root CA|$root_ca_type|${ca_cert_line}|${ca_key_line}")

    # Add servers with tree structure (build dynamically)
    if [[ ${#found_servers[@]} -gt 0 ]]; then
        local server_tree="|  |"
        for i in "${!found_servers[@]}"; do
            local server="${found_servers[$i]}"
            if [[ $i -eq $((${#found_servers[@]} - 1)) ]] && [[ ${#found_servers[@]} -gt 1 ]]; then
                server_tree+="|  \`-- ${server}|"
            elif [[ ${#found_servers[@]} -eq 1 ]]; then
                server_tree+="|  \`-- ${server}|"
            else
                server_tree+="|  +-- ${server}|"
            fi
        done
        summary_sections+=("Servers (${#found_servers[@]})|$server_tree")
    fi

    print_summary "Import Summary" summary_sections

    if [[ "$(prompt_yes_no "Proceed with import?" "y")" != "yes" ]]; then
        print_message "info" "Import cancelled"
        pause
        return 0
    fi

    # Create target directory
    mkdir -p "$target_dir"

    # Copy Root CA certificate
    if ! cp "$root_ca_cert" "${target_dir}/rootCA.crt"; then
        print_message "error" "Failed to copy Root CA certificate"
        pause
        return 1
    fi

    # Copy Root CA private key if exists
    if [[ "$has_root_ca_key" == "true" ]]; then
        if ! cp "${source_dir}/rootCA.key" "${target_dir}/rootCA.key"; then
            print_message "error" "Failed to copy Root CA private key"
            pause
            return 1
        fi
    fi

    # Copy servers folder
    if ! cp -r "$servers_dir" "${target_dir}/servers"; then
        print_message "error" "Failed to copy servers folder"
        pause
        return 1
    fi

    # Set appropriate permissions using helper function
    set_cert_permissions "$target_dir" "root_ca"

    # Set permissions on server files
    for server in "${found_servers[@]}"; do
        set_cert_permissions "${target_dir}/servers/${server}" "server"
    done

    echo ""
    echo ""

    # Build success summary
    local target_display="$target_dir"
    if [[ ${#target_display} -gt 50 ]]; then
        target_display="...${target_display: -47}"
    fi

    local success_sections=()

    # Add location
    success_sections+=("Location|${target_display}/")

    # Add Root CA info
    local ca_info_text="$root_ca_type"
    if [[ "$has_root_ca_key" == "true" ]]; then
        ca_info_text+="|New server certificates can be generated"
    else
        ca_info_text+="|Existing server certificates can be used"
    fi
    success_sections+=("Root CA|$ca_info_text")

    # Add servers with tree structure
    if [[ ${#found_servers[@]} -gt 0 ]]; then
        local server_tree="|"
        for i in "${!found_servers[@]}"; do
            local server="${found_servers[$i]}"
            if [[ $i -eq $((${#found_servers[@]} - 1)) ]] && [[ ${#found_servers[@]} -gt 1 ]]; then
                server_tree+="|\`-- ${server}|"
            elif [[ ${#found_servers[@]} -eq 1 ]]; then
                server_tree+="|\`-- ${server}|"
            else
                server_tree+="|+-- ${server}|"
            fi
        done
        success_sections+=("Servers (${#found_servers[@]})|$server_tree")
    fi

    print_summary "${GREEN}✓ Import Completed Successfully${NC}" success_sections

    pause

    # Set the imported Root CA as active and go to main menu
    ACTIVE_ROOT_CA_DIR="$target_dir"
    menu_with_root_key
}

create_portable() {
    print_message "info" "Portable export feature is coming soon."
    print_message "info" "This will create a self-contained archive with all necessary files."
}

# ===========================================
# INITIALIZATION FUNCTION
# ===========================================

initialize() {
    # Initialize log FIRST (before any print_message calls)
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "${MATRIX_PLUS_NAME} Log - $(date)" > "$LOG_FILE"

    # Detect and load OS module if directory exists
    if [[ -d "$OS_DIR" ]]; then
        detect_os_module || true
    fi

    # If no OS module detected, fall back to built-in detection
    if [[ -z "$ACTIVE_OS_MODULE" ]]; then
        detect_os || true
    fi

    # Check for required dependencies
    if check_dependencies; then
        local deps_status=0
    else
        local deps_status=$?
    fi

    # Print welcome header
    print_welcome_header

    # Check dependencies and prompt to install if missing
    if [[ $deps_status -ne 0 ]]; then
        prompt_install_dependencies
    fi

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

    # Step 2: Discover Root CAs in certs/ and show selection menu
    mapfile -t FOUND_ROOT_CAS < <(list_root_cas)

    # Always show selection menu (handles empty list internally)
    if [[ -z "$ACTIVE_ROOT_CA_DIR" ]]; then
        local select_result
        prompt_select_root_ca_from_certs "${FOUND_ROOT_CAS[@]}" || select_result=$?
        select_result="${select_result:-0}"
        if [[ $select_result -eq 1 ]]; then
            # User chose to create new Root Key
            create_root_ca_from_menu
            mapfile -t FOUND_ROOT_CAS < <(list_root_cas)
        elif [[ $select_result -eq 4 ]]; then
            # User chose to Export/Import
            export_menu
        elif [[ $select_result -eq 3 ]]; then
            # User pressed Back - no Root Key selected, exit
            print_message "info" "No Root Key selected. Exiting."
            exit 0
        fi
    fi

    # Only show main menu if we have an active Root CA
    if [[ -n "$ACTIVE_ROOT_CA_DIR" ]]; then
        menu_with_root_key
    else
        print_message "info" "No Root Key available. Exiting."
        exit 0
    fi
}

# ===========================================
# SCRIPT ENTRY POINT
# ===========================================
main "$@"
