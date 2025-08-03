# Ansible Playbook for Ubuntu 25.04 Desktop Setup

This Ansible playbook (`install-core.yml`) contains the core installation logic for setting up a desktop environment on Ubuntu 25.04 Server. It is designed to be called by the `install.sh` shell script wrapper, which handles prechecks and user interaction.

## Prerequisites

- Ubuntu 25.04 Server (not desktop)
- Ansible installed on the control machine
- SSH access to the target server
- Sudo privileges on the target server
- **Note**: Ensure Ansible is preinstalled on all target VMs before running the playbook

## Usage

### Basic Usage

```bash
# Run the playbook against localhost (if running on the target server)
ansible-playbook install-core.yml

# Run against a remote server
ansible-playbook install-core.yml -i inventory.ini
```

### With Proxy Configuration

If you need to configure a proxy for internet access, you can set the variables:

```bash
# Set proxy variables
ansible-playbook install-core.yml -e "use_proxy=true" -e "proxy_ip=192.168.1.1" -e "proxy_port=9000"

# Or use a vars file
ansible-playbook install-core.yml -e "@proxy-vars.yml"
```

Example `proxy-vars.yml`:
```yaml
use_proxy: true
proxy_ip: "192.168.1.1"
proxy_port: 9000
```

## Classroom Lab Setup

For training environments with multiple identical VMs, create a simple inventory file:

```ini
# inventory.ini - 10 identical student VMs
[students]
student01 ansible_host=192.168.1.101 ansible_user=azureuser
student02 ansible_host=192.168.1.102 ansible_user=azureuser
student03 ansible_host=192.168.1.103 ansible_user=azureuser
student04 ansible_host=192.168.1.104 ansible_user=azureuser
student05 ansible_host=192.168.1.105 ansible_user=azureuser
student06 ansible_host=192.168.1.106 ansible_user=azureuser
student07 ansible_host=192.168.1.107 ansible_user=azureuser
student08 ansible_host=192.168.1.108 ansible_user=azureuser
student09 ansible_host=192.168.1.109 ansible_user=azureuser
student10 ansible_host=192.168.1.110 ansible_user=azureuser

[students:vars]
use_proxy=true
proxy_ip=192.168.1.1
proxy_port=9000
set_user_password=true
user_password=Training2025!
```

Deploy to all VMs:

```bash
# Deploy to all 10 VMs in parallel
ansible-playbook install-core.yml -i inventory.ini -f 10

# Test connectivity first
ansible students -i inventory.ini -m ping
```

**Note**: After running the playbook, remember to reboot all VMs for the desktop environment and system changes to take full effect.

## What the Playbook Does

**Note**: This playbook (`install-core.yml`) contains only the core installation logic. Prechecks and system validation are handled by the `install.sh` shell script wrapper.

1. **Package Installation**:
   - Updates and upgrades packages
   - Installs all required packages in a single operation:
     - cinnamon-desktop-environment (desktop environment)
     - xrdp (remote desktop)
     - docker.io (container runtime)
     - nix-bin (package manager)
   - Creates flag file `/etc/cinnamon-desktop-installed-by-cnpg-lab` after successful installation
3. **Docker Configuration**:
   - Adds user to docker group
   - Configures proxy settings if needed
4. **Nix Configuration**:
   - Adds experimental features
   - Adds user to nix-users group
5. **System Tuning**:
   - Increases file watch limits for kind clusters
6. **Firefox Setup**:
   - Creates desktop shortcuts
   - Configures homepage and startup behavior
   - Sets up bookmarks toolbar visibility
   - Automatically installs default bookmarks using Firefox Enterprise Policies
7. **Desktop Configuration**:
   - Creates autostart script for GNOME Terminal colors
8. **Development Environment**:
   - Configures KUBECONFIG
   - Sets up auto-entry into nix development environment

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `use_proxy` | `false` | Whether to configure proxy settings |
| `proxy_ip` | Gateway IP | Proxy server IP address |
| `proxy_port` | `9000` | Proxy server port |
| `target_user` | `{{ ansible_user }}` | User to configure |
| `target_user_home` | `/home/{{ target_user }}` | User's home directory |
| `set_user_password` | `false` | Whether to set user password |
| `user_password` | `''` | Password to set for user |
| `script_dir` | `{{ playbook_dir }}/..` | Project directory |
| `homepage_url` | GitHub lab URL | Firefox homepage URL |

## Files Created

- `/etc/cinnamon-desktop-installed-by-cnpg-lab` (flag file indicating Cinnamon was installed by this playbook)
- `/etc/systemd/system/docker.service.d/http-proxy.conf` (if proxy enabled)
- `/etc/nix/nix.conf` (with experimental features)
- `/etc/sysctl.d/99-inotify.conf` (file watch limits)
- `~/.local/share/applications/firefox.desktop` (Firefox shortcut)
- `~/.config/autostart/firefox.desktop` (Firefox autostart)
- `~/.mozilla/firefox/[profile]/policies.json` (Firefox Enterprise Policies)
- `~/configure-desktop.sh` (Desktop configuration script)
- `~/.config/autostart/configure-desktop.desktop` (Autostart entry)
- Firefox profile with custom homepage and bookmarks toolbar

## Notes

- A reboot is recommended for all changes to take full effect
- The user will be added to docker and nix-users groups
- RDP access will be available after installation (port 3389) - ensure proper firewall rules are in place

## Architecture

This Ansible playbook is designed to work as part of a hybrid approach:

- **`install.sh`**: Shell script wrapper that handles:
  - System prechecks and validation (with smart detection for re-runs)
  - User interaction (password setup, proxy configuration)
  - Calls the Ansible playbook with appropriate variables
  - Post-installation flow (reboot prompt)

- **`install-core.yml`**: Ansible playbook that handles:
  - Core installation logic
  - Package management
  - Configuration file creation
  - Template-based setup

This approach combines the user-friendly interaction of shell scripts with the structured, idempotent nature of Ansible playbooks.