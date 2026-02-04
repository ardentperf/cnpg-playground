#!/bin/bash
#
# This script automates the setup and execution of Exercise 5: PgBouncer
# Connection Pooling with mTLS Certificate Authentication. It configures
# a three-tier PKI using cert-manager (simulating external CA integration),
# applies certificate-based authentication to the pg-eu cluster, deploys
# PgBouncer with mTLS, and tests connectivity using both psql and pgbench.
#
# The script is idempotent and can be re-run safely. It will check if the
# patch has already been applied and skip that step if needed.
#
# Prerequisites:
#   - CNPG Playground is running with pg-eu cluster available
#   - kubectl context is set to kind-k8s-eu
#   - cert-manager is installed and running
#
# Usage:
#   cd ~/cnpg-playground
#   bash lab/exercise-5-pgbouncer-mtls/test-pgbouncer-mtls-setup.sh
#
# The script will:
#   1. Apply cert-manager certificates (3-tier PKI)
#   2. Wait for all certificates to be ready
#   3. Apply the PostgreSQL cluster configuration patch
#   4. Wait for the cluster to restart and be ready
#   5. Deploy the PgBouncer pooler with mTLS
#   6. Wait for the pooler to be ready
#   7. Test psql connection through pooler with mTLS
#   8. Initialize pgbench through pooler with mTLS
#   9. Run pgbench workload through pooler with mTLS
#   10. Test negative case (connection without certificate should fail)
#
# Output is logged to pgbouncer-mtls-test_<timestamp>.log in the current directory.
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Create a log file with timestamp in the current directory
LOG_FILE="pgbouncer-mtls-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Print header with test information
echo "=========================================="
echo "PgBouncer mTLS Setup Test"
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

# Check if cert-manager is installed
echo "Verifying cert-manager is installed..."
if ! kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
  echo "ERROR: cert-manager is not installed"
  echo "Please run the demo setup script to install cert-manager"
  exit 1
fi
echo "cert-manager is installed"
echo ""

# Apply cert-manager certificates
echo "=========================================="
echo "Step 1: Applying cert-manager certificates"
echo "=========================================="
echo ""
kubectl apply -f lab/exercise-5-pgbouncer-mtls/cert-manager-certs.yaml
echo ""

# Wait for all certificates to be ready
echo "Waiting for certificates to be ready..."
echo "This may take 30-60 seconds as cert-manager issues the certificates..."
echo ""

# Wait for Root CA
echo "Waiting for Root CA certificate..."
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-root-ca
echo "✓ Root CA ready"

# Wait for Intermediate CAs
echo "Waiting for Intermediate CA certificates..."
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-server-ca
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-client-ca
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-pooler-client-ca
echo "✓ Intermediate CAs ready"

# Wait for End-Entity certificates
echo "Waiting for end-entity certificates..."
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-server-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-pooler-server-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-replication-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-pooler-client-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-eu-app-cert
echo "✓ All end-entity certificates ready"
echo ""

# Verify certificates are in secrets
echo "Verifying certificate secrets exist..."
kubectl get secret pg-eu-server-cert pg-eu-server-ca pg-eu-client-ca \
  pg-eu-replication-cert pg-eu-pooler-server-cert pg-eu-pooler-client-cert \
  pg-eu-app-cert pg-eu-pooler-client-ca
echo ""

# Check if the patch has already been applied
echo "=========================================="
echo "Step 2: Applying cluster configuration patch"
echo "=========================================="
echo ""
echo "Checking if pg-eu.yaml patch is already applied..."
if grep -q "serverTLSSecret" demo/yaml/eu/pg-eu.yaml; then
  echo "Patch already applied (certificates section found in pg-eu.yaml)"
  PATCH_APPLIED=true
else
  echo "Patch not yet applied, will apply now"
  PATCH_APPLIED=false
fi
echo ""

# Apply the patch if needed
if [ "$PATCH_APPLIED" = false ]; then
  echo "Applying patch to demo/yaml/eu/pg-eu.yaml..."
  if patch -p1 < lab/exercise-5-pgbouncer-mtls/pg-eu.yaml.patch; then
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
echo "Waiting for pg-eu cluster to restart with new certificates..."
echo "This will trigger a rolling restart and may take several minutes..."
echo ""

# Wait for pods to be ready
echo "Waiting for pg-eu cluster pods to be ready (timeout: 10 minutes)..."
kubectl wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
echo "All pg-eu pods are ready"
echo ""

# Wait for the cluster condition to be ready
echo "Waiting for pg-eu cluster to be ready..."
kubectl wait --timeout 5m --for=condition=Ready cluster/pg-eu
echo "Cluster pg-eu is ready"
echo ""

# Deploy PgBouncer pooler
echo "=========================================="
echo "Step 3: Deploying PgBouncer pooler with mTLS"
echo "=========================================="
echo ""
kubectl apply -f lab/exercise-5-pgbouncer-mtls/pg-eu-pooler.yaml
echo ""

# Wait for pooler to be ready
echo "Waiting for PgBouncer pooler to be ready..."
sleep 5  # Give the deployment a moment to start
kubectl wait --timeout 5m --for=condition=Ready pod -l cnpg.io/poolerName=pg-eu-pooler-rw || true
echo ""

# Check pooler status
echo "Checking pooler deployment status..."
kubectl get pooler pg-eu-pooler-rw
kubectl get pods -l cnpg.io/poolerName=pg-eu-pooler-rw
echo ""

# Deploy test job
echo "=========================================="
echo "Step 4: Running mTLS connection tests"
echo "=========================================="
echo ""
echo "Deploying test job to run psql and pgbench tests..."
kubectl delete job pgbouncer-mtls-test --ignore-not-found=true
kubectl apply -f lab/exercise-5-pgbouncer-mtls/test-job.yaml
echo ""

# Wait for job to complete
echo "Waiting for test job to complete (this may take up to 2 minutes)..."
kubectl wait --timeout=3m --for=condition=Complete job/pgbouncer-mtls-test 2>/dev/null || {
  # If wait times out, check if failed
  if kubectl get job pgbouncer-mtls-test -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' | grep -q "True"; then
    echo "✗ Tests FAILED"
    kubectl logs job/pgbouncer-mtls-test
    exit 1
  fi
}

# Show job logs
echo ""
echo "Test job output:"
echo "----------------"
kubectl logs job/pgbouncer-mtls-test
echo "----------------"
echo ""

# Check final job status
JOB_SUCCEEDED=$(kubectl get job pgbouncer-mtls-test -o jsonpath='{.status.succeeded}' || echo "0")
if [ "$JOB_SUCCEEDED" = "1" ]; then
  echo "✓ All tests PASSED"
else
  echo "✗ Tests FAILED or incomplete"
  kubectl get job pgbouncer-mtls-test
  exit 1
fi
echo ""

# Print final status
echo "=========================================="
echo "PgBouncer mTLS Setup Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Three-tier PKI created with cert-manager (external CA architecture)"
echo "  ✓ PostgreSQL cluster configured with cert-manager certificates"
echo "  ✓ PgBouncer pooler deployed with mTLS verify-full"
echo "  ✓ psql connection test passed"
echo "  ✓ pgbench initialization passed (scale factor 10)"
echo "  ✓ pgbench workload test passed (30s, 2 clients)"
echo ""
echo "Next steps:"
echo ""
echo "1. Run ad-hoc tests with the test pod:"
echo "   kubectl apply -f lab/exercise-5-pgbouncer-mtls/test-client-pod.yaml"
echo "   kubectl wait --timeout=60s --for=condition=Ready pod/pgbouncer-mtls-test"
echo "   kubectl exec pgbouncer-mtls-test -- env PGSSLMODE=verify-full \\"
echo "     PGSSLCERT=/etc/secrets/client/tls.crt PGSSLKEY=/etc/secrets/client/tls.key \\"
echo "     PGSSLROOTCERT=/etc/secrets/ca/ca.crt psql -h pg-eu-pooler-rw -U app postgres"
echo ""
echo "2. View PgBouncer statistics:"
echo "   kubectl cnpg pgbouncer pg-eu-pooler-rw -- -c 'SHOW POOLS;'"
echo "   kubectl cnpg pgbouncer pg-eu-pooler-rw -- -c 'SHOW CLIENTS;'"
echo "   kubectl cnpg pgbouncer pg-eu-pooler-rw -- -c 'SHOW SERVERS;'"
echo ""
echo "3. View certificate details:"
echo "   kubectl get certificates"
echo "   kubectl describe certificate pg-eu-app-cert"
echo ""
echo "4. Check PgBouncer logs:"
echo "   kubectl logs -l cnpg.io/poolerName=pg-eu-pooler-rw"
echo ""
echo "5. Clean up and re-run:"
echo "   bash lab/exercise-5-pgbouncer-mtls/cleanup.sh"
echo ""
echo "Log file: $LOG_FILE"
echo "Completed at $(date)"
echo ""
