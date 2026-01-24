# Root CA Loading Workflow

## Overview

Matrix Plus supports loading an existing Root CA from next to `main.sh`, enabling you to use a single CA for multiple Matrix deployments. This is useful for:
- Federation between multiple servers in isolated networks
- Consistent certificate management
- Centralized PKI infrastructure

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      User runs ./main.sh                         │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ Check for rootCA.key and       │
              │ rootCA.crt next to main.sh     │
              └───────────────────────────────┘
                     │                    │
              Found? │                    │ Not Found
                     ▼                    △
              ┌─────────────┐              │
              │ Prompt user │              │
              │ "Use this   │              │
              │ Root CA?"   │              │
              └──────┬──────┘              │
                     │                     │
              ┌──────┴──────┐              │
              │             │              │
         Yes  │             │ No           │
              │             │              │
              ▼             △              │
       ┌──────────┐   ┌─────┴─────┐       │
       │ Copy to  │   │ Continue  │       │
       │ certs/   │   │ without   │       │
       │ with     │   │ copying   │       │
       │ overwrite│   │           │       │
       └────┬─────┘   └───────────┘       │
            │                              │
            └──────────┬───────────────────┘
                       ▼
          ┌────────────────────────┐
          │ Show menu based on      │
          │ certs/rootCA.crt exists │
          └────────────────────────┘
```

## Step-by-Step Process

### 1. Detection Phase

When `main.sh` starts, the SSL Manager checks for Root CA files:

```bash
# In main.sh, detect_root_ca() function
if [[ -f "${SCRIPT_DIR}/rootCA.key" ]] && [[ -f "${SCRIPT_DIR}/rootCA.crt" ]]; then
    ROOT_CA_DETECTED="true"
    ROOT_CA_SOURCE_PATH="$SCRIPT_DIR"
fi
```

**Requirements:**
- Both `rootCA.key` AND `rootCA.crt` must exist
- Files must be in the same directory as `main.sh`
- No specific naming pattern required beyond the exact filenames

### 2. Prompt Phase

If Root CA is detected, user is prompted:

```
[INFO] Root CA found at: /path/to/script
Use this Root CA for Matrix Plus? [y/N]:
```

**Behavior:**
- Default is "No" (N) for security
- Requires explicit "yes" or "y" to proceed
- Empty input defaults to "No"

### 3. Copy Phase

If user accepts, files are copied:

```bash
# Copy to certs/
cp "${ROOT_CA_SOURCE_PATH}/rootCA.key" "${CERTS_DIR}/rootCA.key"
cp "${ROOT_CA_SOURCE_PATH}/rootCA.crt" "${CERTS_DIR}/rootCA.crt"

# Copy .srl if exists (for certificate serial number tracking)
if [[ -f "${ROOT_CA_SOURCE_PATH}/rootCA.srl" ]]; then
    cp "${ROOT_CA_SOURCE_PATH}/rootCA.srl" "${CERTS_DIR}/rootCA.srl"
fi

# Set proper permissions
chmod 600 "${CERTS_DIR}/rootCA.key"
chmod 644 "${CERTS_DIR}/rootCA.crt"
```

**What gets copied:**
- `rootCA.key` - Private key (4096-bit RSA)
- `rootCA.crt` - Certificate (10-year validity)
- `rootCA.srl` - Serial number file (if exists)

**Security:**
- Private key: `0600` (owner read/write only)
- Certificate: `0644` (world-readable)

### 4. Menu Selection

After copying, menu is determined by `certs/rootCA.crt` existence:

**With Root CA** (`certs/rootCA.crt` exists):
```
Root CA: Available

  1) Generate server certificate for Synapse
  2) Install addon
  3) Generate new Root CA (overwrite existing)
  4) Exit
```

**Without Root CA** (`certs/rootCA.crt` missing):
```
Root CA: Not Available

  1) Generate new Root CA
  2) Exit
```

## Use Cases

### Single Server Deployment

**Scenario:** First-time setup for a single server

1. No Root CA exists next to `main.sh`
2. Choose "Generate new Root CA" from menu
3. Root CA is created in `certs/`
4. Generate server certificate
5. Install addon

### Multiple Server Deployment

**Scenario:** Deploying multiple Matrix servers with federation

1. **First Server:**
   - Run `main.sh` (no existing Root CA)
   - Generate new Root CA
   - Complete installation

2. **Subsequent Servers:**
   - Copy `rootCA.key` and `rootCA.crt` from first server
   - Place next to `main.sh` on new server
   - Run `main.sh`
   - Accept prompt to use existing Root CA
   - Generate server certificate
   - Install addon

### Bring Your Own CA

**Scenario:** Using existing corporate PKI

1. Export your Root CA key and certificate
2. Rename to `rootCA.key` and `rootCA.crt`
3. Place next to `main.sh`
4. Run `main.sh` and accept prompt
5. Generate server certificates signed by your CA

## Overwrite Behavior

When choosing "Generate new Root CA" from the menu:

```
[WARNING] Existing Root CA found in certs/
Overwrite existing Root CA? [y/N]:
```

**If accepted:**
- All `certs/rootCA.*` files are removed
- New Root CA is generated
- Any existing server certificates remain valid (if using same CA)
- **Warning:** Servers with old Root CA cannot verify new certificates

## Troubleshooting

### Root CA Not Detected

**Symptom:** Files exist but not detected

**Solutions:**
1. Verify both files exist: `ls -la rootCA.*`
2. Check exact filenames (case-sensitive)
3. Ensure files are in same directory as `main.sh`

### Permission Errors

**Symptom:** Permission denied during copy

**Solutions:**
1. Check source file permissions
2. Ensure `certs/` directory is writable
3. Run with appropriate user permissions

### Certificate Chain Issues

**Symptom:** Federation fails between servers

**Solutions:**
1. Verify both servers use same Root CA
2. Check certificate: `openssl x509 -in certs/cert-full-chain.pem -noout -text`
3. Ensure full chain includes Root CA

## Security Best Practices

1. **Protect Root CA Key**
   - Store `rootCA.key` in secure location
   - Limit access to authorized personnel only
   - Consider hardware security module (HSM) for production

2. **Backup Root CA**
   - Keep secure backup of `rootCA.key` and `rootCA.crt`
   - Store offline in encrypted format
   - Document recovery procedures

3. **Access Control**
   - Set `certs/` directory permissions to `0700`
   - Set `rootCA.key` permissions to `0600`
   - Audit access regularly

4. **Certificate Rotation**
   - Root CA valid for 10 years (plan rotation)
   - Server certificates valid for 1 year (renew annually)
   - Document rotation procedures

## File Reference

### Root CA Files

| File | Description | Permissions |
|------|-------------|-------------|
| `rootCA.key` | Root CA private key (4096-bit RSA) | `0600` |
| `rootCA.crt` | Root CA certificate (10 years) | `0644` |
| `rootCA.srl` | Certificate serial number | `0644` |

### Server Certificate Files

| File | Description | Permissions |
|------|-------------|-------------|
| `server.key` | Server private key (4096-bit RSA) | `0600` |
| `server.crt` | Server certificate (1 year) | `0644` |
| `cert-full-chain.pem` | Full chain (server + Root CA) | `0644` |
