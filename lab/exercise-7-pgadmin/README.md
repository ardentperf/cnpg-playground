# pgAdmin for CloudNativePG

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deploying pgAdmin](#deploying-pgadmin)
- [Connecting to pgAdmin](#connecting-to-pgadmin)
- [Exploring the Cluster](#exploring-the-cluster)
- [Cleaning Up](#cleaning-up)
- [Automation Script](#automation-script)

## Overview

This exercise deploys [pgAdmin 4](https://www.pgadmin.org/) — the most widely
used PostgreSQL administration tool — into the Kubernetes cluster using the
[official pgAdmin Helm chart](https://github.com/pgadmin-org/pgadmin4/tree/master/pkg/helm).

The Helm chart is published as an OCI image at `oci://docker.io/dpage/pgadmin4-helm`
and supports pre-registering PostgreSQL server connections via a `serverDefinitions`
values block. This exercise uses that feature to pre-wire pgAdmin to `pg-eu`
so the cluster appears in the server tree immediately after login.

## Prerequisites

- The CNPG Playground is up and running with the `pg-eu` cluster available.
- `helm` is installed on the lab VM.
- Your kubectl context targets `kind-k8s-eu`:

```bash
k config current-context   # should print kind-k8s-eu
helm version               # should show Helm v3.x
```

## Deploying pgAdmin

**Note:** All commands in this exercise should be run from the CNPG playground
root directory (`~/cnpg-playground`).

Install pgAdmin using the official Helm chart with the lab values file:

```bash
helm install pgadmin4 oci://docker.io/dpage/pgadmin4-helm \
  -f lab/exercise-7-pgadmin/pgadmin-values.yaml
```

The values file configures:
- A predictable release name (`fullnameOverride: pgadmin4`) so the service is
  simply `pgadmin4`
- Login credentials: `admin@pgadmin.org` / `admin`
- No persistent volume (not needed for a lab)
- A pre-registered server definition pointing to `pg-eu-rw` as the `postgres`
  user

Wait for the pgAdmin pod to be ready:

```bash
k wait --timeout 3m --for=condition=Ready \
  pod -l app=pgadmin4
```

## Connecting to pgAdmin

Port-forward the pgAdmin service to your local machine:

```bash
k port-forward service/pgadmin4 8090:80
```

Open `http://localhost:8090` in Firefox and log in:

- **Email:** `admin@pgadmin.org`
- **Password:** `admin`

You will see `pg-eu` already listed under **Servers** in the left-hand tree.
Click it to connect — pgAdmin will prompt for the PostgreSQL password. Retrieve
it from the CNPG superuser secret:

```bash
kubectl get secret pg-eu-superuser \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Paste that value into the pgAdmin password prompt and optionally tick
**Save password** for the session.

> **Tip:** If pgAdmin shows a blank page or a loading spinner for more than
> 30 seconds, give the pod a moment to finish starting and refresh the browser.

## Exploring the Cluster

Once connected, take a few minutes to browse the cluster:

**Check installed extensions:**

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

**View active connections:**

```sql
SELECT pid, usename, application_name, state, query_start
FROM pg_stat_activity
WHERE state IS NOT NULL
ORDER BY query_start;
```

**Inspect the pg_active_session_history view** (if Exercise 4 is complete):

```sql
SELECT ash_time, usename, application_name, wait_event_type, wait_event
FROM pg_active_session_history
ORDER BY ash_time DESC
LIMIT 20;
```

## Cleaning Up

To remove the pgAdmin deployment:

```bash
helm uninstall pgadmin4
```

## Automation Script

After following the manual steps above, the automation script can be used to
quickly verify or re-create the pgAdmin deployment:

```bash
cd ~/cnpg-playground
bash lab/exercise-7-pgadmin/test-pgadmin-setup.sh
```

The script:
- Installs pgAdmin via Helm (idempotent — upgrades if already installed)
- Waits for the pod to be ready
- Verifies the service exists
- Prints the port-forward command and login credentials
