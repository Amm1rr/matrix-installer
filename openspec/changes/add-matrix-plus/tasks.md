## 1. Core Orchestrator

- [x] 1.1 Create `main.sh` with SSL Manager module
- [x] 1.2 Implement Addon Loader for dynamic module discovery
- [x] 1.3 Implement Environment Provider for secure variable injection
- [x] 1.4 Add interactive menu system for addon selection
- [x] 1.5 Extract UI/Helpers functions from `install.sh`

## 2. Certificate Infrastructure

- [x] 2.1 Create `certs/` directory structure
- [x] 2.2 Extract SSL functions from `install.sh`
- [x] 2.3 Implement Root CA detection next to `main.sh`
- [x] 2.4 Implement Root CA loading prompt (y/N)
- [x] 2.5 Implement Root CA copy to `certs/` with overwrite
- [x] 2.6 Implement Root CA generation with `v3_ca` extensions
- [x] 2.7 Implement server certificate signing with SAN (IP + DNS)
- [x] 2.8 Add certificate chain generation (server + Root CA)

## 3. Dynamic Menu System

- [x] 3.1 Implement menu based on `certs/rootCA.crt` existence
- [x] 3.2 Menu with Root CA: Generate cert, Install addon, New Root CA, Exit
- [x] 3.3 Menu without Root CA: Generate Root CA, Exit
- [x] 3.4 Add overwrite warning for existing Root CA

## 4. Addon Interface Definition

- [x] 4.1 Define environment variable protocol (SERVER_NAME, SSL_CERT, SSL_KEY, ROOT_CA)
- [x] 4.2 Document addon `install.sh` contract
- [x] 4.3 Create addon validation helper

## 5. Ansible-Synapse Module

- [x] 5.1 Create `ansible-synapse/` directory
- [x] 5.2 Extract all Ansible logic from `install.sh`
- [x] 5.3 Extract Synapse configuration logic from `install.sh`
- [x] 5.4 Implement `ansible-synapse/install.sh` (self-contained)
- [x] 5.5 Extract inventory/hosts configuration
- [x] 5.6 Extract vars.yml configuration
- [ ] 5.7 Test ansible-synapse module end-to-end

## 6. Documentation

- [ ] 6.1 Update user guide with new workflow
- [x] 6.2 Document addon interface protocol
- [ ] 6.3 Document Root CA loading workflow
- [ ] 6.4 Add federation troubleshooting section
