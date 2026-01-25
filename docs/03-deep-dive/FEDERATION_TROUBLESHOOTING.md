# Federation Troubleshooting Guide

## Overview

Matrix federation allows homeservers to communicate with each other. This guide covers common federation issues and their solutions.

## Common Issues

### 1. Certificate Verification Failures

**Symptom:**
```
Failed to fetch federation endpoint: SSL: CERTIFICATE_VERIFY_FAILED
```

**Causes:**
- Self-signed certificates not trusted
- Root CA not installed in system trust store
- Certificate chain incomplete

**Solutions:**

#### Option A: Disable Certificate Verification (IP-based deployments)

The `ansible-synapse` addon automatically sets this for IP-based deployments:

```yaml
matrix_synapse_configuration_extension_yaml: |
  federation_verify_certificates: false
```

#### Option B: Install Root CA in System Trust Store

For domain-based deployments with proper certificates:

```bash
# Copy Root CA to system trust store
sudo cp certs/rootCA.crt /usr/local/share/ca-certificates/matrix-root-ca.crt
sudo update-ca-certificates
```

#### Option C: Use Full Chain Certificate

Ensure `cert-full-chain.pem` includes both server certificate and Root CA:

```bash
cat certs/server.crt certs/rootCA.crt > certs/cert-full-chain.pem
```

### 2. IP Range Blacklist Blocking Federation

**Symptom:**
```
Federation blocked: IP in blacklist
```

**Causes:**
- Default Synapse configuration blocks private/local IP ranges
- IP-based federation requires removing this restriction

**Solution:**

The `ansible-synapse` addon automatically sets this for IP-based deployments:

```yaml
matrix_synapse_federation_ip_range_blacklist: []
```

**Manual verification:**

```bash
# Check Synapse configuration
docker exec matrix-synapse cat /data/homeserver.yaml | grep -A 5 ip_range_blacklist
```

### 3. Firewall Blocking Federation Port

**Symptom:**
```
Connection timeout to remote server
```

**Causes:**
- Port 8448 (federation) not open
- Firewall blocking incoming connections

**Solution:**

Verify firewall rules:

```bash
# Check if port is listening
sudo ss -tlnp | grep 8448

# For UFW
sudo ufw status | grep 8448

# For firewalld
sudo firewall-cmd --list-ports | grep 8448
```

Open federation port:

```bash
# UFW
sudo ufw allow 8448/tcp comment 'Matrix Federation'

# firewalld
sudo firewall-cmd --permanent --add-port=8448/tcp
sudo firewall-cmd --reload
```

### 4. Well-Known Federation Record Missing

**Symptom:**
```
Failed to discover server via well-known
```

**Causes:**
- Domain-based deployment missing `.well-known` record
- DNS not configured properly

**Solution:**

For IP-based deployments, this is not required. For domain-based:

Create `.well-known/matrix/server` file:

```json
{
  "m.server": "matrix.example.com:8448"
}
```

Create `.well-known/matrix/client` file:

```json
{
  "m.homeserver": {
    "base_url": "https://matrix.example.com"
  }
}
```

### 5. Root CA Mismatch Between Servers

**Symptom:**
```
Servers cannot verify each other's certificates
```

**Causes:**
- Each server has different Root CA
- Servers not configured to trust the same CA chain

**Solution:**

#### Option A: Use Same Root CA

1. Generate Root CA on first server
2. Copy `rootCA.key` and `rootCA.crt` to other servers
3. Place next to `main.sh` and accept prompt
4. Generate server certificates signed by same CA

#### Option B: Cross-Trust Root CAs

Copy each server's Root CA to the other:

```bash
# On Server A
sudo cp serverB_rootCA.crt /usr/local/share/ca-certificates/matrix-server-b.crt
sudo update-ca-certificates

# On Server B
sudo cp serverA_rootCA.crt /usr/local/share/ca-certificates/matrix-server-a.crt
sudo update-ca-certificates
```

### 6. DNS Resolution Issues

**Symptom:**
```
Failed to resolve hostname
```

**Causes:**
- DNS not configured
- Using IP addresses without proper SAN
- Reverse DNS missing

**Solution:**

For IP-based federation:
- Ensure server certificate includes IP in SAN
- Use `matrix_synapse_federation_ip_range_blacklist: []`

For domain-based federation:
- Configure proper DNS records
- Set up reverse DNS (optional but recommended)

## Diagnostic Commands

### Check Federation Status

```bash
# From inside Synapse container
docker exec matrix-synapse curl -s https://<remote-server>/_matrix/federation/v1/version

# Check if federation is enabled
docker exec matrix-synapse cat /data/homeserver.yaml | grep federation_enabled
```

### Test Certificate Chain

```bash
# Verify certificate chain is complete
openssl s_client -connect <server>:8448 -showcerts

# Check certificate validity
openssl x509 -in certs/cert-full-chain.pem -noout -text | grep -A 2 "Subject Alternative Name"
```

### Check Network Connectivity

```bash
# Test port 8448
nc -zv <remote-server> 8448

# Test federation endpoint
curl -v https://<remote-server>:_matrix/federation/v1/version
```

### View Synapse Logs

```bash
# View recent logs
docker logs matrix-synapse --tail 100

# Follow logs in real-time
docker logs matrix-synapse -f

# Search for federation errors
docker logs matrix-synapse 2>&1 | grep -i federation
```

## Configuration Verification

### Verify Synapse Configuration

```bash
# Check federation is enabled
docker exec matrix-synapse grep -A 5 "federation_enabled" /data/homeserver.yaml

# Check certificate verification setting
docker exec matrix-synapse grep -A 5 "federation_verify_certificates" /data/homeserver.yaml

# Check IP range blacklist
docker exec matrix-synapse grep -A 10 "ip_range_blacklist" /data/homeserver.yaml
```

### Verify Traefik Configuration

```bash
# Check SSL certificate paths
docker exec matrix-traefik cat /traefik/ssl/cert.pem

# Verify Traefik can access certificates
ls -la /matrix/traefik/ssl/
```

## IP-Based vs Domain-Based Federation

### IP-Based Federation

**Characteristics:**
- Uses IP addresses instead of domain names
- Certificate verification disabled
- IP range blacklist disabled
- Suitable for isolated/private networks

**Configuration:**
```yaml
matrix_synapse_federation_enabled: true
matrix_synapse_federation_ip_range_blacklist: []
matrix_synapse_configuration_extension_yaml: |
  federation_verify_certificates: false
```

**Limitations:**
- Not recommended for public servers
- Requires manual trust establishment
- Limited discoverability

### Domain-Based Federation

**Characteristics:**
- Uses domain names
- Certificate verification enabled
- Standard IP range blacklist
- Suitable for public federation

**Configuration:**
```yaml
matrix_synapse_federation_enabled: true
# Use default IP range blacklist
```

**Requirements:**
- Valid DNS records
- Proper certificates (Let's Encrypt or trusted CA)
- `.well-known` records configured

## Testing Federation

### Test Between Two Servers

```bash
# From Server A, test connection to Server B
curl -X GET \
  "https://server-b-ip:8448/_matrix/federation/v1/version" \
  -H "Host: server-b-ip"

# Expected response:
# {"server":{"name":"Synapse","version":"1.x.x"}}
```

### Check Server List in Admin Console

1. Log in to Element Web
2. Go to Room Settings → Advanced
3. Check "Servers in this room" section

### Use Federation Tester

Online tools:
- https://federation-tester.matrix.org/
- https://matrix.org/federation-test

## Common Pitfalls

1. **Forgetting to Restart Services**
   - After certificate changes, restart Synapse and Traefik
   - `systemctl restart matrix-synapse matrix-traefik`

2. **Using Wrong Certificate Format**
   - Traefik expects PEM format
   - Ensure `cert-full-chain.pem` is used, not just `server.crt`

3. **Missing SAN in Certificates**
   - Modern clients require Subject Alternative Names
   - IP addresses must be in SAN for IP-based federation

4. **Ignoring Firewall Rules**
   - Both TCP 443 and 8448 must be open
   - Check both local firewall and cloud provider rules

5. **Mixing IP and Domain Names**
   - Be consistent: use either IP or domain, not both
   - Certificate must match `matrix_domain` setting

## Getting Help

If issues persist:

1. Collect diagnostic information:
   ```bash
   # Export logs
   docker logs matrix-synapse > synapse.log
   docker logs matrix-traefik > traefik.log

   # Export configuration
   ansible-inventory -i matrix-docker-ansible-deploy/inventory/hosts --list
   ```

2. Check relevant documentation:
   - Synapse Federation Guide
   - Matrix Installer User Guide
   - Addon Interface Documentation

3. Seek help from:
   - Matrix community forums
   - Project issue tracker
   - System administrator
