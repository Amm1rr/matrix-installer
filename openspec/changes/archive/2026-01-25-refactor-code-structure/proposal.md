# Change: Refactor Code Structure

## Why

The current `main.sh` has several maintainability issues:

1. **Code duplication**: Root Key configuration prompts are repeated 4 times (lines 1021-1082, 1092-1157, 1196-1268, 1457-1517)
2. **Inconsistent prompting**: Some prompts use `prompt_user()`, others use `read -rp` directly
3. **IP detection repetition**: Same IP detection code appears in multiple places (lines 945-948, 1304-1307, 1374-1377)
4. **No navigation back**: Selection menus (`prompt_select_root_ca_from_files`, `prompt_select_root_ca_from_certs`) have no "back to main menu" option
5. **Inconsistent menu styling**: `menu_without_root_ca` uses styled header, `menu_with_root_ca` doesn't

These issues make the code harder to maintain and extend.

## What Changes

### Code Structure Changes

**New helper functions:**
- `get_detected_ip()` - Centralized IP address detection
- `prompt_root_ca_config()` - Reusable Root Key configuration prompts
- `create_root_ca_from_menu()` - Unified Root Key creation flow
- `print_menu_header()` - Unified menu styling

**Functions removed:**
- `create_new_root_ca_with_config()` - Replaced by `prompt_root_ca_config()` + `create_root_ca_from_menu()`

**Functions modified:**
- `prompt_select_root_ca_from_files()` - Add "back to main menu" option
- `prompt_select_root_ca_from_certs()` - Add "back to main menu" option
- `menu_with_root_ca()` - Use new helper functions, add styled header
- `menu_without_root_ca()` - Use new helper functions
- `menu_run_addon()` - Use `get_detected_ip()` helper
- `ssl_manager_create_root_ca()` - Use `get_detected_ip()` helper

### Behavior Changes

1. **Menu navigation**: All selection menus now have option 0 to return to main menu
2. **Consistent prompting**: All user input uses `prompt_user()` or `prompt_yes_no()` helpers
3. **Unified styling**: All menus use the same styled header format

### Non-Breaking Changes

All user-facing behavior is preserved:
- IP/domain suggestions still work
- Addon system unchanged
- Certificate generation unchanged
- Menu flows preserved (with added "back" option)

## Impact

### Affected specs
- `user-interface` - All menu and prompt interactions
- `helper-functions` - New helper functions added

### Affected code
- `main.sh:55-153` - Helper functions section (add ~80 lines)
- `main.sh:361-544` - Selection menu functions (modify for "back" option)
- `main.sh:546-622` - SSL Manager functions (use helpers)
- `main.sh:861-1412` - Menu system functions (use helpers, add styling)
- `main.sh:1457-1517` - Remove duplicate function

### Code reduction
- ~150 lines of duplicate code removed
- ~120 lines of new helper code added
- Net reduction: ~30 lines
- 4 new reusable functions
- 1 duplicate function removed

## Dependencies

None - this is a pure refactoring with no external dependencies.
