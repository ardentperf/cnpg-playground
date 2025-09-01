# Creating a "CNPG Lab" Virtual Desktop

- [Option 1: Run a VM on your laptop](#option-1-run-a-vm-on-your-laptop)
  - [Confirm Laptop Power Settings](#confirm-laptop-power-settings)
  - [Install HAV-Capable Virtualization Software](#install-hav-capable-virtualization-software)
  - [Download Ubuntu 25.04 Server ISO](#download-ubuntu-2504-server-iso)
  - [Creating a VM and installing Ubuntu](#creating-a-vm-and-installing-ubuntu)
  - [Converting the Ubuntu 25.04 Server into a CNPG Lab VM](#converting-the-ubuntu-2504-server-into-a-cnpg-lab-vm)
- [Option 2: From your mac/linux, provision a compute instance from AWS or Azure](#option-2-from-your-maclinux-provision-a-compute-instance-from-aws-or-azure)
  - [Prerequisites](#prerequisites)
  - [AWS Setup and Teardown](#aws-setup-and-teardown)
  - [Azure Setup and Teardown](#azure-setup-and-teardown)
- [Other Options](#other-options)

## Option 1: Run a VM on your laptop

### Confirm Laptop Power Settings

Check you laptop's operating system power settings and make sure it's not
configured to sleep or hibernate before something like 30 minutes of inactivity. The
installation might take a little time, and we don't want the laptop to go to
sleep while the installation is running.

### Install HAV-Capable Virtualization Software

Be careful with software like VirtualBox which can fall back to software
virtualization; performance is very poor without Hardware Assisted
Virtualization (HAV).

On Windows, **Hyper-V** is the best choice.  Don't use WSL for the CNPG lab. It's
probably best to avoid VirtualBox, because VirtualBox can't be used alongside
WSL or Hyper-V and it requires special configuration to leverage VT-x/AMD-V
due to increasing Windows restrictions.

On Mac, several options exist such as **UTM, VirtualBox and Parallels**. These
should all be able to leverage Harware-Assisted Virtualization.

On Linux, most desktop virtualization options use **KVM/QEMU under the hood**
which leverage Hardware-Assisted Virtualization.

### Download Ubuntu 25.04 Server ISO

Download the Ubuntu 25.04 Server installation ISO:

https://ubuntu.com/download/server

**⚠️ Do not download a Desktop installer! Make sure to get a Server installer!
Make sure you have the right version! (25.04) ⚠️**

### Creating a VM and installing Ubuntu

Create the Virtual Machine with at least 4 CPUs, 16 GB memory, and 100 GB disk.

When installing Ubuntu:
1. Choose the option to install the SSH server
2. On the disk partition screen, you'll need to edit the `ubuntu-lv` underneath the `DEVICES` heading so that Ubuntu uses the whole disk. For some reason it only uses about half the disk by default.
3. Do not install any snaps (like docker, etcd, postgres, etc). The CNPG LAB install script takes care of everything; we just want an empty clean Ubuntu Server install.

After Ubuntu is installed, make sure you have internet access by logging in and testing something like `curl example.com`

### Converting the Ubuntu 25.04 Server into a CNPG Lab VM

Run these two commands to convert the Ubuntu 25.04 Server into a CNPG Lab VM:

```bash
git clone https://github.com/ardentperf/cnpg-playground  &&  cd cnpg-playground  &&  git checkout tmp-work
```

```bash
bash lab/install.sh
```

*Important Note: You can re-run the `install.sh` scripts as many times as needed. If you run into unexpected problems, just re-run. You don't need to start over at the beginning.*


## Option 2: From your mac/linux, provision a compute instance from AWS or Azure

Automated scripts are available for mac and linux to create and manage Ubuntu 25.04 server instances on AWS and Azure. These scripts prompt for configuration variables with sensible defaults and handle all the setup and cleanup automatically. After provisioning cloud compute, they automatically convert the cloud instance into a CNPG Lab VM, after starting the instance.

### Prerequisites

Before running the scripts, ensure you have:
- AWS CLI configured (`aws configure`) and a key pair exists for AWS scripts
- Azure CLI installed and logged in (`az login`) for Azure scripts

### AWS Setup and Teardown

**Setup:**
```bash
bash lab/exercise-1-setup/aws-setup.sh
```

**Teardown:**
```bash
bash lab/exercise-1-setup/aws-teardown.sh
```

The AWS scripts will:
- Create an EC2 instance with Ubuntu 25.04 on ARM64 architecture
- Configure security groups for SSH (port 22) and RDP (port 3389) access
- Set up proper tagging for easy identification
- Prompt for region, instance name, key pair, instance type, and disk size
- Default to `m7g.xlarge` instance type (4 vCPUs, 16GB RAM)

### Azure Setup and Teardown

**Setup:**
```bash
bash lab/exercise-1-setup/azure-setup.sh
```

**Teardown:**
```bash
bash lab/exercise-1-setup/azure-teardown.sh
```

The Azure scripts will:
- Create a VM with Ubuntu 25.04 on ARM64 architecture
- Set up a new resource group
- Configure network security for SSH and RDP access
- Prompt for location, resource group name, VM name, VM size, and disk size
- Default to `Standard_D4ps_v6` VM size (4 vCPUs, 16GB RAM)


## Other Options

If you're using windows then you can provision a cloud instance with Ubuntu 25.04
Server from the console, then ssh and run the CNPG lab script to convert it.

All you need is a freshly installed Ubuntu 25.04 server. There are lots of ways
to do this. You can use virtualization software (like UTM or Proxmox) and you
can use cloud compute providers (like oracle cloud or digital ocean or linode).

Just clone this repo and run the `install.sh` script on any clean Ubuntu 25.04 server.