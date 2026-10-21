#!/bin/bash

# Platform detection and per-step defaults. Sourced by the setup scripts AFTER the config file.
#
# Two independent facts are detected (both can be overridden in the config file):
#   platform:    wsl | hyperv | other   (other = bare metal or any other hypervisor)
#   environment: desktop | headless
#
# Each step has a switch (setupXxx) that can be set to 'yes' or 'no' in the config file.
# Leave it empty (or 'auto') to get the default for the detected platform/environment.

# Set a variable to a default value unless it has been configured (empty or 'auto' = not configured)
defaultTo() {

    local name="$1"
    local value="$2"

    if [[ -z "${!name}" || "${!name}" == "auto" ]]; then

        printf -v "${name}" '%s' "${value}"

    fi

}

# Check if a value means 'yes' (y, yes, true - case insensitive)
isYes() {

    [[ "${1,,}" =~ ^(y|yes|true)$ ]]

}

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

# Detect the environment (a graphical default target means a desktop install)
detectEnvironment() {

    if [[ "$(timeout 5 systemctl get-default 2>/dev/null)" == "graphical.target" ]]; then

        echo "desktop"

    else

        echo "headless"

    fi

}

# Only detect when not configured
[[ -n "${platform}" && "${platform}" != "auto" ]] || platform="$(detectPlatform)"
[[ -n "${environment}" && "${environment}" != "auto" ]] || environment="$(detectEnvironment)"

# Helpers for the defaults below
isWsl=false;      [[ "${platform}" == "wsl" ]] && isWsl=true
isDesktop=false;  [[ "${environment}" == "desktop" ]] && isDesktop=true

# STEP DEFAULTS (yes / no)

# Locale generation (desktop installers already handle this)
defaultTo setupLocale "$( ${isDesktop} && echo no || echo yes )"

# OpenSSH server, key-based login and firewall rule (Windows handles this for WSL)
defaultTo setupSsh "$( ${isWsl} && echo no || echo yes )"
defaultTo setupFirewall "$( ${isWsl} && echo no || echo yes )"

# Avahi (mDNS) is only needed on headless machines that are not WSL
defaultTo setupAvahi "$( (${isWsl} || ${isDesktop}) && echo no || echo yes )"

# GPG key, 'pass' and GitHub HTTPS credentials (for remote development on headless machines)
defaultTo setupPass "$( ${isDesktop} && echo no || echo yes )"

# Clone and run the dotfiles repository
defaultTo setupDotfiles "yes"

# Work setup (host share, work cloud symlink, copy of personal cloud to host).
# Only the user knows if it is relevant on WSL/Hyper-V, so it is left blank (= ask).
# The legacy 'connectSmb' variable is still honored.
[[ -n "${setupWork}" ]] || setupWork="${connectSmb}"
[[ "${setupWork}" != "auto" ]] || setupWork=""
[[ "${platform}" == "other" && -z "${setupWork}" ]] && setupWork="no"

# Desktop clients (Nextcloud) are configured in the UI. Only the local folder is prepared.
[[ -n "${connectCloud}" || "${environment}" != "desktop" ]] || connectCloud="no"

# Architecture name used by the apt packages and release downloads
architecture="$(dpkg --print-architecture 2>/dev/null)"

# Never let the last command status fail the sourcing script (the ERR trap would fire)
return 0
