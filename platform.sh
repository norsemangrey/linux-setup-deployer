#!/bin/bash

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message and exit."
    echo ""
    echo "This script detects the platform and environment the system is running on."
    echo "It is sourced by the setup scripts after the configuration file, but it can also be run directly."
    echo ""
    echo "Platform:"
    echo "  wsl                     Windows Subsystem for Linux (hosted on Windows)."
    echo "  hyperv                  Hyper-V virtual machine (hosted on Windows)."
    echo "  proxmox                 QEMU/KVM virtual machine (Proxmox)."
    echo "  physical                Anything else (bare metal)."
    echo ""
    echo "Environment:"
    echo "  desktop                 Graphical target with an installed display manager or desktop session."
    echo "  headless                Anything else."
    echo ""
    echo "Both values can be set in the configuration file to override the detection."
    echo "Leave them empty (or set to 'auto') to detect them."
    echo ""
}

# Parsed from command line arguments (only when run directly, not when sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Invalid option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

fi

# =========================
# === FUNCTIONS ===========
# =========================
# region

# Detect the platform
detectPlatform() {

    # Check if running under Windows Subsystem for Linux
    if [[ -n "${WSL_DISTRO_NAME}" ]] || grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; then

        echo "wsl"

    # Check if the virtual machine vendor is Microsoft
    elif grep -qi "microsoft" /sys/class/dmi/id/sys_vendor 2>/dev/null; then

        echo "hyperv"

    # Check if the virtual machine vendor is QEMU
    elif grep -qi "qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null; then

        echo "proxmox"

    else

        echo "physical"

    fi

}

# Detect the environment (desktop = graphical target AND an installed display manager or desktop session)
detectEnvironment() {

    # Ubuntu Server also defaults to graphical.target, so the target alone is not enough
    if [[ "$(timeout 5 systemctl get-default 2>/dev/null)" != "graphical.target" ]]; then

        echo "headless"

    elif [[ -n "$(ls -A /usr/share/xsessions /usr/share/wayland-sessions 2>/dev/null)" ]] \
        || [[ -e /etc/systemd/system/display-manager.service ]]; then

        echo "desktop"

    else

        echo "headless"

    fi

}

# endregion

# =========================
# === DETECTION ===========
# =========================
# region

# Detect the platform and environment unless configured ('auto' = not configured)
[[ -n "${platform}" && "${platform}" != "auto" ]] || platform="$(detectPlatform)"
[[ -n "${environment}" && "${environment}" != "auto" ]] || environment="$(detectEnvironment)"

# endregion

# Print the result and exit if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    echo "Platform: '${platform}'  -  Environment: '${environment}'."

    exit 0

fi

# Never let the last command status fail the sourcing script (the ERR trap would fire)
return 0
