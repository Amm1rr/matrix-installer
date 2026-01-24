# Project Context

## Purpose
Matrix-Plus is a modular, decentralized Matrix installation system designed for **isolated networks** (air-gapped environments) without external CA dependencies like Let's Encrypt. It enables private federation between Matrix servers using a shared Root CA trust chain.

**Language:** Persian (Farsi) documentation with English codebase

## Tech Stack

### Core Technologies
- **Bash**: Shell scripting for orchestration and automation
- **Ansible**: Configuration management and deployment automation
- **Docker**: Containerization for all Matrix services
- **OpenSSL**: Certificate generation and PKI management
- **Matrix Synapse**: Primary homeserver implementation
- **Element Web**: Matrix web client

### Supporting Tools
- **Traefik**: Reverse proxy for TLS termination
- **PostgreSQL**: Database backend
- **systemd**: Service management

### Supported Platforms
- **Linux**: Arch Linux, Manjaro, Debian, Ubuntu, Fedora, RHEL, CentOS
- **macOS**: Via Homebrew
- **Windows/WSL**: Via MSYS/MinGW/Cygwin

## Project Conventions

### Code Style

#### Shell Scripting (Bash)
- Use `set -e`, `set -u`, `set -o pipefail` for error handling
- Function naming: `snake_case` with descriptive names
- Constants: `UPPER_SNAKE_CASE`
- Color output: Use ANSI escape codes (`\033[0;31m`)
- All functions include header documentation:
  ```bash
  # ===========================================
  # FUNCTION: function_name
  # Description: Brief description
  # Arguments: $1 - first_arg, $2 - second_arg
  # Output: Description of return value
  # ===========================================
  ```

#### Configuration Files
- YAML for Ansible configurations
- 2-space indentation
- Inline comments for complex settings

#### Documentation
- Persian (Farsi) for user-facing docs
- English for code comments and technical docs
- Markdown format with clear section headers

### Architecture Patterns

#### Three-Layer Architecture (Proposed)
1. **Orchestrator Layer** (`main.sh`)
   - SSL Manager: Root CA generation and certificate signing
   - Addon Loader: Dynamic module discovery
   - Environment Provider: Secure variable injection

2. **Addon Layer** (`<addon>/install.sh`)
   - Standard entry point via `install.sh`
   - Input: Only via environment variables
   - Output: Docker compose files, service configs

3. **Infrastructure Layer** (`certs/`)
   - Root CA storage
   - Certificate chain for federation

#### Certificate Chain Pattern
```
Root CA (rootCA.crt)
    └── Server Certificate (server.crt) + Root CA → cert-full-chain.pem
```

### Testing Strategy

#### Manual Testing
- Local installation: `ansible_connection=local`
- Remote installation: SSH-based deployment
- Federation testing: Multiple servers with shared Root CA

#### Verification Steps
1. Certificate validation: `openssl verify`
2. Service status: `systemctl status matrix-*`
3. Federation test: Cross-server communication
4. Browser trust: Element Web access with self-signed cert

### Git Workflow

#### Branching
- `master`: Main development branch
- Feature branches: `feature/add-<capability>`

#### Commit Convention
- Prefix based: `docs:`, `feat:`, `fix:`, `refactor:`
- Persian commit messages acceptable for user docs

#### No Auto-Commit
- Never create git commits without explicit user request

## Domain Context

### Matrix Federation
- **Federation**: Decentralized communication between Matrix homeservers
- **Server Name**: Identity in Matrix network (IP or domain)
- **Well-known**: Discovery mechanism for federation

### Private PKI
- **Root CA**: Trust anchor for isolated network
- **Certificate Signing**: SAN (Subject Alternative Names) with IP + DNS
- **Chain of Trust**: All servers trust the same Root CA

### Isolated Networks
- No internet access for ACME/Let's Encrypt
- Self-signed certificates required
- Manual Root CA distribution to clients

## Important Constraints

### Security
- **Private Key Protection**: Root CA private key must be kept secure
- **No Certificate Verification**: `federation_verify_certificates: false` required for IP-based federation
- **Credential Storage**: Avoid storing passwords in plaintext

### Network
- **Firewall Ports**: 443/tcp (HTTPS), 8448/tcp (Federation)
- **IP Range Blacklist**: Must be emptied for IP-based federation
- **IPv6 Support**: Enabled by default

### Deployment
- **Clean Installation**: Auto-cleanup of existing PostgreSQL data
- **Service Conflicts**: Auto-stop/disable existing Matrix services
- **Docker Volumes**: Preserved during reinstallation

## External Dependencies

### Ansible Playbook
- **Repository**: https://github.com/spantaleev/matrix-docker-ansible-deploy
- **Local Path**: `matrix-docker-ansible-deploy/`
- **Minimum Ansible Version**: 2.15.1

### System Packages
- `ansible`: Configuration management
- `git`: Version control
- `python3`/`python`: Python runtime
- `docker`: Container runtime
- `openssl`: Certificate management

### Services (via Ansible)
- Matrix Synapse: Homeserver
- Element Web: Web client
- PostgreSQL: Database
- Traefik: Reverse proxy
