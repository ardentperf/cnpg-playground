## CNPG Lab Exercises

Welcome to the CloudNativePG Lab Exercises! Get set up, explore the playground, and test resilience.

| Exercise | Description |
| --- | --- |
| [Exercise 1: Create a Lab VM](exercise-1-create-lab-vm/README.md) | Provision an Ubuntu 25.04 Server VM locally (VirtualBox) or in AWS/Azure, then convert it into a CNPG Lab VM using the install script. |
| [Exercise 2: Start and Explore the Playground](exercise-2-start-playground/README.md) | Spin up the CNPG Playground infrastructure and clusters; explore with kubectl/k9s; adjust basic Postgres parameters. |
| [Exercise 3: Run Jepsen Against CNPG](exercise-3-jepsen/README.md) | Run the Jepsen append workload on the `pg-eu` cluster; induce primary failovers; inspect results; enable synchronous replication and repeat. |

### Other Links

- [Main Lab README](README.md)
- [Main Playground README](../README.md)

### Playground Architecture

![CNPG Playground Architecture](../images/cnpg-playground-architecture.png)

The playground runs a local Kubernetes cluster (kind) with the CloudNativePG operator. It provisions two PostgreSQL clusters (`pg-eu`, `pg-us`) and per‑region S3‑compatible object stores (MinIO) for backups and archiving. Demo manifests and jobs (including Jepsen) run inside the cluster to generate load and exercise failover and data‑safety features.

- **Control plane**: kind-based Kubernetes with CNPG operator
- **Data plane**: CNPG-managed Postgres clusters with streaming replication and automatic failover
- **Storage**: Regional MinIO buckets (EU/US) for WAL archiving and backups
- **Tooling**: `kubectl`, `k9s`, and provided setup/teardown scripts