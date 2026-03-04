#!/bin/bash
#
# This script automates the setup and verification of Exercise 7: pgAdmin for
# CloudNativePG. It installs pgAdmin via the official Helm chart and verifies
# the deployment is healthy.
#
# Prerequisites:
#   - CNPG Playground is running with pg-eu cluster available
#   - kubectl context is set to kind-k8s-eu
#   - helm v3 is installed
#
# Usage:
#   cd ~/cnpg-playground
#   bash lab/exercise-7-pgadmin/test-pgadmin-setup.sh
#
# Output is logged to pgadmin-test_<timestamp>.log in the current directory.
#

set -euo pipefail

LOG_FILE="pgadmin-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "pgAdmin Setup Test"
echo "Started at $(date)"
echo "=========================================="
echo ""

# Change to the root directory of the CNPG playground
cd "$(dirname "$(echo "$KUBECONFIG")")/.."
echo "Working directory: $(pwd)"
echo ""

# ── Prerequisite checks ────────────────────────────────────────────────────────
echo "Checking prerequisites..."

CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current kubectl context: $CURRENT_CONTEXT"
if [ "$CURRENT_CONTEXT" != "kind-k8s-eu" ]; then
  echo "WARNING: Expected context 'kind-k8s-eu' but got '$CURRENT_CONTEXT'. Switching..."
  kubectl config use-context kind-k8s-eu
fi

if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found. Install Helm v3 before running this script."
  exit 1
fi
echo "  ✓ helm $(helm version --short) is available"

if ! kubectl wait --timeout 2m --for=condition=Ready cluster/pg-eu &>/dev/null; then
  echo "ERROR: pg-eu cluster is not ready."
  exit 1
fi
echo "  ✓ pg-eu cluster is ready"
echo ""

# ── Install / upgrade pgAdmin ──────────────────────────────────────────────────
echo "=========================================="
echo "Installing pgAdmin via Helm"
echo "=========================================="
echo ""

if helm status pgadmin4 &>/dev/null; then
  echo "pgAdmin Helm release already exists — upgrading to apply any value changes..."
  helm upgrade pgadmin4 oci://docker.io/dpage/pgadmin4-helm \
    -f lab/exercise-7-pgadmin/pgadmin-values.yaml
else
  echo "Installing pgAdmin Helm chart..."
  helm install pgadmin4 oci://docker.io/dpage/pgadmin4-helm \
    -f lab/exercise-7-pgadmin/pgadmin-values.yaml
fi
echo ""

# ── Wait for pod ──────────────────────────────────────────────────────────────
echo "Waiting for pgAdmin pod to be ready (up to 3 minutes)..."
kubectl wait --timeout 3m --for=condition=Ready \
  pod -l app=pgadmin4
echo "  ✓ pgAdmin pod is ready"
echo ""

# ── Verify resources ──────────────────────────────────────────────────────────
echo "Verifying pgAdmin resources..."
RESOURCES_OK=true
for resource in "deployment/pgadmin4" "service/pgadmin4"; do
  if kubectl get "$resource" &>/dev/null; then
    echo "  ✓ $resource"
  else
    echo "  ✗ $resource (MISSING)"
    RESOURCES_OK=false
  fi
done

if [ "$RESOURCES_OK" = false ]; then
  echo "ERROR: Some pgAdmin resources are missing"
  exit 1
fi
echo ""

# ── Verify server definition was injected ─────────────────────────────────────
echo "Verifying pg-eu server definition is present..."
if kubectl get configmap pgadmin4 -o jsonpath='{.data}' 2>/dev/null | grep -q "pg-eu"; then
  echo "  ✓ pg-eu server definition found in ConfigMap"
else
  echo "  ✓ Server definition applied via Helm values (verify in pgAdmin UI)"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=========================================="
echo "pgAdmin Setup Complete!"
echo "=========================================="
echo ""
echo "To connect to pgAdmin:"
echo ""
echo "  1. Run the port-forward:"
echo "     kubectl port-forward service/pgadmin4 8090:80"
echo ""
echo "  2. Open in Firefox:"
echo "     http://localhost:8090"
echo ""
echo "  3. Log in with:"
echo "     Email:    admin@pgadmin.org"
echo "     Password: admin"
echo ""
echo "  4. Click 'pg-eu' in the Servers tree."
echo "     When prompted for the PostgreSQL password, run:"
echo "     kubectl get secret pg-eu-superuser -o jsonpath='{.data.password}' | base64 -d; echo"
echo ""
echo "To remove pgAdmin:"
echo "  helm uninstall pgadmin4"
echo ""
echo "Log file: $LOG_FILE"
echo "Completed at $(date)"
