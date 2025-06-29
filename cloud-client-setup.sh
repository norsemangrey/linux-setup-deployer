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

logMessage "Setting up Personal cloud directory..." "INFO"

# Set the path to the cloud storage directory
cloudPath="${HOME}/cloud/personal"

# Set the path to the DAVFS2 configuration file
configFile="/etc/davfs2/secrets"

# Check and install DAVFS2 (mounts a WebDAV resource as a regular file system)
if ! command -v mount.davfs &> /dev/null; then

    logMessage "Installing WebDav Client (davfs2)..." "INFO"

    # Disables interactive configuration prompts during package installations
    export DEBIAN_FRONTEND=noninteractive

    echo "You might need to hit 'Enter' to continue..."

    # Installing DAVFS2 (run non-interactively)
    run sudo apt-get install -y davfs2

    logMessage "WebDav Client (davfs2) installed successfully." "INFO"

    # Add user to the davfs2 group
    sudo usermod -aG davfs2 "${username}"

else

    logMessage "WebDav Client (davfs2) is already installed." "DEBUG"

fi

# Create a directory for the cloud storage
mkdir -p "${cloudPath}"

# Prompt the user for the WebDav entry or continue
read -p "Do you want to make a new entry to the WebDav client (davfs2) configuration? (y/N): " 2>&1 confirm

# Check the user's response
if [[ "$confirm" =~ ^[Yy]$ ]]; then

    while [[ -z "$url" || "$retry" =~ ^[Yy]$ ]]; do

        echo "To add a new WebDav folder mount, you need to provide the following information:"

        # Proceed with prompting the user for the WebDav information
        read -p "Enter the address (e.g., 'cloud.domain.com'): " 2>&1 webDavAddress
        read -p "Enter the username: " 2>&1 webDavUsername
        read -s -p "Enter the password: " 2>&1 webDavPassword

        echo # Move to a new line after the password input

        # Set the full WebDav URL
        url="https://${webDavAddress}/remote.php/dav/files/${webDavUsername}"

        echo "The following entry will be added to the WebDav client configuration:"
        echo "URL:      ${url}"
        echo "Username: ${webDavUsername}"
        echo "Password: ********"
        read -p "Do you want to enter the information again? (y/N): " 2>&1 retry

    done

    # Check if the URL already exists in the configuration file
    if grep -q "^${url}" "${configFile}"; then

        logMessage "The URL '${url}' already exists in the configuration file (${configFile})." "INFO"

    else

        # Create the configuration entry string
        configEntry="${url} ${webDavUsername} ${webDavPassword}"

        # Append the string to the configuration file
        echo "${configEntry}" | sudo tee -a "${configFile}" > /dev/null

        logMessage "Entry successfully added to configuration file (${configFile})." "INFO"

    fi

    # Check if the URL already exists in /etc/fstab
    if grep -q "^${url}" /etc/fstab; then

        logMessage "The URL '${url}' already exists in the fstab (/etc/fstab)." "INFO"

    else

        # Create the fstab entry string
        fstabEntry="${url} ${cloudPath} davfs user,rw,auto 0 0"

        # Append the string to the fstab
        echo "${fstabEntry}" | sudo tee -a /etc/fstab > /dev/null

        logMessage "Entry successfully added to fstab (/etc/fstab)." "INFO"

        # Reload the systemd manager configuration
        sudo systemctl daemon-reload

        # Mount the cloud storage directory
        sudo mount "${cloudPath}"

    fi

else

    # Skip the operation
    echo "Operation canceled. No changes were made to WebDav client configuration."

fi


### WORK CLOUD DIRECTORY

logMessage "Setting up Work cloud directory..." "INFO"

# Set the path to the cloud storage directory
cloudPath="${HOME}/cloud/work"

# Check if '/mnt/c' is already mounted
if mountpoint -q /mnt/c; then

    logMessage "There is already a mountpoint on '/mnt/c'. Skipping mount step." "DEBUG"

else

    # Check and install CIFS utilities (used for mounting SMB shares)
    if ! command -v mount.cifs &> /dev/null; then

        logMessage "Installing CIFS Share Utilities (cifs-utils)..." "INFO"

        # Installing cifs-utils (run non-interactively)
        run sudo apt-get install -y cifs-utils


        logMessage "CIFS Share Utilities (cifs-utils) installed successfully." "INFO"

    else

        logMessage "CIFS Share Utilities (cifs-utils) is already installed." "DEBUG"

    fi

    # Prompt the user for the Windows share credentials
    read -p "Do you want to set up a mountpoint for a Windows share (C$)? (y/N): " 2>&1 confirm

    # Check the user's response
    if [[ "$confirm" =~ ^[Yy]$ ]]; then

        while [[ -z "$smbHost" || -z "$smbUsername" || -z "$smbPassword" || "$retry" =~ ^[Yy]$ ]]; do

            echo "To mount the Windows share, you need to provide the following information:"

            # Proceed with prompting the user for the host and credential information
            read -p "Enter the hostname or IP address of the Windows host: " 2>&1 smbHost
            read -p "Enter the Windows username: " 2>&1 smbUsername
            read -s -p "Enter the Windows password: " 2>&1 smbPassword

            echo # Move to a new line after the password input

            echo "The following will be used to mount the Windows share:"
            echo "Host:     ${smbHost}"
            echo "Username: ${smbUsername}"
            echo "Password: ********"
            read -p "Do you want to enter the information again? (y/N): " 2>&1 retry

        done

        # Save SMB credentials securely for reuse
        logMessage "Saving Windows share credentials to '/etc/smb-credentials'..." "INFO"

        # Save credentials to file
        if ! sudo bash -c "cat > /etc/smb-credentials" <<EOF
username=${smbUsername}
password=${smbPassword}
EOF
        then

            logMessage "Failed to SMB save credentials." "ERROR"
            exit 1

        fi

        # Set credentials file permissions
        sudo chmod 600 /etc/smb-credentials

        logMessage "Windows share credentials saved." "DEBUG"

        # Create new directory for the C$ share mount point
        if ! sudo mkdir -p /mnt/c; then

            logMessage "Failed to create mount point '/mnt/c'" "ERROR"
            exit 1

        fi

        logMessage "Mounting Windows share ('//${smbHost}/C\$') to mount point ('/mnt/c')..." "INFO"

        # Attempt to mount the Windows C$ share
        if ! sudo mount -t cifs //${smbHost}/c\$ /mnt/c \
            -o credentials=/etc/smb-credentials,uid=$(id -u),gid=$(id -g),vers=3.0,mfsymlinks; then

            logMessage "Mount failed. Please check credentials, network, or permissions." "ERROR"

            exit 1

        fi

        logMessage "Windows share mounted successfully." "INFO"

        # Add fstab line to ensure mount persists across reboots

        # Set the Windows share
        smbShare="//${smbHost}/c\$"

        # Check if the entry already exists in /etc/fstab
        if grep -q "^${smbShare}" /etc/fstab; then

            logMessage "The Windows share '${smbShare}' already exists in the fstab (/etc/fstab)." "INFO"

        else

            # Create the fstab entry string
            fstabEntry="//${smbHost}/c\$ /mnt/c cifs credentials=/etc/smb-credentials,uid=$(id -u),gid=$(id -g),vers=3.0,mfsymlinks 0 0"

            # Append the string to the fstab
            echo "${fstabEntry}" | sudo tee -a /etc/fstab > /dev/null

            logMessage "Entry successfully added to fstab (/etc/fstab)." "INFO"

        fi

    else

        # Skip the operation
        echo "Operation canceled. No new Windows share mountpoint configured."

    fi

fi

logMessage "Checking for Windows symlink ('C:/Cloud') in '/mnt/c/Cloud'..." "INFO"

# Check for existence of a symlink specifically named '/mnt/c/Cloud' in mount point
if [[ ! -L "/mnt/c/Cloud" ]]; then

    logMessage "Symlink '/mnt/c/Cloud' not found. Aborting." "ERROR"

    echo "Expected symlink folder 'C:/Cloud' was not found on the Windows host's C drive."

    exit 1

fi

logMessage "Found Windows symlink ('C:/Cloud') in '/mnt/c/Cloud'." "DEBUG"

# Read the target of the symlink
winTarget=$(readlink "/mnt/c/Cloud")

logMessage "Original Windows symlink target: '$winTarget'" "DEBUG"

# Convert Windows-style path (/??/C:/Users/...) → Linux-style (/mnt/c/Users/...)
linuxTarget=$(echo "$winTarget" | sed -E 's|^/..?/([A-Za-z]):|/mnt/\L\1|')

logMessage "Converted to Linux target: '$linuxTarget'" "DEBUG"

# Check if the Linux symlink target already exists
if [[ -e "${cloudPath}" || -L "${cloudPath}" ]]; then

    logMessage "Symlink '${cloudPath} → $linuxTarget' already exists." "INFO"

else

    # Create the Linux-native symlink pointing to the resolved Windows share path
    if ! ln -s "$linuxTarget" "${cloudPath}"; then

        logMessage "Failed to create symlink '${cloudPath} → $linuxTarget'" "ERROR"

        exit 1

    fi

    logMessage "Symlink created: '${cloudPath} → $linuxTarget'" "INFO"

fi

exit 0
