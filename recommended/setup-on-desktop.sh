#!/bin/bash

# Check if running inside a GNOME session
if [ "$XDG_CURRENT_DESKTOP" != "GNOME" ] && [ "$XDG_SESSION_DESKTOP" != "gnome" ]; then
    echo "ERROR: This script must be run inside a GNOME desktop session."
    echo "Current desktop: ${XDG_CURRENT_DESKTOP:-$XDG_SESSION_DESKTOP}"
    exit 1
fi

gateway=$(ip route | awk '/default/ {print $3}')
read -p "Do you need to configure a proxy for internet access? [y/N]: " use_proxy
use_proxy=${use_proxy,,}  # to lowercase

if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    read -p "Enter proxy IP address [${gateway}]: " proxy_ip
    proxy_ip=${proxy_ip:-$gateway}
    echo "Proxy will be set to: $proxy_ip"
fi

# Set favorite applications (for environments installed from desktop ISO)
gsettings set org.gnome.shell favorite-apps "['firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'snap-store_snap-store.desktop', 'yelp.desktop', 'org.gnome.Terminal.desktop']"

sudo apt install docker.io nix-bin -y

if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    # Create a systemd service to set the proxy
    sudo mkdir -vp /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$proxy_ip:8080"
Environment="HTTPS_PROXY=http://$proxy_ip:8080"
Environment="NO_PROXY=localhost,127.0.0.0/8,::1"
EOF
fi

sudo usermod -aG docker $USER

echo experimental-features = nix-command flakes | sudo tee -a /etc/nix/nix.conf

sudo usermod -aG nix-users $USER

sudo tee /etc/sysctl.d/99-inotify.conf <<EOF
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

echo "Setup complete! You need to restart the system for all changes to take effect. (In particular, the current user needs to be added to the docker group.)"
echo .
echo "Press Enter to reboot the system, or Ctrl+C to cancel..."
read -r
sudo reboot