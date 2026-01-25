## Purpose
User interface conventions and interaction patterns for the Matrix Plus installer.
## Requirements
### Requirement: Back to Main Menu Option
All selection menus SHALL provide an option to return to the main menu without making a selection.

#### Scenario: Root CA selection from files - back option
- **WHEN** user is presented with multiple Root CA files next to script
- **THEN** the system SHALL display option 0 labeled "Back to main menu"
- **AND** when user selects 0, return to main menu flow

#### Scenario: Root CA selection from certs - back option
- **WHEN** user is presented with multiple Root CAs in certs/
- **THEN** the system SHALL display option 0 labeled "Back to main menu"
- **AND** when user selects 0, return to main menu flow

### Requirement: Unified Menu Styling
All menus SHALL use consistent styled headers with the same visual format.

#### Scenario: Main menu with Root CA available
- **WHEN** displaying menu with active Root CA
- **THEN** the system SHALL use the styled header format

#### Scenario: Main menu without Root CA
- **WHEN** displaying menu without active Root CA
- **THEN** the system SHALL use the styled header format

### Requirement: Consistent Prompt Functions
All user input prompts SHALL use the centralized helper functions (`prompt_user()` or `prompt_yes_no()`) instead of direct `read -rp` calls.

#### Scenario: Server name prompt uses helper
- **WHEN** prompting for server IP address or domain
- **THEN** the system SHALL use `prompt_user()` function
- **AND** display default value in format `[default]`

#### Scenario: Confirmation prompt uses helper
- **WHEN** prompting for yes/no confirmation
- **THEN** the system SHALL use `prompt_yes_no()` function
- **AND** display default choice as `[Y/n]` or `[y/N]`

### Requirement: IP Detection in Prompts
When prompting for server IP address or domain, the system SHALL automatically detect the local IP address and suggest it as the default value.

#### Scenario: Server certificate generation with detected IP
- **WHEN** generating server certificate and local IP is detected
- **THEN** the system SHALL call `get_detected_ip()` helper
- **AND** use detected IP as default in `prompt_user()` call

#### Scenario: Addon installation with detected IP
- **WHEN** installing addon and no server certificates exist
- **THEN** the system SHALL call `get_detected_ip()` helper
- **AND** use detected IP as default in `prompt_user()` call

### Requirement: Root CA Configuration Prompts
Root CA configuration prompts (Organization, Country, State, City, Validity) SHALL be centralized in a single reusable function.

#### Scenario: Creating Root CA from menu
- **WHEN** user selects option to create new Root CA
- **THEN** the system SHALL call `prompt_root_ca_config()` function
- **AND** display all configuration prompts in sequence
- **AND** show configuration summary before creation

#### Scenario: Configuration summary display
- **WHEN** user completes Root CA configuration prompts
- **THEN** the system SHALL display:
  - Organization name
  - Country code
  - State/Province
  - City
  - Validity in days
- **AND** prompt for confirmation before creation

### Requirement: Root CA Creation Flow
Root CA creation from menu options SHALL use a unified flow that handles configuration prompting, confirmation, and creation.

#### Scenario: Create Root CA from option 8 (switch/create)
- **WHEN** user selects option 8 in menu_with_root_ca and chooses to create new
- **THEN** the system SHALL call `create_root_ca_from_menu()` function
- **AND** follow the unified creation flow

#### Scenario: Create Root CA from option 9
- **WHEN** user selects option 9 in menu_with_root_ca
- **THEN** the system SHALL call `create_root_ca_from_menu()` function
- **AND** follow the unified creation flow

#### Scenario: Create Root CA from menu without Root CA
- **WHEN** user selects option 1 in menu_without_root_ca
- **THEN** the system SHALL call `create_root_ca_from_menu()` function
- **AND** switch to menu_with_root_ca after successful creation

