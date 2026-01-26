## 1. Implementation

- [ ] 1.1 Add Root Key directory naming logic (based on server IP/domain)
- [ ] 1.2 Implement `migrate_old_cert_structure()` function
- [ ] 1.3 Update `ssl_manager_init()` to detect and run migration
- [ ] 1.4 Update `ssl_manager_create_root_ca()` to use new directory structure
- [ ] 1.5 Update `ssl_manager_generate_server_cert()` to use `servers/` subdirectory
- [ ] 1.6 Update `detect_root_ca()` to scan for Root Key directories
- [ ] 1.7 Update `get_root_ca_info()` to work with new structure
- [ ] 1.8 Update `env_provider_export_for_addon()` to export new paths
- [ ] 1.9 Add `get_active_root_ca_dir()` function
- [ ] 1.10 Add `list_root_cas()` function
- [ ] 1.11 Add backup functionality for duplicate Root Key directories
- [ ] 1.12 Update menu system to handle Root Key selection from certs/ (if multiple exist)
- [ ] 1.13 Implement `detect_root_ca_files_next_to_script()` to find all .key/.crt pairs
- [ ] 1.14 Implement `prompt_select_root_ca_from_files()` for multiple Root Key selection menu
- [ ] 1.15 Update `prompt_use_existing_root_ca()` to handle multiple Root Key files
- [ ] 1.16 Implement Root Key copy to new directory structure with proper naming

## 2. Testing

- [ ] 2.1 Test fresh installation (no existing certs)
- [ ] 2.2 Test migration from old flat structure
- [ ] 2.3 Test creating Root Key with new structure
- [ ] 2.4 Test duplicate directory handling with backup
- [ ] 2.5 Test server certificate generation under new structure
- [ ] 2.6 Test addon environment variables with new paths
- [ ] 2.7 Test multiple Root Key scenario
- [ ] 2.8 Test certificate validation with new paths
- [ ] 2.9 Test multiple Root Key files next to main.sh scenario
- [ ] 2.10 Test single Root Key file next to main.sh scenario

## 3. Documentation

- [ ] 3.1 Update ARCHITECTURE.md with new directory structure
- [ ] 3.2 Update MANUAL_SSL_CERTIFICATES.md with new paths
- [ ] 3.3 Update ADDON_INTERFACE.md with new environment variables
- [ ] 3.4 Update project.md with new structure
