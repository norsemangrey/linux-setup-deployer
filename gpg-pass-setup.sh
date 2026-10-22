#!/bin/bash

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --config FILE       Use configuration file to provide input variables."
    echo "  -d, --debug             Enable debug output messages for detailed logging."
    echo "  -v, --verbose           Show standard output from commands (suppress by default)."
    echo "  -h, --help              Show this help message and exit."
    echo ""
    echo "This script installs 'pass' (the standard Unix password manager), creates a GPG key if needed"
    echo "and initializes the password store. It can be run multiple times."
    echo ""
    echo "Configuration file format:"
    echo "  The configuration file is a bash script that will be sourced."
    echo "  Use standard bash variable assignment syntax: variable=\"value\""
    echo "  Lines starting with # are treated as comments and ignored."
    echo ""
}

# Parsed from command line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            configFile="$2"
            shift 2
            ;;
        -d|--debug)
            debug=true
            shift
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
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

# ===================================
# === PREPARE ENVIRONMENT ===========
# ===================================
# region

# INFRASTRUCTURE SETUP

# Set external logger- and error handling script paths
externalLogger=$(dirname "${BASH_SOURCE[0]}")"/utils/logging-and-output-function.sh"
externalErrorHandler=$(dirname "${BASH_SOURCE[0]}")"/utils/error-handling-function.sh"

# Source external logger and error handler (but allow execution without them)
source "${externalErrorHandler}" "Failed to set up GPG and pass" || true
source "${externalLogger}" || true

# Redirect output functions if not debug enabled
run() {

    if [[ "${verbose}" == "true" ]]; then

        "$@"

    else

        "$@" > /dev/null

    fi

}

# Verify if logger function exists or sett fallback
if [[ $(type -t logMessage) != function ]]; then

    # Fallback minimalistic logger function
    logMessage() {

        local level="${2:-INFO}"
        echo "[${level}] $1"

    }

fi

# CONFIG FILE SOURCING

# Set default config file if none specified
: "${configFile:=$(dirname "${BASH_SOURCE[0]}")/setup.conf}"

# Source configuration file if it exists and is readable
if [[ -r "$configFile" ]]; then

    logMessage "Sourcing configuration from '$configFile'..." "INFO"

    # Source the configuration file
    if source "$configFile"; then

        logMessage "Configuration file loaded successfully." "DEBUG"

    else

        logMessage "Failed to source configuration file. Continuing with interactive prompts..." "WARNING"

    fi

else

    logMessage "No readable configuration file found. Continuing with interactive prompts..." "INFO"

fi

# PLATFORM DETECTION AND STEP DEFAULTS (see platform.sh)
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

# BUSINESS LOGIC SETUP

# Make sure GPG can ask for the key passphrase in this terminal
export GPG_TTY=$(tty)

logMessage "Starting GPG and 'pass' setup..." "INFO"

# ===================================
# === INSTALL PASS ==================
# ===================================
# region

# Check if pass is installed
if command -v pass &> /dev/null; then

    logMessage "Pass is already installed." "DEBUG"

else

    logMessage "Installing Pass Password Manager..." "INFO"

    # Install Pass - The Standard Unix Password Manager
    run aptGet update
    run aptGet install -y pass

fi

# endregion

# ===================================
# === CREATE KEY & INITIALIZE PASS ==
# ===================================
# region

logMessage "Initializing 'Pass' Password Manager..." "INFO"

# Check if Pass is already initialized
if [[ -f "${HOME}/.password-store/.gpg-id" ]]; then

    logMessage "Pass is already initialized." "DEBUG"

else

    logMessage "Checking for existing GPG keys..." "INFO"

    # Check for existing GPG keys
    existingGpgKeys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null || true)

    if [[ -n "${existingGpgKeys}" ]]; then

        logMessage "Existing GPG keys found." "DEBUG"

        echo "You already have one or more GPG keys:"
        echo "${existingGpgKeys}"

        # Default is to use the existing key (the last one), so a re-run does not create more keys
        read -p "Press 'Enter' to use the existing key, or type 'Y/y' to add a new GPG key: " 2>&1 confirm

        [[ "${confirm}" =~ ^[Yy]$ ]] && createKey=true

    else

        createKey=true

    fi

    # Generate a new GPG key if needed
    if [[ "${createKey}" == "true" ]]; then

        logMessage "Generating a new GPG key..." "INFO"

        # Prompt for GPG details if not provided in config
        [[ -n "$gpgNameReal" ]] || read -p "Enter your real name for the GPG key: " 2>&1 gpgNameReal
        [[ -n "$gpgNameEmail" ]] || read -p "Enter your email address for the GPG key: " 2>&1 gpgNameEmail

        # Set default GPG configuration values if not provided
        [[ -n "$gpgKeyType" ]] || gpgKeyType="RSA"
        [[ -n "$gpgKeyLength" ]] || gpgKeyLength="4096"
        [[ -n "$gpgExpireDate" ]] || gpgExpireDate="0"

        # Create temporary GPG batch file
        tempBatchFile=$(mktemp)
        cat > "$tempBatchFile" <<EOF
Key-Type: ${gpgKeyType}
Key-Length: ${gpgKeyLength}
Name-Real: ${gpgNameReal}
Name-Email: ${gpgNameEmail}
Expire-Date: ${gpgExpireDate}
%commit
EOF

        # Generate GPG key using temporary batch file
        if gpg --batch --pinentry-mode=ask --generate-key "$tempBatchFile"; then

            logMessage "GPG key generated successfully." "DEBUG"

        else

            logMessage "Failed to generate GPG key." "ERROR"

        fi

        # Clean up temporary file
        rm -f "$tempBatchFile"

    fi

    logMessage "Fetching the last generated GPG key..." "INFO"

    # Get the last generated key's fingerprint
    keyId=$(gpg --list-secret-keys --keyid-format LONG | grep 'sec' | tail -n1 | awk '{print $2}' | cut -d'/' -f2 || true)

    # Check if the key ID is empty
    if [[ -z "${keyId}" ]]; then

        logMessage "No GPG key found. Cannot initialize password manager." "ERROR"

        exit 1

    fi

    logMessage "Found GPG Key ID: ${keyId}" "DEBUG"

    logMessage "Initializing Password Manager with GPG key..." "INFO"

    # Initialize pass with this key
    pass init "${keyId}"

fi

# endregion

exit 0
