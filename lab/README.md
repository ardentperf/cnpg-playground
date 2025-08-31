# CloudNativePG Lab

- [Hardware Requirements](#-hardware-requirements)
- [Getting Started](#-getting-started)
- [Cost estimate for using the cloud (US Dollars)](#-cost-estimate-for-using-the-cloud-us-dollars)
- [Cost estimate for buying hardware to directly run Ubuntu (US Dollars)](#-cost-estimate-for-buying-hardware-to-directly-run-ubuntu-us-dollars)
- [Frequently Asked Questions](#-frequently-asked-questions)

---

Do you want to try the CNPG Playground - but you don't want to spend time tweaking `sysctl fs.inotify` on Linux, or wrestling with WSL on Windows, or getting Rancher & KinD cooperating on your Mac?

The *CloudNativePG LAB* hands you a ready-to-use, batteries-included, runs-anywhere Virtual Machine with the CNPG Playground and some Lab Exercises.

This is done with a **post-install bootstrap script** that transforms a clean Ubuntu 25.04 server into a fully functional **virtual desktop lab environment** accessible directly (with VirtualBox, etc) and accessible remotely via Remote Desktop.

In addition to the CNPG Playground, this also includes:
- Browser preconfigured with bookmarks for CNPG docs and Grafana monitoring
  dashboards based on Prometheus and Loki (WIP/TODO)
- Useful CLI tools like `kubectl`, `btop`, `lazydocker`, `k9s`, `bat`, etc
  (including aliases, shell completion, and the CNPG playground's `nix` devshell).
- Optional sample clusters, exercises, and visual tools (WIP/TODO)
- Ansible playbooks that can be used to preconfigure an entire classroom

## 🔧 Hardware Requirements

You specifically need **Ubuntu 25.04 Server** and make sure you *do not install a desktop*.

Requirements for **your laptop**, to run locally with VirtualBox or another virtualization software:

```
6 CPUs, 24GB memory, 150GB disk
(this includes extra hardware capacity for your laptop, while the VM is running)
```

Requirements of **the VM or cloud instance itself**:

```
4 CPUs, 16GB memory, 100GB disk
Ubuntu 25.04 Server (fresh install)
Outbound internet connection (proxies and custom CAs are supported)
Inbound ports 22 and 3389 (port forwarding is fine)
```


## 🎯 Getting Started

For detailed instructions go to [Lab Exercise 1: Creating a CNPG Lab Virtual Machine](exercise-1-create-lab-vm/README.md)

TLDR/summary: Run these two commands on a fresh Ubuntu 25.04 Server.

```bash
git clone https://github.com/ardentperf/cnpg-playground  &&  cd cnpg-playground  &&  git checkout tmp-work
```

```bash
bash lab/install.sh
```

*Installation time tends to run around 10-15 minutes.
When the script completes, it will reboot the server. After the reboot, you
can connect with Remote Desktop.*


## ☁️ Cost estimate for using the cloud (US Dollars)

*On-demand rates for "US East 1" region as of 6-July-2025 in US Dollars*

| Cloud | Instance | per-hour | per-day | per-week |
| --- |  --- | --- | --- | --- |
| AWS | m7g.xlarge | $ 0.1632  | $ 3.9168 | $ 27.4176
| Azure | Standard_D4ps_v6 | $ 0.140 | $ 3.36 | $ 23.520
| GCP | t2a-standard-4 | $ 0.154 | $ 3.696 | $ 25.872

You're of course welcome to try different families than those above. These
suggestions are targeting the lowest price point that will provide a
consistent and reliable experience.

Besides trying fewer CPUs or less memory, there are also some options like spot
instances or bursting instance families or lower cost instance families like GCP's E2
family. Note that even with 4 CPUs, CNPG playground baseline cpu utilization
might run hot (maybe over 50% depending on what you're doing) - so if you
try a bursting instance class then keep an eye on your cpu usage and your
instance's baseline utilization for burst.

## 🖥️ Cost estimate for buying hardware to directly run Ubuntu (US Dollars)

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

*If you are running this in a Virtual Machine on your Windows or Mac laptop,
the Virtual Machine you create needs to match the recommended specs, and you
will need to leave enough resources for everything else running on your
laptop. When configuring the VM, if you are asked to set a CPU count, assign
`4 CPUs` to the VM. As with cloud environments, you are assigning virtual
CPUs—not physical cores—to your virtual machine. VirtualBox, UTM (on mac)
and WSL2 (on windows) should all work for installing and running Ubuntu in a
VM.*


**What's the vCPU/core rule of thumb? What's the reasoning behind it?** Rule
of thumb for "what is a CPU": In cloud environments, count vCPUs. On your own
hardware, count physical cores (not smt threads or operating system CPUs. Those of us
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


