# CloudNativePG Lab

- [Hardware Requirements](#-hardware-requirements)
- [Getting Started](#-getting-started)
- [Cost estimate for using the cloud (US Dollars)](#%EF%B8%8F-cost-estimate-for-using-the-cloud-us-dollars)
- [Cost estimate for buying hardware to directly run Ubuntu (US Dollars)](#%EF%B8%8F-cost-estimate-for-buying-hardware-to-directly-run-ubuntu-us-dollars)

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
git clone https://github.com/ardentperf/cnpg-playground
```

```bash
bash cnpg-playground/lab/install.sh
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
