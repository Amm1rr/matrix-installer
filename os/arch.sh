#!/bin/bash
# arch.sh - Arch/Manjaro specific package management

OS_NAME="arch"
OS_ID=("arch" "manjaro" "artix" "garuda")

# Required commands (abstract names that will be mapped to package names)
REQUIRED_COMMANDS=("openssl" "ip")

# Map command name to package name for this OS
get_package_for_command() {
    local cmd="$1"
    case "$cmd" in
        openssl) echo "openssl" ;;
        ip) echo "iproute2" ;;
        git) echo "git" ;;
        *) echo "$cmd" ;;
    esac
}

os_detect() {
    unset ID ID_LIKE  # Clear any previous values
    [[ -f /etc/os-release ]] && source /etc/os-release
    [[ "${ID:-}" == "arch" ]] || [[ "${ID:-}" == "manjaro" ]] || \
    [[ "${ID:-}" == "artix" ]] || [[ "${ID:-}" == "garuda" ]]
}

os_install_packages() {
    local packages=("$@")
    sudo pacman -S --noconfirm "${packages[@]}"
}
