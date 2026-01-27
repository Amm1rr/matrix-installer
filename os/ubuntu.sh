#!/bin/bash
# ubuntu.sh - Ubuntu/Debian specific package management

OS_NAME="ubuntu"
OS_ID=("ubuntu" "debian")

# Required commands (abstract names that will be mapped to package names)
REQUIRED_COMMANDS=("openssl" "ip")

# Map command name to package name for this OS
get_package_for_command() {
    local cmd="$1"
    case "$cmd" in
        openssl) echo "openssl" ;;
        ip) echo "iproute2" ;;
        git) echo "git-all" ;;
        *) echo "$cmd" ;;
    esac
}

os_detect() {
    unset ID ID_LIKE  # Clear any previous values
    [[ -f /etc/os-release ]] && source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || [[ "${ID:-}" == "debian" ]] || \
    [[ "${ID_LIKE:-}" == *"ubuntu"* ]] || [[ "${ID_LIKE:-}" == *"debian"* ]]
}

os_install_packages() {
    local packages=("$@")
    sudo apt-get update -qq || true
    sudo apt-get install -y "${packages[@]}"
}
