# Addon Interface Protocol

This document describes the technical interface between `main.sh` and addons. For a complete guide on creating addons, see the [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md).

## Overview

Matrix Installer uses a modular addon system where each addon is a self-contained module invoked by `main.sh`. Communication happens through environment variables—no complex APIs or protocols needed.

## Addon Structure

```
addons/
└── <addon-name>/
    └── install.sh    # The only required file
```

That's the entire structure. No manifest files, no configuration—just a bash script.

## Addon Metadata

Metadata is defined at the top of `install.sh` as bash variables:

```bash
#!/bin/bash

# ===========================================
# ADDON METADATA
# ===========================================
ADDON_NAME="my-addon"
ADDON_VERSION="1.0.0"
ADDON_DESCRIPTION="Brief description of what this addon does"
ADDON_AUTHOR="Author name (optional)"

set -e
set -u
set -o pipefail
```

### Required Metadata Fields

| Field | Required | Description |
|-------|----------|-------------|
| `ADDON_NAME` | Yes | Display name in the menu (alphanumeric, hyphens only) |
| `ADDON_VERSION` | Yes | Version number (semantic versioning recommended) |
| `ADDON_DESCRIPTION` | Yes | Short description shown in the menu |
| `ADDON_AUTHOR` | No | Author name or organization |

### Addon Discovery

`main.sh` automatically discovers addons by:

1. Scanning the `addons/` directory for subdirectories
2. Checking each subdirectory for an `install.sh` file
3. Reading the first 15 lines of `install.sh` for `ADDON_NAME`
4. Adding valid addons to the menu

No registration or configuration required.

## Environment Variables

When `main.sh` invokes an addon, the following environment variables are exported:

### Standard Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `SERVER_NAME` | string | Server IP address or domain name | `192.168.1.100` or `matrix.example.com` |
| `SSL_CERT` | path | Full-chain certificate file | `/path/to/certs/192.168.1.100/servers/192.168.1.100/cert-full-chain.pem` |
| `SSL_KEY` | path | Server private key file | `/path/to/certs/192.168.1.100/servers/192.168.1.100/server.key` |
| `ROOT_CA` | path | Root CA certificate file | `/path/to/certs/192.168.1.100/rootCA.crt` |
| `ROOT_CA_DIR` | path | Root CA directory path | `/path/to/certs/192.168.1.100` |
| `CERTS_DIR` | path | Certificates directory | `/path/to/certs` |
| `WORKING_DIR` | path | Script working directory | `/path/to/script` |

### Directory Structure

```
certs/
├── 192.168.1.100/              # Root CA directory (named by IP/domain)
│   ├── rootCA.key
│   ├── rootCA.crt
│   └── servers/                # Server certificates for this Root CA
│       └── 192.168.1.100/
│           ├── server.key
│           ├── server.crt
│           └── cert-full-chain.pem
└── matrix.example.com/         # Another Root CA (if exists)
    └── ...
```

### Variable Guarantees

- All variables are **always set** when an addon is invoked (never empty/unset)
- All file paths **always exist** (main.sh verifies before invoking)
- All file permissions are **appropriate** (keys are 0600, certs are 0644)

## Expected Addon Behavior

### 1. Validation

Addons should verify required variables before proceeding:

```bash
if [[ -z "${SERVER_NAME:-}" ]]; then
    echo "[ERROR] SERVER_NAME environment variable not set"
    echo "[ERROR] This addon must be run from main.sh"
    exit 1
fi

if [[ ! -f "$SSL_CERT" ]]; then
    echo "[ERROR] SSL certificate not found: $SSL_CERT"
    exit 1
fi
```

### 2. Exit Codes

Addons must use appropriate exit codes:

| Code | Meaning | Usage |
|------|---------|-------|
| 0 | Success | Installation completed successfully |
| 1 | General error | Any unspecified error |
| 2 | Missing requirements | Missing commands, files, or variables |
| 3 | Configuration error | Invalid user input or settings |
| 4 | Installation failure | Service failed to start or configure |

### 3. Output Format

Addons should:
- Print progress messages to stdout
- Print error messages to stderr
- Use consistent message formatting (consider using colors)
- Write detailed logs to a file

## Certificate File Details

The certificate files provided are:

### File: `cert-full-chain.pem`

This is the full certificate chain, containing:
1. The server certificate
2. The Root CA certificate

Used by web servers and reverse proxies for TLS termination.

**Format**: PEM concatenated certificates
**Permissions**: 0644

### File: `server.key`

This is the server's private key.

**Format**: PEM (PKCS#8 or traditional)
**Size**: 4096-bit RSA
**Permissions**: 0600

### File: `rootCA.crt`

This is the Root CA certificate used to sign the server certificate.

**Format**: PEM (X.509)
**Validity**: 10 years (3650 days)
**Permissions**: 0644

### Certificate Properties

| Property | Value |
|----------|-------|
| Key Size | 4096-bit RSA |
| Signature Algorithm | SHA-256 |
| Server Certificate Validity | 1 year (365 days) |
| Root CA Validity | 10 years (3650 days) |
| SAN Includes | Server IP/domain, `matrix.local`, `localhost`, `127.0.0.1` |

## Execution Flow

Here's what happens when a user selects an addon from the menu:

```
User selects addon
        ↓
main.sh checks for existing certificates
        ↓
If none: prompts to create certificate
        ↓
If multiple: prompts to select certificate
        ↓
Exports environment variables
        ↓
Executes addon/install.sh
        ↓
Addon takes control (main.sh exits)
```

Important: **The addon takes full control once invoked**. `main.sh` exits immediately after calling the addon, so the addon is responsible for everything from that point on.

## Example: Minimal Addon

```bash
#!/bin/bash

ADDON_NAME="minimal-addon"
ADDON_VERSION="1.0.0"
ADDON_DESCRIPTION="A minimal example addon"
ADDON_AUTHOR="Example"

set -e
set -u
set -o pipefail

# Verify environment
if [[ -z "${SERVER_NAME:-}" ]]; then
    echo "ERROR: SERVER_NAME not set"
    exit 2
fi

# Use the provided certificates
echo "Installing for: $SERVER_NAME"
echo "Certificate: $SSL_CERT"
echo "Private Key: $SSL_KEY"
echo "Root CA: $ROOT_CA"
echo "Root CA Directory: $ROOT_CA_DIR"

# Your installation logic here
# ...

exit 0
```

## Integration Points

### How main.sh Finds Addons

From `main.sh`, lines 508-521:

```bash
addon_loader_get_list() {
    local found_addons=()

    # Find all directories containing install.sh
    for dir in addons/*/; do
        if [[ -f "${dir}install.sh" ]]; then
            found_addons+=("${dir%/}")
        fi
    done

    # Return list
    printf '%s\n' "${found_addons[@]}"
    return 0
}
```

### How main.sh Validates Addons

From `main.sh`, lines 561-576:

```bash
addon_loader_validate() {
    local addon_dir="$1"
    local addon_install="${addon_dir}/install.sh"

    # Check for install.sh
    if [[ ! -f "$addon_install" ]]; then
        return 1
    fi

    # Check for ADDON_NAME in first 15 lines
    if ! head -n 15 "$addon_install" | grep -q "^ADDON_NAME="; then
        return 1
    fi

    return 0
}
```

### How main.sh Exports Variables

From `main.sh` (updated for new structure):

```bash
env_provider_export_for_addon() {
    local server_name="$1"
    local root_ca_dir="${2:-${ACTIVE_ROOT_CA_DIR}}"

    # Check if Root CA is set
    if [[ -z "$root_ca_dir" ]]; then
        print_message "error" "No active Root CA. Cannot export environment."
        return 1
    fi

    # Get server certificate directory (under Root CA)
    local server_cert_dir="${root_ca_dir}/servers/${server_name}"

    # Check certificates exist
    if [[ ! -f "${server_cert_dir}/server.key" ]] || \
       [[ ! -f "${server_cert_dir}/cert-full-chain.pem" ]] || \
       [[ ! -f "${root_ca_dir}/rootCA.crt" ]]; then
        print_message "error" "SSL certificates not found"
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
```

## See Also

- [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md) - Complete guide for creating addons
- [User Guide](USER_GUIDE.md) - End-user documentation
- [Manual SSL Certificates](MANUAL_SSL_CERTIFICATES.md) - SSL certificate technical details
