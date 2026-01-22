# پلن پیاده‌سازی اسکریپت نصب خودکار Matrix Ansible Playbook
## فایل: install.sh

این سند یک راهنمای کامل و مرحله به مرحله برای پیاده‌سازی اسکریپت نصب خودکار Matrix Ansible Playbook است.

---

## فهرست مطالب

1. [نمای کلی](#نمای-کلی)
2. [ساختار فایل](#ساختار-فایل)
3. [متغیرهای تنظیمات](#متغیرهای-تنظیمات)
4. [توابع کمکی](#توابع-کمکی)
5. [تابع اصلی](#تابع-اصلی)
6. [جریان اجرا](#جریان-اجرای-اسکریپت)
7. [کد کامل](#کد-کامل-اسکریپت)

---

## نمای کلی

### هدف
ساخت یک اسکریپت Shell که فرآیند نصب Matrix Synapse با استفاده از Ansible Playbook را خودکار کند.

### مسیر فایل
```
/home/amir/Works/Startup/Matrix/matrix-second/script/install.sh
```

### قابلیت‌های اصلی
1. تشخیص سیستم‌عامل (Linux, macOS, Windows/WSL)
2. نصب Ansible بر اساس سیستم‌عامل
3. پشتیبانی از دو حالت نصب:
   - **This Is Server**: نصب روی همین سرور (ansible_connection=local)
   - **Remote VPS**: نصب روی سرور از راه دور (از طریق SSH)
4. ساخت self-signed SSL certificates
5. تولید پسوردهای قوی
6. تنظیم فایل‌های inventory و vars.yml
7. اجرای playbook
8. ساخت کاربر ادمین

---

## ساختار فایل

### هدر اسکریپت
```bash
#!/bin/bash

# Matrix Ansible Playbook Auto-Installer
# Version: 1.0.0
# Description: Automated installation script for Matrix Synapse using Ansible

set -e  # Exit on error
set -u  # Exit on undefined variable
```

### بخش ۱: تنظیمات قابل تغییر (بالاترین بخش فایل)

تمام تنظیمات که کاربر ممکن است بخواهد تغییر دهد باید در بالای فایل باشند:

```bash
# ===========================================
# CONFIGURATION SECTION
# All user-modifiable settings are here
# ===========================================

# Path configuration (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLAYBOOK_DIR="${PROJECT_DIR}/matrix-docker-ansible-deploy"
CA_DIR="${PROJECT_DIR}/matrix-ca"
LOG_FILE="${SCRIPT_DIR}/install.log"

# Default configuration values
DEFAULT_HOMESERVER_IMPL="synapse"
DEFAULT_IPV6_ENABLED="true"
DEFAULT_ELEMENT_ENABLED="true"
DEFAULT_SSH_USER="admin"
DEFAULT_SSH_PORT="22"

# SSL Certificate settings
SSL_COUNTRY="IR"
SSL_STATE="Tehran"
SSL_CITY="Tehran"
SSL_ORG="MatrixCA"
SSL_OU="IT"
SSL_CERT_DAYS=365
SSL_CA_DAYS=3650

# Ansible settings
ANSIBLE_MIN_VERSION="2.15.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
```

---

## متغیرهای سراسری (Global Variables)

متغیرهایی که در طول اجرای اسکریپت استفاده می‌شوند:

```bash
# Runtime variables (set during execution)
OS_TYPE=""              # linux, darwin, windows
OS_DISTRO=""            # ubuntu, debian, arch, manjaro, centos, etc.
HAS_ANSIBLE=false       # true if ansible is installed
HAS_GIT=false           # true if git is installed
HAS_PYTHON=false        # true if python3 is installed
HAS_DOCKER=false        # true if docker is installed

# User inputs
INSTALLATION_MODE=""    # "local" or "remote"
SERVER_IP=""            # IP address or domain
SERVER_USER=""          # SSH username
SERVER_PORT=""          # SSH port
USE_SSH_KEY=""          # "yes" or "no"
SSH_KEY_PATH=""         # Path to SSH key

# Generated values
MATRIX_SECRET=""        # Generated secret key
POSTGRES_PASSWORD=""    # Generated postgres password
ADMIN_USERNAME=""       # Admin username
ADMIN_PASSWORD=""       # Admin password

# Paths
HOST_VARS_DIR=""        # Path to host_vars directory
VARS_YML_PATH=""        # Path to vars.yml
INVENTORY_PATH=""       # Path to inventory/hosts
```

---

## توابع کمکی

### تابع ۱: نمایش پیام‌های رنگی

```bash
# ===========================================
# FUNCTION: print_message
# Description: Print colored messages to stdout
# Arguments:
#   $1 - Message type: info, success, warning, error
#   $2 - Message content
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

    # Also log to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$msg_type] $message" >> "$LOG_FILE"
}
```

### تابع ۲: تشخیص سیستم‌عامل

```bash
# ===========================================
# FUNCTION: detect_os
# Description: Detect the operating system
# Sets global variables: OS_TYPE, OS_DISTRO
# ===========================================
detect_os() {
    print_message "info" "Detecting operating system..."

    # Detect if running on Windows (MSYS/MinGW/Cygwin/WSL)
    if [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] || [[ -n "${CYGWIN_PREFIX:-}" ]]; then
        OS_TYPE="windows"
        print_message "info" "Detected: Windows (MSYS/MinGW/Cygwin)"
        return 0
    fi

    # Check if WSL
    if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
        OS_TYPE="wsl"
        print_message "info" "Detected: Windows Subsystem for Linux (WSL)"
        return 0
    fi

    # Detect Unix-like systems
    local uname_str
    uname_str="$(uname)"

    case "$uname_str" in
        Linux*)
            OS_TYPE="linux"
            # Detect Linux distribution
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
```

### تابع ۳: چک کردن پیش‌نیازها

```bash
# ===========================================
# FUNCTION: check_prerequisites
# Description: Check if required tools are installed
# Sets global variables: HAS_ANSIBLE, HAS_GIT, HAS_PYTHON, HAS_DOCKER
# ===========================================
check_prerequisites() {
    print_message "info" "Checking prerequisites..."

    # Check Ansible
    if command -v ansible &> /dev/null; then
        HAS_ANSIBLE=true
        local ansible_version
        ansible_version="$(ansible --version 2>&1 | head -n1 | awk '{print $2}')"
        print_message "success" "Ansible is installed: $ansible_version"
    else
        HAS_ANSIBLE=false
        print_message "warning" "Ansible is not installed"
    fi

    # Check Git
    if command -v git &> /dev/null; then
        HAS_GIT=true
        print_message "success" "Git is installed"
    else
        HAS_GIT=false
        print_message "warning" "Git is not installed"
    fi

    # Check Python
    if command -v python3 &> /dev/null; then
        HAS_PYTHON=true
        print_message "success" "Python3 is installed"
    else
        HAS_PYTHON=false
        print_message "warning" "Python3 is not installed"
    fi

    # Check Docker (only for local installation)
    if [[ "$INSTALLATION_MODE" == "local" ]]; then
        if command -v docker &> /dev/null; then
            HAS_DOCKER=true
            print_message "success" "Docker is installed"
        else
            HAS_DOCKER=false
            print_message "warning" "Docker is not installed (will be installed by playbook)"
        fi
    fi

    return 0
}
```

### تابع ۴: نصب Ansible بر اساس سیستم‌عامل

```bash
# ===========================================
# FUNCTION: install_ansible
# Description: Install Ansible based on detected OS
# ===========================================
install_ansible() {
    if [[ "$HAS_ANSIBLE" == true ]]; then
        print_message "info" "Ansible is already installed, skipping..."
        return 0
    fi

    print_message "info" "Installing Ansible..."

    case "$OS_TYPE" in
        windows|wsl)
            # For Windows/WSL, use pip
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
                    print_message "info" "Please install Ansible manually: https://docs.ansible.com/ansible/latest/installation_guide/index.html"
                    return 1
                    ;;
            esac
            ;;

        darwin)
            # For macOS, use Homebrew
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

    # Verify installation
    if command -v ansible &> /dev/null; then
        print_message "success" "Ansible has been installed successfully"
        HAS_ANSIBLE=true
        return 0
    else
        print_message "error" "Failed to install Ansible"
        return 1
    fi
}
```

### تابع ۵: تولید پسورد قوی

```bash
# ===========================================
# FUNCTION: generate_password
# Description: Generate a strong random password
# Arguments:
#   $1 - Length of password (default: 32)
# Output: Generated password
# ===========================================
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}
```

### تابع ۶: ساخت SSL Certificate

```bash
# ===========================================
# FUNCTION: create_ssl_certificates
# Description: Create self-signed SSL certificates for the server
# Arguments:
#   $1 - Server IP address or domain
# Sets global variables: SSL_KEY_PATH, SSL_CERT_PATH
# ===========================================
create_ssl_certificates() {
    local server_ip="$1"

    print_message "info" "Creating self-signed SSL certificates..."

    # Create CA directory
    mkdir -p "$CA_DIR"
    cd "$CA_DIR" || return 1

    # 1. Generate Root CA private key
    print_message "info" "Generating Root CA private key..."
    openssl genrsa -out rootCA.key 4096 2>/dev/null

    # 2. Generate Root CA certificate
    print_message "info" "Generating Root CA certificate..."
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days "$SSL_CA_DAYS" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/OU=${SSL_OU}/CN=Matrix Root CA" \
        -out rootCA.crt 2>/dev/null

    # 3. Generate Server private key
    print_message "info" "Generating Server private key..."
    openssl genrsa -out "server-${server_ip}.key" 4096 2>/dev/null

    # 4. Generate CSR (Certificate Signing Request)
    print_message "info" "Generating Certificate Signing Request..."
    openssl req -new -key "server-${server_ip}.key" -out "server-${server_ip}.csr" \
        -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=Matrix/OU=Server/CN=${server_ip}" \
        2>/dev/null

    # 5. Create config file for Subject Alternative Names (SAN)
    print_message "info" "Creating SAN configuration..."
    cat > "server-${server_ip}.cnf" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
DNS.2 = localhost
IP.1 = ${server_ip}
IP.2 = 127.0.0.1
EOF

    # 6. Sign the certificate with Root CA
    print_message "info" "Signing certificate with Root CA..."
    openssl x509 -req -in "server-${server_ip}.csr" -CA rootCA.crt -CAkey rootCA.key \
        -CAcreateserial -out "server-${server_ip}.crt" -days "$SSL_CERT_DAYS" -sha256 \
        -extfile "server-${server_ip}.cnf" 2>/dev/null

    # 7. Create full-chain certificate
    print_message "info" "Creating full-chain certificate..."
    cat "server-${server_ip}.crt" rootCA.crt > cert-full-chain.pem

    # Set global variables for SSL paths
    SSL_KEY_PATH="${CA_DIR}/server-${server_ip}.key"
    SSL_CERT_PATH="${CA_DIR}/cert-full-chain.pem"
    SSL_CA_PATH="${CA_DIR}/rootCA.crt"

    print_message "success" "SSL certificates created successfully"
    print_message "info" "  - Private key: $SSL_KEY_PATH"
    print_message "info" "  - Certificate: $SSL_CERT_PATH"
    print_message "info" "  - Root CA: $SSL_CA_PATH"

    return 0
}
```

### تابع ۷: تنظیم Inventory

```bash
# ===========================================
# FUNCTION: configure_inventory
# Description: Create or update the inventory/hosts file
# Arguments:
#   $1 - Server IP address
#   $2 - Installation mode: "local" or "remote"
# ===========================================
configure_inventory() {
    local server_ip="$1"
    local mode="$2"

    print_message "info" "Configuring inventory..."

    local inventory_file="${PLAYBOOK_DIR}/inventory/hosts"
    local inventory_dir
    inventory_dir="$(dirname "$inventory_file")"

    # Create inventory directory if it doesn't exist
    mkdir -p "$inventory_dir"

    # Create hosts file
    if [[ "$mode" == "local" ]]; then
        # Local installation (ansible_connection=local)
        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by install.sh on $(date)

[matrix_servers]
${server_ip} ansible_connection=local
EOF
        print_message "success" "Inventory configured for local installation"
    else
        # Remote installation (SSH)
        local ansible_user="${SERVER_USER:-$DEFAULT_SSH_USER}"
        cat > "$inventory_file" <<EOF
# Matrix Ansible Playbook Inventory
# Generated by install.sh on $(date)

[matrix_servers]
${server_ip} ansible_host=${server_ip} ansible_ssh_user=${ansible_user} ansible_become=true ansible_become_user=root
EOF
        print_message "success" "Inventory configured for remote installation"
        print_message "info" "  - Server: $server_ip"
        print_message "info" "  - SSH User: $ansible_user"
    fi

    INVENTORY_PATH="$inventory_file"
    return 0
}
```

### تابع ۸: تنظیم vars.yml

```bash
# ===========================================
# FUNCTION: configure_vars_yml
# Description: Create the vars.yml configuration file
# Arguments:
#   $1 - Server IP address
#   $2 - Enable IPv6: "true" or "false"
#   $3 - Enable Element: "true" or "false"
# ===========================================
configure_vars_yml() {
    local server_ip="$1"
    local ipv6_enabled="$2"
    local element_enabled="$3"

    print_message "info" "Configuring vars.yml..."

    # Create host_vars directory
    HOST_VARS_DIR="${PLAYBOOK_DIR}/inventory/host_vars/${server_ip}"
    mkdir -p "$HOST_VARS_DIR"

    VARS_YML_PATH="${HOST_VARS_DIR}/vars.yml"

    # Generate secrets if not already generated
    if [[ -z "$MATRIX_SECRET" ]]; then
        MATRIX_SECRET="$(generate_password 64)"
    fi
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD="$(generate_password 32)"
    fi

    # Create vars.yml file
    cat > "$VARS_YML_PATH" <<EOF
# ===========================================
# Matrix Ansible Playbook Configuration
# Generated by install.sh on $(date)
# ===========================================

# -------------------------------------------
# Basic Settings
# -------------------------------------------

# The bare domain name which represents your Matrix identity
matrix_domain: "${server_ip}"

# The Matrix server FQN
matrix_server_fqn_matrix: "${server_ip}"

# Homeserver implementation (synapse, dendrite, conduit, conduwuit, continuwuity)
matrix_homeserver_implementation: "${DEFAULT_HOMESERVER_IMPL}"

# A secret key used for generating various other secrets
matrix_homeserver_generic_secret_key: '${MATRIX_SECRET}'

# Reverse proxy type
matrix_playbook_reverse_proxy_type: playbook-managed-traefik

# IPv6 support
devture_systemd_docker_base_ipv6_enabled: ${ipv6_enabled}

# Postgres password
postgres_connection_password: '${POSTGRES_PASSWORD}'

# -------------------------------------------
# Element Web Client
# -------------------------------------------

matrix_client_element_enabled: ${element_enabled}
matrix_server_fqn_element: "${server_ip}"

# Important: Disable redirect when using IP instead of domain
matrix_synapse_container_labels_public_client_root_enabled: false

# -------------------------------------------
# SSL/TLS Configuration (Self-signed)
# -------------------------------------------

# Disable ACME/Let's Encrypt
traefik_config_certificatesResolvers_acme_enabled: false

# Enable SSL directory
traefik_ssl_dir_enabled: true

# TLS configuration for Traefik
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

# -------------------------------------------
# SSL Files
# -------------------------------------------

aux_file_definitions:
  # Private key
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: ${SSL_KEY_PATH}
    mode: "0600"

  # Full chain certificate (server cert + root CA)
  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: ${SSL_CERT_PATH}
    mode: "0644"
EOF

    print_message "success" "vars.yml created successfully"
    print_message "info" "  - Location: $VARS_YML_PATH"

    return 0
}
```

### تابع ۹: ساخت فولدرهای Traefik (Workaround)

```bash
# ===========================================
# FUNCTION: create_traefik_directories
# Description: Create Traefik directories manually (workaround for playbook bug)
# Arguments:
#   $1 - Installation mode: "local" or "remote"
# ===========================================
create_traefik_directories() {
    local mode="$1"

    print_message "info" "Creating Traefik directories (workaround for playbook bug)..."

    if [[ "$mode" == "local" ]]; then
        # Create directories locally
        sudo mkdir -p /matrix/traefik/ssl
        sudo mkdir -p /matrix/traefik/config
        sudo chown -R matrix:matrix /matrix/ 2>/dev/null || true
        print_message "success" "Traefik directories created locally"
    else
        # Create directories on remote server using ansible ad-hoc command
        cd "$PLAYBOOK_DIR"

        ansible -i inventory/hosts all -m shell -a "mkdir -p /matrix/traefik/ssl /matrix/traefik/config" --become 2>/dev/null || {
            print_message "warning" "Failed to create directories via ansible, continuing anyway..."
        }

        ansible -i inventory/hosts all -m shell -a "chown -R matrix:matrix /matrix/ || true" --become 2>/dev/null || {
            print_message "warning" "Failed to set ownership, continuing anyway..."
        }

        print_message "success" "Traefik directories created on remote server"
    fi

    return 0
}
```

### تابع ۱۰: نصب Ansible Roles

```bash
# ===========================================
# FUNCTION: install_ansible_roles
# Description: Install Ansible roles from requirements.yml
# ===========================================
install_ansible_roles() {
    print_message "info" "Installing Ansible roles..."

    cd "$PLAYBOOK_DIR" || return 1

    if ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force >> "$LOG_FILE" 2>&1; then
        print_message "success" "Ansible roles installed successfully"
        return 0
    else
        print_message "error" "Failed to install Ansible roles"
        print_message "info" "Check log file for details: $LOG_FILE"
        return 1
    fi
}
```

### تابع ۱۱: اجرای Playbook

```bash
# ===========================================
# FUNCTION: run_playbook
# Description: Run the Ansible playbook for installation
# Arguments:
#   $1 - Tags to run (default: install-all,ensure-matrix-users-created,start)
# ===========================================
run_playbook() {
    local tags="${1:-install-all,ensure-matrix-users-created,start}"

    print_message "info" "Running Ansible playbook..."
    print_message "warning" "This may take 10-20 minutes, please be patient..."

    cd "$PLAYBOOK_DIR" || return 1

    # Set locale for consistent output
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    # Run playbook
    if ansible-playbook -i inventory/hosts setup.yml --tags="$tags" >> "$LOG_FILE" 2>&1; then
        print_message "success" "Playbook executed successfully"
        return 0
    else
        print_message "error" "Playbook execution failed"
        print_message "info" "Check log file for details: $LOG_FILE"
        return 1
    fi
}
```

### تابع ۱۲: ساخت کاربر ادمین

```bash
# ===========================================
# FUNCTION: create_admin_user
# Description: Create the admin user for Matrix
# Arguments:
#   $1 - Username
#   $2 - Password
# ===========================================
create_admin_user() {
    local username="$1"
    local password="$2"

    print_message "info" "Creating admin user..."

    cd "$PLAYBOOK_DIR" || return 1

    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    if ansible-playbook -i inventory/hosts setup.yml \
        --extra-vars="username=${username} password=${password} admin=yes" \
        --tags=register-user >> "$LOG_FILE" 2>&1; then
        print_message "success" "Admin user created successfully"
        print_message "info" "  - Username: $username"
        return 0
    else
        print_message "error" "Failed to create admin user"
        print_message "info" "You can create it manually later"
        return 1
    fi
}
```

### تابع ۱۳: خواندن ورودی از کاربر

```bash
# ===========================================
# FUNCTION: prompt_user
# Description: Prompt user for input with a default value
# Arguments:
#   $1 - Prompt message
#   $2 - Default value (optional)
# Output: User input or default value
# ===========================================
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

# ===========================================
# FUNCTION: prompt_yes_no
# Description: Prompt user for yes/no confirmation
# Arguments:
#   $1 - Prompt message
#   $2 - Default value: "y" or "n" (default: "n")
# Output: "yes" or "no"
# ===========================================
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    local default_str=""
    if [[ "$default" == "y" ]]; then
        default_str="Y/n"
    else
        default_str="y/N"
    fi

    while true; do
        read -rp "$prompt [$default_str]: " answer

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
```

### تابع ۱۴: نمایش خلاصه نصب

```bash
# ===========================================
# FUNCTION: print_summary
# Description: Print installation summary
# ===========================================
print_summary() {
    cat <<EOF

${GREEN}========================================
MATRIX INSTALLATION COMPLETE
========================================${NC}

${BLUE}Server Information:${NC}
  - IP/Domain: ${SERVER_IP}
  - Installation Mode: ${INSTALLATION_MODE}

${BLUE}Admin User:${NC}
  - Username: ${ADMIN_USERNAME}
  - Password: ${ADMIN_PASSWORD}

${BLUE}Access URLs:${NC}
  - Matrix API: https://${SERVER_IP}/_matrix/client/versions
  - Element Web: https://${SERVER_IP}/

${BLUE}Important Files:${NC}
  - Vars YAML: ${VARS_YML_PATH}
  - Inventory: ${INVENTORY_PATH}
  - SSL Cert: ${SSL_CERT_PATH}
  - Root CA: ${SSL_CA_PATH}

${BLUE}SSL Certificate:${NC}
  To trust the self-signed certificate in your browser:
  1. Open: chrome://settings/certificates (Chrome/Edge)
  2. Go to "Authorities" tab
  3. Import: ${SSL_CA_PATH}

${BLUE}Next Steps:${NC}
  1. Import the Root CA certificate into your browser
  2. Access https://${SERVER_IP}/ in your browser
  3. Log in with your admin credentials

${YELLOW}Note:${NC} Save this information securely!
      The Root CA certificate is required for
      federation between servers.

${GREEN}========================================${NC}

Log file: $LOG_FILE

EOF
}
```

---

## تابع اصلی (main)

```bash
# ===========================================
# FUNCTION: main
# Description: Main execution flow
# ===========================================
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Matrix Ansible Playbook Installation Log - $(date)" > "$LOG_FILE"

    # Print banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     Matrix Ansible Playbook Auto-Installer v1.0.0       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # ============================================
    # PHASE 1: Environment Detection
    # ============================================
    print_message "info" "=== PHASE 1: Environment Detection ==="

    detect_os || exit 1
    check_prerequisites

    # ============================================
    # PHASE 2: Install Prerequisites
    # ============================================
    print_message "info" "=== PHASE 2: Install Prerequisites ==="

    if [[ "$HAS_ANSIBLE" == false ]]; then
        print_message "warning" "Ansible is not installed"
        if [[ "$(prompt_yes_no "Install Ansible now?" "y")" == "yes" ]]; then
            install_ansible || exit 1
        else
            print_message "error" "Ansible is required to continue"
            exit 1
        fi
    fi

    # ============================================
    # PHASE 3: Installation Mode Selection
    # ============================================
    print_message "info" "=== PHASE 3: Installation Mode ==="

    cat <<'EOF'

Select installation mode:

  1) This Is Server
     - Install Matrix on THIS machine
     - Ansible will run locally (ansible_connection=local)

  2) Remote VPS
     - Install Matrix on a remote server via SSH
     - You need SSH access to the server

EOF

    while true; do
        read -rp "Enter your choice (1 or 2): " choice

        case "$choice" in
            1)
                INSTALLATION_MODE="local"
                # Detect server IP
                SERVER_IP="$(hostname -I | awk '{print $1}')"
                if [[ -z "$SERVER_IP" ]]; then
                    SERVER_IP="$(prompt_user "Enter server IP address")"
                fi
                print_message "info" "Local installation mode selected"
                print_message "info" "Server IP: $SERVER_IP"
                break
                ;;
            2)
                INSTALLATION_MODE="remote"
                print_message "info" "Remote installation mode selected"

                # Get server details
                SERVER_IP="$(prompt_user "Enter server IP address or domain")"
                SERVER_USER="$(prompt_user "SSH username" "$DEFAULT_SSH_USER")"
                print_message "info" "Target server: ${SERVER_USER}@${SERVER_IP}"
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

    # ============================================
    # PHASE 4: Configuration Questions
    # ============================================
    print_message "info" "=== PHASE 4: Configuration ==="

    # IPv6
    ipv6_answer="$(prompt_yes_no "Enable IPv6 support?" "$DEFAULT_IPV6_ENABLED")"
    IPV6_ENABLED="$([ "$ipv6_answer" == "yes" ] && echo "true" || echo "false")"

    # Element Web
    element_answer="$(prompt_yes_no "Enable Element Web?" "$DEFAULT_ELEMENT_ENABLED")"
    ELEMENT_ENABLED="$([ "$element_answer" == "yes" ] && echo "true" || echo "false")"

    # Admin user
    echo ""
    print_message "info" "Create admin user:"
    ADMIN_USERNAME="$(prompt_user "Username" "admin")"
    ADMIN_PASSWORD="$(prompt_user "Password" "$(generate_password 16)")"

    print_message "info" "Configuration summary:"
    print_message "info" "  - IPv6: $IPV6_ENABLED"
    print_message "info" "  - Element Web: $ELEMENT_ENABLED"
    print_message "info" "  - Admin User: $ADMIN_USERNAME"

    # ============================================
    # PHASE 5: SSL Certificates
    # ============================================
    print_message "info" "=== PHASE 5: SSL Certificates ==="

    ssl_answer="$(prompt_yes_no "Create self-signed SSL certificates?" "y")"
    if [[ "$ssl_answer" == "yes" ]]; then
        create_ssl_certificates "$SERVER_IP" || exit 1
    else
        print_message "warning" "Skipping SSL certificate creation"
        SSL_KEY_PATH="$(prompt_user "Path to SSL private key")"
        SSL_CERT_PATH="$(prompt_user "Path to SSL certificate")"
        SSL_CA_PATH="$(prompt_user "Path to Root CA certificate")"
    fi

    # ============================================
    # PHASE 6: Configure Playbook
    # ============================================
    print_message "info" "=== PHASE 6: Configure Playbook ==="

    configure_inventory "$SERVER_IP" "$INSTALLATION_MODE" || exit 1
    configure_vars_yml "$SERVER_IP" "$IPV6_ENABLED" "$ELEMENT_ENABLED" || exit 1
    create_traefik_directories "$INSTALLATION_MODE"

    # ============================================
    # PHASE 7: Install Ansible Roles
    # ============================================
    print_message "info" "=== PHASE 7: Install Ansible Roles ==="

    install_ansible_roles || exit 1

    # ============================================
    # PHASE 8: Pre-flight Check
    # ============================================
    print_message "info" "=== PHASE 8: Pre-flight Check ==="

    check_answer="$(prompt_yes_no "Run pre-flight check?" "y")"
    if [[ "$check_answer" == "yes" ]]; then
        print_message "info" "Running pre-flight check..."
        cd "$PLAYBOOK_DIR"
        export LC_ALL=C.UTF-8 LANG=C.UTF-8
        ansible-playbook -i inventory/hosts setup.yml --tags=check-all || {
            print_message "warning" "Pre-flight check found some issues"
            continue_answer="$(prompt_yes_no "Continue anyway?" "n")"
            if [[ "$continue_answer" == "no" ]]; then
                print_message "error" "Installation cancelled"
                exit 1
            fi
        }
    fi

    # ============================================
    # PHASE 9: Run Installation
    # ============================================
    print_message "info" "=== PHASE 9: Installation ==="

    install_answer="$(prompt_yes_no "Start installation now?" "y")"
    if [[ "$install_answer" == "no" ]]; then
        print_message "info" "Installation cancelled by user"
        print_message "info" "You can run the playbook manually:"
        print_message "info" "  cd $PLAYBOOK_DIR"
        print_message "info" "  ansible-playbook -i inventory/hosts setup.yml --tags=install-all,start"
        exit 0
    fi

    run_playbook "install-all,ensure-matrix-users-created,start" || exit 1

    # ============================================
    # PHASE 10: Create Admin User
    # ============================================
    print_message "info" "=== PHASE 10: Create Admin User ==="

    create_admin_user "$ADMIN_USERNAME" "$ADMIN_PASSWORD"

    # ============================================
    # PHASE 11: Summary
    # ============================================
    print_summary

    print_message "success" "Installation completed successfully!"
}

# ============================================
# SCRIPT ENTRY POINT
# ============================================
main "$@"
