# CloudNativePG Lab

**One-shot script to set up a full virtual desktop for CloudNativePG training and experimentation.**

## 🚀 What is it?

This project provides a **post-install bootstrap script** that transforms a clean Ubuntu system into a fully functional **virtual desktop lab environment** for working with [CloudNativePG](https://cloudnative-pg.io/).

It sets up:

- A graphical virtual desktop environment (accessible via RDP)
- Kubernetes with a local cluster (with `kind`)
- CloudNativePG and the CNPG Playground ready to use
- Ready to use Grafana, Prometheus and Loki for monitoring dashboards (WIP/TODO)
- Useful CLI tools like `kubectl`, `btop`, `lazydocker`, `k9s`, `bat`, etc.
- Optional sample clusters, exercises, and visual tools (WIP/TODO)

## 🛠️ Use Cases

- Training classes, hands-on workshops, and demos
- Self-paced learning and experimentation
- Rapid sandbox environment for CloudNativePG development

## ✅ Features

- Scripted install on a fresh Ubuntu VM
- RDP-accessible desktop
- Opinionated defaults, biased to provide ease of use and robustness/stability
- No vendor lock-in — works on local VMs, cloud VMs, or bare metal

## 💻 Hardware Requirements

```
4 CPUs, 16GB memory, 100GB disk
Ubuntu 25.04 Server (fresh install)
Outbound internet connection (proxies and custom CAs are supported)
Inbound ports 22 and 3389 (port forwarding is fine)
```

Rule of thumb for "what is a CPU":
* In cloud environments, count vCPUs.
* On your own hardware, count physical cores (not smt threads or operating
  system CPUs).

*If you are running this in a Virtual Machine on your Windows or Mac laptop,
your laptop itself should have at least `6 physical cores`, `24GB memory`,
and `150GB available storage`. The Virtual Machine you create needs to match
the recommended specs, and you will need to leave enough resources for
everything else running on your laptop. When configuring the VM, if you are
asked to set a CPU count, assign `4 CPUs` to the VM. As with cloud environments,
you are assigning virtual CPUs—not physical cores—to your virtual machine.
VirtualBox, UTM (on mac) and WSL (on windows) should all work for installing
and running Ubuntu in a VM.*

## 🎯 Getting Started

Run this on a fresh Ubuntu 25.04 Server install:

```bash
git clone https://github.com/ardentperf/cnpg-playground  &&  cd cnpg-playground  &&  git checkout tmp-work
```

```bash
bash lab/install.sh
```

Installation time tends to run around 10-15 minutes.

When the script completes, it will reboot the server. After the reboot, you
can connect with either SSH or RDP and all terminals will automatically use a
`nix` devshell to enter an environment with tools for learning and exploring.

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


## ❓ Frequently Asked Questions

**What's the reasoning behind the hardware specs?** After some
experimentation, it seemed that running with 2 CPUs and 8 GBs of memory
could result in a system that was running well over 50% utilized even
before starting a monitoring stack or workload. At present it seems like
4 CPUs and 16 GBs of memory should be able to support a full CloudNativePG
distributed topology for learning including two full kubernetes clusters
with twelve nodes total, data replication between them, monitoring stacks
on both, and a demo workload - all running on just your single personal
machine or a single cloud instance.

**What's the reasoning behind the vCPU/core rule of thumb?** Those of us
who choose cloud environments will be using smaller instances - not whole
servers. While noisy neighbors do sometimes happen, cloud providers generally
don't run their physical hardware at high cpu utilization where SMT would
have a noticable adverse impact on individual small tenants. (As far as I
know... but someone should really test this and publish their findings.)
I might be wrong about this - but at only 4 vCPUs, I'm hoping they will
generally behave like full cores even if the underlying hardware has SMT
or hyperthreading enabled?

**Why a virtual desktop instead of just a server?** Monitoring and
dashboarding systems like Grafana are essential day-two operations for any
database. While it's possible to forward ports and use a browser elsewhere,
having a desktop environment simplifies things and provides a more consistent
experience. We can more easily share demos and screenshots and experiments
when we minimize the differences in how we're doing things. It minimizes
variation and makes the lab more accessible to beginners. It also makes it
easier to build training curriculums on this foundation, which can be used
in formal classes.

**Why a virtual desktop instead of Ubuntu's official Desktop Edition?**
Ubuntu's desktop edition is geared toward specific hardware. There's no
easy way to convert a server installation into a desktop installation
via package managers because much of the desktop setup code lives only
in Ubuntu's installer. By standardizing on a virtual desktop via RDP
(even when running in a local VM), we can provide a single consistent
and universal experience.

**Why the Cinnamon desktop environment instead of something like GNOME
or KDE?** Through a lot of trial and error, we learned that with multiple
installation methods on both 24.04 and 25.04, GNOME has problems
interoperating with xRDP. We experienced crashes and unresponsiveness
at startup. XFCE and KDE are stable however both of them do not support
color emojis in the terminal, which have become somewhat common in
command line tooling recently. Cinnamon was the only environment that
both supported color emojis and also seemed to work reliably with xRDP.

**Why Ubuntu version 25.04 rather than an LTS release?** Because this
has a new enough version of nix package manager in the distro repositories
to work with the CNPG playground's nix devshell. This could have gone
either way - docker seemed to work on 24.04 and we could have installed
bleeding edge versions of nix directly from upstream - but for now we
decided to stick with ubuntu packaged versions of nix in favor of more
stability in the lab environment. We will likely refresh the lab environment
for Ubuntu 26.04 after it is released.

**Why would someone need proxies and custom CAs?** There are a wide
variety of ways internet connectivity and traffic is managed in different
places. For example, the official Docker documentation includes [a guide
for using docker in corporate environments where network traffic is
intercepted and monitored with HTTPS proxies like
Zscaler](https://docs.docker.com/guides/zscaler/). It's certainly possible
to run **`cnpg-playground`** in these environments too, and these ubuntu
automation scripts will handle it if needed.


## Cost estimate for using the cloud (US Dollars)

*For "US East 1" region as of 6-July-2025*

* AWS: m6g.xlarge ... 0.154/hr ... 25.872/week
* Azure: Standard_D4ps_v6 ... 0.140/hr ... 23.520/week
* GCP: t2a-standard-4 ... 0.154/hr ... 25.872/week

I recommend against bursting instance classes in cloud environments, because
even with 4 CPUs, CNPG sandbox baseline cpu utilization might run hot (maybe
over 50% depending on what you're doing).

You're of course welcome to try different families than those above. These
suggestions are targeting the lowest price point that will provide a
consistent and reliable experience.

Besides trying fewer CPUs or less memory, there are also some options like
bursting instance families (but keep an eye on your cpu usage and your
instance's baseline utilization for burst) or lower cost instance families
like GCP's E2 family.

## Cost estimate for buying hardware to directly run Ubuntu (US Dollars)

If you want an environment that can be left running more than a month or two
then you can probably save money by purchasing hardware.

A few hardware choices that are known to work well with Ubuntu:

* Refurbished/Used Lenovo Thinkpad, Dell Latitude or HP EliteBook ... $300 to
  $1000
* Raspberry Pi 5 with 16gb RAM and 128gb MicroSD ... $200

You're of course welcome to try different hardware too. These suggestions are
targeting lower price points and trying to minimize the risks of hardware
compatability problems and other unexpected & frustrating issues you might
encounter.


# Detailed steps to get a freshly installed Ubuntu 25.04 server

## Operating System Installation using official Ubuntu Desktop Installer

If you're running in a Virtual Machine on your Windows or Mac laptop or if
you want to install directly on hardware like a laptop or older server then
download the Ubuntu 25.04 Server Installer ISO and use that to directly
install ubuntu.

https://ubuntu.com/download/server

Cloud instances with the server preinstalled are readily available.

Exact copy-and-paste instructions to get a functional Ubuntu server on
AWS and Azure follow. These have been tested fairly thoroughly; if I find
time to test GCP then I'll add instructions for it too.

## AWS Ubuntu Server Creation

Create an EC2 instance with Ubuntu 25.04 on ARM64 architecture. The
instance will be tagged with the name "cnpg1" for easy identification.

Choose a region that's close to you. From Seattle, RDP remote desktops are
noticably more responsive when using west coast regions (versus east coast
regions).

*nb. to use a different region, lookup AMIs at https://cloud-images.ubuntu.com/locator/ec2/ or use this command:*

```bash
aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/arm64/hvm/ebs-gp3/ami-id --region us-east-1
```

Set environment variables

```bash
REGION=us-east-1
INSTANCE_NAME=cnpg1
KEY_NAME=t430s
```

```bash
AMI_ID=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/arm64/hvm/ebs-gp3/ami-id --region $REGION --query 'Parameters[0].Value' --output text) && echo "AMI ID: $AMI_ID"
```

```bash
aws ec2 run-instances --instance-type m6g.xlarge --image-id $AMI_ID \
    --region $REGION  --monitoring Enabled=true --key-name $KEY_NAME \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"
```

Check if SSH port (22) is already open, if not open it

```bash
aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

Open only if needed

```bash
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-name default \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0
```

Check if RDP port (3389) is already open, if not open it

```bash
aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`3389`]'
```

Open only if needed

```bash
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-name default \
    --protocol tcp \
    --port 3389 \
    --cidr 0.0.0.0/0
```

Get the public IP address of the instance

```bash
aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
```

Connect with SSH

```bash
ssh ubuntu@172.184.113.71
```

## AWS Ubuntu Server Cleanup

Set environment vars

```bash
REGION=us-east-1
INSTANCE_NAME=cnpg1
```

Get the instance ID by name tag

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text) && echo "Instance ID: $INSTANCE_ID"
```

Terminate the instance (this will also delete the EBS volume due to DeleteOnTermination=true)

```bash
aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID
```


## Azure Ubuntu Server Creation

Create a VM with Ubuntu 25.04 on ARM64 architecture in a new resource
group. The VM will be accessible via SSH and RDP.

Choose a region that's close to you. From Seattle, RDP remote desktops are
noticably more responsive when using west coast regions (versus east coast
regions).

```bash
LOCATION=eastus
RESOURCE_GROUP=cnpg1
VM_NAME=cnpg1vm
```

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

Create the VM

```bash
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --location $LOCATION \
  --size Standard_D4ps_v6 \
  --image Canonical:ubuntu-25_04:server-arm64:latest \
  --admin-username azureuser \
  --generate-ssh-keys \
  --os-disk-size-gb 100 \
  --storage-sku Standard_LRS \
  --public-ip-address ${VM_NAME}PublicIP
```

Open RDP port (3389) for remote desktop access

```bash
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 3389
```

```bash
az vm list-ip-addresses --resource-group $RESOURCE_GROUP --output table
```

```bash
      VirtualMachine    PublicIPAddresses    PrivateIPAddresses
      ----------------  -------------------  --------------------
      cnpg-playground   172.184.113.71       10.0.0.4
```

Connect with SSH

```bash
ssh azureuser@172.184.113.71
```

## Azure Ubuntu Server Cleanup

**Simple approach (recommended):**

```bash
RESOURCE_GROUP=cnpg1
```

This will delete the VM and all associated resources in one command

```bash
az group delete --name $RESOURCE_GROUP --yes
```

**Step-by-step approach (if you need more control):**

*Get the actual resource names from the VM before deleting it*

```bash
RESOURCE_GROUP=cnpg1
VM_NAME=cnpg1vm
```

Get the OS disk name and NIC name from the VM

```bash
OS_DISK_NAME=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query "storageProfile.osDisk.name" -o tsv)
```

```bash
NIC_NAME=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query "networkProfile.networkInterfaces[0].id" -o tsv | sed 's/.*\///')
```

Delete the VM (this will also delete the OS disk automatically)

```bash
az vm delete --name $VM_NAME --resource-group $RESOURCE_GROUP --yes
```

Delete the NIC and OS disk (if they still exists)

```bash
[ ! -z "$NIC_NAME" ] && az network nic delete --name "$NIC_NAME" --resource-group $RESOURCE_GROUP || true
[ ! -z "$OS_DISK_NAME" ] && az disk delete --name "$OS_DISK_NAME" --resource-group $RESOURCE_GROUP --yes || true
```

Delete the public IP (this name was specified in the create command)

```bash
az network public-ip delete --name ${VM_NAME}PublicIP --resource-group $RESOURCE_GROUP
```

Delete the resource group (this will clean up any remaining resources)

```bash
az group delete --name $RESOURCE_GROUP --yes
```

## GCP Ubuntu Server Creation

The AWS and Azure setups have been tested fairly thoroughly; if I find time to
test GCP then I'll add instructions for it too.
