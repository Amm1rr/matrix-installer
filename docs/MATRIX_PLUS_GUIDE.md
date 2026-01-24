# Matrix Plus User Guide

## Overview

Matrix Plus is a modular installation system for Matrix homeservers. It transforms the monolithic installation process into a flexible, addon-based architecture.

## Key Concepts

### Main Components

1. **`main.sh`**: Orchestrator that manages SSL certificates and addon installation
2. **`certs/`**: Directory for Root CA and server certificates
3. **Addons**: Self-contained modules for specific Matrix implementations
   - `ansible-synapse/`: Full Ansible-based Synapse installation
   - `zanjir-synapse/`: Placeholder for future Zanjir deployment

### Architecture

```
main.sh (Orchestrator)
├── SSL Manager
│   ├── Root CA detection (next to main.sh)
│   ├── Root CA generation
│   └── Server certificate generation
├── Addon Loader
│   └── Dynamic addon discovery
├── Environment Provider
│   └── Secure variable injection
└── Menu System
    ├── Dynamic menu based on Root CA availability
    └── Addon selection interface
```

## Installation Workflow

### Step 1: Prepare Root CA (Optional)

If you already have a Root CA certificate, place it next to `main.sh`:

```bash
cp /path/to/your/rootCA.key /path/to/script/
cp /path/to/your/rootCA.crt /path/to/script/
```

This allows you to use the same Root CA for multiple Matrix servers, enabling federation between them.

### Step 2: Run the Orchestrator

```bash
cd /path/to/script
./main.sh
```

### Step 3: Initial Menu (Without Root CA)

If no Root CA is detected, you'll see:

```
╔══════════════════════════════════════════════════════════╗
║                  Matrix Plus - Main Menu                ║
╚══════════════════════════════════════════════════════════╝

Root CA: Not Available

  1) Generate new Root CA
  2) Exit
```

**Choose option 1** to create a new Root CA.

### Step 4: Main Menu (With Root CA)

Once you have a Root CA, the menu expands:

```
╔══════════════════════════════════════════════════════════╗
║                  Matrix Plus - Main Menu                ║
╚══════════════════════════════════════════════════════════╝

Root CA: Available

  1) Generate server certificate for Synapse
  2) Install addon
  3) Generate new Root CA (overwrite existing)
  4) Exit
```

#### Option 1: Generate Server Certificate

Prompts for your server IP or domain, then generates a certificate with proper SAN (Subject Alternative Names) for Matrix federation.

#### Option 2: Install Addon

Lists available addons:

```
[INFO] Scanning for addons...
[INFO] Available addons:
  1) ansible-synapse

Select addon number (1-1):
```

The addon will receive SSL certificate paths via environment variables and proceed with installation.

#### Option 3: Generate New Root CA

Overwrites the existing Root CA (requires confirmation).

## Using Existing Root CA

### Workflow

1. Place `rootCA.key` and `rootCA.crt` next to `main.sh`
2. Run `./main.sh`
3. You'll be prompted: `Use this Root CA for Matrix Plus? [y/N]:`
4. If you accept, the files are copied to `certs/` directory

### Benefits

- **Federation**: Multiple servers using the same Root CA can federate
- **Consistency**: Same CA across all Matrix deployments
- **Control**: Keep your Root CA in a secure location

## Certificate Locations

All certificates are stored in the `certs/` directory:

```
certs/
├── rootCA.key              # Root CA private key (4096-bit)
├── rootCA.crt              # Root CA certificate (10-year validity)
├── server.key              # Server private key (4096-bit)
├── server.crt              # Server certificate (1-year validity)
└── cert-full-chain.pem     # Full chain (server.crt + rootCA.crt)
```

## Addon Development

See [ADDON_INTERFACE.md](../ADDON_INTERFACE.md) for details on creating custom addons.

## Troubleshooting

### Root CA Detection

If your Root CA next to `main.sh` is not detected:

1. Verify both `rootCA.key` and `rootCA.crt` exist
2. Check file permissions (key should be 0600, cert 0644)
3. Ensure files are in the same directory as `main.sh`

### Certificate Issues

If you encounter certificate errors:

1. Check certificate expiration: `openssl x509 -in certs/rootCA.crt -noout -dates`
2. Verify certificate chain: `openssl crl2pkcs7 -nocrl -certfile certs/cert-full-chain.pem | openssl pkcs7 -print_certs -noout`
3. Regenerate server certificate from main menu

### Addon Installation

If an addon fails:

1. Check log files: `ansible-synapse.log` or `main.log`
2. Verify environment variables are set: `echo $SERVER_NAME $SSL_CERT`
3. Ensure Ansible is installed: `ansible --version`

## Security Considerations

1. **Root CA Key**: Keep `rootCA.key` secure - it allows signing certificates for any domain
2. **File Permissions**:
   - Private keys: `0600` (owner read/write only)
   - Certificates: `0644` (world-readable)
3. **Password Storage**: Avoid storing passwords in inventory files when possible

## Migration from install.sh

The legacy `install.sh` is still available for backward compatibility. To migrate to Matrix Plus:

1. `install.sh` → `main.sh` (orchestrator)
2. Ansible logic is now in `ansible-synapse/install.sh`
3. Certificate generation is now in `main.sh` SSL Manager

## Support

For issues or questions:
- Check logs: `main.log`, `ansible-synapse.log`
- Review [ADDON_INTERFACE.md](../ADDON_INTERFACE.md) for addon protocol
- Open an issue on the project repository
