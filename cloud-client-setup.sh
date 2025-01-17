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
    echo "TBD"
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

# Source external logger and error handler (but allow execution without them)
source "${externalErrorHandler}" "Failed to set up cloud client" || true
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


# Get the username from the $USER environment variable
username="${USER}"

# Set the path to the cloud storage directory
cloudPath="/home/${username}/cloud"

# Set the path to the DAVFS2 configuration file
configFile="~/.config/davfs2/secrets"


# Check and install DAVFS2 (mounts a WebDAV resource as a regular file system)
if ! command -v mount.davfs &> /dev/null; then

    logMessage "Installing WebDav Client (davfs2)..." "INFO"

    # Installing DAVFS2
    run sudo apt-get install -y davfs2

    logMessage "WebDav Client (davfs2) installed successfully." "INFO"

    # Add user to the davfs2 group
    usermod -aG davfs2 "${username}"

else

    logMessage "WebDav Client (davfs2) is already installed." "DEBUG"

fi


# Create a directory for the cloud storage
mkdir "${cloudPath}"

# Create a directory for the davfs2 configuration
mkdir $(dirname "${configFile}")

# Copy the template secrets file to the davfs2 configuration directory
sudo cp /etc/davfs2/secrets "${configFile}"

# Change the ownership of the secrets file to the user
sudo chown "${username}":"${username}" "${configFile}"

# Change the permissions of the secrets file to read-write for the user only
chmod 600 "${configFile}"


# Prompt the user for the WebDav entry or continue
read -p "Do you want to make a new entry to the WebDav client (davfs2) configuration? (y/N): " confirm

# Check the user's response
if [[ "$confirm" =~ ^[Yy]$ ]]; then

    # Proceed with the new entry
    read -p "Enter the address (e.g., 'cloud.domain.com'): " 2>&1 address
    read -p "Enter the username: " 2>&1 username
    read -s -p "Enter the password: " 2>&1 password

    echo # Move to a new line after the password input

    # Set the full WebDav URL
    url="https://$address/remote.php/dav/files/$username"

    # Create the configuration entry string
    configEntry= "${url} ${username} ${password}"

    # Append the string to the configuration file
    echo "${configEntry}" >> "${configFile}"

    logMessage "Entry successfully added to configuration file ("${configFile}")." "INFO"

    # Create the fstab entry string
    fstabEntry="${url} ${cloudPath} davfs user,rw,auto 0 0"

    # Append the string to the fstab
    sudo echo "${fstabEntry}" >> /etc/fstab

    logMessage "Entry successfully added to fstab (/etc/fstab)." "INFO"

    # Reload the systemd manager configuration
    sudo systemctl daemon-reload

    # Confirm the operation
    logMessage "Systemd manager configuration reloaded." "INFO"

    # Mount the cloud storage directory
    sudo mount "${cloudPath}"

else

    # Skip the operation
    echo "Operation canceled. No changes were made to WebDav client configuration."

fi

exit 0
