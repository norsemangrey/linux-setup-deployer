#!/bin/bash

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --debug             Enable debug output messages for detailed logging."
    echo "  -v, --verbose           Show standard output from commands (suppress by default)."
    echo "  -h, --help              Show this help message and exit."
    echo ""
    echo "This script sets up a Linux environment by installing and configuring"
    echo "essential tools and applications, including ZSH, Oh-My-Posh, LSDeluxe,"
    echo "Fastfetch, and more. It also executes custom setup scripts and ensures"
    echo "the system is up-to-date."
    echo ""
}

# Parsed from command line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
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


# Set external logger- and error handling script paths
externalLogger=$(dirname "${BASH_SOURCE[0]}")"/utils/logging-and-output-function.sh"
externalErrorHandler=$(dirname "${BASH_SOURCE[0]}")"/utils/error-handling-function.sh"
externalCloneAndExecute=$(dirname "${BASH_SOURCE[0]}")"/utils/clone-and-execute-script.sh"

# Source external logger and error handler (but allow execution without them)
source "${externalErrorHandler}" "Linux setup script failed" || true
source "${externalLogger}" || true

# Verify if logger function exists or sett fallback
if [[ $(type -t logMessage) != function ]]; then

    # Fallback minimalistic logger function
    logMessage() {

        local level="${2:-INFO}"
        echo "[$level] $1"

    }

fi

# Redirect output functions if not debug enabled
run() {

    if [[ "${verbose}" == "true" ]]; then

        "$@"

    else

        "$@" > /dev/null

    fi

}

# Check if sudo password is valid (not expired)
sudo -v

# Exit if sudo is not available
if [ $? -ne 0 ]; then

    logMessage "Invalid sudo password. Sudo permissions required to continue." "ERROR"

    exit 1

fi

# Ensure the system is up-to-date
logMessage "Updating and upgrading the system..." "INFO"

run sudo apt-get update -y && run sudo apt-get upgrade -y

logMessage "System update and upgrade completed." "INFO"

# Check and install UFW
if ! command -v ufw &> /dev/null; then

    logMessage "Installing UFW..." "INFO"

    # Install JQuery
    run sudo apt-get install -y ufw

    logMessage "UFW installed successfully." "INFO"

else

    logMessage "UFW is already installed." "DEBUG"

fi

# Check and install ZSH
if ! command -v zsh &> /dev/null; then

    logMessage "Installing ZSH..." "INFO"

    # Installing ZSH
    run sudo apt-get install -y zsh

    logMessage "ZSH installed successfully." "INFO"

else

    logMessage "ZSH is already installed." "DEBUG"

fi

# Check and install Oh-My-Posh
if ! command -v oh-my-posh &> /dev/null; then

    logMessage "Installing Oh-My-Posh..." "INFO"

    # Download Oh-My-Posh
    sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh

    # Set execution permission
    sudo chmod +x /usr/local/bin/oh-my-posh

    logMessage "Oh-My-Posh installed successfully." "INFO"

else

    logMessage "Oh-My-Posh is already installed." "DEBUG"

    run sudo oh-my-posh upgrade

fi

# Check and install LSDeluxe (lsd)
if ! command -v lsd &> /dev/null; then

    logMessage "Installing LSDeluxe (lsd)..." "INFO"

    # Install LSDelux
    run sudo apt-get install -y lsd

    logMessage "LSDeluxe installed successfully." "INFO"

else

    logMessage "LSDeluxe is already installed." "DEBUG"

fi

# Check and install Fastfetch
if ! command -v fastfetch &> /dev/null; then

    logMessage "Installing Fastfetch..." "INFO"

    # Add repository, update and install Fastfetch
    run sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
    run sudo apt-get update
    run sudo apt-get install -y fastfetch

    logMessage "Fastfetch installed successfully." "INFO"

else

    logMessage "Fastfetch is already installed." "DEBUG"

fi

# Check and install JQuery (jq)
if ! command -v jq &> /dev/null; then

    logMessage "Installing JQuery (jq)..." "INFO"

    # Install JQuery
    run sudo apt-get install -y jq

    logMessage "JQuery installed successfully." "INFO"

else

    logMessage "JQuery is already installed." "DEBUG"

fi

# Set external SSH installer script
sshInstaller=$(dirname "${BASH_SOURCE[0]}")"/ssh-setup-and-config.sh"

# Execute external SSH setup script
if [[ -f "${sshInstaller}" ]]; then

    logMessage "Set execute permissions on installer script (${sshInstaller})." "DEBUG"

    # Set permissions on the installer script
    chmod +x "${sshInstaller}"

    logMessage "Executing SSH setup script (${sshInstaller})..." "INFO"

    # Execute SSH installer
    "${sshInstaller}" ${debug:+-d}

    # Check for errors
    if [[ $? -eq 0 ]]; then

        logMessage "SSH setup script executed successfully." "INFO"

    else

        logMessage "SSH setup script failed." "ERROR"

    fi

else

    logMessage "SSH setup script ($sshInstaller) is not executable or not found." "ERROR"

fi

# Set external SSH installer script
cloudClientInstaller=$(dirname "${BASH_SOURCE[0]}")"/cloud-client-setup.sh"

# Execute external SSH setup script
if [[ -f "${cloudClientInstaller}" ]]; then

    logMessage "Set execute permissions on installer script (${cloudClientInstaller})." "DEBUG"

    # Set permissions on the installer script
    chmod +x "${cloudClientInstaller}"

    logMessage "Executing Cloud client setup script (${cloudClientInstaller})..." "INFO"

    # Execute SSH installer
    "${cloudClientInstaller}" ${debug:+-d}

    # Check for errors
    if [[ $? -eq 0 ]]; then

        logMessage "Cloud client setup script executed successfully." "INFO"

    else

        logMessage "Cloud client setup script failed." "ERROR"

    fi

else

    logMessage "Cloud client setup script ($cloudClientInstaller) is not executable or not found." "ERROR"

fi

logMessage "Cloning 'dotfiles' repository and executing installer..."

# Set URL and executable for the 'dotfiles' repository
dotfilesRepo="https://github.com/norsemangrey/.dotfiles.git"
dotfilesInstaller="deploy-config-linux.sh"

# Clone and execute the 'dotfiles' repository, creating symlinks for configurations files in the repo
"${externalCloneAndExecute}" --url "${dotfilesRepo}" --executable "${dotfilesInstaller}" --root "${HOME}" ${debug:+-d} ${verbose:+-v}

# Set ZSH as the default shell if ZSH environment file exists
if [[ -f "$HOME/.zshenv" ]]; then

    # Check that ZSH is not already default shell
    if [[ "$SHELL" != "$(which zsh)" ]]; then

        logMessage "Setting ZSH as the default shell..." "INFO"

        # Set ZSH as the default shell
        chsh -s "$(which zsh)" 2>&1

        # Activate ZSH
        zsh

        logMessage "ZSH is now the default shell. Please log out and log back in for changes to take effect." "INFO"

    else

        logMessage "ZSH is already the default shell." "DEBUG"

    fi

else

    logMessage "No ZSH environment file found. Skipping setting ZSH as the default shell." "WARNING"

fi

logMessage "Installer script completed."
