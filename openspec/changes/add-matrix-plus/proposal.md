# Change: Modular Matrix Plus Installation System

## Why
The current `install.sh` is a monolithic 1966-line script that tightly couples SSL management, Ansible orchestration, and service configuration. This makes it difficult to:
- Add new Matrix homeserver implementations
- Reuse components across different installation methods
- Test individual components in isolation
- Maintain separation of concerns between infrastructure and service logic

## What Changes
- Add `main.sh` orchestrator with SSL Manager, Addon Loader, and Environment Provider
- Create `certs/` infrastructure directory for Root CA and certificate storage
- Define Root CA loading workflow: detect next to `main.sh`, prompt user, copy to `certs/`
- Define addon interface: `<addon>/install.sh` receiving environment variables
- Create `ansible-synapse/` module (self-contained: Ansible management + Synapse config)
- Establish environment variable protocol for addon communication
- Add `zanjir-synapse/` placeholder for future modules (not implemented)

## Impact
- **Affected specs**: New capabilities `orchestrator`, `ansible-addon`
- **Affected code**:
  - New: `main.sh`, `certs/`
  - New: `ansible-synapse/install.sh` (self-contained module)
  - Placeholder: `zanjir-synapse/` (future work, not implemented)
  - Legacy: `install.sh` remains for backward compatibility
