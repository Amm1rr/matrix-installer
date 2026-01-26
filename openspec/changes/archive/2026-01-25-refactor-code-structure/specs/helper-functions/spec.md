## ADDED Requirements

### Requirement: IP Detection Helper Function
The system SHALL provide a centralized `get_detected_ip()` function that detects the local IP address using standard network utilities.

#### Scenario: IP detection with ip route
- **WHEN** `get_detected_ip()` is called
- **THEN** the system SHALL attempt: `ip route get 1 | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}'`
- **AND** return the detected IP address

#### Scenario: IP detection fallback to ip addr
- **WHEN** `ip route get 1` returns empty
- **THEN** the system SHALL fallback to: `ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1`
- **AND** return the detected IP address or empty string if not found

#### Scenario: No IP detected
- **WHEN** both detection methods fail
- **THEN** the function SHALL return empty string

### Requirement: Root Key Configuration Helper Function
The system SHALL provide a `prompt_root_ca_config()` function that prompts for all Root Key configuration values and returns them as pipe-delimited output.

#### Scenario: Prompt for all Root Key configuration
- **WHEN** `prompt_root_ca_config()` is called
- **THEN** the system SHALL prompt for:
  - Organization (default: $SSL_ORG)
  - Country Code (2 letters, default: $SSL_COUNTRY)
  - State/Province (default: $SSL_STATE)
  - City (default: $SSL_CITY)
  - Validity in days (default: $SSL_CA_DAYS)
- **AND** validate country code is exactly 2 characters
- **AND** validate days is a number
- **AND** display configuration summary
- **AND** output as: `org|country|state|city|days`

#### Scenario: Country code validation
- **WHEN** user enters country code that is not 2 characters
- **THEN** the system SHALL display error: "Country code must be exactly 2 letters (e.g., IR, US, DE)"
- **AND** re-prompt for country code

#### Scenario: Invalid days value
- **WHEN** user enters non-numeric days value
- **THEN** the system SHALL display: "Invalid days value, using default: $SSL_CA_DAYS"
- **AND** use the default value

### Requirement: Root Key Creation from Menu Helper Function
The system SHALL provide a `create_root_ca_from_menu()` function that handles the complete Root Key creation flow from menu options.

#### Scenario: Create Root Key with confirmation
- **WHEN** `create_root_ca_from_menu()` is called
- **THEN** the system SHALL prompt for confirmation: "This will create a new Root Key directory. Continue?"
- **AND** if confirmed, call `prompt_root_ca_config()`
- **AND** temporarily set global SSL_* variables with user values
- **AND** prompt for confirmation: "Create Root Key with these settings?"
- **AND** if confirmed, call `ssl_manager_create_root_ca()` with organization name
- **AND** restore original global SSL_* variables

#### Scenario: User cancels Root Key creation
- **WHEN** user declines confirmation prompt
- **THEN** the function SHALL return without creating Root Key
- **AND** global SSL_* variables remain unchanged

### Requirement: Menu Header Helper Function
The system SHALL provide a `print_menu_header()` function that displays a styled menu header with centered title.

#### Scenario: Display menu header
- **WHEN** `print_menu_header "Title"` is called
- **THEN** the system SHALL display:
  - Box border: ╔══════════════════════════════════════════════════════════╗
  - Empty lines with padding
  - Centered title text
  - Closing box border: ╚══════════════════════════════════════════════════════════╝
- **AND** title SHALL be centered within 58 character width
