# docker-compose-synapse

Quick Docker Compose installer for Matrix Synapse with Let's Encrypt SSL and DuckDNS support.

## Version

2.3.0

## Description

This addon provides a fast, opinionated installation of Matrix Synapse using Docker Compose. It automatically configures Let's Encrypt SSL certificates via Traefik and uses DuckDNS for domain management.

## Features

- **Fast Installation**: Deploys in ~2-5 minutes
- **Automatic SSL**: Let's Encrypt certificates via Traefik ACME
- **DuckDNS Integration**: Automatic DNS updates
- **Full Stack**: Synapse, PostgreSQL, Traefik, Element Web, Synapse Admin
- **Root Execution**: Runs with root privileges for system-level configuration

## Requirements

### Software
- Docker
- Docker Compose (v2)
- curl
- openssl
- ufw (for firewall configuration)

### Network
- Ports 80 and 443 accessible from the internet
- Public IP address (auto-detected)

### DuckDNS Account
- DuckDNS account and API token
- DuckDNS subdomain configured

### Getting DuckDNS Token
1. Visit https://www.duckdns.org
2. Login or create an account
3. Copy your token from the dashboard

## Installation

Run from main.sh menu or execute directly:

```bash
./docker-compose-synapse/install.sh
```

Follow the prompts to configure:
1. DuckDNS token
2. DuckDNS subdomain
3. Max registrations per invite (default: 5)
4. Enable/disable user registration

## After Installation

### Access URLs
- **Element Web**: `https://your-subdomain.duckdns.org`
- **Admin UI**: `https://your-subdomain.duckdns.org/admin`
- **Matrix API**: `https://your-subdomain.duckdns.org/_matrix/`

### Default Admin User
- **Username**: `admin`
- **Password**: Auto-generated (shown after installation)

### Docker Compose Management
```bash
cd /opt/matrix

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d
```

## Uninstallation

From the addon menu, select "Uninstall Matrix" or run:

```bash
cd /opt/matrix
docker compose down -v
cd /
rm -rf /opt/matrix
```

## SSL Certificates

This addon uses **Let's Encrypt** for SSL certificate management. Certificates are:
- Automatically generated via Traefik ACME challenge
- Stored in `/opt/matrix/data/traefik/acme.json`
- Auto-renewed by Traefik

**Note**: This does NOT use the custom Root Key certificates from main.sh. Let's Encrypt certificates are trusted by all clients automatically.

## Registration Configuration

### Shared Secret
A registration shared secret is auto-generated during installation. Find it in:
- `/opt/matrix/data/synapse/homeserver.yaml`

### Max Registrations Per Invite
Controls how many times a single invite token can be used. Default: 5

### Enable/Disable Registration
User registration can be enabled or disabled during installation.

## Services

| Service | Description |
|---------|-------------|
| **Synapse** | Matrix homeserver |
| **PostgreSQL** | Database backend |
| **Traefik** | Reverse proxy & SSL termination |
| **Element** | Web client |
| **Synapse Admin** | Admin interface |

## Troubleshooting

### SSL Certificate Issues
```bash
# Reset SSL certificates
cd /opt/matrix
rm -f data/traefik/acme.json
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json
docker compose restart traefik
```

### Container Not Starting
```bash
# Check logs
cd /opt/matrix
docker compose logs [service-name]

# Restart all services
docker compose restart
```

### DuckDNS Not Updating
Verify your token and subdomain are correct:
```bash
curl "https://www.duckdns.org/update?domains=YOUR_SUBDOMAIN&token=YOUR_TOKEN&ip=$(curl -sS https://api.ipify.org)"
```

## Comparison with ansible-synapse

| Feature | docker-compose-synapse | ansible-synapse |
|---------|----------------------|-----------------|
| **Speed** | ~2-5 minutes | ~10-20 minutes |
| **SSL** | Let's Encrypt (automatic) | Custom Root Key (manual) |
| **Target** | Local only | Local OR remote via SSH |
| **Execution** | Runs as root | Uses sudo password |
| **Deployment** | Direct docker-compose | Ansible playbook |
| **DNS** | DuckDNS required | IP or domain |
| **Complexity** | Simple, opinionated | Flexible, configurable |

### When to Use docker-compose-synapse
- Quick testing and development
- Personal servers
- DuckDNS users
- When automatic SSL is preferred

### When to Use ansible-synapse
- Production deployments
- Remote servers
- Custom domains
- When flexibility is needed

## Security Notes

1. **Root Privileges**: This addon requires root access for system configuration
2. **DuckDNS Token**: Your token is used but not stored (prompted each installation)
3. **Passwords**: Auto-generated and shown once after installation
4. **Firewall**: Ports 80 and 443 are automatically opened via ufw

## License

Part of Matrix Installer project.

## Author

Matrix Installer Team
