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
    echo "This script installs the 'pass' password manager, creates (or reuses) a GPG key"
    echo "and initializes the password store with that key. It does not depend on SSH setup."
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

# endregion

logMessage "Starting GPG and pass setup and config..." "INFO"

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
    run sudo apt-get update
    run sudo apt-get install -y pass

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
    existingGpgKeys=$(gpg --list-secret-keys --keyid-format LONG)

    # Check if any existing GPG keys were found
    if [[ -n "${existingGpgKeys}" ]]; then

        logMessage "Existing GPG keys found." "DEBUG"

        echo "You already have one or more GPG keys:"

        # List existing GPG keys
        gpg --list-secret-keys --keyid-format LONG

    fi

    # Prompt the user: Enter to continue (default), Y to add a new entry
    read -p "Press 'Enter' to add a new GPG key, or type 'N/n' to continue without adding: " 2>&1 confirm

    # If user hits Enter, set confirm to "y"
    if [[ -z "$confirm" ]]; then
        confirm="y"
    fi

    # If user confirmed, generate a new GPG key
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then

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

    # Get the last generated key’s fingerprint
    keyId=$(gpg --list-secret-keys --keyid-format LONG | grep 'sec' | tail -n1 | awk '{print $2}' | cut -d'/' -f2)

    # Check if the key ID is empty
    if [[ -z "${keyId}" ]]; then

        logMessage "No GPG key found. Cannot initialize password manager." "ERROR"

    else

        logMessage "Found GPG Key ID: ${keyId}" "DEBUG"

        logMessage "Initializing Password Manager with GPG key..." "INFO"

        # Initialize pass with this key
        pass init "${keyId}"

    fi

fi

# endregion

logMessage "GPG and pass setup completed." "INFO"

exit 0
