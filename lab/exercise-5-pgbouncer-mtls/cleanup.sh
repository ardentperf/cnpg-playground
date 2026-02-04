#!/bin/bash
#
# Cleanup script for Exercise 5: PgBouncer mTLS
# Removes all resources created by test-pgbouncer-mtls-setup.sh
#
# Usage: bash lab/exercise-5-pgbouncer-mtls/cleanup.sh
#

set -e
cd $(dirname $(echo $KUBECONFIG))/..

echo "Cleaning up Exercise 5 resources..."

# Delete pooler
kubectl delete pooler pg-eu-pooler-rw --ignore-not-found=true 2>/dev/null || true

# Delete test resources
kubectl delete job pgbouncer-mtls-test --ignore-not-found=true 2>/dev/null || true
kubectl delete pod pgbouncer-mtls-test --ignore-not-found=true 2>/dev/null || true

# Delete certificates (will cascade delete secrets)
kubectl delete certificate pg-eu-server-cert pg-eu-pooler-server-cert \
  pg-eu-replication-cert pg-eu-pooler-client-cert pg-eu-app-cert \
  pg-eu-server-ca pg-eu-client-ca pg-eu-pooler-client-ca pg-eu-root-ca \
  --ignore-not-found=true 2>/dev/null || true

# Delete issuers
kubectl delete issuer pg-eu-server-ca-issuer pg-eu-client-ca-issuer \
  pg-eu-pooler-client-ca-issuer pg-eu-root-ca-issuer selfsigned-bootstrap \
  --ignore-not-found=true 2>/dev/null || true

# Revert configuration file
git checkout demo/yaml/eu/pg-eu.yaml 2>/dev/null || true

# Apply clean config
kubectl apply -f demo/yaml/eu/pg-eu.yaml 2>/dev/null || true

# Clean up temp files
rm -rf /tmp/pg-certs 2>/dev/null || true
rm -f pgbouncer-mtls-test_*.log 2>/dev/null || true
pkill -f "kubectl port-forward.*pg-eu-pooler-rw" 2>/dev/null || true

echo "✓ Cleanup complete. You can re-run the exercise."
