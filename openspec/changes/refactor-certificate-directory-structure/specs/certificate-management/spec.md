## ADDED Requirements

### Requirement: Root CA Directory Structure
The system SHALL organize all certificate files under a Root CA-specific directory structure where each Root CA is stored in a subdirectory named by the server identifier (IP address or domain name).

#### Scenario: Creating new Root CA creates directory
- **WHEN** user creates a new Root CA with server name "192.168.1.100"
- **THEN** the system SHALL create directory `certs/192.168.1.100/`
- **AND** store rootCA.key, rootCA.crt, and rootCA.srl in that directory
- **AND** create a `servers/` subdirectory for server certificates

#### Scenario: Root CA with domain name
- **WHEN** user creates a new Root CA with server name "matrix.example.com"
- **THEN** the system SHALL create directory `certs/matrix.example.com/`
- **AND** store all Root CA files in that directory

### Requirement: Server Certificate Subdirectory
Server certificates SHALL be stored in a `servers/` subdirectory under their associated Root CA directory.

#### Scenario: Server certificate placement
- **WHEN** generating a server certificate for "192.168.1.100" under Root CA "192.168.1.100"
- **THEN** the system SHALL create `certs/192.168.1.100/servers/192.168.1.100/`
- **AND** store server.key, server.crt, and cert-full-chain.pem in that subdirectory

#### Scenario: Additional server under same Root CA
- **WHEN** generating a certificate for "other.local" under Root CA "192.168.1.100"
- **THEN** the system SHALL create `certs/192.168.1.100/servers/other.local/`
- **AND** store the server certificates in that subdirectory

### Requirement: Duplicate Root CA Directory Handling
When a Root CA directory with the same name already exists, the system SHALL prompt the user to backup the existing directory before creating a new one.

#### Scenario: Duplicate directory with user confirmation
- **WHEN** creating Root CA "192.168.1.100" and directory already exists
- **THEN** the system SHALL warn the user about existing directory
- **AND** prompt for confirmation to backup and create new
- **AND** if confirmed, rename existing to "192.168.1.100.backup-YYYY-MM-DD-HHMMSS"
- **AND** create new empty "192.168.1.100/" directory

#### Scenario: Duplicate directory with user rejection
- **WHEN** creating Root CA "192.168.1.100" and directory already exists
- **AND** user rejects backup and create option
- **THEN** the system SHALL cancel Root CA creation
- **AND** keep existing directory unchanged

### Requirement: Root CA Discovery
The system SHALL discover all available Root CA directories by scanning the `certs/` directory for subdirectories containing rootCA.key and rootCA.crt files.

#### Scenario: Single Root CA found
- **WHEN** scanning certs/ and only one Root CA directory exists
- **THEN** the system SHALL use that Root CA as active
- **AND** display Root CA information in menu

#### Scenario: Multiple Root CAs found - user selection menu
- **WHEN** scanning certs/ and multiple Root CA directories exist
- **THEN** the system SHALL display a selection menu with:
  - List of available Root CA names
  - Expiration date for each Root CA
  - Option to create a new Root CA
- **AND** prompt user to select active Root CA
- **AND** set the selected Root CA as active

#### Scenario: Multiple Root CAs menu display format
- **WHEN** displaying the Root CA selection menu
- **THEN** the system SHALL show each Root CA with:
  - Directory name (e.g., "192.168.1.100" or "matrix.local")
  - Subject/organization from certificate
  - Days remaining until expiration
- **AND** number each option for easy selection

### Requirement: Active Root CA Tracking
The system SHALL track which Root CA directory is currently active for certificate operations.

#### Scenario: Setting active Root CA
- **WHEN** user selects or creates a Root CA
- **THEN** the system SHALL set that Root CA directory as active
- **AND** all certificate operations SHALL use the active Root CA

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

### Requirement: Multiple Root CA Files Next to main.sh
When multiple Root CA key/certificate pairs exist next to main.sh, the system SHALL display a list and prompt user to select which one to use.

#### Scenario: Multiple Root CA pairs found next to main.sh
- **WHEN** scanning SCRIPT_DIR and multiple .key/.crt pairs are found
- **THEN** the system SHALL display a selection menu showing:
  - List of found Root CA file pairs (e.g., rootCA.key/crt, rootCA-backup.key/crt)
  - Subject/organization from each certificate
  - Expiration date for each Root CA
- **AND** prompt user to select which Root CA to copy to certs/
- **AND** copy only the selected Root CA files

#### Scenario: Single Root CA pair found next to main.sh
- **WHEN** scanning SCRIPT_DIR and only rootCA.key/rootCA.crt exists
- **THEN** the system SHALL prompt if user wants to use this Root CA
- **AND** if confirmed, copy files to certs/<name>/ directory

#### Scenario: No Root CA files found next to main.sh
- **WHEN** scanning SCRIPT_DIR and no Root CA files exist
- **THEN** the system SHALL continue to normal menu flow
- **AND** offer to create new Root CA if needed in certs/

## MODIFIED Requirements

### Requirement: Environment Variables for Addons
The system SHALL export environment variables to addons pointing to certificate files in the new directory structure.

#### Scenario: Exporting new environment variables
- **WHEN** running an addon with active Root CA "192.168.1.100" and server "192.168.1.100"
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
- **WHEN** calling `get_server_cert_dir "192.168.1.100"` with active Root CA "192.168.1.100"
- **THEN** the function SHALL return "certs/192.168.1.100/servers/192.168.1.100"

#### Scenario: server_has_certs with new structure
- **WHEN** checking if server "192.168.1.100" has certificates under Root CA "192.168.1.100"
- **THEN** the system SHALL check for files in `certs/192.168.1.100/servers/192.168.1.100/`
