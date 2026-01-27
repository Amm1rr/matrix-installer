# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

## Project Overview

Matrix Installer is a modular installation system for Matrix homeservers. The project uses a private Root Key approach to enable federation between self-hosted Matrix servers without requiring public certificate authorities.

## Running the Project

```bash
# Main entry point - starts the interactive CLI
./matrix-installer.sh

# View logs
cat matrix-installer.log
cat addons/*/install.log  # Addon-specific logs

# Check certificate structure
ls -R certs/
```

## Architecture

### Core Components

**`matrix-installer.sh`** - The orchestrator (1400+ lines)
- Certificate management (Root Key creation, server certificate generation)
- Addon discovery and loading
- Interactive menu system
- Environment variable export to addons

**Certificate System:**
- Hierarchical structure: `certs/<root-ca-name>/servers/<server>/`
- Root Key: 4096-bit RSA, 10-year validity
- Server certificates: 4096-bit RSA, 1-year validity, signed by Root Key
- Supports multiple Root Keys simultaneously

**Addon System:**
- Auto-discovered from `addons/*/install.sh`
- Validated by `ADDON_NAME` in first 15 lines
- Receives certificates via environment variables
- Takes full control (matrix-installer.sh exits after invoking)

### Directory Structure

```
script/
├── matrix-installer.sh              # Main orchestrator
├── CLAUDE.md            # This file
├── AGENTS.md            # OpenSpec agent instructions
├── certs/               # Generated at runtime (gitignored)
│   └── <root-ca-name>/  # Root Key directory (IP or domain)
│       ├── rootCA.key   # Root Key private key (0600)
│       ├── rootCA.crt   # Root Key certificate (0644)
│       └── servers/     # Server certificates for this Root Key
│           └── <server>/
│               ├── server.key
│               ├── server.crt
│               └── cert-full-chain.pem
├── addons/              # Installation modules
│   └── <name>/install.sh
├── docs/                # User and developer documentation
└── openspec/            # Project specifications
```

## Code Conventions

### Bash Style
- Strict mode: `set -e`, `set -u`, `set -o pipefail` (always)
- Function naming: `module_action()` pattern (e.g., `ssl_manager_create_root_ca`)
- Constants: `UPPER_SNAKE_CASE`
- Logging: `print_message()` with types: info, success, warning, error
- Section headers: `# ===========================================`

### Addon Interface
Every addon must:
1. Define `ADDON_NAME` in first 15 lines of `install.sh`
2. Use `set -e -u -o pipefail`
3. Read environment variables: `SERVER_NAME`, `SSL_CERT`, `SSL_KEY`, `ROOT_CA`, `ROOT_CA_DIR`, `CERTS_DIR`, `WORKING_DIR`
4. Create its own log file

### Environment Variables Exported to Addons

| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_NAME` | Server IP or domain | `192.168.1.100` |
| `SSL_CERT` | Full certificate chain | `/path/to/certs/.../cert-full-chain.pem` |
| `SSL_KEY` | Server private key | `/path/to/certs/.../server.key` |
| `ROOT_CA` | Root Key certificate path | `/path/to/certs/.../rootCA.crt` |
| `ROOT_CA_DIR` | Root Key directory | `/path/to/certs/192.168.1.100` |
| `CERTS_DIR` | Certificates directory | `/path/to/certs` |
| `WORKING_DIR` | Script working directory | `/path/to/script` |

## Key Patterns

### Certificate Hierarchy
The system uses a hierarchical structure where each Root Key has its own directory with a `servers/` subdirectory. This allows multiple Root Keys to coexist, each managing their own set of server certificates.

### Handoff Pattern
When an addon is invoked, `matrix-installer.sh` **exits immediately** (see `menu_run_addon()` at line 1348). The addon becomes PID 1 and takes full control. This is intentional—addons are expected to handle everything from that point, including showing their own menus.

### Root Key Detection
The system first detects Root Key files next to `matrix-installer.sh` (`<name>.key`/`<name>.crt` pairs) and offers to import them. Only then does it check `certs/` for existing Root Keys.

## Common Tasks

### Adding a New Addon
Create `addons/<name>/install.sh` with:
```bash
#!/bin/bash
ADDON_NAME="your-addon"
ADDON_VERSION="1.0.0"
set -e -u -o pipefail
# Use $SERVER_NAME, $SSL_CERT, $SSL_KEY, $ROOT_CA...
```

### Certificate Validation
```bash
# Verify Root Key
openssl x509 -in certs/<name>/rootCA.crt -noout -text

# Verify server cert
openssl x509 -in certs/<name>/servers/<server>/server.crt -noout -text

# Check certificate chain
openssl s_client -connect $SERVER_NAME:443 -showcerts
```

### Working with OpenSpec
```bash
# List active changes
openspec list

# List specifications
openspec list --specs

# Validate a change
openspec validate <change-id> --strict

# Show details
openspec show <item>
```

## Important Constraints

- Root Key private keys must never be exposed to network
- All private keys must have 0600 permissions
- Server certificate validity: 365 days (configurable via `SSL_CERT_DAYS`)
- Root Key validity: 3650 days (configurable via `SSL_CA_DAYS`)
- Requires Bash 4+, OpenSSL installed

## Documentation

- `docs/01-start/` - User guides and quick reference
- `docs/02-develop/` - Addon development, interface specs
- `docs/03-deep-dive/` - Architecture, SSL details, troubleshooting
- `openspec/` - Formal specifications and change proposals
