#!/bin/bash
# Ubuntu 25.04 Desktop Setup Script
# This script is intended to run on a freshly installed Ubuntu 25.04 server
# It installs the desktop environment and xRDP for remote desktop access
#
# WARNING: This script enables remote desktop access which may have security implications
# Make sure to use strong passwords and consider firewall rules
#
# Example usage:
#   curl -sSL bit.ly/ubuntu2504desktop -O
#   bash ubuntu2504desktop

echo "You are logged in as: $USER"
echo .

# Check if running in non-interactive mode (like when piped from curl)
if [ ! -t 0 ]; then
    echo "ERROR: This script must be run interactively to set the user password."
    echo "Please download and execute the script in two steps:"
    echo "  curl -sSL bit.ly/ubuntu2504desktop -O"
    echo "  bash ubuntu2504desktop"
    exit 1
fi

echo "On cloud installations, no password is assigned to the default user. Resetting it now."
echo .
echo "WARNING: Remote desktop access will be enabled, which may expose this system to unauthorized access attempts from the internet."
echo .
sudo passwd $USER
echo .
echo .

# Update package lists and upgrade existing packages
echo "Updating package lists and upgrading existing packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install tasksel (Task Select) - a tool for installing predefined software bundles
# echo "Installing tasksel for software bundle management..."
sudo apt install tasksel -y

# Install Ubuntu Desktop environment using tasksel
# This installs the full GNOME desktop environment with all standard applications
echo "Installing Ubuntu Desktop environment (this may take a while)..."
#sudo apt install ubuntu-desktop ubuntu-wallpapers ubuntu-session gnome-shell-extension-ubuntu-dock -y
sudo tasksel install gnome-desktop
sudo apt install ubuntu-wallpapers ubuntu-session gnome-shell-extension-ubuntu-dock -y

# Install Snap Store (Ubuntu Software Center) from the edge channel
# This provides a GUI for installing additional software
echo "Installing Snap Store for software management..."
sudo snap install snap-store --edge

# Create a script to configure GNOME desktop settings in user's home directory
cat > ~/configure-gnome.sh << 'EOF'
#!/bin/bash

# Display a message to the user about potential issues in the first 5 minutes
zenity --info --title="System Setup" --text="The system may experience some issues in the first 5 minutes when you initially login over RDP after a system restart. Applications may not launch, and the desktop environment may not be responsive. This is normal and will resolve automatically." --width=400 &

# Try to configure GNOME settings with retry logic
for attempt in 1 2; do
    echo "Attempt $attempt: Configuring GNOME settings..."

    # Enable Ubuntu dock extension
    gnome-extensions enable ubuntu-dock@ubuntu.com

    # Configure dock settings
    gsettings set org.gnome.shell.extensions.dash-to-dock extend-height true
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide false
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position LEFT

    # Set favorite applications
    gsettings set org.gnome.shell favorite-apps "['firefox_firefox.desktop', 'libreoffice-writer.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.gnome.Terminal.desktop']"

    # Set backgrounds (default Ubuntu wallpaper)
    gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/warty-final-ubuntu.png'
    gsettings set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/ubuntu-wallpaper-d.png'
    gsettings set org.gnome.desktop.background primary-color '#2c001e'
    gsettings set org.gnome.desktop.background secondary-color '#2c001e'
    gsettings set org.gnome.desktop.screensaver picture-uri 'file:///usr/share/backgrounds/warty-final-ubuntu.png'
    gsettings set org.gnome.desktop.screensaver primary-color '#2c001e'
    gsettings set org.gnome.desktop.screensaver secondary-color '#2c001e'
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'default'

    # If this is the first attempt, wait 4 minutes before trying again
    if [ $attempt -eq 1 ]; then
        echo "Waiting 4 minutes before second attempt..."
        sleep 240
    fi
done
EOF

# Make the script executable
chmod +x ~/configure-gnome.sh

# Add the script to autostart for GNOME session
mkdir -vp ~/.config/autostart
cat > ~/.config/autostart/configure-gnome.desktop << EOF
[Desktop Entry]
Type=Application
Name=Configure GNOME
Exec=/home/$USER/configure-gnome.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# Install xRDP (Remote Desktop Protocol server)
# This allows clients to connect to the Ubuntu desktop
echo "Installing xRDP for remote desktop access..."
sudo apt-get install -y xrdp



# completion message and reboot prompt
echo .
echo .
echo "Setup complete! You need to restart the system for all changes to take effect."
echo .
echo "You can now connect via RDP using the password you set."
echo .
echo "Note: This desktop setup is not yet supported by the Ubuntu Desktop team,"
echo "      and there are some known issues. For example, you may see error"
echo "      messages about processes crashing or being killed. However the"
echo "      environment is stable enough for what we need."
echo .
echo "For some reason, on the first RDP connection after a reboot, the desktop"
echo "environment needs about 4-5 minutes to be fully functional. When you first"
echo "connect, you may see error messages about processes crashing or being killed,"
echo "and apps may not launch. This will go away after a few minutes."
echo .

echo "Press Enter to reboot the system, or Ctrl+C to cancel..."
read -r
sudo reboot