# Tasks

## 1. Add new helper functions (matrix-installer.sh:55-153)

- [x] Add `get_detected_ip()` function after `is_ip_address()`
  - Implements IP detection using `ip route get 1` with fallback to `ip -4 addr show`
  - Returns detected IP or empty string

- [x] Add `print_menu_header()` function
  - Displays styled box header with centered title
  - Uses 58 character width for centering

- [x] Add `prompt_root_ca_config()` function
  - Prompts for Organization, Country (2 letters), State, City, Validity
  - Validates country code (must be 2 chars)
  - Validates days (must be numeric)
  - Displays configuration summary
  - Returns pipe-delimited: `org|country|state|city|days`

- [x] Add `create_root_ca_from_menu()` function
  - Prompts for confirmation to create Root Key
  - Calls `prompt_root_ca_config()` for input
  - Temporarily sets global SSL_* variables
  - Prompts for final confirmation
  - Calls `ssl_manager_create_root_ca()` if confirmed
  - Restores original global SSL_* variables

## 2. Add "Back" option to selection menus

- [x] Modify `prompt_select_root_ca_from_files()` (lines 361-395)
  - Add option 0 "Back to main menu"
  - Return code 2 when option 0 selected
  - Update prompt range to include 0

- [x] Modify `prompt_select_root_ca_from_certs()` (lines 470-544)
  - Add option 0 "Back to main menu"
  - Return code 2 when option 0 selected
  - Update prompt range to include 0

- [x] Update `prompt_use_existing_root_ca()` (lines 397-468)
  - Handle return code 2 from `prompt_select_root_ca_from_files()`
  - Return to main menu flow when code 2 received

- [x] Update `main()` Root Key selection handling (lines 1543-1553)
  - Handle return code 2 from `prompt_select_root_ca_from_certs()`
  - Show `menu_without_root_ca()` when user goes back

## 3. Refactor SSL Manager to use helper functions

- [x] Update `ssl_manager_create_root_ca()` (lines 546-622)
  - Replace inline IP detection with `get_detected_ip()` call
  - Simplify prompt logic using helper result

## 4. Refactor menu_with_root_ca() to use helpers (lines 861-1174)

- [x] Add styled header to `menu_with_root_ca()` - SKIPPED (menu already has custom format)
  - Call `print_menu_header()` at start of menu loop
  - Display: "Matrix Installer - Main Menu"

- [x] Simplify option 1 (Generate server certificate)
  - Use `get_detected_ip()` helper
  - Use `prompt_user()` consistently (replace direct `read -rp`)

- [x] Simplify option 8 (Switch/Create Root Key)
  - Use `create_root_ca_from_menu()` helper
  - Handle new return code 2 from selection menu

- [x] Simplify option 9 (Create new Root Key)
  - Use `create_root_ca_from_menu()` helper

## 5. Refactor menu_without_root_ca() to use helpers (lines 1176-1279)

- [x] Simplify option 1 (Generate new Root Key)
  - Use `prompt_root_ca_config()` helper
  - Parse pipe-delimited config output
  - Use `ssl_manager_create_root_ca()` directly

## 6. Refactor menu_run_addon() to use helper (lines 1281-1412)

- [x] Update IP detection when no servers exist (lines 1303-1337)
  - Replace inline IP detection with `get_detected_ip()`
  - Use `prompt_user()` consistently

- [x] Update IP detection for new server option (lines 1373-1385)
  - Replace inline IP detection with `get_detected_ip()`

## 7. Remove duplicate function

- [x] Remove `create_new_root_ca_with_config()` function (lines 1457-1517)
  - Function replaced by `prompt_root_ca_config()` + `create_root_ca_from_menu()`

- [x] Update all callers
  - Replace call at line 1012 with `create_root_ca_from_menu`
  - Replace call at line 1548 with `create_root_ca_from_menu`

## 8. Validation

- [x] Test Root Key selection with "Back" option
  - Run script with multiple Root Keys in certs/
  - Select option 0 to go back
  - Verify returns to main menu

- [x] Test Root Key selection from files with "Back" option
  - Run script with Root Key files next to matrix-installer.sh
  - Select option 0 to go back
  - Verify continues to certs/ menu

- [x] Test IP detection in all prompts
  - Verify server certificate generation shows detected IP
  - Verify addon menu shows detected IP
  - Verify Root Key directory prompt shows detected IP

- [x] Test Root Key creation from all menu options
  - Create from option 8 (single Root Key)
  - Create from option 8 (multiple Root Keys - select create new)
  - Create from option 9
  - Create from menu without Root Key (option 1)

- [x] Test addon functionality
  - Verify addons receive correct environment variables
  - Verify addon discovery still works
  - Verify addon installation completes

- [x] Test all menu navigation paths
  - Files menu → Back → certs/ menu
  - certs/ menu → Back → main menu
  - Generate certificate → return to menu
  - Install addon → exit (addon takes control)

## Dependencies

- Tasks 1-3 can be done in parallel (independent additions)
- Task 4 depends on Task 1 (needs helper functions)
- Task 5 depends on Task 1 (needs helper functions)
- Task 6 depends on Task 1 (needs helper functions)
- Task 7 depends on Tasks 4-6 (needs callers updated first)
- Task 8 depends on all previous tasks (needs all changes complete)
