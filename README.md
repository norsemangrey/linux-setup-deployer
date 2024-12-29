# linux-setup-deployer

## Overview

The `linux-setup-deployer` repository provides automation scripts to streamline the setup of a Linux environment with minimal effort after a fresh install, including tools installation, SSH server configuration, and integration with a `dotfiles` repository. The aim is to ensure that the system is ready for productivity by installing essential software and applying custom configurations. While the script is designed to be robust, it is initial and can be extended with additional tools and packages as needed.

## Features

- Installs and configures essential tools, including:

    | Tool            | Purpose                                     |
    |-----------------|---------------------------------------------|
    | ZSH             | Shell customization                        |
    | Oh-My-Posh      | Cross-platform prompt theme engine         |
    | LSDeluxe (lsd)  | Improved directory listings                |
    | Fastfetch       | System information fetch tool              |
    | JQuery (jq)     | JSON parsing utility                       |

  These tools are selected based on personal preferences and compatibility with both Linux and Windows environments. They might not suit everyone, so feel free to modify the script.
- Sets up and secures an SSH server with key-based authentication (requires copying the public key to the server).
- Integrates with a `dotfiles` repository to link configuration files for installed applications (refer to the `dotfiles` repository for additional documentation).
- Some UFW configuration
- Ensures the system is updated and ready for use.
- Supports debug and verbose modes for detailed logging and output.

## Requirements and Target System

- Tested on Ubuntu Server and Ubuntu WSL (Windows Subsystem for Linux).
- May work on most Debian-based distributions (not guaranteed).
- Sudo privileges for installing software and configuring the system.
- An active internet connection.

## Usage/Instructions

1. **Clone the Repository**

   ```bash
   git clone --recurse-submodules https://github.com/your-repo/linux-setup-deployer.git
   cd linux-setup-deployer
   ```

   - To update the repository, use:
     ```bash
     git pull && git submodule update --init --recursive
     ```

2. **Run the Main Setup Script**

   ```bash
   ./linux-setup-and-config.sh [OPTIONS]
   ```

   Options:

   - `-d, --debug`: Enable debug output messages.
   - `-v, --verbose`: Show standard output from commands (default suppresses output).
   - `-h, --help`: Display usage information.
   - The user might be prompted for their sudo password several times during the execution.

3. **SSH Setup (Optional)**
   If you need to configure an SSH server with key-based authentication:

   ```bash
   ./ssh-setup-and-config.sh [OPTIONS]
   ```

   Note: Ensure you have a way to copy the public key to the server if you want to use this feature.

4. **Dotfiles Integration**
   The main setup script clones and executes a script from a `dotfiles` repository:

   - URL: [Dotfiles Repo](`https://github.com/norsemangrey/.dotfiles.git`)
   - Script: `install-linux.sh`

   Ensure the `dotfiles` repository has appropriate configurations and an executable installation script.

## Script Details

### linux-setup-and-config.sh

This script:

- Updates and upgrades the system.
- Installs and configures various apps and tools.
- Clones the `dotfiles` repository and executes its installation script.
- Supports logging and error handling through external utilities.

### ssh-setup-and-config.sh

This script:

- Installs and configures the OpenSSH server.
- Sets up firewall rules for SSH (UFW).
- Enables key-based authentication for the current user.
- Disables root login and password-based authentication.
- Guides the user through adding their SSH keys.

## Notes

- Run scripts as a non-root user with sudo privileges.
- Ensure all external utilities (`logging-and-output-function.sh`, `error-handling-function.sh`, `clone-and-execute-script.sh`) are available in the `utils` directory.
- The repository includes submodules for helper functions like logging and error handling, which are integral to the scripts.
- Modify the scripts as needed for compatibility with non-Ubuntu Debian-based systems.

For additional help or troubleshooting, open an issue in the repository or consult the script usage instructions with the `-h` flag.

