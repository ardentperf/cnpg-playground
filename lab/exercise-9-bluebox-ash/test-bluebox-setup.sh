#!/bin/bash
#
# This script automates the setup and verification of Exercise 9: Bluebox
# Workload on CNPG with ASH Visualization.
#
# It performs the following steps:
#   1. Apply the PostGIS extension container patch to pg-eu
#   2. Wait for the rolling restart to complete
#   3. Start the bluebox Docker container and wait for full initialization
#   4. Create bluebox roles and database on pg-eu
#   5. Dump the bluebox database from Docker and restore into pg-eu
#   6. Clean up the Docker container
#   7. Deploy Kubernetes CronJobs for rental generation
#   8. Trigger a manual rental run and verify it succeeds
#   9. Print row counts and final instructions
#
# Prerequisites:
#   - CNPG Playground is running with pg-eu cluster available
#   - Exercise 4 (ASH Monitoring) must be complete
#   - kubectl context is set to kind-k8s-eu
#   - Docker is available
#   - psql client is available on this host
#
# Usage:
#   cd ~/cnpg-playground
#   bash lab/exercise-9-bluebox-ash/test-bluebox-setup.sh
#
# Output is logged to bluebox-test_<timestamp>.log
#

set -euo pipefail

LOG_FILE="bluebox-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Bluebox + ASH Setup Test"
echo "Started at $(date)"
echo "=========================================="
echo ""

# Change to playground root
cd "$(dirname "$(echo "$KUBECONFIG")")/.."
echo "Working directory: $(pwd)"
echo ""

# ── Context check ─────────────────────────────────────────────────────────────
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current kubectl context: $CURRENT_CONTEXT"
if [ "$CURRENT_CONTEXT" != "kind-k8s-eu" ]; then
  echo "WARNING: Expected context 'kind-k8s-eu', got '$CURRENT_CONTEXT'. Switching..."
  kubectl config use-context kind-k8s-eu
fi
echo ""

# ── Prerequisite checks ────────────────────────────────────────────────────────
echo "Checking prerequisites..."

# Docker
if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found. Docker is required to load the bluebox dataset."
  exit 1
fi
echo "  ✓ Docker is available"

# psql client on host
if ! command -v psql &>/dev/null; then
  echo "ERROR: psql client not found on this host."
  exit 1
fi
echo "  ✓ psql client is available"

# pg-eu cluster ready
if ! kubectl wait --timeout 2m --for=condition=Ready cluster/pg-eu &>/dev/null; then
  echo "ERROR: pg-eu cluster is not ready. Ensure Exercise 2 is complete."
  exit 1
fi
echo "  ✓ pg-eu cluster is ready"

# pgsentinel (Exercise 4 prerequisite)
if ! kubectl cnpg psql pg-eu -- -qAt -c "SELECT 1 FROM pg_extension WHERE extname='pgsentinel'" 2>/dev/null | grep -q 1; then
  echo "ERROR: pgsentinel extension not found. Complete Exercise 4 before this exercise."
  exit 1
fi
echo "  ✓ pgsentinel is installed (Exercise 4 complete)"
echo ""

# ── Step 1: Apply PostGIS patch ────────────────────────────────────────────────
echo "=========================================="
echo "Step 1: Apply PostGIS extension container patch"
echo "=========================================="
echo ""

if grep -q "postgis-extension" demo/yaml/eu/pg-eu.yaml; then
  echo "PostGIS extension container already in pg-eu.yaml — skipping patch"
  PATCH_APPLIED=true
else
  echo "Applying pg-eu-bluebox.yaml.patch..."
  if patch -p1 < lab/exercise-9-bluebox-ash/pg-eu-bluebox.yaml.patch; then
    echo "Patch applied successfully"
    PATCH_APPLIED=false
  else
    echo "ERROR: Failed to apply patch. Ensure Exercise 4's patch has been applied first."
    exit 1
  fi
fi

echo ""
echo "Applying pg-eu cluster configuration..."
kubectl apply -f demo/yaml/eu/pg-eu.yaml
echo ""

echo "Waiting for pg-eu pods to be ready (rolling restart, may take several minutes)..."
kubectl wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
kubectl wait --timeout 5m  --for=condition=Ready cluster/pg-eu
echo "pg-eu cluster is ready"
echo ""

# Verify PostGIS extension is available (not yet installed, just available)
echo "Verifying PostGIS is available in pg-eu..."
POSTGIS_AVAILABLE=$(kubectl cnpg psql pg-eu -- -qAt \
  -c "SELECT count(*) FROM pg_available_extensions WHERE name='postgis'" 2>/dev/null || echo "0")
if [ "$POSTGIS_AVAILABLE" = "0" ] || [ -z "$POSTGIS_AVAILABLE" ]; then
  echo "ERROR: PostGIS extension is not available. Check that the extension container image was pulled."
  echo "  Try: kubectl describe pod -l cnpg.io/cluster=pg-eu"
  exit 1
fi
echo "  ✓ PostGIS is available as an extension"
echo ""

# ── Step 2: Start bluebox Docker container ─────────────────────────────────────
echo "=========================================="
echo "Step 2: Initialize bluebox via Docker"
echo "=========================================="
echo ""

CONTAINER_NAME="bluebox-loader"
BLUEBOX_IMAGE="ghcr.io/ryanbooz/bluebox-postgres:18"

# Clean up any prior failed run
if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
  echo "Removing existing '$CONTAINER_NAME' container..."
  docker rm -f "$CONTAINER_NAME"
fi

echo "Starting bluebox container: $BLUEBOX_IMAGE"
echo "(This will pull the image on first run — may take a few minutes)"
docker run -d --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD=password \
  "$BLUEBOX_IMAGE"
echo ""

echo "Waiting for bluebox to initialize..."
echo "This includes loading schema, all data files, and backfilling rental history."
echo "Expect 5–15 minutes. Follow progress with: docker logs -f $CONTAINER_NAME"
echo ""

WAIT_LIMIT=1200  # 20 minutes
WAITED=0
while true; do
  # pg_isready succeeds during init while init scripts are still running.
  # We also check that the rental table has rows, which only happens after
  # all init scripts (including the backfill) have completed.
  if docker exec "$CONTAINER_NAME" pg_isready -U postgres -d bluebox -q 2>/dev/null; then
    RENTAL_ROWS=$(docker exec "$CONTAINER_NAME" \
      psql -U postgres -d bluebox -qAt -c "SELECT count(*) FROM bluebox.rental" 2>/dev/null || echo "0")
    if [ "$RENTAL_ROWS" -gt 0 ] 2>/dev/null; then
      echo "Bluebox is fully initialized! (${WAITED}s elapsed, ${RENTAL_ROWS} rentals)"
      break
    fi
  fi

  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
  if [ "$CONTAINER_STATUS" = "exited" ] || [ "$CONTAINER_STATUS" = "dead" ]; then
    echo "ERROR: bluebox container exited unexpectedly."
    echo "Check logs: docker logs $CONTAINER_NAME"
    exit 1
  fi

  if [ "$WAITED" -ge "$WAIT_LIMIT" ]; then
    echo "ERROR: Timed out waiting for bluebox after ${WAIT_LIMIT}s."
    echo "Check logs: docker logs $CONTAINER_NAME"
    exit 1
  fi

  sleep 15
  WAITED=$((WAITED + 15))
  echo "  Still waiting... (${WAITED}s / ${WAIT_LIMIT}s)"
done
echo ""

# Quick sanity check (RENTAL_ROWS already captured in the wait loop above)
echo "  ✓ bluebox.rental table has $RENTAL_ROWS rows (includes backfill)"
echo ""

# ── Step 3: Load bluebox into pg-eu ───────────────────────────────────────────
echo "=========================================="
echo "Step 3: Load bluebox into pg-eu"
echo "=========================================="
echo ""

# Check if already loaded
BLUEBOX_DB_EXISTS=$(kubectl cnpg psql pg-eu -- -qAt \
  -c "SELECT 1 FROM pg_database WHERE datname='bluebox'" 2>/dev/null || echo "")
if [ "$BLUEBOX_DB_EXISTS" = "1" ]; then
  echo "bluebox database already exists on pg-eu — skipping load"
  SKIP_LOAD=true
else
  SKIP_LOAD=false
fi

if [ "$SKIP_LOAD" = false ]; then
  # Create roles and database
  echo "Creating bluebox roles and database on pg-eu..."
  kubectl cnpg psql pg-eu < lab/exercise-9-bluebox-ash/bluebox-preload.sql
  echo "  ✓ Roles and database created"
  echo ""

  # Find the primary pod (peer auth allows password-free psql from within the pod)
  PRIMARY_POD=$(kubectl get pod \
    -l "cnpg.io/cluster=pg-eu,cnpg.io/instanceRole=primary" \
    -o name | head -1)
  if [ -z "$PRIMARY_POD" ]; then
    echo "ERROR: Could not find primary pg-eu pod."
    exit 1
  fi
  echo "Primary pod: $PRIMARY_POD"
  echo ""

  # Dump and restore via kubectl exec -i (avoids port-forward instability in KIND)
  echo "Dumping bluebox from Docker container and restoring into pg-eu..."
  echo "(This may take several minutes for the large rental/payment tables)"
  docker exec "$CONTAINER_NAME" \
    pg_dump -U postgres -d bluebox --no-owner --no-acl \
    | kubectl exec -i "$PRIMARY_POD" -- \
        psql -U postgres -d bluebox

  echo ""
  echo "  ✓ Restore complete"
fi
echo ""

# Remove local container
echo "Removing bluebox Docker container..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
echo "  ✓ Container removed"
echo ""

# Verify row counts
echo "Verifying bluebox data on pg-eu..."
kubectl cnpg psql pg-eu -- -d bluebox -c "
SELECT schemaname, tablename, n_live_tup AS row_count
FROM   pg_stat_user_tables
WHERE  schemaname = 'bluebox'
ORDER  BY n_live_tup DESC;" 2>/dev/null || \
kubectl cnpg psql pg-eu -- -d bluebox -c "
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM   pg_tables WHERE schemaname = 'bluebox' ORDER BY tablename;"
echo ""

# Verify PostGIS was installed by the schema restore
POSTGIS_INSTALLED=$(kubectl cnpg psql pg-eu -- -d bluebox -qAt \
  -c "SELECT count(*) FROM pg_extension WHERE extname='postgis'" 2>/dev/null || echo "0")
if [ "$POSTGIS_INSTALLED" = "1" ]; then
  echo "  ✓ PostGIS extension is installed in the bluebox database"
else
  echo "  WARNING: PostGIS not found in bluebox database — schema restore may have had issues"
fi
echo ""

# ── Step 4: Deploy CronJobs ───────────────────────────────────────────────────
echo "=========================================="
echo "Step 4: Deploy Kubernetes CronJobs"
echo "=========================================="
echo ""

kubectl apply -f lab/exercise-9-bluebox-ash/bluebox-cronjobs.yaml
echo ""

echo "Waiting for CronJobs to be registered..."
sleep 5
kubectl get cronjobs -l app=bluebox-cronjobs
echo ""

# ── Step 5: Verify rental generation ──────────────────────────────────────────
echo "=========================================="
echo "Step 5: Verify rental generation functions"
echo "=========================================="
echo ""

echo "Triggering a manual rental generation run to verify the stored procedure..."
TEST_JOB="bluebox-gen-verify-$(date +%s)"
kubectl create job --from=cronjob/bluebox-generate-rentals "$TEST_JOB"
echo "Waiting for job to complete (up to 3 minutes)..."

if kubectl wait --timeout 3m --for=condition=Complete "job/$TEST_JOB" 2>/dev/null; then
  echo "  ✓ generate_rentals procedure ran successfully"
  echo ""
  echo "Job output:"
  kubectl logs "job/$TEST_JOB" | head -20
else
  echo "  WARNING: generate_rentals job did not complete in time."
  echo "  Checking pod status for errors..."
  kubectl get pods -l "job-name=$TEST_JOB" 2>/dev/null
  kubectl logs "job/$TEST_JOB" 2>/dev/null | tail -10
fi
kubectl delete job "$TEST_JOB" --ignore-not-found &>/dev/null
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=========================================="
echo "Bluebox Setup Complete!"
echo "=========================================="
echo ""
echo "What's running:"
echo "  - PostGIS extension container: ghcr.io/cloudnative-pg/postgis-extension:3.6.2-18-trixie"
echo "  - bluebox database loaded into pg-eu"
echo "  - 6 Kubernetes CronJobs scheduled (generate-rentals runs every 5 minutes)"
echo ""
echo "Next steps:"
echo ""
echo "1. Watch rental generation in the ASH dashboard:"
echo "   - Open Grafana: http://localhost:3000"
echo "   - Navigate to the ASH dashboard (imported in Exercise 4)"
echo "   - Set 'Group By' to 'query' or 'wait_event'"
echo "   - Wait for the next CronJob run (up to 5 minutes)"
echo "   - Zoom in on a 5-minute window to see the rental burst"
echo ""
echo "2. Explore the schema in pgAdmin:"
echo "   - If pgAdmin is running (Exercise 7), connect to the bluebox database"
echo "   - Browse bluebox schema tables: film, rental, payment, customer, inventory"
echo ""
echo "3. Check CronJob status anytime:"
echo "   kubectl get cronjobs -l app=bluebox-cronjobs"
echo "   kubectl get jobs | grep bluebox"
echo ""
echo "Log file: $LOG_FILE"
echo "Completed at $(date)"
