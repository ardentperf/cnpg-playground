# Exercise 9: Bluebox Workload on CNPG with ASH Visualization

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Step 1: Add the PostGIS Extension Container](#step-1-add-the-postgis-extension-container)
- [Step 2: Initialize Bluebox Locally](#step-2-initialize-bluebox-locally)
- [Step 3: Load Bluebox into pg-eu](#step-3-load-bluebox-into-pg-eu)
- [Step 4: Deploy Kubernetes CronJobs](#step-4-deploy-kubernetes-cronjobs)
- [Step 5: Visualize the Workload in ASH](#step-5-visualize-the-workload-in-asfh)
- [Understanding the Workload](#understanding-the-workload)
- [Exploring the Schema in pgAdmin](#exploring-the-schema-in-pgadmin)
- [Cleaning Up](#cleaning-up)
- [Automation Script](#automation-script)

## Overview

[Bluebox](https://github.com/ryanbooz/bluebox) is a realistic DVD rental
sample database built on top of Pagila. It ships with stored procedures that
generate a continuous stream of rental activity — new rentals, completions,
payment processing, and inventory rebalancing.

This exercise loads bluebox into the `pg-eu` CNPG cluster **with zero changes
to the bluebox source** and wires up the workload so you can watch it live in
the Active Session History (ASH) Grafana dashboard from Exercise 4.

Key design decisions:
- **PostGIS** is added via CloudNativePG's new [image-volume extension
  mechanism](https://cloudnative-pg.io/docs/1.28/imagevolume_extensions/) —
  the official `postgis-extension` container published by the CNPG project.
- **pg_cron** is replaced by **Kubernetes CronJobs** — a cloud-native
  alternative that keeps the PostgreSQL image unchanged and makes the schedule
  visible with `kubectl get cronjobs`.
- Bluebox is loaded by running its Docker image locally, letting it fully
  initialize (including rental history backfill), then `pg_dump | psql` into
  pg-eu.

## Prerequisites

- The CNPG Playground is running with the `pg-eu` cluster available
- **Exercise 4** (Active Session History Monitoring) must be complete —
  pgsentinel must be loaded and the ASH Grafana dashboard imported
- **Exercise 7** (pgAdmin) must be complete — pgAdmin is used in this
  exercise to explore the bluebox schema
- Docker is available on the lab VM (`docker info` should succeed)
- Your kubectl context targets `kind-k8s-eu`

```bash
k config current-context   # should print kind-k8s-eu
docker info | head -5      # should show Docker daemon info
```

**Note:** All commands in this exercise should be run from the CNPG playground
root directory (`~/cnpg-playground`).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Kubernetes (kind-k8s-eu)                           │
│                                                     │
│  pg-eu cluster (PostgreSQL 18)                      │
│  ├── Extension: pgsentinel (from Exercise 4)        │
│  ├── Extension: postgis-extension (new, this ex.)   │
│  └── Database: bluebox                              │
│       ├── bluebox schema (films, rentals, etc.)     │
│       └── called by CronJobs every 5 min            │
│                                                     │
│  CronJobs (replaces pg_cron)                        │
│  ├── bluebox-generate-rentals  (*/5 * * * *)        │
│  ├── bluebox-complete-rentals  (*/15 * * * *)       │
│  └── ... (maintenance jobs, daily/weekly)           │
│                                                     │
│  Grafana (from Exercise 4)                          │
│  └── ASH dashboard shows rental INSERT/UPDATE       │
│      activity grouped by query or wait_event        │
└─────────────────────────────────────────────────────┘
         ↑ loaded via pg_dump | psql
┌────────────────────────────────┐
│  Docker (local, temporary)     │
│  ghcr.io/ryanbooz/bluebox-     │
│  postgres:18                   │
│  └── Initializes full dataset  │
│      including rental backfill │
└────────────────────────────────┘
```

## Step 1: Add the PostGIS Extension Container

The bluebox schema uses PostGIS `geography` types for customer and store
locations. We add PostGIS to pg-eu using CNPG's image-volume extension
mechanism — a separate OCI image mounted as a read-only volume, no custom
PostgreSQL image required.

### Apply the patch

This patch builds on top of Exercise 4's patch (pgsentinel must already be in
the extensions list):

```bash
cd ~/cnpg-playground
patch -p1 < lab/exercise-8-bluebox-ash/pg-eu-bluebox.yaml.patch
```

Verify the changes:

```bash
git diff demo/yaml/eu/pg-eu.yaml
```

You should see the `postgis` extension container added below `pgsentinel`:

```yaml
    extensions:
      - name: pgsentinel
        image:
          reference: ghcr.io/ardentperf/pgsentinel:1.3.1-18-trixie
      - name: postgis
        image:
          reference: ghcr.io/cloudnative-pg/postgis-extension:3.6.2-18-trixie
        ld_library_path:
          - system
```

The `ld_library_path: [system]` entry is required for PostGIS because it
depends on system libraries (GEOS, GDAL, PROJ) that live outside the extension
directory.

### Apply and wait for rolling restart

```bash
k apply -f demo/yaml/eu/pg-eu.yaml
k wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
k wait --timeout 5m  --for=condition=Ready cluster/pg-eu
```

### Verify PostGIS is available

```bash
kc psql pg-eu -- -c "SELECT name, default_version FROM pg_available_extensions WHERE name = 'postgis';"
```

You should see `postgis` listed with a version number (3.6.x). The extension
is not yet *installed* (no `CREATE EXTENSION` yet) — that happens as part of
the bluebox schema restore in Step 3.

> **Image version note:** `3.6.2-18-trixie` is the version at time of writing.
> To find the latest tag, check the
> [postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers)
> repository.

## Step 2: Initialize Bluebox Locally

Bluebox's Docker image (`ghcr.io/ryanbooz/bluebox-postgres:18`) bundles all
initialization SQL and compressed data files. When started, it runs PostgreSQL,
executes the init scripts (schema, reference data, customer data, inventory,
historical rentals, and a backfill to bring rental history up to yesterday),
and then becomes ready for connections.

We run it locally to let it initialize, then dump the result into pg-eu.

### Pull and start the container

```bash
docker run -d --name bluebox-loader \
  -e POSTGRES_PASSWORD=password \
  ghcr.io/ryanbooz/bluebox-postgres:18
```

### Monitor initialization progress

```bash
docker logs -f bluebox-loader
```

You will see the init scripts running in order:

```
running /docker-entrypoint-initdb.d/01-create-roles-and-database.sql
...
running /docker-entrypoint-initdb.d/09-backfill-rental-data.sql
```

The backfill script (`09-backfill-rental-data.sql`) generates rental records
from the last date in the sample data through yesterday. This is the slowest
step — **expect 5–15 minutes** depending on the gap.

### Wait for the container to be healthy

```bash
until docker exec bluebox-loader pg_isready -U postgres -d bluebox -q; do
  echo "Waiting for bluebox to be ready..."
  sleep 10
done
echo "Bluebox is ready"
```

> **Note:** `pg_isready` returns success as soon as PostgreSQL accepts
> connections, which happens only after all init scripts complete. If the
> container exits with an error, check `docker logs bluebox-loader`.

## Step 3: Load Bluebox into pg-eu

With bluebox initialized locally and pg-eu ready with PostGIS, we dump the
`bluebox` database and restore it into pg-eu.

### Create roles and database on pg-eu

The `pg_dump` of a single database does not include role definitions (those are
cluster-global). Create them first:

```bash
kc psql pg-eu < lab/exercise-8-bluebox-ash/bluebox-preload.sql
```

Verify the database was created:

```bash
kc psql pg-eu -- -c "\l bluebox"
```

### Port-forward the pg-eu primary

```bash
kubectl port-forward service/pg-eu-rw 15432:5432 &
PF_PID=$!
sleep 2
```

### Retrieve the superuser password

```bash
PGPASSWORD=$(kubectl get secret pg-eu-superuser \
  -o jsonpath='{.data.password}' | base64 -d)
```

### Dump and restore

```bash
docker exec bluebox-loader \
  pg_dump -U postgres -d bluebox --no-owner --no-acl \
  | PGPASSWORD="$PGPASSWORD" psql \
      -h localhost -p 15432 \
      -U postgres -d bluebox
```

This may take a few minutes depending on the size of the backfill. You will
see psql output as each object is restored.

### Stop the port-forward and clean up the local container

```bash
kill $PF_PID 2>/dev/null || true
docker rm -f bluebox-loader
```

### Verify the restore

```bash
kc psql pg-eu -- -d bluebox -c "
SELECT
  schemaname,
  tablename,
  n_live_tup AS row_count
FROM pg_stat_user_tables
WHERE schemaname = 'bluebox'
ORDER BY n_live_tup DESC;
"
```

You should see all bluebox tables with row counts. Key ones to check:

| Table | Expected rows |
|---|---|
| `bluebox.film` | ~5,000 |
| `bluebox.customer` | ~10,000 |
| `bluebox.inventory` | ~70,000 |
| `bluebox.rental` | hundreds of thousands (includes backfill) |

Also verify PostGIS was installed by the schema restore:

```bash
kc psql pg-eu -- -d bluebox -c "SELECT PostGIS_Version();"
```

## Step 4: Deploy Kubernetes CronJobs

Bluebox normally uses `pg_cron` to schedule its stored procedures. Since
CloudNativePG's standard PostgreSQL 18 image does not include `pg_cron`, we
use Kubernetes CronJobs instead. The same stored procedures are called on the
same schedule — the only difference is the scheduler lives outside the
database.

```bash
k apply -f lab/exercise-8-bluebox-ash/bluebox-cronjobs.yaml
```

Verify all six CronJobs are created:

```bash
k get cronjobs -l app=bluebox-cronjobs
```

```
NAME                          SCHEDULE      LAST SCHEDULE   ACTIVE
bluebox-generate-rentals      */5 * * * *   <none>          0
bluebox-complete-rentals      */15 * * * *  <none>          0
bluebox-process-lost          0 2 * * *     <none>          0
bluebox-customer-activity     0 3 * * *     <none>          0
bluebox-rebalance-inventory   0 4 * * 0     <none>          0
bluebox-analyze-tables        0 1 * * *     <none>          0
```

Wait for the first `generate-rentals` run (up to 5 minutes from now), then
check it succeeded:

```bash
k get jobs -l job=generate-rentals
k logs -l job=generate-rentals --tail=20
```

### Manually trigger a rental run

You don't have to wait — trigger a job immediately to verify the functions work:

```bash
kubectl create job --from=cronjob/bluebox-generate-rentals bluebox-gen-test
kubectl wait --timeout 2m --for=condition=Complete job/bluebox-gen-test
kubectl logs job/bluebox-gen-test
kubectl delete job bluebox-gen-test
```

You should see output from `generate_rentals()` confirming new rental records
were inserted.

## Step 5: Visualize the Workload in ASH

With bluebox running and CronJobs firing every 5 minutes, open the ASH
dashboard from Exercise 4 in Grafana.

Open Grafana (`http://localhost:3000` or the Grafana-EU bookmark in Firefox)
and navigate to the ASH dashboard.

### What to look for

Every 5 minutes when `generate_rentals()` runs, pgsentinel captures the
active session doing multi-table INSERTs and UPDATEs across the rental,
payment, and inventory tables. Between runs, the session count drops back to
near zero.

**Recommended views:**

- **Group By: `query`** — See the `INSERT INTO bluebox.rental` and related
  statements during each rental generation burst. The first 40 characters of
  each query text are shown.

- **Group By: `wait_event`** — During rental generation you will see `CPU`
  wait events (active computation) and potentially `Lock` or `IO` waits
  during the multi-table transaction.

- **Group By: `application_name`** — The CronJob pods connect with
  `application_name = psql`, making it easy to distinguish bluebox activity
  from other connections.

- **Filter Field: `query`, Filter Text: `rental`** — Show only sessions
  touching rental tables.

**Tip:** Zoom into a 5-minute window around the time a CronJob fires to see
the spike clearly. The "Max Active Sessions" panel is especially useful for
catching short-lived bursts.

## Understanding the Workload

Bluebox's `generate_rentals()` procedure:
1. Selects available inventory items across stores
2. Inserts new records into `bluebox.rental` (using a range type for the
   rental period)
3. Creates corresponding `bluebox.payment` records
4. Updates `bluebox.inventory` availability

This produces a burst of concurrent DML touching three tables, which is
exactly the kind of workload where ASH's per-second sampling shows more than
a once-per-minute metric would.

The `complete_rentals()` procedure (every 15 minutes) closes out open rentals
older than 16 hours, producing UPDATE activity on the rental table.

## Exploring the Schema in pgAdmin

With pgAdmin running from Exercise 7, register a connection to the `bluebox`
database and browse the schema visually.

### Connect pgAdmin to the bluebox database

The `pg-eu` server is already pre-registered in pgAdmin from Exercise 7, but
it points to the `postgres` maintenance database. Add a second entry for
`bluebox`:

1. If pgAdmin is not yet port-forwarded, start it:

```bash
k port-forward service/pgadmin4 8090:80
```

2. Open `http://localhost:8090`, log in (`admin@pgadmin.org` / `admin`)
3. In the sidebar, right-click **Servers** → **Register** → **Server**
4. **General tab** → Name: `pg-eu (bluebox)`
5. **Connection tab:**
   - Host: `pg-eu-rw`
   - Port: `5432`
   - Maintenance database: `bluebox`
   - Username: `postgres`
   - Password: retrieve with:

```bash
kubectl get secret pg-eu-superuser \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

6. Click **Save**

### Browse the schema

Expand **pg-eu bluebox** → `bluebox` → **Schemas** → `bluebox` → **Tables**
to see the full schema: `film`, `rental`, `payment`, `customer`, `inventory`,
and supporting tables.

Open the **Query Tool** and explore the rental data:

```sql
-- Most recently created rentals
SELECT r.rental_id,
       c.first_name || ' ' || c.last_name AS customer,
       f.title AS film,
       r.rental_period
FROM   bluebox.rental r
JOIN   bluebox.inventory i ON i.inventory_id = r.inventory_id
JOIN   bluebox.film f ON f.film_id = i.film_id
JOIN   bluebox.customer c ON c.customer_id = r.customer_id
ORDER  BY lower(r.rental_period) DESC
LIMIT  20;
```

## Cleaning Up

To remove bluebox and the CronJobs (while leaving pg-eu and pgsentinel intact):

```bash
# Remove CronJobs
k delete -f lab/exercise-8-bluebox-ash/bluebox-cronjobs.yaml

# Drop the bluebox database and roles
kc psql pg-eu -- -c "DROP DATABASE bluebox;"
kc psql pg-eu -- -c "DROP USER bb_admin; DROP USER bb_app;"
kc psql pg-eu -- -c "DROP ROLE bluebox_admin; DROP ROLE bluebox_app;"
```

To revert the PostGIS extension container patch:

```bash
git checkout demo/yaml/eu/pg-eu.yaml
k apply -f demo/yaml/eu/pg-eu.yaml
k wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
```

## Automation Script

After you have learned how the exercise works through the manual steps, the
automation script runs the full end-to-end setup:

```bash
cd ~/cnpg-playground
bash lab/exercise-8-bluebox-ash/test-bluebox-setup.sh
```

The script automates all steps:
- Applies the PostGIS extension container patch and waits for the rolling
  restart
- Starts the bluebox Docker container and waits for full initialization
- Creates bluebox roles/database on pg-eu and restores via pg_dump | psql
- Deploys the Kubernetes CronJobs
- Triggers a manual rental generation run to verify the functions work
- Checks row counts and prints final instructions

Output is logged to `bluebox-test_<timestamp>.log`.
