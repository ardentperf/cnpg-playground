# Detailed steps to get a freshly installed Ubuntu 25.04 server

## Operating System Installation using official Ubuntu Server Installer

If you're running in a Virtual Machine on your Windows or Mac laptop or if
you want to install directly on hardware like a laptop or older server then
download the Ubuntu 25.04 Server Installer ISO and use that to directly
install ubuntu.

https://ubuntu.com/download/server

**⚠️ Do not use the Desktop installer! Make sure to use the Server installer,
and don't install a desktop environment! ⚠️**

VirtualBox and UTM have been used successfully; WSL2 should work in theory
so please let us know if you test it successfully. Be careful of licensing
on the VirtualBox extension pack - Reddit users have reported Oracle going
after money after they noticed downloads. VirtualBox version 4 should not
need the extension pack for these labs anyway.

## Cloud Provider Setup Scripts

Cloud instances with Ubuntu server preinstalled are readily available.

Automated scripts are available for mac and linux to create and manage Ubuntu 25.04 server instances on AWS and Azure. These scripts prompt for configuration variables with sensible defaults and handle all the setup and cleanup automatically.

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

### Manual Setup (Alternative)

If you prefer manual setup or need to customize beyond what the scripts offer,
you can reference the scripts in `lab/exercise-1-setup/` and copy/paste the
commands to run them manually.


Run this command to create infrastructure including S3-compatible storage and
kubernetes clusters named `kind-k8s-eu` and `kind-k8s-us`:

```bash
bash scripts/setup.sh
```

Run this comand to deploy the CloudNativePG operator and create postgres clusters
named `pg-eu` and `pg-us` which both have three-node HA within their respective
kubernetes clusters and also replicate data between the two kubernetes clusters:

```bash
LEGACY=true demo/setup.sh
```

*note: there may be an issue with the new backup plugin at the moment?*

A few useful tools to start exploring include `btop` to monitor server
utilization, `lazydocker` to monitor the docker pods (aka k8s nodes),
and `k9s` to explore the kubernetes clusters themselves.

Some aliases are preconfigured:
* `k` for `kubectl`
* `kc` for `kubectl cnpg`
* `c` for `kubectx`
* `n` for `kubens`

Auto-completion is configured for most commands and alaises.

