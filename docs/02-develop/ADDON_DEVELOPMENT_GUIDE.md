# Addon Development Guide

This guide shows you how to create addons for Matrix Installer.

## What is an Addon?

An addon is a self-contained installation module. A directory with an `install.sh` script that does the actual work. The `matrix-installer.sh` script handles certificates and menus, then hands off to your addon.

Think of it this way: `matrix-installer.sh` is the conductor, addons are the musicians.

## Basic Structure

```
addons/
└── my-addon/
    └── install.sh    # The only required file
```

## Metadata

Every addon must define metadata in the first 15 lines of `install.sh`:

```bash
# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="my-addon"              # Required: internal identifier
ADDON_NAME_MENU="My Addon"         # Optional: display name (defaults to ADDON_NAME)
ADDON_VERSION="1.0.0"              # Required: semantic versioning
ADDON_ORDER="50"                   # Optional: menu order (10, 20, 30... lower first)
ADDON_DESCRIPTION="Brief description"  # Required
ADDON_AUTHOR="Your Name"           # Optional
ADDON_HIDDEN="true"                # Optional: hide from menu (for WIP addons)
```

### Menu Ordering

Addons display in ascending order by `ADDON_ORDER`:

```bash
ADDON_ORDER="10"  # First (e.g., Docker options)
ADDON_ORDER="20"  # Second
ADDON_ORDER="50"  # Default (easy to reorder later)
```

## Environment Variables

When your addon runs, these variables are exported:

| Variable | What It Is | Example |
|----------|------------|---------|
| `SERVER_NAME` | Server IP or domain | `192.168.1.100` |
| `SSL_CERT` | Full-chain certificate path | `/path/to/certs/my-root/servers/192.168.1.100/cert-full-chain.pem` |
| `SSL_KEY` | Private key path | `/path/to/certs/my-root/servers/192.168.1.100/server.key` |
| `ROOT_CA` | Root Key certificate | `/path/to/certs/my-root/rootCA.crt` |
| `ROOT_CA_DIR` | Active Root Key directory | `/path/to/certs/my-root` |
| `CERTS_DIR` | Certificates base directory | `/path/to/certs` |
| `WORKING_DIR` | Script working directory | `/path/to/script` |

> **Certificate Structure**: `certs/<root-ca-name>/servers/<server>/` — multiple Root Keys can coexist.

### Using ROOT_CA_DIR

```bash
# Access Root Key files
root_ca_cert="$ROOT_CA_DIR/rootCA.crt"

# List servers under this Root Key
ls -1 "$ROOT_CA_DIR/servers/"
```

## Validating Environment

Always check required variables:

```bash
if [[ -z "${SERVER_NAME:-}" ]]; then
    echo "[ERROR] SERVER_NAME not set. Run from matrix-installer.sh"
    exit 1
fi

if [[ ! -f "$SSL_CERT" ]]; then
    echo "[ERROR] Certificate not found: $SSL_CERT"
    exit 1
fi
```

## Minimal Template

```bash
#!/bin/bash

ADDON_NAME="my-addon"
ADDON_VERSION="1.0.0"
ADDON_DESCRIPTION="Brief description"

set -e -u -o pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${WORKING_DIR}/$(basename "$ADDON_DIR").log"

print_message() {
    local type="$1" msg="$2"
    echo "[$type] $msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$type] $msg" >> "$LOG_FILE"
}

main() {
    print_message "INFO" "Installing for $SERVER_NAME"

    # Your installation code here

    print_message "SUCCESS" "Done!"
}

main "$@"
```

## Best Practices

- **Strict mode**: Always use `set -e -u -o pipefail`
- **Logging**: Write to `LOG_FILE` for troubleshooting
- **Idempotent**: Handle re-runs gracefully (check if files exist first)
- **Permissions**: `chmod 600 "$SSL_KEY"` and `chmod 644 "$SSL_CERT"`
- **Exit codes**: `0` success, `1` error, `2` missing vars, `3` config error

## Common Patterns

### Check required commands

```bash
for cmd in docker docker-compose; do
    command -v "$cmd" || { echo "Missing: $cmd"; exit 1; }
done
```

### Generate password

```bash
password="$(openssl rand -base64 16 | tr -d '=+')"
```

### Idempotency check

```bash
if [[ -d "$install_dir" ]]; then
    read -rp "Directory exists. Continue? [y/N]: " answer
    [[ "$answer" != "y" ]] && exit 0
fi
```

## Testing

1. Run from `matrix-installer.sh`
2. Try without env vars (should error gracefully)
3. Run twice (idempotency)
4. Test error conditions (missing files, wrong paths)

## Installing Your Addon

```bash
mkdir -p addons/my-addon
# ... create install.sh ...
chmod +x addons/my-addon/install.sh
./matrix-installer.sh  # your addon appears automatically
```

## Limitations

- **Active Root Key only**: User must switch Root Key in main menu if needed
- **No global state**: Each run is fresh
- **Current directory**: Runs from `WORKING_DIR`, not addon dir
- **Self-contained**: Don't depend on other addons

## Resources

- **Example addons**: `addons/*/install.sh`
- **Bash guide**: https://tldp.org/LDP/Bash-Beginners-Guide/html/
- **Matrix docs**: https://matrix.org/docs/

---

Happy coding!
