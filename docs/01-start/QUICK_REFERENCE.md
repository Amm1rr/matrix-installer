# Matrix Installer Quick Reference

This is a quick reference guide for Matrix Installer. For complete documentation, see the [User Guide](USER_GUIDE.md).

## Quick Start

```bash
cd /path/to/script
./matrix-installer.sh
```

## Menu System

### Without Root Key

```
Root Key: Not Available

  1) Generate new Root Key
  2) Exit
```

### With Root Key

```
Root Key: Available
  | Subject: Matrix Root Key
  | Expires: 2034-01-25 (in 3650 days)
  | Country: UK

  1) Generate server certificate

  2) Install Docker Synapse (Let's Encrypt)
  3) Install Docker Synapse (Private Key)
  4) Install Zanjir Synapse (Private Key+Dendrite)
  5) Install Synapse by Ansible (Private Key)


  ---------------------------
  S) Switch active Root Key (MatrixUK)
  N) Create new Root Key
  0) Exit
```

The addon list is dynamic—all addons in `addons/` appear here.

## Directory Structure

```
script/
├── matrix-installer.sh     # Main orchestrator
├── certs/                  # Certificate storage
│   ├── rootCA.key          # Root Key private key
│   ├── rootCA.crt          # Root Key certificate
│   └── <server>/           # Per-server certificates
│       ├── server.key
│       ├── server.crt
│       └── cert-full-chain.pem
└── addons/                 # Installation modules
    ├── ansible-synapse/
    ├── docker-compose-synapse/
    └── ...
```

## Common Workflows

### First Time Setup

1. Run `./matrix-installer.sh`
2. Choose "Generate new Root Key"
3. Choose "Generate server certificate"
4. Select an addon to install

### Adding Another Server

1. Run `./matrix-installer.sh`
2. Choose "Generate server certificate" (for new server)
3. Select an addon to install

### Reusing an Existing Root Key

1. Copy `*.key` and `*.crt` next to `matrix-installer.sh` (e.g., `server.key` and `server.crt`)
2. Run `./matrix-installer.sh`
3. Accept the prompt to use existing Root Key

## Environment Variables Passed to Addons

| Variable | Description |
|----------|-------------|
| `SERVER_NAME` | Server IP or domain |
| `SSL_CERT` | Path to full-chain certificate |
| `SSL_KEY` | Path to private key |
| `ROOT_CA` | Path to Root Key certificate |
| `CERTS_DIR` | Certificates directory |
| `WORKING_DIR` | Working directory |

## Log Files

- `matrix-installer.log` - Main script log
- `ansible-synapse.log` - Ansible addon log (if used)
- `docker-compose-synapse.log` - Docker addon log (if used)
- `private-key-docker-compose-synapse.log` - Docker (Private Key) addon log (if used)
- `zanjir-synapse.log` - Zanjir addon log (if used)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Root Key not detected | Ensure `*.key` and `*.crt` files have identical names (e.g., `server.key` and `server.crt`) as expected by `matrix-installer.sh` |
| Certificate errors | Regenerate server certificate from menu |
| Addon not showing | Check `install.sh` has `ADDON_NAME` in first 15 lines |
| Installation failed | Check relevant log file in working directory |

## Security Notes

1. **Keep `rootCA.key` private** - anyone with this file can issue trusted certificates
2. **Backup your Root Key** - store encrypted copies in a safe location
3. **File permissions** - private keys should be 0600, certificates 0644
4. **Monitor expiration** - Root Key valid for 10 years, server certs for 1 year

## Documentation Index

- [User Guide](USER_GUIDE.md) - Complete end-user guide
- [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md) - Creating addons
- [Addon Interface Protocol](ADDON_INTERFACE.md) - Technical interface specs
- [Manual SSL Certificates](MANUAL_SSL_CERTIFICATES.md) - SSL certificate details
- [Root Key Workflow](ROOT_CA_WORKFLOW.md) - Certificate authority management
- [Federation Troubleshooting](FEDERATION_TROUBLESHOOTING.md) - Federation issues
