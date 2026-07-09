#!/bin/bash
#
# This script automates Exercise 10: Recovering a Deleted CNPG Cluster from
# Retained PVs. It creates a disposable cluster (pg-orphan-demo) on a
# Retain-reclaim StorageClass, writes test data, deletes the cluster,
# reattaches the retained PVs to a renamed cluster (pg-orphan-restored) in a
# new namespace (pg-restored), and verifies the data survived.
#
# pg-eu and pg-us are never touched.
#
# The script is idempotent and can be re-run safely.
#
# Prerequisites:
#   - CNPG Playground is running
#   - kubectl context is set to kind-k8s-eu
#
# Usage:
#   cd ~/cnpg-playground
#   bash lab/exercise-10-orphan-pvc-reattach/test-orphan-pvc-reattach.sh
#
# Output is logged to orphan-pvc-reattach-test_<timestamp>.log in the
# current directory.
#

set -euo pipefail

LOG_FILE="orphan-pvc-reattach-test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

EX_DIR="lab/exercise-10-orphan-pvc-reattach"
DEMO_CLUSTER="pg-orphan-demo"
NEW_CLUSTER="pg-orphan-restored"
NEW_NS="pg-restored"

echo "=========================================="
echo "Orphan PVC Reattach Test"
echo "Started at $(date)"
echo "=========================================="
echo ""

cd $(dirname $(echo $KUBECONFIG))/..
echo "Working directory: $(pwd)"
echo ""

echo "--- Step 1: Create the Retain StorageClass ---"
kubectl apply -f "${EX_DIR}/retain-storageclass.yaml"
echo ""

echo "--- Step 2: Create the demo cluster ---"
kubectl apply -f "${EX_DIR}/pg-orphan-demo.yaml"
kubectl wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
  cluster/${DEMO_CLUSTER} --timeout=300s
echo ""

echo "--- Step 3: Write test data ---"
kubectl cnpg psql ${DEMO_CLUSTER} -- -c "
  CREATE TABLE orphan_demo (id serial PRIMARY KEY, note text, ts timestamptz DEFAULT now());
  INSERT INTO orphan_demo (note) VALUES ('written before cluster deletion');
  SELECT * FROM orphan_demo;
"
echo ""

echo "--- Step 4: Delete the cluster ---"
kubectl delete cluster ${DEMO_CLUSTER}
kubectl wait --for=delete pod/${DEMO_CLUSTER}-1 pod/${DEMO_CLUSTER}-2 pod/${DEMO_CLUSTER}-3 --timeout=120s || true
echo ""

echo "Confirming PVCs are gone and PVs are Released..."
kubectl get pvc -l cnpg.io/cluster=${DEMO_CLUSTER}
kubectl get pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name' | grep "${DEMO_CLUSTER}" || true
echo ""

echo "--- Step 5: Prepare PVs for rebinding ---"
DEMO_PVS=$(kubectl get pv -o json | python3 -c "
import json, sys
pvs = json.load(sys.stdin)['items']
for pv in pvs:
    claim = pv.get('spec', {}).get('claimRef', {})
    if claim.get('name', '').startswith('${DEMO_CLUSTER}-'):
        print(pv['metadata']['name'])
")

for pv in $DEMO_PVS; do
  kubectl patch pv "$pv" --type=merge -p '{"spec":{"claimRef":null}}'
done

kubectl get pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' | grep -F "$(echo "$DEMO_PVS" | head -1)" || true
echo ""

echo "--- Step 6: Create the target namespace ---"
kubectl create namespace ${NEW_NS} --dry-run=client -o yaml | kubectl apply -f -
echo ""

echo "--- Step 7: Pre-create PVCs with static PV bindings ---"
python3 - "$DEMO_PVS" <<'EOF' | kubectl apply -f -
import sys
import yaml
import subprocess
import json

NEW_CLUSTER = "pg-orphan-restored"
NEW_NS      = "pg-restored"

demo_pvs = sys.argv[1].split()

pv_json = json.loads(subprocess.check_output(["kubectl", "get", "pv", "-o", "json"]))
by_name = {pv["metadata"]["name"]: pv for pv in pv_json["items"]}

# serial -> (instanceRole, data-pv-name, wal-pv-name)
instances = {}
for name in demo_pvs:
    pv = by_name[name]
    claim_name = pv["spec"]["claimRef"]["name"]  # pg-orphan-demo-<serial>[-wal]
    suffix = claim_name[len("pg-orphan-demo-"):]
    is_wal = suffix.endswith("-wal")
    serial = int(suffix[:-4]) if is_wal else int(suffix)
    role = "primary" if serial == 2 else "replica"
    entry = instances.setdefault(serial, [role, None, None])
    if is_wal:
        entry[2] = name
    else:
        entry[1] = name

docs = []
for serial, (role, data_pv, wal_pv) in instances.items():
    instance_name = f"{NEW_CLUSTER}-{serial}"
    for pvc_role, pv_name, suffix in [
        ("PG_DATA", data_pv, ""),
        ("PG_WAL",  wal_pv,  "-wal"),
    ]:
        docs.append({
            "apiVersion": "v1",
            "kind": "PersistentVolumeClaim",
            "metadata": {
                "name": f"{instance_name}{suffix}",
                "namespace": NEW_NS,
                "labels": {
                    "app.kubernetes.io/component": "database",
                    "app.kubernetes.io/managed-by": "cloudnative-pg",
                    "app.kubernetes.io/name": "postgresql",
                    "cnpg.io/cluster":       NEW_CLUSTER,
                    "cnpg.io/instanceName":  instance_name,
                    "cnpg.io/instanceRole":  role,
                    "cnpg.io/pvcRole":       pvc_role,
                    "role":                  role,
                },
                "annotations": {
                    "cnpg.io/nodeSerial": str(serial),
                    "cnpg.io/pvcStatus":  "ready",
                },
            },
            "spec": {
                "accessModes":     ["ReadWriteOnce"],
                "storageClassName": "retain-local-path",
                "volumeName":      pv_name,
                "resources":       {"requests": {"storage": "1Gi"}},
            },
        })

print("---\n".join(yaml.dump(d) for d in docs))
EOF
echo ""

kubectl get pvc -n ${NEW_NS}
echo ""

echo "--- Step 8: Create the new cluster ---"
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${NEW_CLUSTER}
  namespace: ${NEW_NS}
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18-standard-trixie

  storage:
    size: 1Gi
    storageClass: retain-local-path

  walStorage:
    size: 1Gi
    storageClass: retain-local-path

  affinity:
    nodeSelector:
      node-role.kubernetes.io/postgres: ""
    tolerations:
    - key: node-role.kubernetes.io/postgres
      operator: Exists
      effect: NoSchedule
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
    podAntiAffinityType: required
EOF
echo ""

echo "--- Step 9: Watch the operator reattach ---"
kubectl wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
  cluster/${NEW_CLUSTER} -n ${NEW_NS} --timeout=300s
echo ""

echo "Operator log lines mentioning orphan/restore:"
kubectl logs -n cnpg-system deployment/cnpg-controller-manager --since=5m \
  | grep -i 'orphan\|restore' || true
echo ""

echo "--- Step 10: Verify data ---"
kubectl cnpg psql ${NEW_CLUSTER} -n ${NEW_NS} -- -c "SELECT * FROM orphan_demo;"
echo ""

echo "=========================================="
echo "Orphan PVC Reattach Test Complete!"
echo "=========================================="
echo ""
echo "The pg-orphan-demo cluster was deleted and its data was recovered"
echo "as pg-orphan-restored in the ${NEW_NS} namespace."
echo ""
echo "To clean up all resources created by this exercise:"
echo "  bash lab/exercise-10-orphan-pvc-reattach/cleanup.sh"
echo ""
echo "Log file: $LOG_FILE"
echo "Completed at $(date)"
echo ""
