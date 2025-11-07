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
    echo "This script sets up a Linux environment by installing and configuring"
    echo "essential tools and applications, including ZSH, Oh-My-Posh, LSDeluxe,"
    echo "Fastfetch, and more. It also executes custom setup scripts and ensures"
    echo "the system is up-to-date."
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

# =========================
# === PREPARE ENVIRONMENT =
# =========================
# region

# INFRASTRUCTURE SETUP

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

# BUSINESS LOGIC SETUP

# Check if sudo password is valid (not expired)
sudo -v

# Exit if sudo is not available
if [ $? -ne 0 ]; then

    logMessage "Invalid sudo password. Sudo permissions required to continue." "ERROR"

    exit 1

fi

# TODO: Consider moving out of script
# Personal variables
personalReposPath="${HOME}/workspace/personal/repos"
personalGithubUser="norsemangrey"
personalGithubToken="xxx"

export DOWNLOADS="${HOME}/downloads"
mkdir -p "${DOWNLOADS}"

# endregion

# =========================
# === FUNCTIONS ===========
# =========================
# region

# Install a package if not already installed
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

# Perform alternative installation actions
alternativeInstallationActions() {

    local packageName="$1"

    case "${packageName}" in

        "oh-my-posh")

            # Download Oh-My-Posh
            sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh

            return 0
            ;;

        "git-credential-manager")

            # Get the latest Git Credential Manager release download URL
            downloadUrl=$(curl -s https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest | grep "browser_download_url" | grep ".deb" | cut -d '"' -f 4)

            # Download Git Credential Manager
            sudo wget "${downloadUrl}" -O ${DOWNLOADS}/gcm-linux.deb

            # Install Git Credential Manager
            sudo dpkg -i ${DOWNLOADS}/gcm-linux.deb

            return 0
            ;;

        "lazygit")

            # Download the latest Lazygit release
            downloadUrl=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep "browser_download_url" | grep "linux_x86_64.tar.gz" | cut -d '"' -f 4)

            # Download and extract Lazygit
            wget "${downloadUrl}" -O ${DOWNLOADS}/lazygit.tar.gz

            # Extract Lazygit
            tar -xzf ${DOWNLOADS}/lazygit.tar.gz -C ${DOWNLOADS}

            # Install Lazygit
            sudo install ${DOWNLOADS}/lazygit -D -t /usr/local/bin/

            return 0
            ;;

        *)
            return 1
            ;;

    esac

}

# Perform pre-installation actions
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

# Perform post-installation actions
postInstallationActions() {

    local packageName="$1"

    logMessage "Performing post-installation actions for package '${packageName}'..." "DEBUG"

    case "${packageName}" in

        "fd-find")

            # Create a symlink for fd as it will be installed as fdfind due to clash with other packages
            ln -sf /usr/bin/fdfind ~/.local/bin/fd

            ;;

        "bat")

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

        "git-credential-manager")

            # Remove downloaded package
            rm -f ${DOWNLOADS}/gcm-linux.deb

            # Configure Git Credential Manager
            #git-credential-manager configure

            ;;

        *)

            logMessage "No post-installation actions for package '${packageName}'." "DEBUG"

            ;;

    esac

}

# Run a local script with error handling and logging
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

# Clone and run an external script
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

# endregion

logMessage "Starting setup and config script..." "INFO"

# =========================
# === SYSTEM UPGRADE ======
# =========================
# region

logMessage "Updating and upgrading the system..." "INFO"

# Ensure the system is up-to-date
run sudo apt-get update -y && run sudo apt-get upgrade -y

# Clean up unnecessary packages
run sudo apt-get autoremove -y

# endregion

# =========================
# === LOCALE SETUP ========
# =========================
# region

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

    logMessage "All required locales are already available." "DEBUG"

fi

#endregion

# =========================
# === PACKAGE INSTALL =====
# =========================
# region

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
    "git-credential-manager"
    "lazygit"
)

# Create local bin folder if it does not exist
mkdir -p ~/.local/bin

# Loop through packages and install them if not already installed
for package in "${packages[@]}"; do

    installPackage "${package}"

done

# endregion

# =========================
# === SSH, CLOUD & MOUNT ==
# =========================
# region

# Runs script to configure SSH
runLocalScript "ssh-setup-and-config"

# Runs script to configure cloud and network client(s)
runLocalScript "cloud-client-setup"

# endregion

# =========================
# === DOTFILES SETUP ======
# =========================
# region

# Clone and run the dotfiles setup script
cloneAndRunExternalScript "${personalGithubUser}" ".dotfiles" "deploy-config-linux.sh"

# Source common environment variables
[ -f "$HOME/.env" ] && source "$HOME/.env"

#endregion

# =========================
# === CERTIFICATE SETUP ===
# =========================
# region

# Define certificate search locations
certificateLocations=(
    "${HOME}/cloud/work/setup/certificates"
)
certificateDestination="/usr/local/share/ca-certificates"

logMessage "Checking for certificates in specified locations..." "INFO"

# Loop through each certificate location
for certLocation in "${certificateLocations[@]}"; do

    # Check if the directory exists
    if [[ -d "${certLocation}" ]]; then

        logMessage "Searching for certificates in '${certLocation}'..." "DEBUG"

        # Find files with PEM, CER, CRT extensions
        find "${certLocation}" -type f \( -iname "*.pem" -o -iname "*.cer" -o -iname "*.crt" \) | while read -r certFile; do

            # Get certificate base name and destination name
            certBaseName=$(basename "${certFile}")

            # Get certificate extension
            certExt="${certBaseName##*.}"

            # Set destination name with CRT extension
            certDestName="${certBaseName%.*}.crt"

            # Set destination path
            certDestPath="${certificateDestination}/${certDestName}"

            logMessage "Copying certificate '${certFile}' to '${certDestPath}'..." "DEBUG"

            # Copy certificate to destination
            if sudo cp "${certFile}" "${certDestPath}"; then

                logMessage "Certificate '${certFile}' copied successfully." "DEBUG"

            else

                logMessage "Failed to copy certificate '${certFile}'." "ERROR"

            fi

        done

    else

        logMessage "Certificate location '${certLocation}' does not exist. Skipping." "DEBUG"

    fi

done


# Update CA certificates if any certs were found
if find "${certificateDestination}" -type f -iname "*.crt" | grep -q .; then

    logMessage "Updating CA certificates..." "INFO"

    # Update the CA certificates
    if sudo update-ca-certificates; then

        logMessage "CA certificates updated successfully." "DEBUG"

    else

        logMessage "Failed to update CA certificates." "ERROR"

    fi

else

    logMessage "No certificates found in specified locations. Skipping CA update." "DEBUG"

fi

# endregion

# =========================
# === GIT REPOS TO SSH ====
# =========================
# region

# Converts all repositories in a path to use SSH protocol for the origin remote
convertRepoToSSH() {

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
#convertRepoToSSH "${personalReposPath}" "${personalGithubUser}"

# endregion

# =========================
# === GITHUB CREDENTIALS ==
# =========================
# region

personalGithubCredentialsStored=false

# Prompt user to configure GitHub credentials for HTTPS access
while [[ "${personalGithubCredentialsStored}" != "true" ]]; do

    read -p "Do you want to configure GitHub credentials for HTTPS access? (Y/n): " configureChoice

    # Set default choice to Y
    configureChoice="${configureChoice:-Y}"

    # Check user choice
    if [[ "${configureChoice}" =~ ^[Nn]$ ]]; then

        logMessage "Skipping GitHub credential configuration." "INFO"
        break

    fi

    # Prompt for cloud credentials if not set in config
    [[ -n "$personalGithubToken" ]] || read -p "GitHub PAT ('gho_<token>'): " 2>&1 personalGithubToken

    # Check that the GitHub token starts with 'gho_'
    if [[ "${personalGithubToken}" != gho_* ]]; then

        logMessage "Invalid GitHub token. The token must start with 'gho_'." "ERROR"

        personalGithubToken=""

    else

        # Store GitHub credentials using Git Credential Manager
        if printf "protocol=https\nhost=github.com\nusername=${personalGithubUser}\npassword=${personalGithubToken}\n" \
        | git credential approve; then

            logMessage "GitHub credentials stored successfully." "DEBUG"

            personalGithubCredentialsStored=true

        else

            logMessage "Failed to store GitHub credentials." "ERROR"

            personalGithubToken=""

        fi

    fi

done

# endregion

# Install plugins and configure applications
# (done after dotfiles to get correct paths etc.)

# =========================
# === TMUX CONFIG =========
# =========================
# region

tmuxConfigDirectory="${XDG_CONFIG_HOME}/tmux"
tpmDirectory="${tmuxConfigDirectory}/plugins"

# Proceed with TPM setup only if the TMUX config directory exists
if [[ -d "${tmuxConfigDirectory}" ]]; then

    cloneAndRunExternalScript "tmux-plugins" "tpm" "bin/install_plugins" "${tpmDirectory}" > /dev/null 2>&1

else

    logMessage "TMUX config directory not found. Skipping TPM and plugin installation." "WARNING"

fi

# endregion

# =========================
# === ZSH CONFIG ==========
# =========================
# region

# Check if ZSH is installed and set as the default shell if ZSH environment file exists
if command -v zsh &> /dev/null && [[ -f "$HOME/.zshenv" ]]; then

    # Check that ZSH is not already default shell
    if [[ "$SHELL" != "$(which zsh)" ]]; then

        logMessage "Setting ZSH as the default shell..." "INFO"

        # Set ZSH as the default shell
        chsh -s "$(which zsh)" 2>&1

        logMessage "ZSH is now the default shell. Please log out and log back in for changes to take effect." "INFO"

    else

        logMessage "ZSH is already the default shell." "DEBUG"

    fi

else

    logMessage "ZSH is not installed or no ZSH environment file found. Skipping setting ZSH as the default shell." "WARNING"

fi

# endregion

logMessage "Setup and config script completed."

# =========================
# === REBOOT PROMPT =======
# =========================
# region

logMessage "System setup is complete. A reboot is recommended to ensure all changes take effect." "INFO"

# Prompt user for reboot
read -p "Would you like to reboot the system now? (y/N): " rebootChoice 2>&1
echo

# Check user choice and reboot if confirmed
if [[ $rebootChoice =~ ^[Yy]$ ]]; then

    logMessage "Rebooting the system..." "INFO"

    # Give user a moment to see the message
    sleep 2

    # Reboot the system
    sudo reboot

else

    logMessage "Reboot skipped. Please remember to reboot manually when convenient to ensure all changes take effect." "WARNING"

    # Return to home directory
    cd ~

    # Activate ZSH
    zsh

fi

# endregion
