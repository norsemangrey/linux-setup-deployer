#!/bin/bash
set -euo pipefail

sourceDirectory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "${fixture}"' EXIT
mkdir -p "${fixture}/repo/utils" "${fixture}/bin" "${fixture}/home"
cp "${sourceDirectory}/linux-setup-and-config.sh" "${sourceDirectory}/config-helpers.sh" "${fixture}/repo/"
cp "${sourceDirectory}/utils/platform.sh" "${sourceDirectory}/utils/logging-and-output-function.sh" "${fixture}/repo/utils/"
# Avoid the error handler's shared /tmp file and stop before any system changes.
printf '%s\n' 'exec 2>"${HOME}/errors.log"' > "${fixture}/repo/utils/error-handling-function.sh"
cat > "${fixture}/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${HOME}/sudo-calls"
exit 1
EOF
cat > "${fixture}/bin/systemctl" <<'EOF'
#!/bin/bash
[[ "$*" == get-default ]] || exit 1
printf 'multi-user.target\n'
EOF
chmod +x "${fixture}/bin/sudo" "${fixture}/bin/systemctl"
export HOME="${fixture}/home" PATH="${fixture}/bin:${PATH}" WSL_DISTRO_NAME=PlatformTest

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    tail -n 30 "${fixture}/output" >&2
    exit 1
}
setup() {
    platform=hyperv environment=desktop bash "${fixture}/repo/linux-setup-and-config.sh" "$@" \
        > "${fixture}/output" 2>&1
}
hasLog() { grep -Fq -- "$1" "${fixture}/output" || fail "Missing log: $1"; }
expectPlatform() {
    local expectedPlatform="$1"
    local expectedEnvironment="$2"
    shift 2
    rm -f -- "${HOME}/sudo-calls"
    if setup "$@"; then fail "Setup continued past the sudo guard"; fi
    hasLog "Platform: '${expectedPlatform}', environment: '${expectedEnvironment}'."
    hasLog "Invalid sudo password. Sudo permissions required to continue."
    [[ -f "${HOME}/sudo-calls" && "$(cat "${HOME}/sudo-calls")" == -v ]] ||
        fail "Unexpected sudo calls"
}

printf 'platform=physical\nenvironment=headless\n' > "${fixture}/overrides.conf"
expectPlatform physical headless --config "${fixture}/overrides.conf"
printf 'platform=auto\nenvironment=auto\n' > "${fixture}/repo/setup.conf"
expectPlatform wsl headless
printf 'platform=""\nenvironment=""\n' > "${fixture}/empty.conf"
expectPlatform wsl headless --config "${fixture}/empty.conf"

for optionalUtilities in present absent; do
    if [[ "${optionalUtilities}" == absent ]]; then
        rm -- "${fixture}/repo/utils/logging-and-output-function.sh" \
            "${fixture}/repo/utils/error-handling-function.sh"
        cp "${sourceDirectory}/utils/platform.sh" "${fixture}/repo/utils/"
        expectPlatform wsl headless
    fi
    rm -- "${fixture}/repo/utils/platform.sh" "${HOME}/sudo-calls"
    if setup; then fail "Missing platform helper accepted"; fi
    hasLog "Unable to load platform detection. Initialize the utils submodule."
    [[ ! -e "${HOME}/sudo-calls" ]] || fail "Sudo ran without platform detection"
done

printf 'All setup platform integration tests passed.\n'
