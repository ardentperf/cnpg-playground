#!/bin/bash
#
# This script sets up the cnpg-playground learning environment on a fresh Ubuntu 25.04 Desktop installation.
# It configures GNOME favorites, installs Docker and Nix, handles proxy settings if needed, and prepares the system for CloudNativePG training.
#

# Ensure the script is run inside a GNOME session, to make sure it's not executed on a server that doesn't have a desktop environment.
if [ "$XDG_CURRENT_DESKTOP" != "GNOME" ] && [ "$XDG_SESSION_DESKTOP" != "gnome" ]; then
    echo "ERROR: This script must be run inside a GNOME desktop session."
    echo "Current desktop: ${XDG_CURRENT_DESKTOP:-$XDG_SESSION_DESKTOP}"
    exit 1
fi

# Prompt the user to configure a proxy if needed for internet access. (Optional)
gateway=$(ip route | awk '/default/ {print $3}')
read -p "Do you need to configure a proxy for internet access? [y/N]: " use_proxy
use_proxy=${use_proxy,,}  # to lowercase

if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    read -p "Enter proxy IP address [${gateway}]: " proxy_ip
    proxy_ip=${proxy_ip:-$gateway}
    echo "Proxy will be set to: $proxy_ip"
fi

# Pre-configure the GNOME favorites bar for a consistent user experience.
gsettings set org.gnome.shell favorite-apps "['firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'snap-store_snap-store.desktop', 'yelp.desktop', 'org.gnome.Terminal.desktop']"

# Install Docker and Nix package manager.
sudo apt install docker.io nix-bin -y

# If a proxy is required, set up Docker to use it via a systemd drop-in file.
if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    sudo mkdir -vp /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$proxy_ip:8080"
Environment="HTTPS_PROXY=http://$proxy_ip:8080"
Environment="NO_PROXY=localhost,127.0.0.0/8,::1"
EOF
fi

# Allow the current user to run Docker commands without sudo.
sudo usermod -aG docker $USER

# Append the required experimental features to the Nix configuration.
echo experimental-features = nix-command flakes | sudo tee -a /etc/nix/nix.conf

# Grant the user permissions to use Nix.
sudo usermod -aG nix-users $USER

# Increase file watch limits - needed for running kind with a large number of nodes.
sudo tee /etc/sysctl.d/99-inotify.conf <<EOF
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

# Set KUBECONFIG and auto-enters the nix development environment on login.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat <<EOF >> ~/.bash_profile
echo "Setting KUBECONFIG to $SCRIPT_DIR/k8s/kube-config.yaml"
export KUBECONFIG=$SCRIPT_DIR/k8s/kube-config.yaml
cd $SCRIPT_DIR
echo "Entering nix development environment..."
if nix develop .; then
    echo "nix develop . completed successfully."
else
    echo "nix develop . failed. Please check the output above for errors."
fi
EOF

# Inform the user that a reboot is required and prompts for confirmation.
echo "Setup complete! You need to restart the system for all changes to take effect. (In particular, the current user needs to be added to the docker group.)"
echo .
echo "Press Enter to reboot the system, or Ctrl+C to cancel..."
read -r
sudo reboot