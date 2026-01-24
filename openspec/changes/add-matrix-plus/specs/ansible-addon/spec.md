# Ansible Addon Capability Specification

## ADDED Requirements

### Requirement: Self-Contained Ansible Management
The addon SHALL manage all Ansible operations internally without depending on external modules.

#### Scenario: Install Ansible if missing
- **GIVEN** target system is Linux
- **AND** Ansible is not installed
- **WHEN** addon is executed
- **THEN** installs Ansible using system package manager
- **AND** verifies installation with `ansible --version`

#### Scenario: Skip Ansible installation if present
- **GIVEN** Ansible 2.15.1+ is already installed
- **WHEN** addon is executed
- **THEN** skips installation
- **AND** continues to next task

### Requirement: Playbook Repository Management
The addon SHALL clone and update the matrix-docker-ansible-deploy playbook repository.

#### Scenario: Clone playbook repository
- **GIVEN** playbook directory does not exist
- **AND** `MATRIX_PLAYBOOK_REPO_URL` environment variable is set
- **WHEN** addon is executed
- **THEN** clones repository to specified directory
- **AND** verifies .git directory exists

#### Scenario: Update existing playbook
- **GIVEN** playbook directory exists
- **AND** is a valid git repository
- **WHEN** addon is executed
- **THEN** performs git pull to update
- **OR** skips if user prefers existing version

### Requirement: Ansible Roles Installation
The addon SHALL install required Ansible roles from requirements.yml.

#### Scenario: Install galaxy roles
- **GIVEN** playbook directory contains `requirements.yml`
- **WHEN** addon is executed
- **THEN** executes `ansible-galaxy install -r requirements.yml`
- **AND** installs roles to `roles/galaxy/` directory

### Requirement: Inventory Configuration
The addon SHALL configure inventory/hosts file for the target server.

#### Scenario: Configure local inventory
- **GIVEN** installation mode is "local"
- **AND** `SERVER_NAME` environment variable is set
- **WHEN** addon configures inventory
- **THEN** creates `inventory/hosts` with `ansible_connection=local`

#### Scenario: Configure remote inventory
- **GIVEN** installation mode is "remote"
- **AND** SSH credentials are provided via environment variables
- **WHEN** addon configures inventory
- **THEN** creates `inventory/hosts` with SSH connection details

### Requirement: Vars Configuration
The addon SHALL configure vars.yml with Synapse-specific settings.

#### Scenario: Configure vars.yml
- **GIVEN** `SERVER_NAME`, `SSL_CERT`, `SSL_KEY`, `ROOT_CA` are set
- **WHEN** addon configures vars.yml
- **THEN** creates `inventory/host_vars/$SERVER_NAME/vars.yml`
- **AND** sets `matrix_domain` to `SERVER_NAME`
- **AND** configures SSL certificate paths
- **AND** configures federation settings for IP-based deployment

### Requirement: Playbook Execution
The addon SHALL execute the Ansible playbook with specified tags.

#### Scenario: Run installation playbook
- **GIVEN** inventory and vars.yml are configured
- **AND** `PLAYBOOK_TAGS` environment variable is set
- **WHEN** addon executes
- **THEN** runs `ansible-playbook -i inventory/hosts setup.yml --tags=$PLAYBOOK_TAGS`
- **AND** returns exit code to caller

#### Scenario: Handle playbook failure
- **GIVEN** playbook execution fails
- **WHEN** failure is detected
- **THEN** logs error to `install.log`
- **AND** returns non-zero exit code
- **AND** displays error message to user

### Requirement: User Creation
The addon SHALL create admin user via playbook execution.

#### Scenario: Create admin user
- **GIVEN** `ADMIN_USERNAME` and `ADMIN_PASSWORD` are set
- **WHEN** addon is invoked with user-creation phase
- **THEN** executes playbook with `register-user` tag
- **AND** passes username and password as extra vars

#### Scenario: Handle existing user
- **GIVEN** admin user already exists
- **WHEN** addon attempts to create user
- **THEN** detects "User ID already taken" message
- **AND** continues without error
- **AND** logs warning message

### Requirement: Environment Variable Interface
The addon SHALL receive configuration via environment variables from orchestrator.

#### Scenario: Receive SSL configuration
- **GIVEN** orchestrator sets SSL environment variables
- **WHEN** addon is executed
- **THEN** reads `SERVER_NAME`, `SSL_CERT`, `SSL_KEY`, `ROOT_CA`
- **AND** uses them for vars.yml configuration

#### Scenario: Receive installation mode
- **GIVEN** orchestrator sets `INSTALLATION_MODE=local` or `remote`
- **WHEN** addon configures inventory
- **THEN** uses appropriate connection method

### Requirement: Pre-flight Check
The addon SHALL run pre-flight validation before installation.

#### Scenario: Run check-all
- **GIVEN** inventory and configuration are ready
- **WHEN** addon is invoked with check phase
- **THEN** runs playbook with `check-all` tag
- **AND** reports any issues found
- **AND** prompts user to continue or abort

### Requirement: Cleanup Operations
The addon SHALL cleanup existing data and services before installation.

#### Scenario: Cleanup PostgreSQL data
- **GIVEN** existing PostgreSQL data exists in `/matrix/postgres`
- **WHEN** addon is invoked with cleanup phase
- **THEN** removes `/matrix/postgres` directory
- **AND** logs cleanup action

#### Scenario: Stop existing services
- **GIVEN** existing Matrix services are running
- **WHEN** addon is invoked with cleanup phase
- **THEN** stops all `matrix-*` services
- **AND** disables all `matrix-*` services
- **AND** removes Docker containers

### Requirement: Firewall Configuration
The addon SHALL configure firewall to open required ports.

#### Scenario: Configure UFW firewall
- **GIVEN** target system uses UFW
- **WHEN** addon configures firewall
- **THEN** opens port 443/tcp with comment "Matrix HTTPS"
- **AND** opens port 8448/tcp with comment "Matrix Federation"

#### Scenario: Configure firewalld
- **GIVEN** target system uses firewalld
- **WHEN** addon configures firewall
- **THEN** adds https service permanently
- **AND** adds port 8448/tcp permanently
- **AND** reloads firewall

#### Scenario: Configure iptables
- **GIVEN** target system uses iptables only
- **WHEN** addon configures firewall
- **THEN** adds INPUT rules for ports 443 and 8448
- **AND** logs warning about non-persistent rules
