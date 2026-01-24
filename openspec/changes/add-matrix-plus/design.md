## Context

Matrix-Plus aims to transform the monolithic `install.sh` (1966 lines) into a modular system where:
- Core orchestration (SSL, menu, env vars) lives in `main.sh`
- Each addon is self-contained with embedded Ansible management
- Addons communicate only via environment variables
- Root CA can be loaded from next to `main.sh` or generated in `certs/`

### Stakeholders
- System administrators deploying Matrix in isolated networks
- Developers adding new homeserver implementations
- Users needing simple installation with minimal interaction

## Goals / Non-Goals

### Goals
- Modular architecture enabling independent addon development
- Self-contained addons with embedded Ansible management
- Root CA loading workflow: detect next to `main.sh`, prompt user, copy to `certs/`
- Standardized environment variable protocol for addon communication
- Backward compatibility with existing `install.sh`

### Non-Goals
- Separate ansible-manager module (each addon is self-contained)
- Complete rewrite of existing Ansible playbook logic
- Cross-platform addon support (Linux only initially)
- Implementation of `zanjir-synapse` in this phase (placeholder only)

## Decisions

### 1. Orchestrator Architecture
**Decision**: Three-layer architecture with `main.sh` as orchestrator

```
main.sh (Orchestrator)
├── UI/Helpers
├── SSL Manager (Root CA loading/generation, server certificates)
└── Addon Loader & Menu
```

### 2. Root CA Loading Workflow
**Decision**: Detect Root CA next to `main.sh`, prompt user, copy to `certs/`

**Workflow**:
```
./main.sh starts
    ↓
Check for rootCA.crt/rootCA.key next to main.sh
    ↓
Found? → Ask user: "Use this rootCA? [y/N]"
    ├─ Yes → Copy to certs/ (overwrite if exists)
    └─ No  → Continue
    ↓
Menu based on certs/rootCA.crt existence
```

**Rationale**: Allows users to bring their own Root CA for federation while keeping all certificates in organized `certs/` directory.

### 3. Self-Contained Addons
**Decision**: Each addon includes its own Ansible management logic

```
ansible-synapse/
└── install.sh (Ansible + Synapse config all-in-one)
```

**Rationale**: No dependency on external ansible-manager module. Each addon is independently deployable and testable.

**Responsibilities embedded in each addon**:
- Install Ansible (if not present)
- Clone/update matrix-docker-ansible-deploy playbook
- Install ansible-galaxy roles
- Configure inventory and vars.yml
- Execute playbook with given tags
- Create admin user

### 4. Addon Communication Protocol
**Decision**: Environment variables only

**SSL Protocol** (from main.sh to addon):
```bash
SERVER_NAME=<ip|domain>      # Matrix server identity
SSL_CERT=<path>               # Full chain certificate (certs/cert-full-chain.pem)
SSL_KEY=<path>                # Private key (certs/server.key)
ROOT_CA=<path>                # Root CA certificate (certs/rootCA.crt)
```

### 5. Certificate Storage
**Decision**: `certs/` directory in project root

**Rationale**: Single source of truth for PKI materials. Root CA loaded from next to `main.sh` is copied here.

| File | Source | Destination |
|------|--------|-------------|
| rootCA.key, rootCA.crt | Next to `main.sh` | `certs/` (on user approval) |
| rootCA.key, rootCA.crt | Generated | `certs/` |
| server.key, server.crt | Generated | `certs/` |
| cert-full-chain.pem | Generated | `certs/` |

### 6. Dynamic Menu System
**Decision**: Menu options depend on Root CA availability

**With Root CA** (`certs/rootCA.crt` exists):
```
1) Generate server certificate for Synapse
2) Install ansible-synapse addon
3) Generate new Root CA (overwrite existing)
4) Exit
```

**Without Root CA**:
```
1) Generate new Root CA
2) Exit
```

### 7. Addon Types
**Decision**: One implemented addon, one placeholder

- `ansible-synapse/`: Self-contained module (implemented in this phase)
- `zanjir-synapse/`: Placeholder for future alternative deployment (not implemented)

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| Addon interface breaking changes | High | Version the protocol, document carefully |
| Root CA key exposure | Critical | File permissions (0600), warn user |
| Root CA overwrite | High | Explicit user confirmation before overwrite |
| Certificate expiration | Medium | 10-year Root CA, 1-year server certs |
| Backward compatibility | Medium | Keep `install.sh` as legacy entry point |
| Code duplication in addons | Low | Acceptable for independence; can refactor later |

## Migration Plan

### Phase 1: Core Infrastructure
1. Create `main.sh` with basic menu system
2. Implement SSL Manager in `main.sh`
3. Create `certs/` directory
4. Extract UI/Helpers from `install.sh`
5. Implement Root CA detection next to `main.sh`
6. Implement Root CA loading prompt and copy to `certs/`

### Phase 2: Dynamic Menu System
1. Implement menu based on `certs/rootCA.crt` existence
2. Add Generate server certificate option
3. Add Install addon option
4. Add Generate new Root CA option (with overwrite warning)

### Phase 3: Ansible-Synapse Module
1. Create `ansible-synapse/` directory
2. Extract all Ansible logic from `install.sh`
3. Extract Synapse configuration logic from `install.sh`
4. Implement `ansible-synapse/install.sh` (self-contained)
5. Test end-to-end

### Phase 4: Documentation & Polish
1. Update user guides
2. Document addon interface protocol
3. Document Root CA loading workflow
4. Create troubleshooting guides

### Phase 5: Future Work (Not in Scope)
1. Implement `zanjir-synapse/` addon
2. Consider refactoring common Ansible logic if code duplication becomes problematic

### Rollback
- Keep `install.sh` functional throughout development
- Feature flag for enabling new system

## Open Questions

1. Should addons support post-installation configuration updates?
2. How to handle addon dependencies (e.g., PostgreSQL vs SQLite)?
3. Should we support addon uninstallation?
4. Should there be a way to list installed addons?
