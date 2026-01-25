# Addon Development Guide

This guide shows you how to create addons for Matrix Plus. Addons are how you extend the system to install Matrix in different ways—whether that's using Ansible, Docker Compose, or something entirely custom.

## What is an Addon?

An addon is a self-contained installation module. It's a directory with an `install.sh` script that does the actual work. The `main.sh` script handles the boring stuff (certificates, menus, etc.) and then hands off to your addon when the user selects it.

Think of it this way: `main.sh` is the conductor, and addons are the musicians. The conductor doesn't play any instruments—it just makes sure everyone's ready and cues them at the right time.

## Basic Structure

Every addon lives in the `addons/` directory and follows this structure:

```
addons/
└── my-addon/
    └── install.sh    # The only required file
```

That's it. Just one file. Of course, real addons will have more going on inside `install.sh`, but structurally, that's all you need.

## The install.sh Script

The `install.sh` script is where everything happens. Here's what a minimal one looks like:

```bash
#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="my-addon"
ADDON_VERSION="1.0.0"
ADDON_DESCRIPTION="Brief description of what this addon does"
ADDON_AUTHOR="Your Name"

set -e
set -u
set -o pipefail

# Your installation code goes here
```

The metadata at the top is important. `main.sh` reads this to display your addon in the menu. Without it, your addon won't be recognized.

### Metadata Fields

| Field | Required | Purpose |
|-------|----------|---------|
| `ADDON_NAME` | Yes | Display name in the menu |
| `ADDON_VERSION` | Yes | Version number (use semantic versioning) |
| `ADDON_DESCRIPTION` | Yes | Short description of what the addon does |
| `ADDON_AUTHOR` | No | Who wrote it (good for credit/support) |

## Environment Variables

When `main.sh` runs your addon, it exports several environment variables that you'll need:

### Required Variables (Always Available)

| Variable | What It Is | Example |
|----------|------------|---------|
| `SERVER_NAME` | The server's IP or domain | `192.168.1.100` or `matrix.example.com` |
| `SSL_CERT` | Path to full-chain certificate | `/path/to/certs/192.168.1.100/cert-full-chain.pem` |
| `SSL_KEY` | Path to private key | `/path/to/certs/192.168.1.100/server.key` |
| `ROOT_CA` | Path to Root CA certificate | `/path/to/certs/rootCA.crt` |
| `CERTS_DIR` | The certs directory | `/path/to/certs` |
| `WORKING_DIR` | Where the script is running from | `/path/to/script` |

### Checking These Variables

Always verify the required variables are set before doing anything:

```bash
# Check for required variables
if [[ -z "${SERVER_NAME:-}" ]]; then
    echo "[ERROR] SERVER_NAME environment variable not set"
    echo "[ERROR] This addon must be run from main.sh"
    exit 1
fi

if [[ -z "${SSL_CERT:-}" ]] || [[ -z "${SSL_KEY:-}" ]] || [[ -z "${ROOT_CA:-}" ]]; then
    echo "[ERROR] SSL certificate environment variables not set"
    echo "[ERROR] Please generate a server certificate from main.sh first"
    exit 1
fi

# Verify files actually exist
if [[ ! -f "$SSL_CERT" ]]; then
    echo "[ERROR] Certificate file not found: $SSL_CERT"
    exit 1
fi

if [[ ! -f "$SSL_KEY" ]]; then
    echo "[ERROR] Private key file not found: $SSL_KEY"
    exit 1
fi
```

This kind of defensive programming makes your addon more robust and provides helpful error messages.

## A Complete Example

Let's walk through a simple addon that installs a basic Matrix server using Docker Compose:

```bash
#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="simple-synapse"
ADDON_VERSION="1.0.0"
ADDON_DESCRIPTION="Simple Docker Compose Synapse installation"
ADDON_AUTHOR="Your Name"

set -e
set -u
set -o pipefail

# ===========================================
# CONFIGURATION
# ===========================================
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_DIR="$(pwd)"
LOG_FILE="${WORKING_DIR}/simple-synapse.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# ===========================================
# MAIN INSTALLATION
# ===========================================

main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "simple-synapse addon log - $(date)" > "$LOG_FILE"

    # Print banner
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║            Simple Synapse Installer                      ║
║                      Version 1.0.0                       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF

    # Check environment variables
    if [[ -z "${SERVER_NAME:-}" ]]; then
        print_message "error" "SERVER_NAME environment variable not set"
        print_message "info" "This addon must be run from main.sh"
        exit 1
    fi

    if [[ -z "${SSL_CERT:-}" ]] || [[ -z "${SSL_KEY:-}" ]]; then
        print_message "error" "SSL certificate environment variables not set"
        exit 1
    fi

    print_message "info" "Installing for server: $SERVER_NAME"
    print_message "info" "Using SSL certificate: $SSL_CERT"
    print_message "info" "Using SSL key: $SSL_KEY"

    # Get configuration from user
    print_message "info" "=== Configuration ==="

    local db_password
    db_password="$(prompt_user "Database password" "$(openssl rand -base64 16 | tr -d '=+')")"

    local admin_username
    admin_username="$(prompt_user "Admin username" "admin")"

    local admin_password
    admin_password="$(prompt_user "Admin password" "$(openssl rand -base64 16 | tr -d '=+')")"

    print_message "info" "=== Creating Docker Compose Configuration ==="

    # Create a directory for this installation
    local install_dir="${WORKING_DIR}/simple-synapse-${SERVER_NAME}"
    mkdir -p "$install_dir"
    cd "$install_dir"

    # Create docker-compose.yml
    cat > docker-compose.yml <<EOF
version: "3.8"

services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix-synapse
    restart: unless-stopped
    ports:
      - "8008:8008"
      - "8448:8448"
    volumes:
      - ./data:/data
    environment:
      - SYNAPSE_SERVER_NAME=${SERVER_NAME}
      - SYNAPSE_REPORT_STATS=no
      - POSTGRES_PASSWORD=${db_password}
      - SYNAPSE_NO_TLS=YES
    networks:
      - matrix

  postgres:
    image: postgres:15-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    volumes:
      - ./postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=${db_password}
      - POSTGRES_DB=synapse
    networks:
      - matrix

networks:
  matrix:
    driver: bridge
EOF

    # Create Synapse configuration
    mkdir -p data
    cat > data/homeserver.yaml <<EOF
server_name: ${SERVER_NAME}
public_baseurl: https://${SERVER_NAME}/

database:
  name: psycopg2
  args:
    user: synapse
    password: ${db_password}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true

federation_verify_certificates: false
federation_ip_range_blacklist: []

suppress_key_server_warning: true
report_stats: false
signing_key_path: /data/${SERVER_NAME}.signing.key
EOF

    # Copy SSL certificates
    print_message "info" "=== Setting up SSL Certificates ==="
    mkdir -p ssl
    cp "$SSL_CERT" ssl/cert-full-chain.pem
    cp "$SSL_KEY" ssl/server.key
    cp "$ROOT_CA" ssl/rootCA.crt

    print_message "success" "Configuration created in: $install_dir"

    # Start services
    print_message "info" "=== Starting Services ==="

    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    elif command -v docker &> /dev/null; then
        docker compose up -d
    else
        print_message "error" "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi

    # Wait for Synapse to start
    print_message "info" "Waiting for Synapse to start..."
    sleep 10

    # Create admin user
    print_message "info" "=== Creating Admin User ==="

    docker exec -it matrix-synapse register_new_matrix_user \
        -u "$admin_username" \
        -p "$admin_password" \
        -a \
        --no-guest

    # Print summary
    cat <<EOF

╔══════════════════════════════════════════════════════════╗
║                  Installation Complete!                  ║
╚══════════════════════════════════════════════════════════╝

Server: ${SERVER_NAME}
Admin User: ${admin_username}
Admin Password: ${admin_password}

Installation Directory: ${install_dir}

To manage the installation:
  cd ${install_dir}
  docker-compose logs -f

To restart services:
  cd ${install_dir}
  docker-compose restart

To stop services:
  cd ${install_dir}
  docker-compose down

EOF

    print_message "success" "Installation completed successfully!"
}

# Run the main function
main "$@"
```

This is a simplified example, but it shows all the important patterns.

## Best Practices

### 1. Always Use Strict Mode

```bash
set -e
set -u
set -o pipefail
```

This makes your script fail on errors, use of undefined variables, and pipe failures. It catches bugs early.

### 2. Provide Clear Output

Use colors and consistent message formatting. The print_message function in the example above is a good pattern to follow.

### 3. Log Everything

Keep a log file of what happens. This is invaluable for troubleshooting:

```bash
LOG_FILE="${WORKING_DIR}/$(basename "$ADDON_DIR").log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Something happened" >> "$LOG_FILE"
```

### 4. Make It Idempotent

Your addon should handle being run multiple times without breaking. Check if things already exist before creating them:

```bash
if [[ -d "$install_dir" ]]; then
    if [[ "$(prompt_yes_no "Installation directory exists. Continue?" "n")" != "yes" ]]; then
        exit 0
    fi
fi
```

### 5. Clean Up Temporary Files

If you create temporary files during installation, remove them when done:

```bash
trap "rm -f /tmp/my-addon-temp-*" EXIT
```

### 6. Set Proper Permissions

SSL private keys should always have restrictive permissions:

```bash
chmod 600 "$SSL_KEY"
chmod 644 "$SSL_CERT"
```

### 7. Use Meaningful Exit Codes

```bash
exit 0   # Success
exit 1   # General error
exit 2   # Missing required variables
exit 3   # Configuration error
exit 4   # Installation failure
```

## Testing Your Addon

Before considering your addon complete, test it:

1. **Manual testing**: Run it from `main.sh` and verify it works
2. **Missing variables**: Try running it without the environment variables set
3. **Idempotency**: Run it twice and make sure it doesn't break
4. **Error handling**: Intentionally break things (wrong paths, missing files) and see how it handles errors

## Getting Your Addon into Matrix Plus

Once your addon is working:

1. Create a directory in `addons/` with your addon name
2. Put your `install.sh` inside
3. Make it executable: `chmod +x install.sh`
4. Run `main.sh`—your addon will automatically appear in the menu

That's it—no registration or configuration needed. The addon loader finds anything with an `install.sh` that has the proper metadata.

## Common Patterns

### Checking for Required Commands

```bash
check_required_commands() {
    local missing=()

    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "error" "Missing required commands: ${missing[*]}"
        return 1
    fi
}

# Usage
check_required_commands docker docker-compose || exit 1
```

### Generating Random Passwords

```bash
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '=+/' | cut -c1-"$length"
}
```

### Detecting the OS

```bash
detect_os() {
    if [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}
```

## Limitations and Gotchas

1. **No global state**: Don't rely on variables persisting between runs. Each run is fresh.

2. **Current directory**: The addon runs from `WORKING_DIR`, not from the addon's own directory. Use `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` to get the addon's directory.

3. **User interaction**: Keep user interaction to a minimum. Too many prompts make for a poor experience.

4. **Timeout awareness**: Long-running operations (like downloading large files) should show progress so the user knows something is happening.

5. **No dependencies on other addons**: Each addon should be self-contained. Don't assume another addon has run before yours.

## Resources

- **Example addons**: Look at the existing addons in `addons/` for real-world examples
- **Bash scripting**: The [Bash Guide for Beginners](https://tldp.org/LDP/Bash-Beginners-Guide/html/) is a good starting point
- **Matrix documentation**: The [Matrix.org documentation](https://matrix.org/docs/) has details on Synapse configuration

---

Now you know everything you need to create addons for Matrix Plus. Start simple, test thoroughly, and don't hesitate to look at the existing addons for inspiration. Happy coding!
