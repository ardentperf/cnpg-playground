## CNPG Lab Exercises

Welcome to the CloudNativePG Lab Exercises! Get set up, explore the playground, and test resilience.

| Exercise | Description |
| --- | --- |
| [Exercise 1: Create a Lab VM](exercise-1-create-lab-vm/README.md) | Provision an Ubuntu 25.04 Server VM locally (VirtualBox) or in AWS/Azure, then convert it into a CNPG Lab VM using the install script. |
| [Exercise 2: Start and Explore the Playground](exercise-2-start-playground/README.md) | Spin up the CNPG Playground infrastructure and clusters; explore with kubectl/k9s; adjust basic Postgres parameters. |
| [Exercise 3: Run Jepsen Against CNPG](exercise-3-jepsen/README.md) | Run the Jepsen append workload on the `pg-eu` cluster; induce primary failovers; inspect results; enable synchronous replication and repeat. |
| [Exercise 4: Active Session History Monitoring](exercise-4-active-session-history/README.md) | Set up ASH monitoring using pgsentinel extension, custom Prometheus queries, and Grafana dashboards; generate workload with pgbench to visualize active sessions. |
| [Exercise 5: PgBouncer with mTLS Authentication](exercise-5-pgbouncer-mtls/README.md) | Configure connection pooling with PgBouncer using mutual TLS; set up a three-tier PKI with cert-manager; test certificate-based authentication with psql and pgbench. |
| [Exercise 6: Cross-Cluster Replication with mTLS](exercise-6-cross-cluster-replication/README.md) | Bootstrap the `pg-us` replica cluster from `pg-eu` backup using mTLS; configure disaster recovery topology across EU and US Kubernetes clusters with unified PKI. |

### Other Links

- [Main Lab README](README.md)
- [Main Playground README](../README.md)

### Playground Architecture

The playground uses [KIND](https://kind.sigs.k8s.io/) to run two Kubernetes clusters locally (named "EU" and "US") with the CloudNativePG operator installed in both. It provisions a primary PostgreSQL cluster (`pg-eu`) and a replica cluster (`pg-us`). It also provisions per‑region S3‑compatible object stores (MinIO) for backups and archiving. Demo manifests and jobs (including Jepsen) run inside the cluster to generate load and exercise failover and data‑safety features.

![CNPG Playground Architecture](../images/cnpg-playground-architecture.png)
