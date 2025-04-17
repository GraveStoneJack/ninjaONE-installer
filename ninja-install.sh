#!/bin/bash

USER_HOME=$(eval echo ~$USER)

# Ninja-Remote Installation Script for Hyprland
# This script installs Ninja-Remote using a locally downloaded executable

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Log file
LOG_FILE="/tmp/ninja-remote-install.log"

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

# Function to log errors
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

# Function to log warnings
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$LOG_FILE"
}

# Cleanup function
cleanup() {
    log_warning "An error occurred. Cleaning up..."
    # Don't remove the entire .wine64 directory as it might contain other applications
    # Instead, just remove the temporary installer
    if [ -f "$USER_HOME/.wine64/drive_c/temp/ncinstaller.exe" ]; then
        rm -f "$USER_HOME/.wine64/drive_c/temp/ncinstaller.exe"
    fi
}

# Add error handling at the beginning
trap cleanup ERR

# Function to check if a package is installed
package_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

# Function to install a package if not already installed
install_package() {
    if ! package_installed "$1"; then
        log "Installing $1..."
        sudo pacman -S --noconfirm "$1" >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            log_error "Failed to install $1. Check $LOG_FILE for details."
            return 1
        fi
        log "$1 installed successfully."
    else
        log "$1 is already installed."
    fi
    return 0
}

# Function to create a directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        log "Created directory: $1"
    fi
}

# Clear log file
> "$LOG_FILE"

log "Starting Ninja-Remote installation for Hyprland (64-bit)"
log "Installation log will be saved to $LOG_FILE"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please do not run this script as root. It will use sudo when necessary."
    exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    log_error "Sudo is not installed. Please install sudo first."
    exit 1
fi

if ! sudo -n true 2>/dev/null; then
    log_warning "Sudo requires a password. You may be prompted for your password during installation."
fi

# Check if Hyprland is installed
if ! command -v hyprctl &> /dev/null; then
    log_warning "Hyprland does not appear to be installed. This script is designed for Hyprland."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Installation aborted by user."
        exit 1
    fi
fi

# Get script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Check for local installer
if [ ! -f "$SCRIPT_DIR/ncinstaller.exe" ]; then
    log_error "Could not find ncinstaller.exe in the script directory. Please download the installer and place it there."
    exit 1
fi

# Install required packages
log "Installing required packages..."
PACKAGES=("wine" "wine-mono" "wine-gecko" "xdg-desktop-portal-hyprland" "xdg-utils")

for pkg in "${PACKAGES[@]}"; do
    install_package "$pkg" || exit 1
done

# Initialize Wine properly
log "Initializing Wine (64-bit)..."
# Create Wine directory if it doesn't exist
create_dir_if_not_exists "$USER_HOME/.wine64"

# Initialize Wine with explicit prefix (64-bit)
WINEPREFIX="$USER_HOME/.wine64" WINEARCH=win64 wine winecfg -v >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_error "Failed to initialize Wine. Check $LOG_FILE for details."
    exit 1
fi
log "Wine initialized successfully."

# Create directories
WINE_DIR="$USER_HOME/.wine64"
APPLICATIONS_DIR="$USER_HOME/.local/share/applications"
BIN_DIR="$USER_HOME/.local/bin"

create_dir_if_not_exists "$APPLICATIONS_DIR"
create_dir_if_not_exists "$BIN_DIR"

# Add ~/.local/bin to PATH if not already there
if [[ ":$PATH:" != *":$USER_HOME/.local/bin:"* ]]; then
    log "Adding $BIN_DIR to PATH"

    # Check which shell the user is using
    SHELL_NAME=$(basename "$SHELL")

    if [ "$SHELL_NAME" = "zsh" ]; then
        SHELL_RC="$USER_HOME/.zshrc"
    elif [ "$SHELL_NAME" = "bash" ]; then
        SHELL_RC="$USER_HOME/.bashrc"
    else
        log_warning "Unknown shell: $SHELL_NAME. You may need to manually add $BIN_DIR to your PATH."
        SHELL_RC=""
    fi

    if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
        if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$SHELL_RC"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
            log "Added $BIN_DIR to PATH in $SHELL_RC"
        fi
    fi

    export PATH="$USER_HOME/.local/bin:$PATH"
fi

# Create desktop entry file
DESKTOP_FILE="$APPLICATIONS_DIR/ninja-remote.desktop"
log "Creating desktop entry file: $DESKTOP_FILE"

cat > "$DESKTOP_FILE" << EOF
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=NinjaOne Remote
Exec=bash -c 'WINEPREFIX="$USER_HOME/.wine64" WINEARCH=win64 wine "$USER_HOME/.wine64/drive_c/Program Files/NinjaRemote/ncplayer.exe" "%u"'
Type=Application
Terminal=false
MimeType=x-scheme-handler/ninjarmm;
Name[en_US]=NinjaOne Remote
Icon=$USER_HOME/.wine64/drive_c/Program\ Files/NinjaRemote/ncplayer.exe
EOF

chmod +x "$DESKTOP_FILE"
log "Desktop entry file created successfully."

# Create launcher script for Hyprland
LAUNCHER_SCRIPT="$BIN_DIR/ninja-remote"
log "Creating launcher script for Hyprland: $LAUNCHER_SCRIPT"

cat > "$LAUNCHER_SCRIPT" << EOF
#!/bin/bash
WINEPREFIX="$USER_HOME/.wine64" WINEARCH=win64 wine "$USER_HOME/.wine64/drive_c/Program Files/NinjaRemote/ncplayer.exe"
EOF

chmod +x "$LAUNCHER_SCRIPT"
log "Launcher script created successfully."

# Install NinjaRemote using local installer
log "Installing NinjaRemote using local installer..."
# Copy installer to Wine drive
create_dir_if_not_exists "$USER_HOME/.wine64/drive_c/temp"
cp "$SCRIPT_DIR/ncinstaller.exe" "$USER_HOME/.wine64/drive_c/temp/"
chmod +x "$USER_HOME/.wine64/drive_c/temp/ncinstaller.exe"

# Run installer from Wine C: drive
WINEPREFIX="$USER_HOME/.wine64" WINEARCH=win64 wine "C:\\temp\\ncinstaller.exe" /S >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    # Try alternative installation method
    log "Trying alternative installation method..."
    WINEPREFIX="$USER_HOME/.wine64" WINEARCH=win64 wine cmd /c "start /wait C:\\temp\\ncinstaller.exe /S" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_error "Failed to install NinjaRemote. Check $LOG_FILE for details."
        exit 1
    fi
fi
log "NinjaRemote installed successfully."

# Configure Hyprland integration
log "Setting up Hyprland integration..."
HYPR_CONFIG="$USER_HOME/.config/hypr"

# Create Hyprland config directory if it doesn't exist
create_dir_if_not_exists "$HYPR_CONFIG"

# Create hyprland.conf if it doesn't exist
HYPR_CONFIG_FILE="$HYPR_CONFIG/hyprland.conf"
if [ ! -f "$HYPR_CONFIG_FILE" ]; then
    touch "$HYPR_CONFIG_FILE"
    log "Created new Hyprland config file: $HYPR_CONFIG_FILE"
fi

# Add NinjaRemote window rules if they don't exist
if ! grep -q "NinjaOne Remote|NinjaRemote" "$HYPR_CONFIG_FILE"; then
    log "Adding NinjaRemote window rules to Hyprland config..."
    cat >> "$HYPR_CONFIG_FILE" << EOF

# NinjaRemote window rules
windowrulev2 = float, title:^(NinjaOne Remote|NinjaRemote)$
windowrulev2 = center, title:^(NinjaOne Remote|NinjaRemote)$
windowrulev2 = monitor 0, title:^(NinjaOne Remote|NinjaRemote)$
EOF
    log "Hyprland configuration updated successfully."
else
    log "NinjaRemote window rules already exist in Hyprland config."
fi

# Configure Firefox for ninjarmm protocol
log "Configuring Firefox for ninjarmm protocol..."

# Find Firefox profile directory
FIREFOX_DIR="$USER_HOME/.mozilla/firefox"
if [ -d "$FIREFOX_DIR" ]; then
    PROFILE_DIR=$(find "$FIREFOX_DIR" -name "*.default*" -type d | head -n 1)

    if [ -z "$PROFILE_DIR" ]; then
        log_warning "Could not find Firefox profile directory. You'll need to configure Firefox manually."
    else
        # Create user.js file if it doesn't exist
        USER_JS="$PROFILE_DIR/user.js"
        if [ ! -f "$USER_JS" ]; then
            touch "$USER_JS"
        fi

        # Add ninjarmm protocol handler configuration
        if ! grep -q "network.protocol-handler.expose.ninjarmm" "$USER_JS"; then
            echo 'user_pref("network.protocol-handler.expose.ninjarmm", true);' >> "$USER_JS"
            log "Added ninjarmm protocol handler configuration to Firefox."
        else
            log "Firefox already configured for ninjarmm protocol."
        fi
    fi
else
    log_warning "Firefox profile directory not found. You'll need to configure Firefox manually."
fi

# Register protocol handler
log "Registering ninjarmm protocol handler..."
xdg-mime default ninja-remote.desktop x-scheme-handler/ninjarmm

# Clean up temporary files
if [ -f "$USER_HOME/.wine64/drive_c/temp/ncinstaller.exe" ]; then
    rm -f "$USER_HOME/.wine64/drive_c/temp/ncinstaller.exe"
    log "Cleaned up temporary installer file."
fi

# Provide instructions for User-Agent Switcher
log "Installation completed successfully!"
log "Please follow these additional steps:"
log "1. Install a User-Agent Switcher extension for Firefox"
log "2. Configure the User-Agent Switcher to use a Windows user agent when accessing NinjaONE websites"

# Instructions for Hyprland integration
log "For Hyprland integration:"
log "1. You can now launch NinjaOne Remote from rofi/dmenu by typing 'ninja-remote'"
log "2. To add a keyboard shortcut, add the following line to your hyprland.conf:"
log "   bind = SUPER, N, exec, ninja-remote"
log "3. Restart Hyprland for the configuration to take effect"

exit 0
