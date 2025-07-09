#!/bin/bash
# Ubuntu 25.04 Desktop Setup Script
#
# This script is intended to run on a freshly installed Ubuntu 25.04 server. It
# installs a desktop environment for remote desktop access via RDP.
#
# WARNING: This script enables remote desktop access which may have security implications.
# Make sure to use strong passwords and consider firewall rules.
#

# Create a log file with timestamp
LOG_FILE="install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"
echo "You are logged in as: $USER"
echo "Starting script execution at: $(date)"
echo .

# Check if we're running on Ubuntu 25.04 Server
if ! grep -q "Ubuntu 25.04" /etc/os-release; then
    echo "ERROR: This script is designed for Ubuntu 25.04 Server only."
    echo "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Please run this script on Ubuntu 25.04 Server."
    exit 1
fi

# Check if this is a server installation (not desktop)
if dpkg -l | grep -q "^ii.*xorg"; then
    echo "ERROR: This script is designed for Ubuntu 25.04 Server installations only."
    echo "Detected X11/Xorg installation. Please use Ubuntu 25.04 Server instead."
    exit 1
fi

echo "✓ Confirmed: Running on Ubuntu 25.04 Server"
echo .

# Check if the current user has a password set by examining /etc/shadow
echo "On cloud installations, no password is assigned to the default user. Needed for RDP remote access."
echo .
echo "WARNING: Remote desktop access may expose this system to unauthorized access attempts from the internet."
echo .
echo "Checking if user '$USER' has a password set..."
if sudo grep "^$USER:" /etc/shadow | cut -d: -f2 | grep -q "^[!*]"; then
    echo "✗ User '$USER' does not have a password set (locked account)"
    echo "Setting password for user '$USER'..."
    sudo passwd $USER
elif sudo grep "^$USER:" /etc/shadow | cut -d: -f2 | grep -q "^$"; then
    echo "✗ User '$USER' does not have a password set (empty password field)"
    echo "Setting password for user '$USER'..."
    sudo passwd $USER
else
    echo "✓ User '$USER' has a password set"
fi
echo .

# Prompt the user to configure a proxy if needed for internet access. (Optional)
gateway=$(ip route | awk '/default/ {print $3}')
read -p "Do you need to configure a proxy for internet access? [y/N]: " use_proxy
use_proxy=${use_proxy,,}  # to lowercase

if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    read -p "Enter proxy IP address [${gateway}]: " proxy_ip
    proxy_ip=${proxy_ip:-$gateway}
    read -p "Enter proxy port [9000]: " proxy_port
    proxy_port=${proxy_port:-9000}
    echo "Proxy will be set to: http://$proxy_ip:$proxy_port/"
fi


# Add timestamp to the installation log
echo "Starting installation at: $(date)"
echo .

# Enable strict error handling for the installation phase
set -euo pipefail

sudo apt-get update
sudo apt-get upgrade -y

sudo apt install tasksel -y
sudo tasksel install cinnamon-desktop

sudo apt install xrdp docker.io nix-bin -y

# Docker setup: proxy and add user to docker group.
if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    sudo mkdir -vp /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$proxy_ip:$proxy_port"
Environment="HTTPS_PROXY=http://$proxy_ip:$proxy_port"
Environment="NO_PROXY=localhost,127.0.0.0/8,::1"
EOF
fi
sudo usermod -aG docker $USER

# Nix setup: add user to nix-users group and set experimental features.
echo experimental-features = nix-command flakes | sudo tee -a /etc/nix/nix.conf
sudo usermod -aG nix-users $USER

# Increase file watch limits - needed for running kind with a large number of nodes.
sudo tee /etc/sysctl.d/99-inotify.conf <<EOF
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

mkdir -vp $HOME/.local/share/applications
mkdir -vp $HOME/.config/autostart
ln -svf /var/lib/snapd/desktop/applications/firefox_firefox.desktop $HOME/.local/share/applications/firefox.desktop
ln -svf /var/lib/snapd/desktop/applications/firefox_firefox.desktop $HOME/.config/autostart/
# Remove existing Firefox profile(s) for this user, then create a new default profile (snap install)
FIREFOX_PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox"
if [ -d "$FIREFOX_PROFILE_DIR" ]; then
    echo "Removing existing Firefox profiles (snap)..."
    rm -rf "$FIREFOX_PROFILE_DIR"
fi
echo "Creating new default Firefox profile (snap)..."
snap run firefox --headless --createprofile "default" >/dev/null 2>&1
# Find the new profile directory
PROFILE_INI="$FIREFOX_PROFILE_DIR/profiles.ini"
if [ -f "$PROFILE_INI" ]; then
    PROFILE_PATH=$(awk -F= '/^Path=/{print $2; exit}' "$PROFILE_INI")
    PROFILE_DIR="$FIREFOX_PROFILE_DIR/$PROFILE_PATH"
    if [ -d "$PROFILE_DIR" ]; then
        # Write a new user.js to set homepage and startup behavior
        USER_JS="$PROFILE_DIR/user.js"
        HOMEPAGE_URL="https://github.com/ardentperf/cnpg-playground/blob/tmp-work/lab/README.md"
        cat > "$USER_JS" <<EOF
user_pref("browser.startup.page", 1); // 1 = home page, 0 = blank page
user_pref("browser.startup.homepage", "$HOMEPAGE_URL"); // Set the homepage URL
user_pref("browser.aboutwelcome.enabled", false); // Disable the new-style about:welcome
user_pref("browser.startup.homepage_override.mstone", "ignore"); // Skip the "What's New" page
user_pref("startup.homepage_welcome_url", "$HOMEPAGE_URL"); // Set the welcome URL
EOF
        echo "Firefox profile (snap) configured with custom homepage via user.js."
    else
        echo "Could not find Firefox profile directory (snap). Skipping homepage configuration."
    fi
else
    echo "Could not find profiles.ini (snap). Skipping Firefox homepage configuration."
fi

# Create a script to configure desktop settings in user's home directory
cat > ~/configure-desktop.sh << 'EOF'
#!/bin/bash
LOGFILE="$HOME/configure-desktop-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "[$(date)] Starting configure-desktop.sh"
sleep 30
# Launch gnome-terminal once to trigger profile creation
gnome-terminal --window -- bash -c "exit"
sleep 1  # give it a moment to write to dconf
default_uuid=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
# Set GNOME Terminal profile colors and options
# Set background color (dark), foreground color (light), bold-is-bright, and use-theme-colors
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_uuid/" background-color 'rgb(23,20,33)'
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_uuid/" foreground-color 'rgb(208,207,204)'
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_uuid/" bold-is-bright true
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_uuid/" use-theme-colors false
EOF
# Make the script executable
chmod +x ~/configure-desktop.sh
# Add the script to autostart for GNOME session
mkdir -vp ~/.config/autostart
cat > ~/.config/autostart/configure-desktop.desktop << EOF
[Desktop Entry]
Type=Application
Name=Configure Desktop
Exec=/home/$USER/configure-desktop.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# Set KUBECONFIG and auto-enters the nix development environment on login.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat <<EOF >> ~/.bashrc
echo "Setting KUBECONFIG to $SCRIPT_DIR/k8s/kube-config.yaml"
export KUBECONFIG=$SCRIPT_DIR/k8s/kube-config.yaml
cd $SCRIPT_DIR
# Only auto-enter nix develop if not already inside, and only for login interactive shells
if [ -z "\$IN_NIX_SHELL" ] && [ -z "\$CNPG_DEV_ENTERED" ] && [[ "\$-" == *i* ]]; then
    export CNPG_DEV_ENTERED=1
    echo "Entering nix development environment..."
    if nix develop .; then
        echo "nix develop . completed successfully."
    else
        echo "nix develop . failed. Please check the output above for errors."
    fi
else
    echo "Already inside a nix environment or already entered. Skipping 'nix develop .'."
fi
EOF

# Inform the user that a reboot is required and prompts for confirmation
echo .
echo "Installation complete at: $(date)"
echo .
echo "You need to restart the system for all changes to take effect. (In particular, the current user needs to be added to the docker group.)"
echo .
echo "You can now connect via RDP as user '$USER' using the password."
echo .
echo "Press Enter to reboot the system, or Ctrl+C to cancel..."
read -r
sudo reboot
