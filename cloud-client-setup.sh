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

# DEFAULT VALUES

# Get the username from the $USER environment variable
username="${USER}"

logMessage "Setting up Personal cloud directory..." "INFO"

# Set the path to the cloud storage directory
[[ -n "$localCloudPath" ]] || localCloudPath="${HOME}/cloud/personal"
[[ -n "$localFromSmbCloudPath" ]] || localFromSmbCloudPath="${HOME}/cloud/work"
[[ -n "$smbCloudPath" ]] || smbCloudPath="Cloud/work"
[[ -n "$smbFromLocalCloudPath" ]] || smbFromLocalCloudPath="Cloud/personal"

# endregion


# ===================================
# === PERSONAL CLOUD DIRECTORY ======
# ===================================
# region

# Set flag to skip cloud sync
connectPersonalCloud=false

# Ask the user if they want to connect to a cloud directory
[[ -n "$connectCloud" ]] || read -p "Do you want to connect to a personal cloud directory? [Y/n]: " 2>&1 connectCloud

# Check the user's response (default to 'yes' on Enter)
if [[ -z "$connectCloud" || "$connectCloud" =~ ^[Yy]$ ]]; then

    # Check if the local cloud directory already exists
    if [[ -d "${localCloudPath}" ]]; then

        # Check if directory has any content (excluding . and ..)
        if [[ $(ls -A "${localCloudPath}") ]]; then

            logMessage "The local cloud directory is not empty (${localCloudPath})." "WARNING"

            # Prompt the user to confirm continuation
            [[ -n "$continueWithContent" ]] || read -p "Do you want to continue and potentially overwrite existing content? [Y/n]: " 2>&1 continueWithContent

            # Check the user's response (default to 'yes' on Enter)
            if [[ -z "$continueWithContent" || "$continueWithContent" =~ ^[Yy]$ ]]; then

                # Set flag to indicate cloud sync should be performed
                connectPersonalCloud=true

            fi

        fi

    else

        # Create the directory if it does not exist
        mkdir -p "${localCloudPath}"

        logMessage "Created local cloud directory at '${localCloudPath}'." "DEBUG"

        # Set flag to indicate cloud sync should be performed
        connectPersonalCloud=true

    fi

fi

# Set flag to skip cloud sync
if [[ "$connectPersonalCloud" == "false" ]]; then

    logMessage "Personal cloud directory setup will not be performed." "DEBUG"

else

    logMessage "Preparing for setup of personal cloud directory..." "INFO"

    # Prompt the user to confirm continuation
    [[ -n "$connectMethod" ]] || read -p "Do you want to [m]ount using WebDav or [s]ync using Nextcloud CLI? [m/S]: " 2>&1 connectMethod

fi

# endregion

### SYNC CLOUD DIRECTORY

if [[ "$connectPersonalCloud" == "true" && (-z "$connectMethod" || "$connectMethod" =~ ^[Ss]$) ]]; then

    logMessage "Starting NextCloud client setup and cloud directory sync..." "INFO"

    # ===================================
    # === INSTALL NEXTCLOUD CLI =========
    # ===================================
    # region

    # Check and install Nextcloud CLI
    if ! command -v nextcloudcmd &> /dev/null; then

        logMessage "Installing Nextcloud CLI..." "INFO"

        # Add Nextcloud repository
        run sudo add-apt-repository -y ppa:nextcloud-devs/client

        # Update package lists
        run sudo apt-get update

        # Installing Nextcloud CLI (run non-interactively)
        run sudo apt-get install -y nextcloud-client

        logMessage "Nextcloud CLI installed successfully." "DEBUG"

    else

        logMessage "Nextcloud CLI is already installed." "DEBUG"

    fi

    # endregion

    # ===================================
    # === CHECK CLOUD DIRECTORY =========
    # ===================================
    # region

    # Check if there is a .sync_*.db file in the root of the local cloud directory
    if [[ "${continueWithContent}" == "true" && ! $(ls "${localCloudPath}"/.sync_*.db 1> /dev/null 2>&1) ]]; then

        logMessage "The local directory has content but no sync file." "WARNING"

        # Prompt the user to confirm continuation
        read -p "Do you want to continue with two way sync and possible conflicts? [Y/n]: " 2>&1 continueSync

    else

        # Default to continue sync
        continueSync="y"

    fi

    # endregion

    # ===================================
    # === SYNC CLOUD DIRECTORY ==========
    # ===================================
    # region

    # Check the user's response
    if [[ -z "$continueSync" || "$continueSync" =~ ^[Yy]$ ]]; then

        logMessage "Configuring sync command..." "INFO"

        while [[ -z "$url" || "$retry" =~ ^[Rr]$ ]]; do

            echo "To sync the cloud directory, you need to provide the following information:"

            # Prompt for cloud credentials if not set in config
            [[ -n "$cloudAddress" ]] || read -p "Address (e.g., 'cloud.domain.com'): " 2>&1 cloudAddress
            [[ -n "$cloudUsername" ]] || read -p "Username: " 2>&1 cloudUsername
            if [[ -z "$cloudPassword" ]]; then
                read -s -p "Password: " 2>&1 cloudPassword
                echo # Move to a new line after the password input
            fi

            # Set the full URL
            url="https://${cloudAddress}"

            echo "The following details will be used to sync the cloud directory:"
            echo "URL:      ${url}"
            echo "Username: ${cloudUsername}"
            echo "Password: ********"
            read -p "Press 'Enter' to continue or 'R/r' to re-enter the information: " 2>&1 retry

            # If user hits Enter or types N/n, break the loop
            if [[ -z "$retry" || "$retry" =~ ^[Nn]$ ]]; then
                break
            fi

        done

        logMessage "Executing Nextcloud directory sync command..." "INFO"

        # Execute the Nextcloud sync command
        if ! nextcloudcmd --silent --user "${cloudUsername}" --password "${cloudPassword}" --path / "${localCloudPath}" "${url}" 2>&1; then

            logMessage "Nextcloud sync failed. Please check credentials, network, or permissions." "WARNING"

        else

            logMessage "Cloud directory successfully synced with local folder." "DEBUG"

            # Ensure the sync script is executable
            find "${localCloudPath}" -type f -name "nextcloud-sync.sh" -exec chmod +x {} \;

            # Save cloud password securely for reuse if 'pass' is installed
            if command -v pass &> /dev/null; then

                logMessage "Saving cloud password securely using 'pass'..." "INFO"

                # Insert or update the password in the pass store
                echo "${cloudPassword}" | pass insert -e nextcloud/"${cloudUsername}"

                logMessage "Cloud password saved to pass store under 'nextcloud/${cloudUsername}'." "DEBUG"

            else

                logMessage "The 'pass' application is not installed. Skipping secure password storage." "WARNING"

            fi

            # ===================================
            # === ENABLE NEXTCLOUD SYNC SERVICE =
            # ===================================
            # region

            # logMessage "Checking for Nextcloud Sync service files..." "INFO"

            # # Define service file paths
            # sourceServicePath="${localCloudPath}/nextcloud"
            # targetServicePath="${HOME}/.config/systemd/user"
            # serviceBaseName="nextcloud-sync"

            # # Check if all required service files exist
            # if [[ -f "${sourceServicePath}.service" && -f "${sourceServicePath}.timer" && -f "${sourceServicePath}.sh" ]]; then

            #     logMessage "Found Nextcloud Sync service files in cloud directory. Creating symlinks..." "INFO"

            #     # Create target directory if it doesn't exist
            #     mkdir -p "${targetServicePath}"

            #     # Create symlinks for each service file
            #     for extension in service timer sh; do

            #         sourceFile="${sourceServicePath}/${serviceBaseName}.${extension}"
            #         targetFile="${targetServicePath}/${serviceBaseName}.${extension}"

            #         # Remove existing file/symlink if it exists
            #         if [[ -e "${targetFile}" || -L "${targetFile}" ]]; then
            #             rm "${targetFile}"
            #         fi

            #         # Create the symlink
            #         if ln -s "${sourceFile}" "${targetFile}"; then
            #             logMessage "Created symlink: ${targetFile} -> ${sourceFile}" "DEBUG"
            #         else
            #             logMessage "Failed to create symlink for ${serviceBaseName}.${extension}" "WARNING"
            #         fi
            #     done

            #     # Make the script executable
            #     chmod +x "${serviceFiles}.sh"

            #     # Reload systemd user daemon to recognize new service files
            #     if systemctl --user daemon-reload; then

            #         logMessage "Systemd user daemon reloaded successfully." "DEBUG"

            #         # Enable and start the timer
            #         if systemctl --user enable nextcloud-sync.timer; then

            #             logMessage "Nextcloud sync timer enabled successfully." "DEBUG"

            #         else

            #             logMessage "Failed to enable Nextcloud Sync timer." "WARNING"

            #         fi

            #     else

            #         logMessage "Failed to reload systemd user daemon." "WARNING"

            #     fi

            # else

            #     logMessage "Nextcloud Sync service files not found in '${HOME}/.config/systemd/user/'. Skipping service setup." "WARNING"

            # fi

            # endregion

        fi

    else

        # Skip the operation
        logMessage "Skipping cloud directory sync..." "INFO"

    fi

    # endregion

fi

### MOUNT CLOUD DIRECTORY

if [[ "$connectPersonalCloud" == "true" && ("$connectMethod" =~ ^[Mm]$) ]]; then

    logMessage "Starting WebDav client setup and cloud directory mount..." "INFO"

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

    # ===================================
    # === CHECK WEBDAV CONFIGURATION ====
    # ===================================
    # region

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

            # Prompt for WebDav credentials if not set in config
            [[ -n "$cloudAddress" ]] || read -p "Address (e.g., 'cloud.domain.com'): " 2>&1 cloudAddress
            [[ -n "$cloudUsername" ]] || read -p "Username: " 2>&1 cloudUsername
            if [[ -z "$cloudPassword" ]]; then
                read -s -p "Password: " 2>&1 cloudPassword
                echo # Move to a new line after the password input
            fi

            # Set the full WebDav URL
            url="https://${cloudAddress}/remote.php/dav/files/${cloudUsername}"

            echo "The following entry will be added to the WebDav client configuration:"
            echo "URL:      ${url}"
            echo "Username: ${cloudUsername}"
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
            configEntry="${url} ${cloudUsername} ${cloudPassword}"

            # Append the string to the configuration file
            echo "${configEntry}" | sudo tee -a "${configFile}" > /dev/null

            logMessage "Entry for WebDav added to configuration file (${configFile})." "INFO"

        fi

        # Check if the URL already exists in /etc/fstab
        if grep -q "^${url}" /etc/fstab; then

            logMessage "The URL '${url}' already exists in the fstab (/etc/fstab)." "INFO"

        else

            # Create the fstab entry string
            fstabEntry="${url} ${localCloudPath} davfs user,rw,auto,uid=1000,gid=1000,file_mode=0600,dir_mode=0700 0 0"

            # Append the string to the fstab
            echo "${fstabEntry}" | sudo tee -a /etc/fstab > /dev/null

            logMessage "Entry for WebDav mount added to fstab (/etc/fstab)." "INFO"

            # Reload the systemd manager configuration
            sudo systemctl daemon-reload

            # Mount the cloud storage directory
            sudo mount "${localCloudPath}"

        fi

    else

        # Skip the operation
        logMessage "No changes were made to WebDav client configuration." "INFO"

    fi

    # endregion

fi

# ===================================
# === HOST DIRECTORY SETUP ==========
# ===================================
# region

# Set flag to skip cloud connection
connectSmbShare=false

# Set default mount point if not specified
[[ -n "$smbMountPoint" ]] || smbMountPoint="/mnt/smb"

# Check if the mount point is already mounted
if mountpoint -q "${smbMountPoint}"; then

    logMessage "There is already a mountpoint on '${smbMountPoint}'. Skipping SMB mount step." "DEBUG"

else

    # Prompt the user for SMB share setup
    [[ -n "$connectSmb" ]] || read -p "Do you want to set up a mountpoint for an SMB/CIFS share? [Y/n]: " 2>&1 connectSmb

    # Check the user's response
    if [[ -z "$connectSmb" || "$connectSmb" =~ ^[Yy]$ ]]; then

        # Set flag to indicate cloud connection should be performed
        connectSmbShare=true

    else

        # Skip the operation
        logMessage "No new SMB share mountpoint configured."

        # Set flag to indicate no SMB share mount point was created or exists
        noSmbShareMountPoint=true

    fi

fi

# endregion

# Check the user's response
if [[ "$connectSmbShare" == "true" ]]; then

    logMessage "Setting up host share directory..." "INFO"

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
    # === SMB SHARE MOUNT POINT =========
    # ===================================
    # region

    # Prompt the user for the SMB share credentials
    while [[ -z "$smbHost" || -z "$smbUsername" || -z "$smbPassword" || "$retry" =~ ^[Rr]$ ]]; do

        echo "To mount the SMB share, you need to provide the following information:"

        # Prompt for SMB credentials if not set in config
        [[ -n "$smbHost" ]] || read -p "Hostname or IP address of the SMB server: " 2>&1 smbHost
        [[ -n "$smbShare" ]] || read -p "SMB share name (e.g., 'c$', 'shared', 'documents'): " 2>&1 smbShare
        [[ -n "$smbMountPoint" ]] || read -p "Local mount point [/mnt/smb]: " 2>&1 smbMountPoint
        [[ -n "$smbUsername" ]] || read -p "SMB username: " 2>&1 smbUsername
        if [[ -z "$smbPassword" ]]; then
            read -s -p "SMB password: " 2>&1 smbPassword
            echo # Move to a new line after the password input
        fi

        echo "The following will be used to mount the SMB share:"
        echo "Host:        ${smbHost}"
        echo "Share:       ${smbShare}"
        echo "Mount point: ${smbMountPoint}"
        echo "Username:    ${smbUsername}"
        echo "Password:    ********"
        read -p "Press 'Enter' to continue or 'R/r' to re-enter the information: " 2>&1 retry

        # If user hits Enter or types N/n, break the loop
        if [[ -z "$retry" || "$retry" =~ ^[Nn]$ ]]; then
            break
        fi

    done

    # Save SMB credentials securely for reuse
    logMessage "Saving SMB share credentials to '/etc/smb-credentials'..." "INFO"

    # Save credentials to file
    if ! sudo bash -c "cat > /etc/smb-credentials" <<EOF
username=${smbUsername}
password=${smbPassword}
EOF
    then

        logMessage "Failed to save SMB credentials for share." "ERROR"

        exit 1

    fi

    # Set credentials file permissions
    sudo chmod 600 /etc/smb-credentials

    logMessage "SMB share credentials saved." "DEBUG"

    # Create new directory for the SMB share mount point
    if ! sudo mkdir -p "${smbMountPoint}"; then

        logMessage "Failed to create mount point for SMB share to '${smbMountPoint}'" "ERROR"

        exit 1

    fi

    logMessage "Mounting SMB share ('//${smbHost}/${smbShare}') to mount point ('${smbMountPoint}')..." "INFO"

    # Attempt to mount the SMB share
    if ! sudo mount -t cifs "//${smbHost}/${smbShare}" "${smbMountPoint}" \
        -o credentials=/etc/smb-credentials,uid=$(id -u),gid=$(id -g),vers=3.0,mfsymlinks; then

        logMessage "Mounting SMB share failed. Please check credentials, network, or permissions." "ERROR"

        exit 1

    fi

    logMessage "SMB share mounted successfully." "DEBUG"

    # Add fstab line to ensure mount persists across reboots

    # Set the SMB share path
    smbSharePath="//${smbHost}/${smbShare}"

    # Check if the entry already exists in /etc/fstab
    if grep -q "^${smbSharePath}" /etc/fstab; then

        logMessage "The SMB share '${smbSharePath}' already exists in the fstab (/etc/fstab)." "INFO"

    else

        # Create the fstab entry string
        fstabEntry="${smbSharePath} ${smbMountPoint} cifs credentials=/etc/smb-credentials,uid=$(id -u),gid=$(id -g),vers=3.0,mfsymlinks 0 0"

        # Append the string to the fstab
        echo "${fstabEntry}" | sudo tee -a /etc/fstab > /dev/null

        logMessage "Entry successfully added to fstab (/etc/fstab)." "DEBUG"

    fi

    # endregion

fi

# ===================================
# === SYMLINK TO HOST CLOUD FOLDER ==
# ===================================
# region

if [[ "${noSmbShareMountPoint}" == "true" ]]; then

    # Skip symlink creation
    logMessage "Skipping symlink creation for SMB share directory as no mount point exists." "WARNING"

else

    logMessage "Checking for symlink ('${smbShare}/${smbCloudPath}') in '${smbMountPoint}/Cloud'..." "INFO"

    # Check for existence of a symlink specifically named 'Cloud' in mount point
    if [[ ! -L "${smbMountPoint}/${smbCloudPath}" ]]; then

        logMessage "Symlink '${smbMountPoint}/${smbCloudPath}' not found. Aborting..." "ERROR"

        echo "Expected symlink folder '${smbCloudPath}' was not found on the remote host's share."

    else

        logMessage "Found symlink ('${smbShare}/${smbCloudPath}') in '${smbMountPoint}/Cloud'." "DEBUG"

        # Read the target of the symlink
        remoteTarget=$(readlink "${smbMountPoint}/${smbCloudPath}")

        logMessage "Original symlink target: '${remoteTarget}'" "DEBUG"

        # Convert any Windows-style path references to Linux-style
        linuxTarget=$(echo "${remoteTarget}" | sed -E 's|^/..?/([A-Za-z]):|/mnt/\L\1|')

        logMessage "Converted symlink to Linux target: '${linuxTarget}'" "DEBUG"

        # Check if the Linux symlink target already exists
        if [[ -e "${localFromSmbCloudPath}" || -L "${localFromSmbCloudPath}" ]]; then

            logMessage "Symlink '${localFromSmbCloudPath} → ${linuxTarget}' already exists." "INFO"

        else

            # Create the Linux-native symlink pointing to the resolved share path
            if ! ln -s "${linuxTarget}" "${localFromSmbCloudPath}"; then

                logMessage "Failed to create symlink '${localFromSmbCloudPath} → ${linuxTarget}'" "ERROR"

            fi

            logMessage "Symlink created: '${localFromSmbCloudPath} → ${linuxTarget}'" "INFO"

        fi

    fi

fi

# endregion

# ===================================
# === COPY PERSONAL CLOUD TO HOST ===
# ===================================
# region

if [[ "${noSmbShareMountPoint}" == "true" ]]; then

    # Skip symlink creation
    logMessage "Skipping copying of local cloud files to remote host as no mount point exists." "WARNING"

elif [[ ! $(ls -A "${localCloudPath}") ]]; then

    logMessage "No files found in local cloud directory ('${localCloudPath}'). Skipping copy to remote host." "INFO"

else

    # Path on remote host for local cloud sync
    localCloudPathOnRemoteHost="${smbMountPoint}/${smbFromLocalCloudPath}/"

    logMessage "Setting up local cloud sync to remote host..." "INFO"

    # Only run this if the local cloud directory exists on remote share
    if [ -d "${localCloudPathOnRemoteHost}" ]; then

        # Define the sync command without log redirection for immediate execution
        syncCommand="find \"${localCloudPath}\" -mindepth 1 \\( -name 'lost+found' -prune \\) -o -print | grep -q . && rsync -a --delete --exclude='lost+found' \"${localCloudPath}/\" \"${localCloudPathOnRemoteHost}\""

        logMessage "Sync command: ${syncCommand}" "DEBUG"

        # Initial sync to ensure everything is up-to-date (no log redirection)
        eval "${syncCommand}"

        # Define the cron job command with log redirection
        cronJob="0 * * * * ${syncCommand} >> \"$HOME/logs/rsync.log\" 2>&1"

        # Check if the cron job already exists
        if crontab -l 2>/dev/null | grep -Fq "${cronJob}"; then

            logMessage "Cron job already exists: ${cronJob}" "DEBUG"

        else

            logMessage "Adding cron job to run local cloud content sync to host every hour..." "INFO"

            # Add the cron job to the user's crontab
            ( crontab -l 2>/dev/null; echo "${cronJob}" ) | crontab -

        fi

    else

        logMessage "Local cloud directory location does not exist on remote share. Skipping local cloud sync and cron job setup." "WARNING"

    fi

fi

# endregion

exit 0
