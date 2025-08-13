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


# Ensure required locales are available

# Required locales
locales=("en_US" "nb_NO")

# Check if each locale is available
missingLocales=()

# Check if each locale is available
for locale in "${locales[@]}"; do

    # Append UTF string to locale
    localeCheck="${locale}.utf8"

    # Check if locale is available
    if ! locale -a | grep -q "${localeCheck}"; then

        # Add missing locale to array
        missingLocales+=("${locale}")

    fi

done

# Regenerate locales if any are missing
if [ ${#missingLocales[@]} -ne 0 ]; then

    logMessage "Found missing locales (${missingLocales[*]}). Adding to locale file (/etc/locale.gen)..." "INFO"

    # Backup locale.gen
    sudo cp /etc/locale.gen /etc/locale.gen.bak

    # Add missing locales to locale file
    for locale in "${missingLocales[@]}"; do

        # Append UTF string to locale
        localeNew="${locale}.UTF-8"

        # Add locale to locale.gen file
        sudo sed -i "/${localeNew}/s/^#//" /etc/locale.gen

    done


    logMessage "Generating missing locales..." "INFO"

    # Regenerate locales
    run sudo locale-gen

else

    echo "All required locales are already available." "DEBUG"

fi

# Function to install a package if not already installed
installPackage() {

    local packageName="$1"

    if ! dpkg -s "${packageName}" &> /dev/null; then

        logMessage "Installing '${packageName}'..." "INFO"

        # Perform any pre-installation actions
        preInstallationActions "${packageName}"

        # Check for alternative installation methods
        if alternativeInstallationActions "${packageName}"; then

            logMessage "Alternative installation for '${packageName}' completed successfully." "DEBUG"

        else

            # Install the package
            run sudo apt-get install -y "${packageName}"

        fi

        # Perform any post-installation actions
        postInstallationActions "${packageName}"

        logMessage "Successfully installed package '${packageName}'." "DEBUG"

    else

        logMessage "Package '${packageName}' is already installed." "DEBUG"

    fi

}

# Function to perform alternative installation actions
alternativeInstallationActions() {

    local packageName="$1"

    case "${packageName}" in

        "oh-my-posh")

            # Download Oh-My-Posh
            sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh

            return 0
            ;;

        *)
            return 1

            ;;

    esac

}

# Function to perform pre-installation actions
preInstallationActions() {

    local packageName="$1"

    logMessage "Performing pre-installation actions for package '${packageName}'..." "DEBUG"

    case "${packageName}" in

        "fastfetch")

            # Add repository, update and install Fastfetch
            run sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
            run sudo apt-get update

            ;;

        *)

            logMessage "No pre-installation actions for package '${packageName}'." "DEBUG"

            ;;

    esac

}

# Function to perform post-installation actions
postInstallationActions() {

    local packageName="$1"

    logMessage "Performing post-installation actions for package '${packageName}'..." "DEBUG"

    case "${packageName}" in

        "fd-find")

            # Create a symlink for fd as it will be installed as fdfind due to clash with other packages
            ln -sf /usr/bin/fdfind ~/.local/bin/fd

            ;;

        "batcat")

            # Create a symlink for batcat as it will be installed as bat due to clash with other packages
            ln -sf /usr/bin/batcat ~/.local/bin/bat

            ;;

        "avahi-daemon")

            # Start and enable Avahi service
            run sudo systemctl enable --now avahi-daemon

            ;;

        "oh-my-posh")

            # Set execution permission
            sudo chmod +x /usr/local/bin/oh-my-posh

            ;;

        *)

            logMessage "No post-installation actions for package '${packageName}'." "DEBUG"

            ;;

    esac

}

# Array of packages to install
declare -a packages=(
    "ufw"
    "zsh"
    "lsd"
    "tmux"
    "fzf"
    "fastfetch"
    "oh-my-posh"
    "jq"
    "yq"
    "fd-find"
    "bat"
    "avahi-daemon"
    "python3-libtmux"
)

# Create local bin folder if it does not exist
mkdir -p ~/.local/bin

# Loop through packages and install them if not already installed
for package in "${packages[@]}"; do

    installPackage "${package}"

done


# Function to run an local script with error handling and logging
runLocalScript() {

    local scriptName="$1"

    # Set local setup script path
    scriptPath=$(dirname "${BASH_SOURCE[0]}")"/${scriptName}.sh"

    # Execute local setup script
    if [[ -f "${scriptPath}" ]]; then

        logMessage "Set execute permissions on installer script (${scriptPath})." "DEBUG"

        # Set permissions on the installer script
        chmod +x "${scriptPath}"

        logMessage "Executing setup script '${scriptName}'..." "INFO"

        # Execute installer script
        "${scriptPath}" ${debug:+-d} ${verbose:+-v}

        # Check for errors
        if [[ $? -eq 0 ]]; then

            logMessage "Setup script '${scriptName}' executed successfully." "DEBUG"

        else

            logMessage "Setup script '${scriptPath}' failed." "ERROR"

        fi

    else

        logMessage "Setup script '${scriptPath}' is not executable or not found." "ERROR"

    fi

}

### SSH SETUP

# Runs script to configure SSH
runLocalScript "ssh-setup-and-config"

### CLOUD CLIENT SETUP

# Runs script to configure cloud and network client(s)
runLocalScript "cloud-client-setup"


personalReposPath="${HOME}/workspace/personal/repos"
personalGithubUser="norsemangrey"

# Function to clone and run an external script
cloneAndRunExternalScript() {

    repoOwner="$1"
    repoName="$2"
    repoExecutable="$3"
    repoDirectory="$4"

    repoAddress="https://github.com/${repoOwner}/${repoName}.git"

    if [ "${repoOwner}" == "${personalGithubUser}" ]; then

        # Use path for personal repositories
        repoLocalPath="${repoDirectory:-${personalReposPath}}"

    else

        # Use default path for other repositories
        repoLocalPath="${repoDirectory:-/tmp/repos}"

    fi

    logMessage "Cloning '${repoName}' repository and executing '${repoExecutable}'..." "INFO"

    # Clone and execute the 'dotfiles' repository, creating symlinks for configurations files in the repo
    "${externalCloneAndExecute}" --url "${repoAddress}" --executable "${repoExecutable}" --root "${repoLocalPath}" ${debug:+-d} ${verbose:+-v}

}

### DOTFILES SETUP

# Clone and run the dotfiles setup script
cloneAndRunExternalScript "${personalGithubUser}" ".dotfiles" "deploy-config-linux.sh"

# Configure install plugins and configure applications
# (done after dotfiles to get correct paths etc.)

# Source common environment variables
[ -f "$HOME/.env" ] && source "$HOME/.env"

# Git

# Tell Git to use SSH for the following repos
# git -C "${repoLocalPath}"/linux-setup-deployer remote set-url origin github:norsemangrey/linux-setup-deployer.git
# git -C "${repoLocalPath}"/.dotfiles remote set-url origin github:norsemangrey/.dotfiles.git

# Function to set all repositories in a path to use SSH for the origin remote
setReposToUseSSH() {

    local rootPath="$1"
    local repoOwner="$2"

    logMessage "Setting all repositories in '${rootPath}' to use SSH for the origin remote..." "INFO"

    # Find all .git directories in path (depth 2 to catch nested repos)
    find "${rootPath}" -type d -name ".git" | while read -r gitDirectory; do

        local repoPath
        local repoName

        # Get the parent directory of the .git directory
        repoPath="$(dirname "${gitDirectory}")"

        # Get repo name from path
        repoName="$(basename "${repoPath}")"

        # Set repo to use SSH for the origin remote
        git -C "$repoPath" remote set-url origin "git@github.com:${repoOwner}/${repoName}.git"

        logMessage "Set repo '${repoName}' to use SSH remote." "DEBUG"

    done

}

# Set all personal repositories to use SSH
setReposToUseSSH "${personalReposPath}" "${personalGithubUser}"

### TMUX SETUP

tmuxConfigDirectory="${XDG_CONFIG_HOME}/tmux"
tpmDirectory="${tmuxConfigDirectory}/plugins/tpm"

# Proceed with TPM setup only if the TMUX config directory exists
if [[ -d "${tmuxConfigDirectory}" ]]; then

    # # Install TMUX Plugin Manager (TPM) if not already installed
    # if [[ ! -d "${tpmDirectory}" ]]; then

    #     logMessage "Installing Tmux Plugin Manager (TPM)..." "INFO"

    #     # Clone the TPM repository
    #     git clone https://github.com/tmux-plugins/tpm "${tpmDirectory}"

    #     logMessage "TPM installed successfully." "INFO"

    # else

    #     logMessage "TPM is already installed." "DEBUG"
    # fi

    # logMessage "Installing TPM plugins..." "INFO"

    # # Automatically install TPM plugins
    # "${tpmDirectory}/bin/install_plugins"

    # logMessage "TPM plugins installed." "INFO"

    cloneAndRunExternalScript "tmux-plugins" "tpm" "bin/install_plugins" "${tpmDirectory}"

else

    logMessage "TMUX config directory not found. Skipping TPM and plugin installation." "WARNING"

fi


### ZSH SETUP

# Check if ZSH is installed and set as the default shell if ZSH environment file exists
if command -v zsh &> /dev/null && [[ -f "$HOME/.zshenv" ]]; then

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

    logMessage "ZSH is not installed or no ZSH environment file found. Skipping setting ZSH as the default shell." "WARNING"

fi

logMessage "Installer script completed."
