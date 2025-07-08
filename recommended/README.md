# Recommended Learning Environment

```
4 CPUs, 16GB memory, 100GB disk
Ubuntu 24.04.x LTS Server
Outbound internet connection (proxies and custom CAs are supported)
Inbound ports 22 and 3389
```

*Rule of thumb for "what is a CPU":*
* *In cloud environments, count vCPUs.*
* *On your own hardware, count physical cores (not smt threads or operating
  system CPUs).*

**Why recommend Ubuntu 25.04 specifically, when cnpg-playground supports
running on many other operating systems too?** You're of course welcome
to run **`cnpg-playground`** wherever you want, and it will continue to
support many operating systems. But by choosing one operating system for
focused attention, we can provide scripts that completely automate setup
and installation from zero to fully functional learning environment, and
we can all collaborate to troubleshoot and maintain the complete learning
environment. (Windows users, Mac users, Linux users, Cloud users,
Raspberry Pi users, or whatever else you use!)

**What's the reasoning behind the hardware specs?** After some
experimentation, it seemed that running with 2 CPUs and 8 GBs of memory
could result in a system that was running well over 50% utilized even
before starting a monitoring stack or workload. At present it seems like
these specs should be able to support a full CloudNativePG distributed
topology for learning including two full kubernetes clusters with twelve
nodes total, data replication between them, monitoring stacks on both, and
a demo workload - all running on just your single personal machine or a
single cloud instance.

**What's the reasoning behind the vCPU/core rule of thumb?** Those of us
who choose cloud environments will be using smaller instances - not whole
servers. While noisy neighbors do sometimes happen, cloud providers generally
don't run their physical hardware at high cpu utilization where SMT would
have a noticable adverse impact on individual small tenants. (As far as I
know... but someone should really test this and publish their findings.)
I might be wrong about this - but at only 4 vCPUs, I'm hoping they will
generally behave like full cores even if the underlying hardware has SMT
or hyperthreading enabled?

**Why the Desktop edition instead of the Server edition of Ubuntu?**
Monitoring and dashboarding systems like Grafana are essential day-two
operations for any database. While it's possible to forward ports and use a
browser elsewhere, having a desktop environment simplifies things and
provides a more consistent experience. We can more easily share demos
and screenshots and experiments when we minimize the differences in how
we're doing things.

**Why Ubuntu version 25.04 rather than an LTS release?** There are
currently no LTS releases with Desktop ISOs for ARM architectures. In
particular, anyone who wants to install Ubuntu Desktop inside a Virtual
Machine on a MacBook with Apple Silicon requires this ISO. These
instructions will likely be updated to use 26.04 LTS after it is
released with Ubuntu Desktop ISOs for both x86 and ARM.

**Why would someone need proxies and custom CAs?** There are a wide
variety of ways internet connectivity and traffic is managed in different
places. For example, the official Docker documentation includes [a guide
for using docker in corporate environments where network traffic is
intercepted and monitored with HTTPS proxies like
Zscaler](https://docs.docker.com/guides/zscaler/). It's certainly possible
to run **`cnpg-playground`** in these environments too, and these ubuntu
automation scripts will handle it if needed.


## Running in a Virtual Machine on your Windows or Mac laptop (for free)

Your laptop itself should have at least `6 physical cores, 24GB memory, 150GB
available storage`. The Virtual Machine that you create is what needs to match
the recommended specs and you need leftover resources for everything else
you're running on your laptop.

Check your hardware specs because the number of CPUs visible in
windows/macos is often much higher than the real number of cores (due to
SMT or hyperthreading).

If you are required to configure a CPU count when creating a virtual
machine, then assign `4 CPUs` to the VM. Similar to cloud environments,
you're assigning virtual CPUs - not cores - into your virtual machine.

VirtualBox, UTM (on mac) and WSL (on windows) should all work for installing
and running Ubuntu in a VM.

## Cloud pricing (US Dollars)

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

## Pricing for hardware to directly run Ubuntu (US Dollars)

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


# Setup Instructions

The `setup-on-desktop-sh` script will automatically install and configure
everything needed for **`cnpg-playground`** on a clean installation of a
Ubuntu 25.04 Desktop.

```bash
git clone https://github.com/ardentperf/cnpg-playground
cd cnpg-playground
git checkout tmp-work

bash recommended/setup-on-desktop.sh
```

When the script completes, it will reboot the server. After you reconnect,
terminals will automatically use `nix` to enter an environment will all of
the tools needed for learning.

After reconnecting, you can create the learning environment.

```bash
# create kubernetes infrastructure
scripts/setup.sh

export KUBECONFIG=/home/$USER/cnpg-playground/k8s/kube-config.yaml

# create CloudNativePG clusters (there may be an issue with the new backup plugin at the moment?)
LEGACY=true demo/setup.sh
```

A few useful tools to start exploring include `btop` to monitor server
utilization, `lazydocker` to monitor the docker pods (aka k8s nodes),
and `k9s` to explore the kubernetes clusters themselves.

Some aliases are preconfigured:
* `k` for `kubectl`
* `kc` for `kubectl cnpg`
* `c` for `kubectx`
* `n` for `kubens`

Auto-completion is configured for most commands and alaises.


## Operating System Installation using official Ubuntu Desktop Installer

If you're running in a Virtual Machine on your Windows or Mac laptop or if
you're running directly on a well support laptop (like a Thinkpad) then
download the Ubuntu Desktop 25.04 Installer ISO and use that to directly
install ubuntu.

https://ubuntu.com/download/desktop

However if you're running on a cloud instance then you don't have the option
to directly run a deskop install. Ubuntu does not officially support this,
but it's possible to install a desktop on top of the server image and make it
accessible via RDP. This is fully scripted and automated for Ubuntu 25.04
at https://gist.github.com/ardentperf/6a224902ad4ecfb93380795030d17dcf

Exact copy-and-paste instructions to get a functional Ubuntu desktop on
AWS and Azure follow. These have been tested fairly thoroughly; if I find
time to test GCP then I'll add instructions for it too.

There are a few glitches with this unsupported and unofficial Ubuntu RDP
desktop setup, but it works well enough for our purposes.

## AWS Ubuntu Server Creation

Create an EC2 instance with Ubuntu 25.04 on ARM64 architecture. The
instance will be tagged with the name "cnpg1" for easy identification.

Choose a region that's close to you. From Seattle, RDP remote desktops are
noticably more responsive when using west coast regions (versus east coast
regions).

```bash
# nb. to use a different region, lookup AMIs at https://cloud-images.ubuntu.com/locator/ec2/
#     or use this command:
#
# aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/arm64/hvm/ebs-gp3/ami-id --region us-east-1
#

REGION=us-east-1
INSTANCE_NAME=cnpg1
KEY_NAME=t430s
AMI_ID=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/arm64/hvm/ebs-gp3/ami-id --region $REGION --query 'Parameters[0].Value' --output text)
echo "AMI ID: $AMI_ID"

aws ec2 run-instances --instance-type m6g.xlarge --image-id $AMI_ID \
    --region $REGION  --monitoring Enabled=true --key-name $KEY_NAME \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"

# Check if SSH port (22) is already open, if not open it
aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# Open only if needed
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-name default \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Check if RDP port (3389) is already open, if not open it
aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`3389`]'

# Open only if needed
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-name default \
    --protocol tcp \
    --port 3389 \
    --cidr 0.0.0.0/0

# Get the public IP address of the instance
aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text


ssh ubuntu@172.184.113.71

curl -sSL bit.ly/ubuntu2504desktop -O

bash ubuntu2504desktop
```

Cleanup:

```bash
REGION=us-east-1
INSTANCE_NAME=cnpg1

# Get the instance ID by name tag
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text) && echo "Instance ID: $INSTANCE_ID"


# Terminate the instance (this will also delete the EBS volume due to DeleteOnTermination=true)
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

az group create --name $RESOURCE_GROUP --location $LOCATION

# Create the VM
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

# Open RDP port (3389) for remote desktop access
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 3389

az vm list-ip-addresses --resource-group $RESOURCE_GROUP --output table

      VirtualMachine    PublicIPAddresses    PrivateIPAddresses
      ----------------  -------------------  --------------------
      cnpg-playground   172.184.113.71       10.0.0.4

ssh azureuser@172.184.113.71

curl -sSL bit.ly/ubuntu2504desktop -O

bash ubuntu2504desktop
```

Cleanup

**Simple approach (recommended):**

```bash
RESOURCE_GROUP="cnpg1"

# This will delete the VM and all associated resources in one command
az group delete --name $RESOURCE_GROUP --yes
```

**Step-by-step approach (if you need more control):**

```bash
# Get the actual resource names from the VM before deleting it
RESOURCE_GROUP=cnpg1
VM_NAME=cnpg1vm

# Get the OS disk name and NIC name from the VM
OS_DISK_NAME=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query "storageProfile.osDisk.name" -o tsv)
NIC_NAME=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query "networkProfile.networkInterfaces[0].id" -o tsv | sed 's/.*\///')

# Delete the VM (this will also delete the OS disk automatically)
az vm delete --name $VM_NAME --resource-group $RESOURCE_GROUP --yes

# Delete the NIC and OS disk (if they still exists)
[ ! -z "$NIC_NAME" ] && az network nic delete --name "$NIC_NAME" --resource-group $RESOURCE_GROUP || true
[ ! -z "$OS_DISK_NAME" ] && az disk delete --name "$OS_DISK_NAME" --resource-group $RESOURCE_GROUP --yes || true

# Delete the public IP (this name was specified in the create command)
az network public-ip delete --name ${VM_NAME}PublicIP --resource-group $RESOURCE_GROUP

# Delete the resource group (this will clean up any remaining resources)
az group delete --name $RESOURCE_GROUP --yes
```

## GCP Ubuntu Server Creation

The AWS and Azure setups have been tested fairly thoroughly; if I find time to
test GCP then I'll add instructions for it too.