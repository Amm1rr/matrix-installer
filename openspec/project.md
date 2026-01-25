# Project Context

## Purpose
Matrix Plus is a modular installation system for Matrix homeservers. Its primary goal is to simplify the deployment of private Matrix federated servers by handling complex SSL/TLS certificate management and delegating actual installation to specialized addons. The system uses a private Root CA approach to enable federation between self-hosted Matrix servers without requiring public certificate authorities.

## Tech Stack
- **Shell Script (Bash)** - Core orchestrator and certificate management
- **OpenSSL** - SSL/TLS certificate generation and signing
- **Docker** - Container runtime (used by addons)
- **Docker Compose** - Multi-container orchestration (used by some addons)
- **Ansible** - Configuration management (used by some addons)

### Matrix Components
- **Synapse** - Matrix homeserver reference implementation
- **Traefik** - Reverse proxy and SSL termination
- **PostgreSQL** - Database backend for Synapse

## Project Conventions

### Code Style
- **Bash Strict Mode**: All scripts use `set -e`, `set -u`, `set -o pipefail`
- **Function Naming**: `module_action()` pattern (e.g., `ssl_manager_init()`, `addon_loader_run()`)
- **Constants**: UPPER_SNAKE_CASE with descriptive names
- **Logging**: Use `print_message()` helper with types: info, success, warning, error
- **Comments**: Section headers use `# ===========================================` format

### File Structure
```
script/
├── main.sh              # Main orchestrator script
├── certs/               # SSL certificates (generated at runtime)
│   ├── rootCA.key
│   ├── rootCA.crt
│   └── <server>/        # Per-server certificates
├── addons/              # Installation modules
│   └── <addon-name>/
│       └── install.sh
├── docs/                # Documentation
└── openspec/            # Project specifications
```

### Architecture Patterns
- **Modular Design**: Core system handles certificates only; installation delegated to addons
- **Environment Provider**: Certificates and configuration passed via exported environment variables
- **Dynamic Discovery**: Addons auto-discovered by scanning `addons/*/install.sh`
- **Handoff Pattern**: `main.sh` exits when addon takes control (addon becomes PID 1)

### Addon Interface Protocol
Every addon must:
1. Define `ADDON_NAME` variable in first 15 lines of `install.sh`
2. Use `set -e -u -o pipefail` for error handling
3. Read environment variables: `SERVER_NAME`, `SSL_CERT`, `SSL_KEY`, `ROOT_CA`, `CERTS_DIR`, `WORKING_DIR`
4. Create its own log file

### Testing Strategy
- Manual testing of addon installation flows
- Certificate validation using OpenSSL commands
- Federation testing between servers

### Git Workflow
- Main branch: `master`
- Feature branches: Descriptive names (e.g., `matrix-plus`)
- Commit messages: Follow conventional commit format
- No automated commits (user preference)

## Domain Context

### Matrix Federation
Matrix servers communicate using federation protocol which requires:
1. Each server has a valid SSL certificate
2. Servers trust each other's certificates
3. Well-known federation endpoints (`/.well-known/matrix/server`)

### Private Certificate Authority
Matrix Plus uses a private Root CA approach:
- Root CA created once per deployment (10-year validity)
- Server certificates signed by private Root CA (1-year validity)
- Root CA certificate distributed to all servers for trust

### Addon Types
- **ansible-synapse**: Ansible-based installation for production environments
- **docker-compose-synapse**: Docker Compose deployment for development/testing
- **private-key-docker-compose-synapse**: Variant with private key authentication
- **zanjir-synapse**: Custom deployment variant

## Important Constraints
- Root CA private key (`rootCA.key`) must never be exposed to network
- Server certificates valid for 365 days by default
- Root CA valid for 3650 days (10 years) by default
- All private keys must have 0600 permissions
- Scripts require Bash 4+ (specific features used)
- Requires OpenSSL installed on host system

## External Dependencies
- **OpenSSL** - Required for certificate operations
- **iproute2** - For IP address detection (used in prompts)
- **Docker** - Required by docker-compose addons
- **Docker Compose** - Required by docker-compose addons
- **Ansible** - Required by ansible addons (when used)

## Certificate Reference

### Root CA
- Location: `certs/rootCA.crt`, `certs/rootCA.key`
- Default: 4096-bit RSA, SHA256
- Validity: 3650 days (configurable)

### Server Certificates
- Location: `certs/<server>/`
- Files: `server.key`, `server.crt`, `cert-full-chain.pem`
- Default: 4096-bit RSA, SHA256
- Validity: 365 days (configurable)
- SAN: Includes server IP/domain, matrix.local, localhost

### Environment Variables Exported to Addons
| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_NAME` | Server IP or domain | `192.168.1.100` |
| `SSL_CERT` | Full certificate chain | `/path/to/certs/server/cert-full-chain.pem` |
| `SSL_KEY` | Server private key | `/path/to/certs/server/server.key` |
| `ROOT_CA` | Root CA certificate path | `/path/to/certs/rootCA.crt` |
| `CERTS_DIR` | Certificates directory | `/path/to/certs` |
| `WORKING_DIR` | Script working directory | `/path/to/script` |
