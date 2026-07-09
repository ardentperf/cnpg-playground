#!/bin/bash
#
# Cleanup script for Exercise 10: Orphan PVC Reattach
# Removes all resources created by test-orphan-pvc-reattach.sh, leaving
# pg-eu and pg-us untouched.
#
# Usage: bash lab/exercise-10-orphan-pvc-reattach/cleanup.sh
#

set -e
cd $(dirname $(echo $KUBECONFIG))/..

echo "Cleaning up Exercise 10 resources..."

# Delete clusters (ignore if already deleted as part of the exercise)
kubectl delete cluster pg-orphan-demo --ignore-not-found=true 2>/dev/null || true
kubectl delete cluster pg-orphan-restored -n pg-restored --ignore-not-found=true 2>/dev/null || true

# Delete the target namespace (also removes any leftover PVCs in it)
kubectl delete namespace pg-restored --ignore-not-found=true 2>/dev/null || true

# Delete any leftover PVCs for the demo cluster in the default namespace
kubectl delete pvc -l cnpg.io/cluster=pg-orphan-demo --ignore-not-found=true 2>/dev/null || true

# Delete retained PVs left behind by either cluster
for pv in $(kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="retain-local-path")]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  kubectl delete pv "$pv" --ignore-not-found=true 2>/dev/null || true
done

# Delete the Retain StorageClass
kubectl delete storageclass retain-local-path --ignore-not-found=true 2>/dev/null || true

# Clean up log files
rm -f orphan-pvc-reattach-test_*.log 2>/dev/null || true

echo "Exercise 10 cleanup complete."
