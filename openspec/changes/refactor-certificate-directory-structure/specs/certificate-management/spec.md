## ADDED Requirements

### Requirement: Root Key Directory Structure
The system SHALL organize all certificate files under a Root Key-specific directory structure where each Root Key is stored in a subdirectory named by the server identifier (IP address or domain name).

#### Scenario: Creating new Root Key creates directory
- **WHEN** user creates a new Root Key with server name "192.168.1.100"
- **THEN** the system SHALL create directory `certs/192.168.1.100/`
- **AND** store rootCA.key, rootCA.crt, and rootCA.srl in that directory
- **AND** create a `servers/` subdirectory for server certificates

#### Scenario: Root Key with domain name
- **WHEN** user creates a new Root Key with server name "matrix.example.com"
- **THEN** the system SHALL create directory `certs/matrix.example.com/`
- **AND** store all Root Key files in that directory

### Requirement: Server Certificate Subdirectory
Server certificates SHALL be stored in a `servers/` subdirectory under their associated Root Key directory.

#### Scenario: Server certificate placement
- **WHEN** generating a server certificate for "192.168.1.100" under Root Key "192.168.1.100"
- **THEN** the system SHALL create `certs/192.168.1.100/servers/192.168.1.100/`
- **AND** store server.key, server.crt, and cert-full-chain.pem in that subdirectory

#### Scenario: Additional server under same Root Key
- **WHEN** generating a certificate for "other.local" under Root Key "192.168.1.100"
- **THEN** the system SHALL create `certs/192.168.1.100/servers/other.local/`
- **AND** store the server certificates in that subdirectory

### Requirement: Duplicate Root Key Directory Handling
When a Root Key directory with the same name already exists, the system SHALL prompt the user to backup the existing directory before creating a new one.

#### Scenario: Duplicate directory with user confirmation
- **WHEN** creating Root Key "192.168.1.100" and directory already exists
- **THEN** the system SHALL warn the user about existing directory
- **AND** prompt for confirmation to backup and create new
- **AND** if confirmed, rename existing to "192.168.1.100.backup-YYYY-MM-DD-HHMMSS"
- **AND** create new empty "192.168.1.100/" directory

#### Scenario: Duplicate directory with user rejection
- **WHEN** creating Root Key "192.168.1.100" and directory already exists
- **AND** user rejects backup and create option
- **THEN** the system SHALL cancel Root Key creation
- **AND** keep existing directory unchanged

### Requirement: Root Key Discovery
The system SHALL discover all available Root Key directories by scanning the `certs/` directory for subdirectories containing rootCA.key and rootCA.crt files.

#### Scenario: Single Root Key found
- **WHEN** scanning certs/ and only one Root Key directory exists
- **THEN** the system SHALL use that Root Key as active
- **AND** display Root Key information in menu

#### Scenario: Multiple Root Keys found - user selection menu
- **WHEN** scanning certs/ and multiple Root Key directories exist
- **THEN** the system SHALL display a selection menu with:
  - List of available Root Key names
  - Expiration date for each Root Key
  - Option to create a new Root Key
- **AND** prompt user to select active Root Key
- **AND** set the selected Root Key as active

#### Scenario: Multiple Root Keys menu display format
- **WHEN** displaying the Root Key selection menu
- **THEN** the system SHALL show each Root Key with:
  - Directory name (e.g., "192.168.1.100" or "matrix.local")
  - Subject/organization from certificate
  - Days remaining until expiration
- **AND** number each option for easy selection

### Requirement: Active Root Key Tracking
The system SHALL track which Root Key directory is currently active for certificate operations.

#### Scenario: Setting active Root Key
- **WHEN** user selects or creates a Root Key
- **THEN** the system SHALL set that Root Key directory as active
- **AND** all certificate operations SHALL use the active Root Key

### Requirement: Old Structure Migration
On first run after upgrade, the system SHALL automatically detect and migrate the old flat certificate structure to the new hierarchical structure.

#### Scenario: Migrating old flat structure
- **WHEN** system detects rootCA.key in certs/ root directory (old structure)
- **THEN** the system SHALL prompt user about migration
- **AND** if confirmed, create new directory structure preserving all certificates
- **AND** remove old files from certs/ root after successful migration

#### Scenario: No migration needed for new structure
- **WHEN** system detects subdirectories in certs/ (new structure)
- **THEN** the system SHALL skip migration
- **AND** continue normal operation

### Requirement: Multiple Root Key Files Next to matrix-installer.sh
When multiple Root Key key/certificate pairs exist next to matrix-installer.sh, the system SHALL display a list and prompt user to select which one to use.

#### Scenario: Multiple Root Key pairs found next to matrix-installer.sh
- **WHEN** scanning SCRIPT_DIR and multiple .key/.crt pairs are found
- **THEN** the system SHALL display a selection menu showing:
  - List of found Root Key file pairs (e.g., rootCA.key/crt, rootCA-backup.key/crt)
  - Subject/organization from each certificate
  - Expiration date for each Root Key
- **AND** prompt user to select which Root Key to copy to certs/
- **AND** copy only the selected Root Key files

#### Scenario: Single Root Key pair found next to matrix-installer.sh
- **WHEN** scanning SCRIPT_DIR and only rootCA.key/rootCA.crt exists
- **THEN** the system SHALL prompt if user wants to use this Root Key
- **AND** if confirmed, copy files to certs/<name>/ directory

#### Scenario: No Root Key files found next to matrix-installer.sh
- **WHEN** scanning SCRIPT_DIR and no Root Key files exist
- **THEN** the system SHALL continue to normal menu flow
- **AND** offer to create new Root Key if needed in certs/

## MODIFIED Requirements

### Requirement: Environment Variables for Addons
The system SHALL export environment variables to addons pointing to certificate files in the new directory structure.

#### Scenario: Exporting new environment variables
- **WHEN** running an addon with active Root Key "192.168.1.100" and server "192.168.1.100"
- **THEN** the system SHALL export:
  - `SERVER_NAME="192.168.1.100"`
  - `SSL_CERT="certs/192.168.1.100/servers/192.168.1.100/cert-full-chain.pem"`
  - `SSL_KEY="certs/192.168.1.100/servers/192.168.1.100/server.key"`
  - `ROOT_CA="certs/192.168.1.100/rootCA.crt"`
  - `ROOT_CA_DIR="certs/192.168.1.100"`
  - `CERTS_DIR="certs"`
  - `WORKING_DIR="<working directory>"`

### Requirement: SSL Manager Functions
SSL Manager module functions SHALL operate on the new directory structure.

#### Scenario: get_server_cert_dir with new structure
- **WHEN** calling `get_server_cert_dir "192.168.1.100"` with active Root Key "192.168.1.100"
- **THEN** the function SHALL return "certs/192.168.1.100/servers/192.168.1.100"

#### Scenario: server_has_certs with new structure
- **WHEN** checking if server "192.168.1.100" has certificates under Root Key "192.168.1.100"
- **THEN** the system SHALL check for files in `certs/192.168.1.100/servers/192.168.1.100/`
