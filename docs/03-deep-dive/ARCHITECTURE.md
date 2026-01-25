# Matrix Plus Architecture

This document explains how Matrix Plus works internally. Understanding the architecture helps with troubleshooting, extending the system, and contributing to development.

## High-Level Overview

Matrix Plus is a modular installation system for Matrix homeservers. It handles the complex certificate management that enables federation between servers, then delegates the actual installation to specialized addons.

```
┌─────────────────────────────────────────────────────────────────┐
│                         User (Terminal)                         │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        main.sh (Orchestrator)                   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ SSL Manager  │  │ Addon Loader │  │ Environment Provider │   │
│  │              │  │              │  │                      │   │
│  │ • Root CA    │  │ • Discover   │  │ • Export variables   │   │
│  │ • Server     │  │ • Validate   │  │ • Verify certs       │   │
│  │   Certs      │  │ • Execute    │  │ • Pass to addons     │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Menu System                           │   │
│  │  • Dynamic based on Root CA availability                 │   │
│  │  • Auto-displays available addons                        │   │
│  │  • Interactive prompts                                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   certs/        │
                    │                 │
                    │  rootCA.key     │
                    │  rootCA.crt     │
                    │  <server>/      │
                    │    server.key   │
                    │    server.crt   │
                    │    cert-full    │
                    └─────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Addons (modules)                         │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐    │
│  │ ansible-synapse │  │ docker-compose  │  │ your-custom   │    │
│  │                 │  │   -synapse      │  │   addon       │    │
│  │ Ansible based   │  │                 │  │               │    │
│  │ installation    │  │ Docker Compose  │  │ Whatever you  │    │
│  │                 │  │                 │  │ want          │    │
│  └─────────────────┘  └─────────────────┘  └───────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. main.sh (The Orchestrator)

The entry point and coordinator. It doesn't install anything itself—it coordinates the pieces.

**Key responsibilities:**
- Display interactive menus
- Manage SSL certificates
- Discover and validate addons
- Pass control to addons with proper environment

**Important design decision:** `main.sh` exits when an addon takes over. The addon becomes the primary process from that point.

### 2. SSL Manager

Handles all certificate operations. This is the heart of the system—without proper certificates, federation doesn't work.

**Functions:**

| Function | Purpose |
|----------|---------|
| `ssl_manager_init()` | Create certs directory, detect existing Root CA |
| `detect_root_ca()` | Check for Root CA next to main.sh |
| `ssl_manager_create_root_ca()` | Generate new Root CA with OpenSSL |
| `ssl_manager_generate_server_cert()` | Generate server certificate signed by Root CA |
| `get_server_cert_dir()` | Get certificate directory for a server |
| `server_has_certs()` | Check if a server has certificates |
| `list_servers_with_certs()` | List all servers with existing certificates |

**Certificate creation process:**

```
1. Check if Root CA exists
   │
   ├─ No → Create Root CA
   │       ├─ Generate private key (4096-bit RSA)
   │       ├─ Create self-signed certificate (10 years)
   │       └─ Save to certs/rootCA.*
   │
   └─ Yes → Continue

2. Get server name (IP or domain)
   │
   └─ Detect local IP or prompt user

3. Create server certificate
   ├─ Create server private key (4096-bit RSA)
   ├─ Create CSR with proper SAN
   ├─ Sign CSR with Root CA
   ├─ Create full-chain file
   └─ Save to certs/<server>/        │
4. Return to menu with Root CA available
```

### 3. Addon Loader

Finds and executes installation addons.

**Functions:**

| Function | Purpose |
|----------|---------|
| `addon_loader_get_list()` | Scan addons/ for valid addons |
| `addon_loader_get_name()` | Extract display name from addon |
| `addon_loader_run()` | Execute an addon |
| `addon_loader_validate()` | Verify addon is valid |

**Discovery process:**

```
1. Scan addons/ directory
   │
   ├─ For each subdirectory:
   │   ├─ Check for install.sh
   │   ├─ Check for ADDON_NAME in first 15 lines
   │   └─ Add to list if valid
   │
2. Return list of valid addons
```

### 4. Environment Provider

Bridges the gap between `main.sh` and addons by exporting environment variables.

**Function:**

| Function | Purpose |
|----------|---------|
| `env_provider_export_for_addon()` | Export all required variables for an addon |

**Exported variables:**

```bash
SERVER_NAME="$server_name"                    # From user input or detection
SSL_CERT="${server_cert_dir}/cert-full-chain.pem"
SSL_KEY="${server_cert_dir}/server.key"
ROOT_CA="${CERTS_DIR}/rootCA.crt"
CERTS_DIR="$CERTS_DIR"
WORKING_DIR="$WORKING_DIR"
```

### 5. Menu System

Provides the interactive user interface.

**Two modes:**

1. **Without Root CA** (`menu_without_root_ca()`):
   - Only option is to create Root CA
   - Minimal options since nothing else works without certificates

2. **With Root CA** (`menu_with_root_ca()`):
   - Full menu with all options
   - Dynamically lists available addons
   - Shows Root CA information

**Menu construction:**

```
1. Get list of addons
2. Determine numbering
3. Display static options (generate cert, exit)
4. Display dynamic options (addons)
5. Get user choice
6. Execute appropriate action
```

## Data Flow

### Complete Installation Flow

```
User runs ./main.sh
        │
        ▼
┌─────────────────────────────────────┐
│ Initialize: Create certs/ directory │
│ Detect existing Root CA             │
└────────────┬────────────────────────┘
             │
             ▼
      ┌──────────────┐
      │ Root CA exists? │
      └──┬───────────┘
         │
    No   │   Yes
    ┌────┴────┐
    ▼         ▼
┌────────┐  ┌─────────────────┐
│ Prompt │  │ Prompt user:    │
│ create │  │Use existing CA? │
│   CA   │  └────┬────────────┘
└───┬────┘       │
    │            │
    │         Yes│ No
    │            ▼  │
    │      ┌────────┐ │
    │      │ Copy to│ │
    │      │ certs/ │ │
    │      └───┬────┘ │
    │          │      │
    └──────────┴──────┘
               │
               ▼
        ┌──────────────┐
        │ Show menu    │
        │ (with addons)│
        └───┬──────────┘
            │
    ┌───────┴────────┐
    ▼                ▼
┌─────────┐    ┌──────────┐
│ Generate│    │ Install  │
│  cert   │    │  addon   │
└────┬────┘    └─────┬────┘
     │              │
     ▼              ▼
┌─────────┐    ┌─────────────────┐
│ Prompt  │    │ Select server   │
│ server  │    │ (if multiple)   │
│ name    │    └─────┬───────────┘
└────┬────┘          │
     │              ▼
     ▼        ┌──────────────┐
┌─────────┐   │ Export env   │
│ Create  │   │ variables    │
│ cert    │   └───┬──────────┘
└────┬────┘       │
     │            ▼
     │    ┌──────────────┐
     │    │ Execute      │
     │    │ addon/install│
     │    │ .sh          │
     │    └───┬──────────┘
     │        │
     │        ▼
     │  ┌──────────────────┐
     │  │ Addon takes over │
     │  │ main.sh exits    │
     │  └──────────────────┘
     │
     └──────────┐
                │
                ▼
          ┌─────────┐
          │ Show    │
          │ menu    │
          └─────────┘
```

## Certificate Lifecycle

### Creation

```
Root CA Creation (one-time):
  openssl genrsa → rootCA.key (4096-bit, 0600)
  openssl req -x509 → rootCA.crt (10 years, 0644)

Server Certificate Creation (per server):
  openssl genrsa → server.key (4096-bit, 0600)
  openssl req → server.csr (with SAN)
  openssl x509 -req → server.crt (signed by Root CA, 1 year)
  cat server.crt rootCA.crt → cert-full-chain.pem
```

### Usage

```
Traefik/Reverse Proxy:
  Reads: cert-full-chain.pem, server.key
  Presents: cert-full-chain.pem to clients
  Validates: Against Root CA (for federation)

Matrix Synapse:
  Trusts: Root CA installed in system
  Presents: server certificate for federation
  Validates: Peer certificates against Root CA
```

### Expiration

```
Timeline:
  Year 0:  Root CA created (valid for 10 years)
  Year 0:  Server cert created (valid for 1 year)
  Year 1:  Server cert expires → regenerate
  Year 2:  Server cert expires → regenerate
  ...
  Year 10: Root CA expires → regenerate all certificates
```

## Configuration Sources

### Precedence (highest to lowest)

1. **User input** (from prompts)
2. **Detected values** (IP address, OS type)
3. **Defaults** (in script constants)
4. **Environment variables** (exported to addons)

### Key Variables

| Variable | Source | Default | Used By |
|----------|--------|---------|---------|
| `WORKING_DIR` | `$(pwd)` | - | main.sh |
| `CERTS_DIR` | `${WORKING_DIR}/certs` | - | main.sh |
| `ADDONS_DIR` | `${WORKING_DIR}/addons` | - | main.sh |
| `SERVER_NAME` | User/Detected | - | Addons |
| `SSL_CERT` | Calculated | - | Addons |
| `SSL_KEY` | Calculated | - | Addons |
| `ROOT_CA` | `${CERTS_DIR}/rootCA.crt` | - | Addons |

## Error Handling

### Strict Mode

```bash
set -e   # Exit on error
set -u   # Exit on undefined variable
set -o pipefail  # Exit on pipe failure
```

This applies to both `main.sh` and all addons.

### Error Recovery

| Error Type | Handling |
|------------|----------|
| Missing Root CA | Prompt to create one |
| Missing server cert | Prompt to create one |
| Invalid addon | Skip, show warning |
| Addon failure | Exit, show log location |
| Permission denied | Show file/permission, suggest fix |

## Extensibility

### Adding a New Addon

```
1. Create directory: addons/my-addon/
2. Create install.sh with metadata
3. Add installation logic
4. Make executable: chmod +x install.sh
5. Run main.sh → addon appears automatically
```

### Adding New Helper Functions

Add to `main.sh` in appropriate section:

```bash
# ===========================================
# HELPER FUNCTIONS
# ===========================================

my_new_function() {
    # Your code here
    return 0
}
```

## Security Architecture

### Trust Model

```
┌─────────────────────────────────────────────┐
│              Root CA (you)                   │
│         Most trusted component              │
│         (never exposed to network)           │
└─────────────────┬───────────────────────────┘
                  │ Signs
                  ▼
        ┌─────────────────────┐
        │  Server Certificate │
        │  (per server)       │
        └─────────┬───────────┘
                  │ Presented by
                  ▼
        ┌─────────────────────┐
        │  Matrix Server      │
        │  (synapse, traefik) │
        └─────────────────────┘
```

### File Permissions

| File | Permissions | Rationale |
|------|-------------|-----------|
| `rootCA.key` | 0600 | Only owner should read |
| `server.key` | 0600 | Only owner should read |
| `rootCA.crt` | 0644 | Public certificate |
| `server.crt` | 0644 | Public certificate |
| `cert-full-chain.pem` | 0644 | Public certificate |

### Attack Surface Considerations

1. **Root CA key compromise**: Attacker can issue trusted certificates
   - **Mitigation**: Keep offline, encrypted backups, access control

2. **Server key compromise**: Attacker can impersonate that server
   - **Mitigation**: File permissions, regular rotation

3. **Addon compromise**: Malicious addon could damage system
   - **Mitigation**: Review addons before use, run as unprivileged user

## Performance Considerations

### Certificate Operations

| Operation | Time | Notes |
|-----------|------|-------|
| Root CA creation | <1 second | One-time operation |
| Server certificate | <1 second | Per server |
| Addon execution | 10-20 minutes | Depends on addon |

### Scalability

- **Servers**: No hard limit (each is a directory in `certs/`)
- **Addons**: No hard limit (each is scanned on startup)
- **Certificates**: ~1KB per cert, negligible storage

## Troubleshooting Architecture

### Log Strategy

```
Component          Log File          Purpose
─────────────────────────────────────────────────────────
main.sh           main.log          General operations, errors
ansible-synapse   ansible-synapse.log  Ansible operations
Browser           DevTools Console   Client-side issues
Synapse           docker logs        Homeserver issues
Traefik           docker logs        Reverse proxy issues
```

### Debug Mode

Not currently implemented, but could be added by:

```bash
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x  # Print commands before execution
fi
```

## Future Considerations

### Potential Improvements

1. **Configuration file**: `~/.matrix-plus.conf` for user preferences
2. **Remote Root CA**: Fetch from URL instead of local file
3. **Certificate auto-renewal**: Check expiration and regenerate
4. **Addon marketplace**: Discover and install addons from repository
5. **Web UI**: Browser-based interface for certificate management

### Technical Debt

1. **No unit tests**: Should test core functions
2. **Limited error messages**: Some errors lack context
3. **No rollback**: Failed installations leave partial state
4. **Manual addon discovery**: Could use plugin system

## Conclusion

Matrix Plus is designed to be simple, modular, and understandable. The architecture follows the Unix philosophy: do one thing well (certificate management) and delegate the rest (installation) to specialized tools (addons).

For implementation details, see the source code in `main.sh`. For extension details, see the [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md).
