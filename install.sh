#!/bin/bash

# Exit if any command fails
set -e

# Check if the system is running under WSL
is_wsl() {
    # Check /proc/version for WSL-specific terms
    if grep -qEi "microsoft.*(subsystem|standard)" /proc/version; then
        return 0
    fi

    # Check if the WSL environment variable exists
    if [ -n "$(grep -i 'Microsoft' /proc/sys/kernel/osrelease 2>/dev/null)" ]; then
        return 0
    fi

    return 1
}

install_firacode_nerd_font() {
    echo "Installing FiraCode Nerd Font..."

    # Create fonts directory if it doesn't exist
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"

    # Download FiraCode Nerd Font
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"
    FONT_ZIP="/tmp/FiraCode.zip"

    echo "Downloading FiraCode Nerd Font..."
    wget -qO "$FONT_ZIP" "$FONT_URL"

    if [ $? -ne 0 ]; then
        echo "Failed to download FiraCode Nerd Font."
        return 1
    fi

    # Extract the font into the fonts directory
    echo "Extracting font files..."
    unzip -o "$FONT_ZIP" -d "$FONT_DIR"

    # Remove the downloaded zip file
    rm "$FONT_ZIP"

    # Refresh font cache
    echo "Refreshing font cache..."
    fc-cache -f "$FONT_DIR"

    echo "FiraCode Nerd Font installed successfully."
}

# Check and install Zsh
if ! command -v zsh &> /dev/null; then
    echo "Installing Zsh..."
    sudo apt update
    sudo apt install -y zsh
    echo "Zsh installed successfully."
else
    echo "Zsh is already installed."
fi

# Check and install Oh-My-Posh
if ! command -v oh-my-posh &> /dev/null; then
    echo "Installing Oh-My-Posh..."
    sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
    sudo chmod +x /usr/local/bin/oh-my-posh
    echo "Oh-My-Posh installed successfully."
else
    echo "Oh-My-Posh is already installed."
fi

# Check and install LSDeluxe (lsd)
if ! command -v lsd &> /dev/null; then
    echo "Installing LSDeluxe (lsd)..."
    sudo apt install -y lsd
    echo "LSDeluxe installed successfully."
else
    echo "LSDeluxe is already installed."
fi

# Check and install fastfetch
if ! command -v fastfetch &> /dev/null; then
    echo "Installing fastfetch..."
    sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
    sudo apt update
    sudo apt install -y fastfetch
    echo "Fastfetch installed successfully."
else
    echo "Fastfetch is already installed."
fi

# Install Nerd Fonts if not running on WSL
# if ! is_wsl; then
#     echo "Installing Nerd Fonts..."
#     install_firacode_nerd_font()
# else
#     echo "This is a WSL environment, skipping Nerd Fonts installation."
# fi

install_firacode_nerd_font()

# Set Zsh as the default shell if it's not already
if [[ "$SHELL" != "$(which zsh)" ]]; then
    echo "Setting Zsh as the default shell..."
    chsh -s "$(which zsh)"
    echo "Zsh is now the default shell. Please log out and log back in for changes to take effect."
else
    echo "Zsh is already the default shell."
fi

echo "All requested applications are installed and up to date!"