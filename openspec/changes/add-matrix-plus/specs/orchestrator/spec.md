# Orchestrator Capability Specification

## ADDED Requirements

### Requirement: Root CA Detection and Loading
The orchestrator SHALL detect Root CA files next to `main.sh` and prompt user to load them into `certs/`.

#### Scenario: Detect Root CA next to main.sh
- **GIVEN** `rootCA.crt` and `rootCA.key` exist next to `main.sh`
- **WHEN** orchestrator starts
- **THEN** displays message: "Found rootCA.crt next to main.sh"
- **AND** prompts user: "Use this rootCA? [y/N]"

#### Scenario: Load Root CA on user approval
- **GIVEN** user responds "y" to load Root CA
- **AND** `rootCA.crt` and `rootCA.key` exist next to `main.sh`
- **WHEN** user confirms
- **THEN** copies `rootCA.crt` to `certs/rootCA.crt`
- **AND** copies `rootCA.key` to `certs/rootCA.key`
- **AND** overwrites if files already exist in `certs/`
- **AND** displays success message

#### Scenario: Skip Root CA loading
- **GIVEN** user responds "N" or "n" to load Root CA
- **WHEN** user declines
- **THEN** does NOT copy files
- **AND** continues to menu without Root CA in `certs/`

#### Scenario: No Root CA found
- **GIVEN** `rootCA.crt` does NOT exist next to `main.sh`
- **WHEN** orchestrator starts
- **THEN** continues to menu without prompting
- **AND** menu shows only "Generate new Root CA" option

### Requirement: SSL Manager
The orchestrator SHALL provide a centralized SSL certificate management system that generates Root CA and server certificates with proper SAN extensions for Matrix federation.

#### Scenario: Create new Root CA
- **GIVEN** no Root CA exists in `certs/` directory
- **WHEN** user selects "Generate new Root CA" option
- **THEN** orchestrator generates `rootCA.key` (4096-bit RSA)
- **AND** generates `rootCA.crt` with `v3_ca` extensions
- **AND** sets 10-year validity period
- **AND** stores files in `certs/` directory

#### Scenario: Overwrite existing Root CA with confirmation
- **GIVEN** Root CA exists in `certs/` directory
- **WHEN** user selects "Generate new Root CA" option
- **THEN** displays warning: "This will overwrite existing Root CA"
- **AND** prompts user: "Continue? [y/N]"
- **AND** on "y": generates new Root CA and overwrites
- **AND** on "N": returns to menu

#### Scenario: Sign server certificate
- **GIVEN** Root CA exists in `certs/`
- **WHEN** user selects "Generate server certificate" option
- **AND** provides server name
- **THEN** orchestrator generates server private key
- **AND** creates CSR with proper CN (server name)
- **AND** signs certificate with Root CA
- **AND** includes Subject Alternative Names (IP + DNS)
- **AND** creates full-chain certificate (server.crt + rootCA.crt)
- **AND** sets 1-year validity period

### Requirement: Addon Loader
The orchestrator SHALL dynamically discover and list available addons from subdirectories containing `install.sh`.

#### Scenario: Discover available addons
- **GIVEN** project contains `ansible-synapse/install.sh`
- **WHEN** orchestrator starts
- **THEN** displays menu with discovered addon
- **AND** shows friendly name from directory name

#### Scenario: Validate addon structure
- **GIVEN** directory `new-addon/` without `install.sh`
- **WHEN** orchestrator scans for addons
- **THEN** directory is excluded from menu
- **AND** warning is logged

### Requirement: Environment Provider
The orchestrator SHALL inject SSL credentials and server configuration to addons via environment variables.

#### Scenario: Inject SSL environment variables
- **GIVEN** user selects `ansible-synapse` addon
- **AND** server name is `192.168.1.100`
- **AND** SSL certificates exist in `certs/`
- **WHEN** addon `install.sh` is executed
- **THEN** `SERVER_NAME=192.168.1.100` is exported
- **AND** `SSL_CERT=certs/cert-full-chain.pem` is exported
- **AND** `SSL_KEY=certs/server.key` is exported
- **AND** `ROOT_CA=certs/rootCA.crt` is exported
- **AND** `install.sh` receives these variables

#### Scenario: Validate required variables
- **GIVEN** addon `install.sh` requires `SERVER_NAME`
- **WHEN** orchestrator prepares execution
- **THEN** all required variables are set
- **OR** execution is aborted with clear error message

### Requirement: Dynamic Menu System
The orchestrator SHALL provide different menu options based on Root CA availability.

#### Scenario: Menu with Root CA available
- **GIVEN** `certs/rootCA.crt` exists
- **WHEN** main menu is displayed
- **THEN** shows "1) Generate server certificate for Synapse"
- **AND** shows "2) Install ansible-synapse addon"
- **AND** shows "3) Generate new Root CA (overwrite existing)"
- **AND** shows "4) Exit"

#### Scenario: Menu without Root CA
- **GIVEN** `certs/rootCA.crt` does NOT exist
- **WHEN** main menu is displayed
- **THEN** shows "1) Generate new Root CA"
- **AND** shows "2) Exit"

#### Scenario: Handle invalid selection
- **GIVEN** user enters invalid menu option
- **WHEN** selection is processed
- **THEN** displays error message
- **AND** redisplays menu

### Requirement: Certificate Chain Generation
The orchestrator SHALL create proper certificate chains for federation between servers.

#### Scenario: Generate full-chain certificate
- **GIVEN** server certificate `server.crt` exists
- **AND** Root CA `rootCA.crt` exists
- **WHEN** full-chain is requested
- **THEN** concatenates `server.crt` + `rootCA.crt` into `cert-full-chain.pem`
- **AND** stores in `certs/` directory
- **AND** verifies chain with `openssl verify`

#### Scenario: Verify SAN extensions
- **GIVEN** certificate for `192.168.1.100` is generated
- **WHEN** certificate is inspected
- **THEN** contains `DNS.1 = matrix.local`
- **AND** contains `DNS.2 = localhost`
- **AND** contains `IP.1 = 192.168.1.100`
- **AND** contains `IP.2 = 127.0.0.1`

### Requirement: UI/Helpers
The orchestrator SHALL provide reusable utility functions for user interaction and output formatting.

#### Scenario: Display colored messages
- **GIVEN** orchestrator needs to display info message
- **WHEN** `print_message "info" "message"` is called
- **THEN** displays blue-colored `[INFO] message`
- **AND** logs to `install.log`

#### Scenario: Prompt user for input
- **GIVEN** orchestrator needs server name from user
- **WHEN** `prompt_user "Enter server name" "default"` is called
- **THEN** displays prompt with default value
- **AND** returns user input or default

#### Scenario: Prompt yes/no confirmation
- **GIVEN** orchestrator needs user confirmation
- **WHEN** `prompt_yes_no "Continue?" "y"` is called
- **THEN** returns "yes" or "no"
- **AND** accepts y/n/yes/no/Enter for default

### Requirement: Backward Compatibility
The orchestrator SHALL maintain compatibility with existing `install.sh` script.

#### Scenario: Legacy script execution
- **GIVEN** user runs `./install.sh` directly
- **WHEN** script executes
- **THEN** all existing functionality works
- **AND** no changes to user workflow required

#### Scenario: Gradual migration
- **GIVEN** user wants to try new system
- **WHEN** `./main.sh` is executed
- **THEN** new menu system is shown
- **AND** `install.sh` remains as fallback option
