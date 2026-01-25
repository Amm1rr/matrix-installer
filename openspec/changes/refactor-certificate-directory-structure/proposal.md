# Change: Refactor Certificate Directory Structure

## Why

The current certificate directory structure (`certs/`) mixes Root CA files and server certificates in a single flat directory. This creates several problems:

1. **Root CA mixing**: When loading a new Root CA, the old files are simply overwritten, breaking the trust chain for existing server certificates
2. **No isolation**: Server certificates signed by different Root CAs are indistinguishable
3. **Unsafe deletion**: Overwriting files loses the previous Root CA permanently with no backup
4. **Multi-root CA support**: Cannot maintain multiple Root CAs simultaneously

## What Changes

### Directory Structure Changes

**Before:**
```
certs/
├── rootCA.key
├── rootCA.crt
├── rootCA.srl
├── 192.168.1.100/
│   ├── server.key
│   ├── server.crt
│   └── cert-full-chain.pem
└── matrix.local/
    └── ...
```

**After:**
```
certs/
├── 192.168.1.100/              # Root CA named by server IP/domain
│   ├── rootCA.key
│   ├── rootCA.crt
│   ├── rootCA.srl
│   └── servers/                # Server certificates for this Root CA
│       ├── 192.168.1.100/
│       │   ├── server.key
│       │   ├── server.crt
│       │   └── cert-full-chain.pem
│       └── other-server.local/
│           └── ...
└── matrix.local/               # Another Root CA
    ├── rootCA.key
    ├── rootCA.crt
    └── servers/
```

### Behavior Changes

1. **Root CA creation/loading**: Now creates a subdirectory named by the server IP/domain
2. **Duplicate handling**: If directory exists, user is prompted to backup the old directory before creating new one
3. **Server certificates**: Stored in `servers/` subdirectory under their Root CA
4. **Active Root CA tracking**: System needs to track which Root CA is currently active
5. **Migration**: Old flat structure needs automatic migration to new structure

### Breaking Changes

- **Environment variables**: Addons receive updated paths (e.g., `ROOT_CA_DIR` instead of individual file paths)
- **Existing deployments**: First run after upgrade will migrate old structure to new structure

## Impact

### Affected specs
- `certificate-management` - All certificate path references and operations

### Affected code
- `main.sh:266-474` - SSL Manager module functions
- `main.sh:480-502` - Environment Provider module
- All addons that read certificate environment variables

### Migration requirements
- Existing `certs/` directories must be migrated on first run
- Backup naming: `<name>.backup-YYYY-MM-DD-HHMMSS`
