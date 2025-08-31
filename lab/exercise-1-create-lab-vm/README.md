# Creating a "CNPG Lab" Virtual Desktop

## Option 1: Run a VM on your laptop with VirtualBox

VirtualBox is recommended for local installations because it's fairly similar
across windows and mac and linux, so it's easier for us to help answer your
questions and get you up and running.

On windows, if you've never installed the MSVC redistributable, the you might also need
to download and install this first (it's required by VirtualBox):

https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

Download and install VirtualBox:

https://www.virtualbox.org/wiki/Downloads

Download the Ubuntu 25.04 Server Installer ISO:

https://ubuntu.com/download/server

**⚠️ Do not get a Desktop installer! Make sure to get the Server installer!
Make sure you have the right version! (25.04) ⚠️**

Be careful of licensing
on the VirtualBox extension pack - Reddit users have reported Oracle going
after money after they noticed downloads. VirtualBox version 4 should not
need the extension pack for these labs anyway.

### Creating a VM and installing Ubuntu

Create the Virtual Machine with 4 CPUs, 16 GB memory, and 100 GB disk.

When installing Ubuntu:
1. Choose the option to install the SSH server
2. On the disk partition screen, you'll need to edit the partition sizes so that Ubuntu uses the whole disk. For some reason it only uses about half the disk by default.

After Ubuntu is installed, make sure you have internet access by logging in and testing something like `curl example.com`

### Converting the Ubuntu 25.04 Server into a CNPG Lab VM

Run these two commands to convert the Ubuntu 25.04 Server into a CNPG Lab VM:

```bash
git clone https://github.com/ardentperf/cnpg-playground  &&  cd cnpg-playground  &&  git checkout tmp-work
```

```bash
bash lab/install.sh
```


## Option 2: From your mac/linux, provision a compute instance from AWS or Azure

Cloud instances with Ubuntu server preinstalled are readily available.

Automated scripts are available for mac and linux to create and manage Ubuntu 25.04 server instances on AWS and Azure. These scripts prompt for configuration variables with sensible defaults and handle all the setup and cleanup automatically.

These automated scripts automatically convert the cloud instance into a CNPG Lab VM, after starting the instance. If you're using windows then you can ssh to any cloud instance with Ubuntu 25.04 Server and run the CNPG lab script to convert it.

### Prerequisites

Before running the scripts, ensure you have:
- AWS CLI configured (`aws configure`) for AWS scripts
- Azure CLI installed and logged in (`az login`) for Azure scripts
- Appropriate permissions to create and manage cloud resources

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

All you need is a freshly installed Ubuntu 25.04 server. There are lots of ways
to do this. You can use virtualization software (like UTM or Proxmox) and you
can use cloud compute providers (like oracle cloud or digital ocean or linode).

Just clone this repo and run the `install.sh` script on any clean Ubuntu 25.04 server.