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
VirtualBox, UTM (on mac) and WSL2 (on windows) should all work for installing
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

You're of course welcome to try different families than those above. These
suggestions are targeting the lowest price point that will provide a
consistent and reliable experience.

Besides trying fewer CPUs or less memory, there are also some options like
bursting instance families or lower cost instance families like GCP's E2
family. Note that even with 4 CPUs, CNPG sandbox baseline cpu utilization
might run hot (maybe over 50% depending on what you're doing) - so if you
try a bursting instance class then keep an eye on your cpu usage and your
instance's baseline utilization for burst.

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

## Operating System Installation using official Ubuntu Server Installer

If you're running in a Virtual Machine on your Windows or Mac laptop or if
you want to install directly on hardware like a laptop or older server then
download the Ubuntu 25.04 Server Installer ISO and use that to directly
install ubuntu.

https://ubuntu.com/download/server

**⚠️ Do not use the Desktop installer! Make sure to use the Server installer! ⚠️**

VirtualBox and UTM have been used successfully; WSL2 might work in theory
so please let us know if you test it successfully. Be careful of licensing
on the VirtualBox extension pack - Reddit users have reported Oracle going
after money after they noticed downloads. VirtualBox version 4 might not
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
bash lab/cloud-setup/aws-setup.sh
```

**Teardown:**
```bash
bash lab/cloud-setup/aws-teardown.sh
```

The AWS scripts will:
- Create an EC2 instance with Ubuntu 25.04 on ARM64 architecture
- Configure security groups for SSH (port 22) and RDP (port 3389) access
- Set up proper tagging for easy identification
- Prompt for region, instance name, key pair, instance type, and disk size
- Default to `m6g.xlarge` instance type (4 vCPUs, 16GB RAM)

### Azure Setup and Teardown

**Setup:**
```bash
bash lab/cloud-setup/azure-setup.sh
```

**Teardown:**
```bash
bash lab/cloud-setup/azure-teardown.sh
```

The Azure scripts will:
- Create a VM with Ubuntu 25.04 on ARM64 architecture
- Set up a new resource group
- Configure network security for SSH and RDP access
- Prompt for location, resource group name, VM name, VM size, and disk size
- Default to `Standard_D4ps_v6` VM size (4 vCPUs, 16GB RAM)

### Manual Setup (Alternative)

If you prefer manual setup or need to customize beyond what the scripts offer, you can reference the scripts in `lab/cloud-setup/` and copy/paste the commands to run them manually.

## GCP Ubuntu Server Creation

GCP setup scripts are planned for future releases.
