#!/bin/bash

# Platform detection. Sourced by the setup scripts AFTER the config file.
#
# Two independent facts are detected (both can be overridden in the config file):
#   platform:    wsl | hyperv | other   (other = bare metal or any other hypervisor)
#   environment: desktop | headless

# Detect the platform
detectPlatform() {

    if [[ -n "${WSL_DISTRO_NAME}" ]] || grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; then

        echo "wsl"

    elif grep -qi "microsoft" /sys/class/dmi/id/sys_vendor 2>/dev/null; then

        echo "hyperv"

    else

        echo "other"

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

# Only detect when not configured ('auto' = not configured)
[[ -n "${platform}" && "${platform}" != "auto" ]] || platform="$(detectPlatform)"
[[ -n "${environment}" && "${environment}" != "auto" ]] || environment="$(detectEnvironment)"

# When run directly (not sourced), print the result
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

    echo "Platform: '${platform}', environment: '${environment}'."

    exit 0

fi

# Never let the last command status fail the sourcing script (the ERR trap would fire)
return 0
