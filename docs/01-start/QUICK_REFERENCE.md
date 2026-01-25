# Matrix Plus Quick Reference

This is a quick reference guide for Matrix Plus. For complete documentation, see the [User Guide](USER_GUIDE.md).

## Quick Start

```bash
cd /path/to/script
./main.sh
```

## Menu System

### Without Root CA

```
Root CA: Not Available

  1) Generate new Root CA
  2) Exit
```

### With Root CA

```
Root CA: Available
  | Subject: Matrix Root CA
  | Expires: 2034-01-25 (in 3650 days)
  | Country: IR

  1) Generate server certificate
  2) Install ansible-synapse
  3) Install docker-compose-synapse
  4) Install private-key-docker-compose-synapse
  5) Install zanjir-synapse

  ---------------------------
  8) Generate new Root CA (overwrite existing)
  0) Exit
```

The addon list (options 2-5) is dynamic—all addons in `addons/` appear here.

## Directory Structure

```
script/
├── main.sh                 # Main orchestrator
├── certs/                  # Certificate storage
│   ├── rootCA.key          # Root CA private key
│   ├── rootCA.crt          # Root CA certificate
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

1. Run `./main.sh`
2. Choose "Generate new Root CA"
3. Choose "Generate server certificate"
4. Select an addon to install

### Adding Another Server

1. Run `./main.sh`
2. Choose "Generate server certificate" (for new server)
3. Select an addon to install

### Reusing an Existing Root CA

1. Copy `rootCA.key` and `rootCA.crt` next to `main.sh`
2. Run `./main.sh`
3. Accept the prompt to use existing Root CA

## Environment Variables Passed to Addons

| Variable | Description |
|----------|-------------|
| `SERVER_NAME` | Server IP or domain |
| `SSL_CERT` | Path to full-chain certificate |
| `SSL_KEY` | Path to private key |
| `ROOT_CA` | Path to Root CA certificate |
| `CERTS_DIR` | Certificates directory |
| `WORKING_DIR` | Working directory |

## Log Files

- `main.log` - Main script log
- `ansible-synapse.log` - Ansible addon log (if used)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Root CA not detected | Check that both `rootCA.key` and `rootCA.crt` exist next to `main.sh` |
| Certificate errors | Regenerate server certificate from menu |
| Addon not showing | Check `install.sh` has `ADDON_NAME` in first 15 lines |
| Installation failed | Check relevant log file in working directory |

## Security Notes

1. **Keep `rootCA.key` private** - anyone with this file can issue trusted certificates
2. **Backup your Root CA** - store encrypted copies in a safe location
3. **File permissions** - private keys should be 0600, certificates 0644
4. **Monitor expiration** - Root CA valid for 10 years, server certs for 1 year

## Documentation Index

- [User Guide](USER_GUIDE.md) - Complete end-user guide
- [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md) - Creating addons
- [Addon Interface Protocol](ADDON_INTERFACE.md) - Technical interface specs
- [Manual SSL Certificates](MANUAL_SSL_CERTIFICATES.md) - SSL certificate details
- [Root CA Workflow](ROOT_CA_WORKFLOW.md) - Certificate authority management
- [Federation Troubleshooting](FEDERATION_TROUBLESHOOTING.md) - Federation issues
