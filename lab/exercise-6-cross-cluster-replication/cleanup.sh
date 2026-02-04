#!/bin/bash
#
# Cleanup script for Exercise 6: Cross-Cluster Replication
# Removes pg-us cluster and certificates from US cluster
# Keeps Exercise 5 resources in EU cluster intact
#
# Usage: bash lab/exercise-6-cross-cluster-replication/cleanup.sh
#

set -e
cd $(dirname $(echo $KUBECONFIG))/..

US_CONTEXT="kind-k8s-us"
ORIGINAL_CONTEXT=$(kubectl config current-context)

echo "Cleaning up Exercise 6 resources from US cluster..."

# Switch to US context
kubectl config use-context $US_CONTEXT > /dev/null 2>&1 || {
    echo "WARNING: US cluster context not found, skipping cleanup"
    exit 0
}

# Delete pg-us cluster
echo "Deleting pg-us cluster from US cluster..."
kubectl delete cluster pg-us --ignore-not-found=true 2>/dev/null || true

# Wait for cluster deletion
echo "Waiting for cluster deletion..."
sleep 5

# Delete pg-us certificates
echo "Deleting pg-us certificates..."
kubectl delete certificate pg-us-server-cert pg-us-replication-cert pg-us-app-cert \
  --ignore-not-found=true 2>/dev/null || true

# Delete issuers
kubectl delete issuer pg-us-root-ca-issuer pg-us-server-ca-issuer pg-us-client-ca-issuer \
  --ignore-not-found=true 2>/dev/null || true

# Delete US intermediate CAs
echo "Deleting US intermediate CAs..."
kubectl delete certificate pg-us-server-ca pg-us-client-ca \
  --ignore-not-found=true 2>/dev/null || true

# Delete copied Root CA
echo "Deleting copied Root CA..."
kubectl delete secret pg-eu-root-ca --ignore-not-found=true 2>/dev/null || true

# Revert pg-us.yaml
echo "Reverting configuration changes..."
git checkout demo/yaml/us/pg-us.yaml 2>/dev/null || true

# Restore original context
kubectl config use-context $ORIGINAL_CONTEXT > /dev/null 2>&1

echo ""
echo "✓ Cleanup complete!"
echo ""
echo "Exercise 5 resources in EU cluster (kind-k8s-eu) are still running."
echo "To clean up Exercise 5:"
echo "  bash lab/exercise-5-pgbouncer-mtls/cleanup.sh"
echo ""
