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

# ===================================
# === PREPARE ENVIRONMENT ===========
# ===================================
# region

# INFRASTRUCTURE SETUP

# Set external logger- and error handling script paths
externalLogger=$(dirname "${BASH_SOURCE[0]}")"/utils/logging-and-output-function.sh"
externalErrorHandler=$(dirname "${BASH_SOURCE[0]}")"/utils/error-handling-function.sh"

# Source external logger and error handler (but allow execution without them)
source "${externalErrorHandler}" "Failed to set up cloud/mount" || true
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

# Get the username from the $USER environment variable
username="${USER}"

logMessage "Setting up Personal cloud directory..." "INFO"

# TODO: Consider moving outside script
# Set the path to the cloud storage directory
personalCloudPath="${HOME}/cloud/personal"
workCloudPath="${HOME}/cloud/work"

# endregion

logMessage "Starting cloud client and mount setup..." "INFO"

# ===================================
# === INSTALL WEBDAV CLIENT =========
# ===================================
# region

# Check and install DAVFS2 (mounts a WebDAV resource as a regular file system)
if ! command -v mount.davfs &> /dev/null; then

    logMessage "Installing WebDav Client (davfs2)..." "INFO"

    # Disables interactive configuration prompts during package installations
    export DEBIAN_FRONTEND=noninteractive

    echo "You might need to hit 'Enter' to continue..."

    # Pre-answer davfs2 questions to avoid prompts
    echo davfs2 davfs2/use_locks boolean true | sudo debconf-set-selections

    # Installing DAVFS2 (run non-interactively)
    run sudo apt-get install -y davfs2

    logMessage "WebDav Client (davfs2) installed successfully." "DEBUG"

    # Add user to the davfs2 group
    sudo usermod -aG davfs2 "${username}"

else

    logMessage "WebDav Client (davfs2) is already installed." "DEBUG"

fi

# endregion

### PERSONAL CLOUD DIRECTORY

logMessage "Setting up personal cloud directory..." "INFO"

# ===================================
# === CHECK WEBDAV CONFIGURATION ====
# ===================================
# region

# Create a directory for the cloud storage
mkdir -p "${personalCloudPath}"

# Set the path to the DAVFS2 configuration file
configFile="/etc/davfs2/secrets"

### CHECK EXISTING CONFIGURATION

logMessage "Checking DAVFS2 configuration..." "INFO"

# Check that the DAVFS2 configuration file exists
if [[ -f "${configFile}" ]]; then

    # Get the address of any entry in the DAVFS2 configuration file
    existingEntry=$(sudo grep -v '^#' "${configFile}" | grep -v '^[[:space:]]*$' | awk '{print $1}')

fi

# Check if an entry was found
if [[ -n "${existingEntry}" ]]; then

    logMessage "Existing WebDav address found: '${existingEntry}'" "INFO"

    # Prompt the user: Enter to continue (default), Y to add a new entry
    read -p "Press 'Enter' to continue, or type 'Y/y' to add a new entry to the WebDav client configuration: " 2>&1 confirm

else

    logMessage "No existing WebDav configuration entry found." "DEBUG"

    # Prompt the user: Enter to add a new entry (default), N to skip
    read -p "Press 'Enter' to add a new entry to the WebDav client configuration, or type 'N/n' to skip: " 2>&1 confirm

    # If user hits Enter, set confirm to "y"
    if [[ -z "$confirm" ]]; then
        confirm="y"
    fi

fi

# endregion

# ===================================
# === CREATE WEBDAV CONFIGURATION ===
# ===================================
# region

### PROMPT USER FOR NEW ENTRY

# Check the user's response
if [[ "$confirm" =~ ^[Yy]$ ]]; then

    logMessage "Adding new WebDav configuration entry..." "INFO"

    while [[ -z "$url" || "$retry" =~ ^[Rr]$ ]]; do

        echo "To add a new WebDav folder mount, you need to provide the following information:"

        # Proceed with prompting the user for the WebDav information
        read -p "Address (e.g., 'cloud.domain.com'): " 2>&1 webDavAddress
        read -p "Username: " 2>&1 webDavUsername
        read -s -p "Password: " 2>&1 webDavPassword

        echo # Move to a new line after the password input

        # Set the full WebDav URL
        url="https://${webDavAddress}/remote.php/dav/files/${webDavUsername}"

        echo "The following entry will be added to the WebDav client configuration:"
        echo "URL:      ${url}"
        echo "Username: ${webDavUsername}"
        echo "Password: ********"
        read -p "Press 'Enter' to continue or 'R/r' to re-enter the information: " 2>&1 retry

        # If user hits Enter or types N/n, break the loop
        if [[ -z "$retry" || "$retry" =~ ^[Nn]$ ]]; then
            break
        fi

    done

    # Check if the URL already exists in the configuration file
    if grep -q "^${url}" "${configFile}"; then

        logMessage "The URL '${url}' already exists in the configuration file." "INFO"

    else

        # Create the configuration entry string
        configEntry="${url} ${webDavUsername} ${webDavPassword}"

        # Append the string to the configuration file
        echo "${configEntry}" | sudo tee -a "${configFile}" > /dev/null

        logMessage "Entry for WebDav added to configuration file (${configFile})." "INFO"

    fi

    # Check if the URL already exists in /etc/fstab
    if grep -q "^${url}" /etc/fstab; then

        logMessage "The URL '${url}' already exists in the fstab (/etc/fstab)." "INFO"

    else

        # Create the fstab entry string
        fstabEntry="${url} ${personalCloudPath} davfs user,rw,auto,uid=1000,gid=1000,file_mode=0600,dir_mode=0700 0 0"

        # Append the string to the fstab
        echo "${fstabEntry}" | sudo tee -a /etc/fstab > /dev/null

        logMessage "Entry for WebDav mount added to fstab (/etc/fstab)." "INFO"

        # Reload the systemd manager configuration
        sudo systemctl daemon-reload

        # Mount the cloud storage directory
        sudo mount "${personalCloudPath}"

    fi

else

    # Skip the operation
    logMessage "No changes were made to WebDav client configuration." "INFO"

fi

# endregion

### WORK CLOUD DIRECTORY

logMessage "Setting up Work cloud directory..." "INFO"

# ===================================
# === INSTALL CIFS SHARE UTILS ======
# ===================================
# region

# Check and install CIFS utilities (used for mounting SMB shares)
if ! command -v mount.cifs &> /dev/null; then

    logMessage "Installing CIFS Share Utilities (cifs-utils)..." "INFO"

    # Installing cifs-utils (run non-interactively)
    run sudo apt-get install -y cifs-utils

    logMessage "CIFS Share Utilities (cifs-utils) installed successfully." "DEBUG"

else

    logMessage "CIFS Share Utilities (cifs-utils) is already installed." "DEBUG"

fi

# endregion

# ===================================
# === WINDOWS SHARE MOUNT POINT =====
# ===================================
# region

# Check if '/mnt/c' is already mounted
if mountpoint -q /mnt/c; then

    logMessage "There is already a mountpoint on '/mnt/c'. Skipping mount step." "DEBUG"

else

    # Prompt the user for the Windows share credentials
    read -p "Press 'Enter' to set up a mountpoint for a Windows share (C$), or 'N/n' to skip: " 2>&1 confirm

    # If user hits Enter, set confirm to "y"
    if [[ -z "$confirm" ]]; then
        confirm="y"
    fi

    # Check the user's response
    if [[ "$confirm" =~ ^[Yy]$ ]]; then

        while [[ -z "$smbHost" || -z "$smbUsername" || -z "$smbPassword" || "$retry" =~ ^[Rr]$ ]]; do

            echo "To mount the Windows share, you need to provide the following information:"

            # Proceed with prompting the user for the host and credential information
            read -p "Hostname or IP address of the Windows host: " 2>&1 smbHost
            read -p "Windows username: " 2>&1 smbUsername
            read -s -p "Windows password: " 2>&1 smbPassword

            echo # Move to a new line after the password input

            echo "The following will be used to mount the Windows share:"
            echo "Host:     ${smbHost}"
            echo "Username: ${smbUsername}"
            echo "Password: ********"
            read -p "Press 'Enter' to continue or 'R/r' to re-enter the information: " 2>&1 retry

            # If user hits Enter or types N/n, break the loop
            if [[ -z "$retry" || "$retry" =~ ^[Nn]$ ]]; then
                break
            fi

        done

        # Save SMB credentials securely for reuse
        logMessage "Saving Windows share credentials to '/etc/smb-credentials'..." "INFO"

        # Save credentials to file
        if ! sudo bash -c "cat > /etc/smb-credentials" <<EOF
username=${smbUsername}
password=${smbPassword}
EOF
        then

            logMessage "Failed to SMB save credentials for Windows share." "ERROR"

            exit 1

        fi

        # Set credentials file permissions
        sudo chmod 600 /etc/smb-credentials

        logMessage "Windows share credentials saved." "DEBUG"

        # Create new directory for the C$ share mount point
        if ! sudo mkdir -p /mnt/c; then

            logMessage "Failed to create mount point for Windows share to '/mnt/c'" "ERROR"

            exit 1

        fi

        logMessage "Mounting Windows share ('//${smbHost}/C\$') to mount point ('/mnt/c')..." "INFO"

        # Attempt to mount the Windows C$ share
        if ! sudo mount -t cifs //${smbHost}/c\$ /mnt/c \
            -o credentials=/etc/smb-credentials,uid=$(id -u),gid=$(id -g),vers=3.0,mfsymlinks; then

            logMessage "Mounting Windows share failed. Please check credentials, network, or permissions." "ERROR"

            exit 1

        fi

        logMessage "Windows share mounted successfully." "DEBUG"

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

            logMessage "Entry successfully added to fstab (/etc/fstab)." "DEBUG"

        fi

    else

        # Skip the operation
        logMessage "No new Windows share mountpoint configured."

        # Set flag to indicate no Windows share mount point was created or exists
        noWindowsShareMountPoint=true

    fi

fi

# endregion

# ===================================
# === SYMLINK TO CLOUD DIRECTORY ====
# ===================================
# region

if [[ "${noWindowsShareMountPoint}" == "true" ]]; then

    # Skip symlink creation
    logMessage "Skipping symlink creation for Windows share directory as no mount point exists." "WARNING"

else

    logMessage "Checking for Windows symlink ('C:/Cloud/work') in '/mnt/c/Cloud'..." "INFO"

    # Check for existence of a symlink specifically named '/mnt/c/Cloud' in mount point
    if [[ ! -L "/mnt/c/Cloud/work" ]]; then

        logMessage "Symlink '/mnt/c/Cloud/work' not found. Aborting..." "ERROR"

        echo "Expected symlink folder 'C:/Cloud/work' was not found on the Windows host's C drive."

    else

        logMessage "Found Windows symlink ('C:/Cloud/work') in '/mnt/c/Cloud'." "DEBUG"

        # Read the target of the symlink
        winTarget=$(readlink "/mnt/c/Cloud/work")

        logMessage "Original Windows symlink target: '${winTarget}'" "DEBUG"

        # Convert Windows-style path (/??/C:/Users/...) → Linux-style (/mnt/c/Users/...)
        linuxTarget=$(echo "${winTarget}" | sed -E 's|^/..?/([A-Za-z]):|/mnt/\L\1|')

        logMessage "Converted Windows symlink to Linux target: '${linuxTarget}'" "DEBUG"

        # Check if the Linux symlink target already exists
        if [[ -e "${workCloudPath}" || -L "${workCloudPath}" ]]; then

            logMessage "Symlink '${workCloudPath} → ${linuxTarget}' already exists." "INFO"

        else

            # Create the Linux-native symlink pointing to the resolved Windows share path
            if ! ln -s "${linuxTarget}" "${workCloudPath}"; then

                logMessage "Failed to create symlink '${workCloudPath} → ${linuxTarget}'" "ERROR"

            fi

            logMessage "Symlink created: '${workCloudPath} → ${linuxTarget}'" "INFO"

        fi

    fi

fi

# endregion

# ===================================
# === COPY PERSONAL CLOUD TO HOST ===
# ===================================
# region

if [[ "${noWindowsShareMountPoint}" == "true" ]]; then

    # Skip symlink creation
    logMessage "Skipping copying of personal cloud files to Windows host as no mount point exists." "WARNING"

else

    # Path on Windows host for personal cloud sync
    personalCloudPathOnWindowsHost="/mnt/c/Cloud/personal/"

    logMessage "Setting up personal cloud sync to Windows host..." "INFO"

    # Only run this if the personal cloud directory exists on Windows share
    if [ -d "${personalCloudPathOnWindowsHost}" ]; then

        # Define the sync command without log redirection for immediate execution
        syncCommand="find \"${personalCloudPath}\" -mindepth 1 \\( -name 'lost+found' -prune \\) -o -print | grep -q . && rsync -a --delete --exclude='lost+found' \"${personalCloudPath}/\" \"${personalCloudPathOnWindowsHost}\""

        logMessage "Sync command: ${syncCommand}" "DEBUG"

        # Initial sync to ensure everything is up-to-date (no log redirection)
        eval "${syncCommand}"

        # Define the cron job command with log redirection
        cronJob="0 * * * * ${syncCommand} >> \"$HOME/logs/rsync.log\" 2>&1"

        # Check if the cron job already exists
        if crontab -l 2>/dev/null | grep -Fq "${cronJob}"; then

            logMessage "Cron job already exists: ${cronJob}" "DEBUG"

        else

            logMessage "Adding cron job to run personal cloud content sync to host every hour..." "INFO"

            # Add the cron job to the user's crontab
            ( crontab -l 2>/dev/null; echo "${cronJob}" ) | crontab -

        fi

    else

        logMessage "Personal cloud directory location does not exist on Windows share. Skipping personal cloud sync and cron job setup." "WARNING"

    fi

fi

# endregion

exit 0
