#!/bin/bash
#
# This script automates the setup and execution of Exercise 4: Active Session
# History (ASH) Monitoring. It configures the pg-eu cluster with the pgsentinel
# extension, creates the necessary SQL functions, applies Prometheus custom
# queries, and runs a pgbench workload to generate ASH data.
#
# The script is idempotent and can be re-run safely. It will check if the patch
# has already been applied and skip that step if needed.
#
# Prerequisites:
#   - CNPG Playground is running with pg-eu cluster available
#   - kubectl context is set to kind-k8s-eu
#   - kubectl cnpg plugin is installed
#
# Usage:
#   cd ~/cnpg-playground
#   bash lab/exercise-4-active-session-history/test-ash-setup.sh
#
# The script will:
#   1. Apply the PostgreSQL cluster configuration patch
#   2. Wait for the cluster to restart and be ready
#   3. Create the sanitize_sql and pgsentinel_poll_ash_data functions
#   4. Apply the Prometheus custom queries ConfigMap
#   5. Initialize pgbench with scale factor 100
#   6. Run pgbench workload for 5 minutes
#   7. Provide instructions for importing the Grafana dashboard
#
# Output is logged to ash-test_<timestamp>.log in the current directory.
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Create a log file with timestamp in the current directory
LOG_FILE="ash-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Print header with test information
echo "=========================================="
echo "ASH Monitoring Setup Test"
echo "Started at $(date)"
echo "=========================================="
echo ""

# Change to the root directory of the CNPG playground
cd $(dirname $(echo $KUBECONFIG))/..
echo "Working directory: $(pwd)"
echo ""

# Print the status & diff of the git tree (this will be included in the log)
echo "Git status:"
git status
echo ""
echo "Git diff:"
git diff
echo ""

# Verify we're using the correct context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current kubectl context: $CURRENT_CONTEXT"
if [ "$CURRENT_CONTEXT" != "kind-k8s-eu" ]; then
  echo "WARNING: Expected context 'kind-k8s-eu' but got '$CURRENT_CONTEXT'"
  echo "Switching context..."
  kubectl config use-context kind-k8s-eu
fi
echo ""

# Optional: Delete the US cluster to free up resources
echo "Checking for pg-us cluster..."
if kubectl get cluster pg-us --context kind-k8s-us &>/dev/null; then
  echo "Deleting pg-us cluster to free up CPU resources..."
  kubectl delete cluster pg-us --context kind-k8s-us --wait=false || true
  echo "Deletion initiated (running in background)"
else
  echo "pg-us cluster not found, skipping deletion"
fi
echo ""

# Check if the patch has already been applied
echo "Checking if pg-eu.yaml patch is already applied..."
if grep -q "pgsentinel" demo/yaml/eu/pg-eu.yaml; then
  echo "Patch already applied (pgsentinel found in pg-eu.yaml)"
  PATCH_APPLIED=true
else
  echo "Patch not yet applied, will apply now"
  PATCH_APPLIED=false
fi
echo ""

# Apply the patch if needed
if [ "$PATCH_APPLIED" = false ]; then
  echo "Applying patch to demo/yaml/eu/pg-eu.yaml..."
  if patch -p1 < lab/exercise-4-active-session-history/pg-eu.yaml.patch; then
    echo "Patch applied successfully"
  else
    echo "ERROR: Failed to apply patch"
    exit 1
  fi
  
  echo ""
  echo "Patch changes:"
  git diff demo/yaml/eu/pg-eu.yaml
  echo ""
else
  echo "Skipping patch application (already applied)"
  echo ""
fi

# Apply the modified cluster configuration
echo "Applying modified pg-eu cluster configuration..."
kubectl apply -f demo/yaml/eu/pg-eu.yaml
echo ""

# Wait for the cluster to restart and be ready
echo "Waiting for pg-eu cluster pods to be ready (this may take several minutes)..."
kubectl wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
echo "All pg-eu pods are ready"
echo ""

# Wait for the cluster condition to be ready
echo "Waiting for pg-eu cluster to be ready..."
kubectl wait --timeout 5m --for=condition=Ready cluster/pg-eu
echo "Cluster pg-eu is ready"
echo ""

# Create the sanitize_sql function
echo "Creating sanitize_sql function..."
if kubectl cnpg psql pg-eu < lab/exercise-4-active-session-history/sanitize_sql.sql; then
  echo "sanitize_sql function created successfully"
else
  echo "Note: sanitize_sql function creation had warnings (may already exist)"
fi
echo ""

# Create the pgsentinel_poll_ash_data function
echo "Creating pgsentinel_poll_ash_data function..."
if kubectl cnpg psql pg-eu < lab/exercise-4-active-session-history/pgsentinel_poll_ash_data.sql; then
  echo "pgsentinel_poll_ash_data function created successfully"
else
  echo "Note: pgsentinel_poll_ash_data function creation had warnings (may already exist)"
fi
echo ""

# Apply the Prometheus custom queries ConfigMap
echo "Applying Prometheus custom queries ConfigMap..."
kubectl apply -f lab/exercise-4-active-session-history/ash-top-sessions.yaml
echo ""

# Wait a moment for the metrics exporter to restart
echo "Waiting 30 seconds for metrics exporter to restart and begin collecting ASH data..."
sleep 30
echo ""

# Verify the setup
echo "Verifying pgsentinel extension is installed..."
kubectl cnpg psql pg-eu -- -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pgsentinel';"
echo ""

echo "Checking for ASH data (may be empty if no activity yet)..."
kubectl cnpg psql pg-eu -- -c "SELECT COUNT(*) as ash_sample_count FROM pg_active_session_history;"
echo ""

# Initialize pgbench
echo "=========================================="
echo "Initializing pgbench with scale factor 100..."
echo "This will create ~10 million rows and may take several minutes"
echo "=========================================="
echo ""
kubectl cnpg pgbench pg-eu -- -i --scale 100

echo ""
echo "Waiting for pgbench initialization to complete..."
echo "Checking status every 10 seconds..."
while true; do
  POD_STATUS=$(kubectl get pods -l cnpg.io/jobRole=pgbench -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [ "$POD_STATUS" = "Succeeded" ] || [ "$POD_STATUS" = "Completed" ]; then
    echo "pgbench initialization complete"
    break
  elif [ "$POD_STATUS" = "Failed" ]; then
    echo "ERROR: pgbench initialization failed"
    kubectl get pods -l cnpg.io/jobRole=pgbench
    exit 1
  fi
  sleep 10
done
echo ""

# Run pgbench workload
echo "=========================================="
echo "Running pgbench workload for 5 minutes..."
echo "Parameters: 4 clients, 4 jobs, 100 TPS rate limit"
echo "=========================================="
echo ""
echo "While pgbench is running, you can:"
echo "  1. Open Grafana (bookmark in Firefox or http://localhost:3000)"
echo "  2. Import the ASH dashboard from:"
echo "     lab/exercise-4-active-session-history/ash-top-sessions-dashboard.json"
echo "  3. Watch the active sessions appear in real-time"
echo ""
echo "Starting pgbench in 5 seconds..."
sleep 5
echo ""

kubectl cnpg pgbench pg-eu -- --client=4 --jobs=4 --rate=100 --progress=1 --time=300

echo ""
echo "=========================================="
echo "pgbench workload completed"
echo "=========================================="
echo ""

# Check ASH data after workload
echo "Checking ASH data collected during workload..."
kubectl cnpg psql pg-eu -- -c "SELECT COUNT(*) as total_samples FROM pg_active_session_history;"
echo ""

# Print final instructions
echo "=========================================="
echo "ASH Monitoring Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Import the Grafana dashboard:"
echo "   - Open Grafana at http://localhost:3000 (login: admin/admin)"
echo "   - Navigate to Dashboards > Import"
echo "   - Upload: lab/exercise-4-active-session-history/ash-top-sessions-dashboard.json"
echo "   - Select your Prometheus datasource and click Import"
echo ""
echo "2. Explore the dashboard:"
echo "   - Use the 'Group By' dropdown to change dimensions (wait_event, query, etc.)"
echo "   - Use 'Filter Field' and 'Filter Text' to filter specific sessions"
echo "   - The dashboard shows the last 5 minutes by default"
echo ""
echo "3. Review ASH data via SQL:"
echo "   kubectl cnpg psql pg-eu -- -c \"SELECT * FROM pg_active_session_history ORDER BY ash_time DESC LIMIT 10;\""
echo ""
echo "Log file: $LOG_FILE"
echo "Completed at $(date)"
echo ""
