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

# Check if we're running on Ubuntu 25.04
if ! grep -q "Ubuntu 25.04" /etc/os-release; then
    echo "ERROR: This script is designed for Ubuntu 25.04 only."
    echo "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Please run this script on Ubuntu 25.04."
    exit 1
fi
echo "✓ Confirmed: Running on Ubuntu 25.04"
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
