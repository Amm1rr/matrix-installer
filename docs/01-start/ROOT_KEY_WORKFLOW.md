# Root Key Workflow

## Overview

Matrix Installer supports importing existing Root Keys for multi-server deployments. This enables:
- Federation between servers in isolated networks
- Consistent certificate management
- Multiple Root Keys coexisting

## Certificate Structure

```
certs/
├── my-root/                 # First Root Key
│   ├── rootCA.key          # Private key (0600)
│   ├── rootCA.crt          # Certificate (0644)
│   └── servers/            # Server certificates
│       ├── 192.168.1.100/
│       │   ├── server.key
│       │   ├── server.crt
│       │   └── cert-full-chain.pem
│       └── matrix.example.com/
└── another-root/           # Second Root Key
    ├── rootCA.key
    ├── rootCA.crt
    └── servers/
```

## Importing an Existing Root Key

### Method 1: Files Next to Script

Place `*.key` and `*.crt` files with identical names next to `matrix-installer.sh`:

```bash
cp /secure/location/my-root.key /path/to/script/
cp /secure/location/my-root.crt /path/to/script/
./matrix-installer.sh
```

**When detected:**
```
[INFO] Root Key files found: my-root.key, my-root.crt
Import as "my-root"? [y/N]:
```

### Method 2: Manual Import

```bash
# Create Root Key directory
mkdir -p certs/my-root/servers

# Copy files
cp /path/to/rootCA.key certs/my-root/
cp /path/to/rootCA.crt certs/my-root/

# Set permissions
chmod 600 certs/my-root/rootCA.key
chmod 644 certs/my-root/rootCA.crt
```

## Multiple Root Keys

Matrix Installer supports multiple Root Keys simultaneously:

```
Root Key: my-root (Active)
  | Subject: Matrix Root Key
  | Expires: 2034-01-25 (in 3200 days)

  1) Generate server certificate

  2) Install Docker Synapse (Let's Encrypt)
  3) Install Docker Synapse (Private Key)
  4) Install Zanjir Synapse (Private Key+Dendrite)
  5) Install Synapse by Ansible (Private Key)

  ---------------------------
  S) Switch active Root Key (my-root)
  N) Create new Root Key
  0) Exit
```

**Switching Root Keys:** Press `S` to select from available Root Keys.

## Use Cases

### Single Server

```bash
./matrix-installer.sh
# → Generate new Root Key
# → Generate server certificate
# → Install addon
```

### Multiple Servers (Federation)

**First server:**
```bash
./matrix-installer.sh
# → Generate new Root Key (named "my-root")
# → Generate certificate for 192.168.1.100
# → Install addon
```

**Second server:**
```bash
# Copy Root Key files from first server
scp server1:/path/to/script/my-root.* .
./matrix-installer.sh
# → Import existing Root Key
# → Generate certificate for 192.168.1.101
# → Install addon
```

**Result:** Both servers trust each other automatically (federation enabled).

### Corporate PKI (Bring Your Own CA)

```bash
# Export your corporate CA
cp /path/to/corporate-ca.key custom-root.key
cp /path/to/corporate-ca.crt custom-root.crt

./matrix-installer.sh
# → Import as "custom-root"
# → All certificates signed by your corporate CA
```

## Overwriting a Root Key

```
[WARNING] Root Key "my-root" already exists
Overwrite? This will invalidate all server certificates under this Root Key! [y/N]:
```

**Warning:** Overwriting breaks federation for all servers using that Root Key.

## Troubleshooting

### Not Detected

```bash
# Verify both files exist with IDENTICAL names
ls -la *.key *.crt

# Check you're in the right directory
ls matrix-installer.sh
```

**Common mistakes:**
- `my-root.key` + `my-root.crt` ✅
- `my-root.key` + `My-root.crt` ❌ (case-sensitive)
- `my-root.key` + `another-root.crt` ❌ (names must match)

### Permission Errors

```bash
# Fix permissions
chmod 600 certs/*/rootCA.key
chmod 644 certs/*/rootCA.crt
chmod 700 certs/*/
```

### Federation Fails

```bash
# Verify both servers use same Root Key
openssl x509 -in certs/my-root/servers/192.168.1.100/cert-full-chain.pem -noout -text

# Check issuer matches
openssl x509 -in certs/my-root/rootCA.crt -noout -subject
```

## Security Best Practices

1. **Protect Root Key** - `rootCA.key` gives full control over your federation
2. **Backup** - Keep encrypted offline copies of all Root Keys
3. **Rotate** - Plan for Root Key expiration (10 years validity)
4. **Isolate** - Store Root Keys on air-gapped systems when possible
5. **Audit** - Log all Root Key operations

## File Reference

| File | Location | Permissions |
|------|----------|-------------|
| Root Key | `certs/<name>/rootCA.key` | `0600` |
| Root Cert | `certs/<name>/rootCA.crt` | `0644` |
| Server Key | `certs/<name>/servers/<server>/server.key` | `0600` |
| Server Cert | `certs/<name>/servers/<server>/cert-full-chain.pem` | `0644` |

---

**See also:** [USER_GUIDE.md](USER_GUIDE.md) | [ADDON_DEVELOPMENT_GUIDE.md](../02-develop/ADDON_DEVELOPMENT_GUIDE.md)
