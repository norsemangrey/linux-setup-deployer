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
    echo "This script automates the setup and configuration of an SSH server with key-based authentication."
    echo "It installs OpenSSH, starts the SSH service, configures firewall rules, and secures the SSH server by"
    echo "disabling root login and password authentication. Additionally, it guides the user to add client keys."
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

# ===================================
# === PREPARE ENVIRONMENT ===========
# ===================================
# region

# INFRASTRUCTURE SETUP

# Set external logger- and error handling script paths
externalLogger=$(dirname "${BASH_SOURCE[0]}")"/utils/logging-and-output-function.sh"
externalErrorHandler=$(dirname "${BASH_SOURCE[0]}")"/utils/error-handling-function.sh"

# Source external logger and error handler (but allow execution without them)
source "${externalErrorHandler}" "Failed to set up SSH" || true
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

# BUSINESS LOGIC SETUP

# Get the username from environment variable
username="${USER}"

# Get the IP address of the machine
address=$(hostname -I | awk '{print $1}')

logMessage "Identified user '${username}' @ host '$(hostname)'" "DEBUG"

# If the username is "root", ask for confirmation before continuing
if [ "${username}" == "root" ]; then

    # Prompt user for confirmation to continue
    read -p "You are logged in as root. Are you sure you want to continue? (y/n): " confirmation

    # If not "Yes" the abort script
    if [[ ! "${confirmation}" =~ ^[Yy]$ ]]; then

        logMessage "Aborted by user. Exiting setup..." "INFO"

        exit 0

    fi

fi

#endregion

logMessage "Starting SSH setup and config..." "INFO"

# ===================================
# === INSTALL & START SSH ===========
# ===================================
# region

# Check if OpenSSH server is installed
if dpkg -l | grep -q openssh-server; then

    logMessage "OpenSSH server is already installed." "DEBUG"

else

    logMessage "Installing OpenSSH server..." "INFO"

    # Update and install OpenSSH server
    run sudo apt-get update && run sudo apt-get install -y openssh-server

fi

# Check if SSH service is already running
if ! systemctl is-active --quiet ssh; then

    logMessage "Starting and enabling SSH service..." "INFO"

    # Start and enable the SSH service
    sudo systemctl start ssh
    sudo systemctl enable ssh

else

    logMessage "SSH service is already running." "DEBUG"

fi

# endregion

# ===================================
# === CONFIGURE FIREWALL ============
# ===================================
# region

# Check if UFW is installed and SSH rule exists
if command -v ufw >/dev/null; then

    logMessage "Checking firewall rules..." "DEBUG"

    # Check if SSH firewall rule is already configured
    if sudo ufw show added | grep -q ' 22/tcp'; then

        logMessage "Firewall rule for SSH already exists." "DEBUG"

    else

        logMessage "Configuring firewall to allow SSH..." "INFO"

        # Set allow rule for SSH on port 22 and reload UFW
        run sudo ufw allow 22/tcp comment 'SSH'
        run sudo ufw reload

    fi

else

    echo "UFW is not installed. Skipping firewall configuration." "WARNING"

fi

# endregion

# ===================================
# === INSTALL KEYCHAIN ==============
# ===================================
# region

# Check if Keychain is installed
if command -v keychain &> /dev/null; then

    logMessage "Keychain is already installed." "DEBUG"

else

    logMessage "Installing Keychain Key Manager..." "INFO"

    # Install Keychain Key Manager
    run sudo apt-get update && run sudo apt-get install -y keychain

fi

# endregion

# Check if pass is installed
if command -v pass &> /dev/null; then

    logMessage "Pass is already installed." "DEBUG"

else

    logMessage "Installing Pass - The Standard Unix Password Manager..." "INFO"

    # Install Pass - The Standard Unix Password Manager
    run sudo apt-get update && run sudo apt-get install -y pass

fi


logMessage "Generating a new GPG key..." "INFO"

# Generate GPG key (semi-automated)
gpg --full-generate-key

logMessage "Fetching the last generated GPG key..." "INFO"

# Get the last generated key’s fingerprint
KEY_ID=$(gpg --list-secret-keys --keyid-format LONG | grep 'sec' | tail -n1 | awk '{print $2}' | cut -d'/' -f2)

if [[ -z "$KEY_ID" ]]; then

    logMessage "No GPG key found. Did you cancel key generation?" "ERROR"

else

    logMessage "Found GPG Key ID: $KEY_ID" "DEBUG"

    logMessage "Initializing Password Manager with GPG key..." "INFO"

    # Initialize pass with this key
    pass init "$KEY_ID"

fi


# ===================================
# === CLIENT SSH AUTHENTICATION =====
# ===================================
# region

logMessage "Setting up SSH key-based authentication for '${username}'..." "INFO"

# Create SSH directory if it doesn't exist and set correct permissions
if [ ! -d "/home/${username}/.ssh" ]; then

    # Create directory and set correct permissions
    sudo mkdir -p /home/"${username}"/.ssh
    sudo chmod 700 /home/"${username}"/.ssh

fi

# Create authorized_keys file if it doesn't exist
if [ ! -f /home/"${username}"/.ssh/authorized_keys ]; then

    echo "Creating the authorized keys file..." "INFO"

    # Create file and set correct permissions
    sudo touch /home/"${username}"/.ssh/authorized_keys
    sudo chmod 600 /home/"${username}"/.ssh/authorized_keys

fi

# Track the initial line count of the authorized_keys file
initialKeyCount=$(wc -l < /home/"${username}"/.ssh/authorized_keys 2>/dev/null || echo 0)

# Check if key file contains any pre-existing client entries
if [ $initialKeyCount -gt 0 ]; then

    # Prompt user to add new key or continue
    echo "The 'Authorized Keys' file already contains one or more entries. Do you want to add a new key entry?"
    echo -e "\e[33mWARNING: Continuing the script will disable SSH password login, ensure the existing client public key is correct."
    read -p "Press 'Enter' to continue or 'Y/y' to add a new client key: " 2>&1 reply

    # If "N" or "n", set flag to add new client key
    if [[ "${reply}" =~ ^[Yy]$ ]]; then

        copyKey=true

    else

        logMessage "Continuing with existing client entries." "DEBUG"

    fi

else

    # Set flag
    copyKey=true

fi

# Loop to check and prompt for the public key until it is found in the authorized_keys file
while [[ "$copyKey" == true ]]; do

    logMessage "Waiting for new client public key..." "INFO"

    # Prompt user to copy the public key from the client computer
    echo "Please use the 'ssh-copy-id' command on your client machine to copy client public key to this server."
    echo "Example: 'ssh-copy-id ${username}@${address}' or 'ssh-copy-id ${username}@$(hostname)'."
    read -p "Press 'Enter' after copying the public key to continue..." 2>&1

    # Get the current line count
    currentKeyCount=$(wc -l < /home/"${username}"/.ssh/authorized_keys 2>/dev/null || echo 0)

    # Check for new line and validate new key
    if [ "${currentKeyCount}" -gt "${initialKeyCount}" ] && tail -n 1 /home/"${username}"/.ssh/authorized_keys | grep -q "^ssh-"; then

        logMessage "Client public key successfully added." "INFO"

        break

    else

        logMessage "Public key not found in the authorized keys file." "WARNING"

    fi

done

# endregion

# ===================================
# === SSH CONFIGURATION =============
# ===================================
# region

logMessage "Backing up existing SSH config and disabling root login and password authentication..."

# Backup existing SSH configuration
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
sshConfigFile="/etc/ssh/sshd_config"
sshConfigBackup="${sshConfigFile}.bak.${timestamp}"
sudo cp "${sshConfigFile}" "${sshConfigBackup}"

# Check and update SSH configuration values only if necessary
sshConfigUpdate() {

    local setting="$1"
    local value="$2"

    # Check if a non-commented line for the setting already exists (excluding lines starting with "# ")
    if sudo grep -E "^[[:space:]]*${setting}\b" "${sshConfigFile}" > /dev/null; then

        # Update existing setting line
        sudo sed -i -E "/^# /! s|^[[:space:]]*${setting}\b.*|${setting} ${value}|" "${sshConfigFile}"

    # If only a commented line exists
    elif sudo grep -E "^[[:space:]]*#?[[:space:]]*${setting}\b" "${sshConfigFile}" > /dev/null; then

        # Replace commented line (but not "# " style comments)
        sudo sed -i -E "/^# /! s|^[[:space:]]*#?[[:space:]]*${setting}\b.*|${setting} ${value}|" "${sshConfigFile}"

    else

        # Append if setting does not exist at all
        echo "${setting} ${value}" | sudo tee -a "${sshConfigFile}" > /dev/null

    fi

    configUpdated=true
}

# Modify config to disable root login and password authentication
sshConfigUpdate "PermitRootLogin" "no"
sshConfigUpdate "PasswordAuthentication" "no"
sshConfigUpdate "ChallengeResponseAuthentication" "no"
sshConfigUpdate "UsePAM" "no"

# If config was updated, restart SSH and keep the backup
if [ "${configUpdated}" = true ]; then

    logMessage "SSH configuration updated. Restarting SSH service..." "INFO"

    # Restart SSH service to apply changes
    sudo systemctl restart ssh

else

    logMessage "No changes made to the SSH configuration. Removing configuration backup..." "INFO"

    # Remove the backup file if no changes were made
    sudo rm "${sshConfigBackup}"

fi

# endregion

logMessage "SSH enabled and key-based authentication configured for user '${username}'." "INFO"

# Inform user about login
echo "You can now log in using the private key corresponding to the provided- or existing public key."

exit 0
