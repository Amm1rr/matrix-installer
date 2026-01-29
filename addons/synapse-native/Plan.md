# Synapse Native Addon - Implementation Plan

## Overview

Native package-based Matrix Synapse installer for Ubuntu/Debian and Arch Linux systems.
This addon installs Synapse, PostgreSQL, Element Web, and Synapse Admin using official system packages.

---

## Metadata

```bash
ADDON_NAME="synapse-native"
ADDON_NAME_MENU="Install Synapse Native (System Packages)"
ADDON_VERSION="1.0.0"
ADDON_ORDER="60"
ADDON_DESCRIPTION="Native package-based Synapse installer for Ubuntu/Debian/Arch"
ADDON_AUTHOR="Matrix Installer"
ADDON_HIDDEN="false"
```

---

## Architecture

### File Structure

```
addons/synapse-native/
└── install.sh              # Single file addon (~700-900 lines)
```

### Design Principles

1. **Single File**: All OS-specific code in one file using internal functions
2. **Dual Mode**: Works with or without matrix-installer.sh
3. **Official Repos**: Use official package sources only
4. **No AUR Dependencies**: For Arch, use official repo (pacman) or manual install

---

## OS Support Matrix

| Feature | Ubuntu/Debian | Arch/Manjaro |
|---------|---------------|--------------|
| **Package Manager** | `apt-get` | `pacman` |
| **Synapse Package** | `matrix-synapse` (from packages.matrix.org) | `synapse` (from official repo) |
| **PostgreSQL** | `postgresql` | `postgresql` |
| **Element Web** | Manual install from GitHub | Manual install from GitHub |
| **Service Name** | `matrix-synapse` | `synapse` |
| **Config Dir** | `/etc/synapse` | `/etc/synapse` |
| **Data Dir** | `/var/lib/synapse` | `/var/lib/synapse` |
| **User** | `matrix-synapse` | `synapse` |

---

## External Sources

| Component | Source | URL |
|-----------|--------|-----|
| **Synapse (Ubuntu)** | packages.matrix.org | https://packages.matrix.org/debian/ |
| **Synapse (Arch)** | Official Repo | pacman -S synapse |
| **Element Web** | GitHub Releases | https://github.com/element-hq/element-web/releases |
| **Synapse Admin** | GitHub Releases | https://github.com/Awesome-Technologies/synapse-admin/releases |
| **PostgreSQL** | Official Repos | apt/pacman |

---

## Installation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Installation Flow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. main()                                                              │
│     ├── detect_os()                                                     │
│     ├── check_prerequisites()                                           │
│     └── check_environment_variables()  ← matrix-installer.sh mode       │
│                                                                         │
│  2. install_synapse()                                                   │
│     │                                                                   │
│     ├── install_postgresql()                                            │
│     │   ├── Ubuntu: apt-get install postgresql python3-psycopg2         │
│     │   └── Arch: pacman -S postgresql python-psycopg2                  │
│     │                                                                   │
│     ├── setup_synapse_user_and_db()                                     │
│     │   ├── create user and database                                    │
│     │   └── set password                                                │
│     │                                                                   │
│     ├── install_synapse_package()                                       │
│     │   ├── Ubuntu: add matrix-org repo → install                       │
│     │   └── Arch: pacman -S synapse                                     │
│     │                                                                   │
│     ├── configure_synapse()                                             │
│     │   ├── generate homeserver.yaml                                    │
│     │   ├── PostgreSQL connection                                       │
│     │   ├── Root Key SSL (if available)                                 │
│     │   └── Federation settings                                         │
│     │                                                                   │
│     ├── setup_root_ca_certificates()  ← if from matrix-installer.sh     │
│     │   ├── copy ROOT_CA to system trust store                          │
│     │   ├── Ubuntu: /usr/local/share/ca-certificates/ → update-ca-cert  │
│     │   └── Arch: /etc/ca-certificates/trust-source/ → trust extract    │
│     │                                                                   │
│     ├── configure_synapse_tls()                                         │
│     │   ├── copy SSL cert and key to /etc/synapse/                      │
│     │   └── set permissions (0600 for key, 0644 for cert)               │
│     │                                                                   │
│     ├── install_element_web()                                           │
│     │   ├── download from GitHub releases                               │
│     │   ├── extract to /var/www/element                                 │
│     │   └── configure config.json                                       │
│     │                                                                   │
│     ├── install_synapse_admin()  ← optional                             │
│     │   ├── download from GitHub releases                               │
│     │   ├── extract to /var/www/synapse-admin                           │
│     │   └── configure                                                   │
│     │                                                                   │
│     ├── enable_and_start_services()                                     │
│     │   ├── systemctl enable postgresql synapse                         │
│     │   └── systemctl start postgresql synapse                          │
│     │                                                                   │
│     └── create_admin_user()                                             │
│         └── register_new_matrix_user                                    │
│                                                                         │
│  3. check_status()                                                      │
│     ├── check synapse service                                           │
│     ├── check postgresql service                                        │
│     └── display version and connection info                             │
│                                                                         │
│  4. uninstall_synapse()                                                 │
│     ├── stop services                                                   │
│     ├── remove packages                                                 │
│     ├── remove configs and data                                         │
│     └── remove users                                                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Function Specifications

### Core Functions

#### `main()`
- Entry point
- Display banner
- Show menu: Install, Status, Create Admin, Uninstall, Exit

#### `detect_os()`
```bash
detect_os() {
    [[ -f /etc/os-release ]] && source /etc/os-release

    case "$ID" in
        arch|artix|garuda|manjaro)
            DETECTED_OS="arch"
            ;;
        ubuntu|debian)
            DETECTED_OS="ubuntu"
            ;;
        *)
            if [[ "$ID_LIKE" == *"ubuntu"* ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
                DETECTED_OS="ubuntu"
            fi
            ;;
    esac
}
```

#### `check_prerequisites()`
- Check for systemd
- Check for openssl, curl, git
- Prompt to install missing dependencies

#### `check_environment_variables()`
- Check if running from matrix-installer.sh
- If not, prompt for certificate paths or use Let's Encrypt/self-signed
- Export: SERVER_NAME, SSL_CERT, SSL_KEY, ROOT_CA, CERTS_DIR, WORKING_DIR

### Installation Functions

#### `install_synapse()`
- Main installation coordinator
- Calls all sub-functions in order
- Error handling with rollback on failure

#### `install_postgresql()`
```bash
install_postgresql() {
    case "$DETECTED_OS" in
        ubuntu)
            apt-get update -qq
            apt-get install -y postgresql postgresql-contrib python3-psycopg2
            ;;
        arch)
            pacman -S --noconfirm postgresql python-psycopg2
            ;;
    esac

    # Initialize database if needed
    # Start service
    systemctl enable postgresql
    systemctl start postgresql
}
```

#### `setup_synapse_user_and_db()`
```bash
setup_synapse_user_and_db() {
    local db_user="synapse"
    local db_name="synapsedb"
    local db_password="$(generate_password 32)"

    # Create user and database
    case "$DETECTED_OS" in
        ubuntu)
            sudo -u postgres createuser "$db_user"
            sudo -u postgres psql -c "ALTER USER $db_user PASSWORD '$db_password';"
            sudo -u postgres createdb -O "$db_user" "$db_name"
            ;;
        arch)
            sudo -u postgres createuser "$db_user"
            sudo -u postgres psql -c "ALTER USER $db_user PASSWORD '$db_password';"
            sudo -u postgres createdb -O "$db_user" "$db_name"
            ;;
    esac

    # Save password for synapse config
    POSTGRES_PASSWORD="$db_password"
}
```

#### `install_synapse_package()`
```bash
install_synapse_package() {
    case "$DETECTED_OS" in
        ubuntu)
            # Add Matrix.org repository
            wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg \
                https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg

            echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] \
                https://packages.matrix.org/debian/ debian main" | \
                tee /etc/apt/sources.list.d/matrix-org.list

            apt-get update
            apt-get install -y matrix-synapse
            ;;
        arch)
            pacman -S --noconfirm synapse
            ;;
    esac
}
```

#### `configure_synapse()`
```bash
configure_synapse() {
    local config_dir="$(get_synapse_config_dir)"
    local config_file="${config_dir}/homeserver.yaml"

    # Backup existing config
    [[ -f "$config_file" ]] && cp "$config_file" "${config_file}.backup"

    # Generate new config
    cat > "$config_file" <<EOF
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

tls_certificate_path: ${config_dir}/${SERVER_NAME}.crt
tls_private_key_path: ${config_dir}/${SERVER_NAME}.key

# Federation settings for Root Key
federation_verify_certificates: false
trust_signed_third_party_certificates: false

# Registration
enable_registration: true
registration_shared_secret: "${REGISTRATION_SHARED_SECRET}"

# Report stats
report_stats: false

# Logging
log_config: "/etc/synapse/${SERVER_NAME}.log.config"
EOF

    # Set permissions
    chmod 640 "$config_file"
    chown synapse:synapse "$config_file"
}
```

#### `setup_root_ca_certificates()`
```bash
setup_root_ca_certificates() {
    [[ -z "${ROOT_CA:-}" ]] && return 0

    print_message "info" "Installing Root Key in system trust store..."

    case "$DETECTED_OS" in
        ubuntu)
            # Copy to Debian trust store
            cp "$ROOT_CA" /usr/local/share/ca-certificates/matrix-root-ca.crt
            update-ca-certificates
            ;;
        arch)
            # Copy to Arch trust store
            cp "$ROOT_CA" /etc/ca-certificates/trust-source/anchors/matrix-root-ca.crt
            trust extract-compat
            ;;
    esac

    print_message "success" "Root Key installed in system trust store"
}
```

#### `configure_synapse_tls()`
```bash
configure_synapse_tls() {
    local config_dir="$(get_synapse_config_dir)"

    # Copy certificates
    cp "$SSL_CERT" "${config_dir}/${SERVER_NAME}.crt"
    cp "$SSL_KEY" "${config_dir}/${SERVER_NAME}.key"

    # Set permissions
    chmod 644 "${config_dir}/${SERVER_NAME}.crt"
    chmod 600 "${config_dir}/${SERVER_NAME}.key"
    chown synapse:synapse "${config_dir}/${SERVER_NAME}".{crt,key}

    print_message "success" "TLS certificates configured for Synapse"
}
```

#### `install_element_web()`
```bash
install_element_web() {
    local install_dir="/var/www/element"

    print_message "info" "Installing Element Web from GitHub..."

    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/element-hq/element-web/releases/latest | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    [[ -z "$latest_version" ]] && latest_version="v1.11.93"

    local download_url="https://github.com/element-hq/element-web/releases/download/${latest_version}/element-web-${latest_version}.tar.gz"

    mkdir -p "$install_dir"
    cd /tmp

    # Download and extract
    curl -fL "$download_url" -o element-web.tar.gz
    tar -xzf element-web.tar.gz
    cp -r element-web/* "$install_dir/"
    rm -rf element-web element-web.tar.gz

    # Configure
    cat > "${install_dir}/config.json" <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${SERVER_NAME}",
            "server_name": "${SERVER_NAME}"
        }
    },
    "disable_custom_urls": true,
    "brand": "Element"
}
EOF

    # Set ownership
    case "$DETECTED_OS" in
        ubuntu) chown -R www-data:www-data "$install_dir" ;;
        arch) chown -R http:http "$install_dir" ;;
    esac

    print_message "success" "Element Web installed to $install_dir"
}
```

#### `install_synapse_admin()`
```bash
install_synapse_admin() {
    local install_dir="/var/www/synapse-admin"

    print_message "info" "Installing Synapse Admin from GitHub..."

    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/Awesome-Technologies/synapse-admin/releases/latest | \
                    grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    [[ -z "$latest_version" ]] && latest_version="v0.10.2"

    local download_url="https://github.com/Awesome-Technologies/synapse-admin/releases/download/${latest_version}/synapse-admin-${latest_version}.tar.gz"

    mkdir -p "$install_dir"
    cd /tmp

    # Download and extract
    curl -fL "$download_url" -o synapse-admin.tar.gz
    tar -xzf synapse-admin.tar.gz
    cp -r synapse-admin/* "$install_dir/"
    rm -rf synapse-admin synapse-admin.tar.gz

    # Set ownership
    case "$DETECTED_OS" in
        ubuntu) chown -R www-data:www-data "$install_dir" ;;
        arch) chown -R http:http "$install_dir" ;;
    esac

    print_message "success" "Synapse Admin installed to $install_dir"
}
```

#### `enable_and_start_services()`
```bash
enable_and_start_services() {
    local synapse_service="$(get_synapse_service_name)"

    print_message "info" "Enabling and starting services..."

    # Enable services
    systemctl enable postgresql
    systemctl enable "$synapse_service"

    # Start services
    systemctl restart postgresql
    sleep 3
    systemctl restart "$synapse_service"

    # Wait for synapse to be ready
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if systemctl is-active --quiet "$synapse_service"; then
            print_message "success" "Synapse is running"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    print_message "warning" "Synapse may not be fully started yet"
}
```

#### `create_admin_user()`
```bash
create_admin_user() {
    local username="$(prompt_user "Admin username" "admin")"
    local password="$(prompt_user "Admin password" "$(generate_password 16)")"

    print_message "info" "Creating admin user: $username"

    register_new_matrix_user \
        --server "$SERVER_NAME:8448" \
        --user "$username" \
        --password "$password" \
        --admin \
        --no-progress 2>&1 || {
        print_message "warning" "Failed to create admin user automatically"
        return 1
    }

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
}
```

### Status Function

#### `check_status()`
```bash
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
    if systemctl is-active --quiet "$synapse_service"; then
        echo -e "${GREEN}✓ Synapse: RUNNING${NC}"
        local version="$(synapse --version 2>/dev/null || echo "unknown")"
        echo "  Version: $version"
    else
        echo -e "${RED}✗ Synapse: NOT RUNNING${NC}"
    fi

    if systemctl is-enabled --quiet "$synapse_service"; then
        echo "  Service: Enabled on boot"
    else
        echo "  Service: Not enabled on boot"
    fi

    echo ""

    # PostgreSQL service
    if systemctl is-active --quiet postgresql; then
        echo -e "${GREEN}✓ PostgreSQL: RUNNING${NC}"
    else
        echo -e "${RED}✗ PostgreSQL: NOT RUNNING${NC}"
    fi

    echo ""

    # Connection test
    if systemctl is-active --quiet "$synapse_service"; then
        echo "Testing connection to $SERVER_NAME:8448..."
        if curl -fsS "https://${SERVER_NAME}:8448/_matrix/client/versions" >/dev/null 2>&1; then
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

    echo ""
}
```

### Uninstall Function

#### `uninstall_synapse()`
```bash
uninstall_synapse() {
    local synapse_service="$(get_synapse_service_name)"

    print_message "warning" "This will remove Synapse and all data"

    if [[ "$(prompt_yes_no "Continue with uninstall?" "n")" != "yes" ]]; then
        print_message "info" "Uninstall cancelled"
        return 0
    fi

    # Stop services
    print_message "info" "Stopping services..."
    systemctl stop "$synapse_service" 2>/dev/null || true
    systemctl stop postgresql 2>/dev/null || true

    # Remove packages
    print_message "info" "Removing packages..."
    case "$DETECTED_OS" in
        ubuntu)
            apt-get remove --purge -y matrix-synapse postgresql python3-psycopg2
            ;;
        arch)
            pacman -Rns --noconfirm synapse postgresql python-psycopg2
            ;;
    esac

    # Remove configs and data
    print_message "info" "Removing configuration and data..."
    rm -rf /etc/synapse
    rm -rf /var/lib/synapse
    rm -rf /var/lib/postgresql
    rm -rf /var/www/element
    rm -rf /var/www/synapse-admin

    # Remove users
    print_message "info" "Removing users..."
    case "$DETECTED_OS" in
        ubuntu)
            userdel matrix-synapse 2>/dev/null || true
            ;;
        arch)
            userdel synapse 2>/dev/null || true
            ;;
    esac

    print_message "success" "Uninstall completed"
}
```

---

## OS-Specific Helper Functions

### Getters

```bash
get_synapse_service_name() {
    case "$DETECTED_OS" in
        ubuntu) echo "matrix-synapse" ;;
        arch) echo "synapse" ;;
    esac
}

get_synapse_config_dir() {
    echo "/etc/synapse"
}

get_synapse_data_dir() {
    echo "/var/lib/synapse"
}

get_synapse_user() {
    case "$DETECTED_OS" in
        ubuntu) echo "matrix-synapse" ;;
        arch) echo "synapse" ;;
    esac
}

get_web_user() {
    case "$DETECTED_OS" in
        ubuntu) echo "www-data" ;;
        arch) echo "http" ;;
    esac
}
```

---

## Environment Variables

### From matrix-installer.sh

```bash
SERVER_NAME="172.19.39.69"                          # Server IP or domain
SSL_CERT="/path/to/certs/.../cert-full-chain.pem"   # Certificate chain
SSL_KEY="/path/to/certs/.../server.key"             # Private key
ROOT_CA="/path/to/certs/.../rootCA.crt"             # Root CA certificate
ROOT_CA_DIR="/path/to/certs/..."                    # Root CA directory
CERTS_DIR="/path/to/certs"                          # Certificates directory
WORKING_DIR="/path/to/script"                       # Working directory
```

### Generated Variables

```bash
POSTGRES_PASSWORD="$(generate_password 32)"
REGISTRATION_SHARED_SECRET="$(generate_password 32)"
```

---

## Configuration Files

### homeserver.yaml locations

| OS | Config Path | Data Path |
|----|-------------|-----------|
| Ubuntu | `/etc/synapse/homeserver.yaml` | `/var/lib/synapse` |
| Arch | `/etc/synapse/homeserver.yaml` | `/var/lib/synapse` |

### Element Web location

| OS | Install Path |
|----|--------------|
| Ubuntu | `/var/www/element` |
| Arch | `/var/www/element` (or `/usr/share/element-web`) |

---

## Security Considerations

### File Permissions

| File Type | Permissions | Owner |
|-----------|-------------|-------|
| `homeserver.yaml` | 0640 | synapse:synapse |
| `*.key` | 0600 | synapse:synapse |
| `*.crt` | 0644 | synapse:synapse |
| `/var/lib/synapse` | 0750 | synapse:synapse |
| `/var/www/element` | 0755 | www-data:www-data |

### Passwords

- PostgreSQL password: auto-generated, 32 characters
- Registration shared secret: auto-generated, 32 characters
- Admin password: prompted or auto-generated

### Root Key Integration

When using matrix-installer.sh Root Key:
1. Root CA copied to system trust store
2. Server certificates copied to `/etc/synapse/`
3. Synapse configured with TLS on port 8448
4. Federation with `federation_verify_certificates: false`

---

## Error Handling

### Rollback Strategy

If installation fails:
1. Log error with details
2. Stop any started services
3. Remove any created files
4. Prompt user to retry or abort

### Logging

```bash
LOG_FILE="${WORKING_DIR}/synapse-native.log"

print_message() {
    local msg_type="$1"
    local message="$2"

    # Console output with colors
    case "$msg_type" in
        "info") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "warning") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "error") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
    esac

    # Log file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$msg_type] $message" >> "$LOG_FILE"
}
```

---

## Menu System

### Main Menu

```
╔══════════════════════════════════════════════════════════╗
║           Synapse Native Installer                       ║
║              Version 1.0.0                               ║
║                                                          ║
║       Native package-based Matrix homeserver             ║
╚══════════════════════════════════════════════════════════╝

Select an option:

  1) Install Matrix Synapse
  2) Check Status
  3) Create Admin User
  4) Uninstall Matrix
  -----------------
  0) Exit

Enter your choice:
```

### Installation Prompts

```
=== Synapse Configuration ===

Server name: [172.19.39.69]:

Enable user registration? [Y/n]:

Install Element Web? [Y/n]:

Install Synapse Admin? [y/N]:

Admin username: [admin]:

Admin password (press Enter for auto-generated):

Configuration Summary:
  Server: 172.19.39.69
  Registration: enabled
  Element Web: yes
  Synapse Admin: no
  Admin: admin

Continue with installation? [Y/n]:
```

---

## Dependencies

### System Requirements

| Requirement | Ubuntu/Debian | Arch |
|-------------|---------------|------|
| systemd | ✅ required | ✅ required |
| curl | ✅ required | ✅ required |
| openssl | ✅ required | ✅ required |
| git | optional | optional |
| 512MB RAM | minimum | minimum |
| 2GB RAM | recommended | recommended |

### Package Dependencies

Ubuntu/Debian:
- postgresql
- postgresql-contrib
- python3-psycopg2
- matrix-synapse (from packages.matrix.org)

Arch:
- postgresql
- python-psycopg2
- synapse (from official repo)

---

## Testing Checklist

- [ ] Install on Ubuntu 22.04
- [ ] Install on Debian 12
- [ ] Install on Arch Linux
- [ ] Install on Manjaro
- [ ] Root Key integration works
- [ ] Standalone mode works (without Root Key)
- [ ] Element Web accessible
- [ ] Admin user creation works
- [ ] Status check displays correctly
- [ ] Uninstall removes all components
- [ ] Federation between servers works

---

## Future Enhancements

1. **Coturn/TURN server** - Optional VoIP support
2. **Well-known discovery** - Auto-generate .well-known files
3. **Backup/Restore** - Automated backup functionality
4. **Update functionality** - In-place Synapse updates
5. **Monitoring** - Prometheus metrics configuration

---

## References

- [Synapse Documentation](https://element-hq.github.io/synapse/latest/)
- [Matrix.org Packages](https://packages.matrix.org/debian/)
- [Element Web](https://github.com/element-hq/element-web)
- [Synapse Admin](https://github.com/Awesome-Technologies/synapse-admin)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
