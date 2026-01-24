# Addon Interface Protocol

## Overview

Matrix Plus uses a modular addon system where each addon is a self-contained module that can be invoked from `main.sh`. Addons communicate with the orchestrator via environment variables.

## Addon Structure

```
<addon-name>/
├── addon.manifest    # Addon metadata
└── install.sh        # Addon installation script (must be executable)
```

## Addon Manifest

The `addon.manifest` file contains metadata about the addon:

```bash
NAME="addon-name"
VERSION="1.0.0"
DESCRIPTION="Brief description of the addon"
AUTHOR="Author name"
REQUIRES="comma,separated,requirements"  # Optional
STATUS="stable|beta|placeholder"         # Optional
```

## Environment Variables

### Variables Provided by main.sh

When `main.sh` invokes an addon, the following environment variables are exported:

| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_NAME` | Matrix server identity (IP or domain) | `192.168.1.100` or `matrix.example.com` |
| `SSL_CERT` | Path to full chain certificate | `/path/to/certs/cert-full-chain.pem` |
| `SSL_KEY` | Path to private key | `/path/to/certs/server.key` |
| `ROOT_CA` | Path to Root CA certificate | `/path/to/certs/rootCA.crt` |
| `CERTS_DIR` | Certificate directory path | `/path/to/certs` |
| `WORKING_DIR` | Working directory path | `/path/to/script` |

### Expected Addon Behavior

1. **Check Required Variables**: Verify all required environment variables are set
2. **Use Provided Paths**: Use the provided certificate paths instead of generating new ones
3. **Exit on Error**: Use appropriate exit codes (0 for success, non-zero for failure)

## Example Addon Template

```bash
#!/bin/bash

set -e
set -u
set -o pipefail

# ===========================================
# My Custom Addon
# ===========================================

# Check environment variables
if [[ -z "${SERVER_NAME:-}" ]]; then
    echo "[ERROR] SERVER_NAME environment variable not set"
    echo "This addon must be run from main.sh"
    exit 1
fi

if [[ -z "${SSL_CERT:-}" ]] || [[ -z "${SSL_KEY:-}" ]] || [[ -z "${ROOT_CA:-}" ]]; then
    echo "[ERROR] SSL certificate environment variables not set"
    exit 1
fi

# Your addon logic here
echo "Installing for server: $SERVER_NAME"
echo "Using SSL certificate: $SSL_CERT"
echo "Using SSL key: $SSL_KEY"
echo "Using Root CA: $ROOT_CA"

# Exit with appropriate code
exit 0
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Missing required environment variables |
| 3 | Configuration error |
| 4 | Installation failure |

## SSL Certificate Files

The certificates provided by `main.sh` are:

- **`cert-full-chain.pem`**: Full certificate chain (server certificate + Root CA)
- **`server.key`**: Private key for the server certificate (4096-bit RSA)
- **`rootCA.crt`**: Root CA certificate

### Certificate Details

- **Root CA**: Valid for 10 years (3650 days)
- **Server Certificate**: Valid for 1 year (365 days)
- **Key Size**: 4096-bit RSA
- **SAN Includes**: Server IP/domain, `matrix.local`, `localhost`, and `127.0.0.1`

## Best Practices

1. **Validate Environment**: Always check required variables before proceeding
2. **Idempotency**: Support running multiple times without errors
3. **Logging**: Use log files for troubleshooting
4. **User Feedback**: Provide clear progress messages
5. **Error Handling**: Handle errors gracefully with informative messages

## See Also

- `main.sh`: Orchestrator that invokes addons
- `ansible-synapse/`: Example of a fully functional addon
