# Exercise 10: Recovering a Deleted CNPG Cluster from Retained PVs

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Background](#background)
- [How the Operator Reattaches PVCs](#how-the-operator-reattaches-pvcs)
- [Variations](#variations)
- [Step 1: Configure a Retain StorageClass](#step-1-configure-a-retain-storageclass)
- [Step 2: Create the Demo Cluster](#step-2-create-the-demo-cluster)
- [Step 3: Write Test Data](#step-3-write-test-data)
- [Step 4: Delete the Cluster](#step-4-delete-the-cluster)
- [Step 5: Prepare PVs for Rebinding](#step-5-prepare-pvs-for-rebinding)
- [Step 6: Create the Target Namespace](#step-6-create-the-target-namespace)
- [Step 7: Pre-create PVCs with Static PV Bindings](#step-7-pre-create-pvcs-with-static-pv-bindings)
- [Step 8: Create the New Cluster](#step-8-create-the-new-cluster)
- [Step 9: Watch the Operator Reattach](#step-9-watch-the-operator-reattach)
- [Step 10: Verify Data](#step-10-verify-data)
- [What Happened Under the Hood](#what-happened-under-the-hood)
- [Cleaning Up Released PVs](#cleaning-up-released-pvs)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Automation Script](#automation-script)

## Overview

With `reclaimPolicy: Retain` on the StorageClass, deleting a CNPG cluster
leaves the underlying PVs intact. Normally those PVs are simply cleaned up
once you're confident the data is no longer needed. But if a cluster is
deleted by mistake, the retained PVs are the recovery path — this exercise
shows how to reattach them to a new cluster, including renaming the cluster
and moving it to a different namespace.

This exercise uses a **dedicated, disposable cluster** (`pg-orphan-demo`) so
that `pg-eu` and `pg-us` — which later exercises depend on — are never
touched.

Tested against CNPG 1.28.1 in the CNPG Playground (KIND, `rancher.io/local-path`
provisioner).

## Prerequisites

- The CNPG Playground is running (EU Kubernetes cluster available)
- Your kubectl context targets `kind-k8s-eu`

```bash
kubectl config current-context   # should print kind-k8s-eu
```

**Note:** All commands in this exercise should be run from the CNPG playground
root directory (`~/cnpg-playground`).

## Background

CNPG tracks PVC ownership via Kubernetes owner references: every PVC carries
an `ownerReference` pointing to its Cluster, so when a Cluster is deleted
Kubernetes garbage-collects the PVCs automatically.

Setting `reclaimPolicy: Retain` on the StorageClass before creating a cluster
means the underlying PVs survive PVC deletion in `Released` state. This must
be paired with a cleanup job to delete `Released` PVs that are no longer
needed (see [Cleaning Up Released PVs](#cleaning-up-released-pvs)) —
otherwise disk space accumulates indefinitely. The benefit is that if a
cluster is deleted by mistake, the retained PVs are your recovery path.

## How the Operator Reattaches PVCs

`cluster_restore.go` in the CloudNativePG operator fires on the **first
reconciliation** of any newly-created cluster (detected by
`status.latestGeneratedNode == 0`). It scans the cluster's namespace for PVCs
that:

1. Have the label `cnpg.io/cluster: <cluster-name>` matching the new cluster
2. Have the annotation `cnpg.io/nodeSerial` set
3. Have **no** `ownerReferences`

When it finds them it reads the serial numbers and `cnpg.io/instanceRole`
labels to reconstruct `status.latestGeneratedNode` and
`status.targetPrimary`, patches owner references back onto the PVCs, and
then lets normal reconciliation spin up pods against the existing volumes —
no `initdb`, no restore from backup.

**Key constraints:**
- PVCs must be in the **same namespace** as the new cluster (the list is
  namespace-scoped)
- PVC names must follow the `<cluster-name>-<serial>` /
  `<cluster-name>-<serial>-wal` pattern the operator expects

## Variations

The steps below cover the most general case: new namespace, new cluster
name. Notes call out what changes for simpler scenarios.

| Scenario | What differs |
|---|---|
| Same namespace, same cluster name | Skip Step 6; PVC names and labels unchanged |
| Same namespace, new cluster name | Skip Step 6; use new name in PVC labels and names |
| New namespace, same cluster name | Skip nothing; use original name in PVC labels and names |
| New namespace, new cluster name | Full steps as written |

## Step 1: Configure a Retain StorageClass

Do this once, before creating the demo cluster. All PVs provisioned from
this StorageClass will inherit `Retain`, so the underlying storage survives
cluster deletion. This exercise uses a dedicated StorageClass
(`retain-local-path`) rather than patching the playground's default, so
`reclaimPolicy: Retain` never applies to `pg-eu` or `pg-us` volumes.

```bash
kubectl apply -f lab/exercise-10-orphan-pvc-reattach/retain-storageclass.yaml
```

Verify it was created:

```bash
kubectl get storageclass retain-local-path
```

```
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
retain-local-path    rancher.io/local-path   Retain          WaitForFirstConsumer   false                  5s
```

## Step 2: Create the Demo Cluster

```bash
kubectl apply -f lab/exercise-10-orphan-pvc-reattach/pg-orphan-demo.yaml
kubectl wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
  cluster/pg-orphan-demo --timeout=300s
```

## Step 3: Write Test Data

```bash
kubectl cnpg psql pg-orphan-demo -- -c "
  CREATE TABLE orphan_demo (id serial PRIMARY KEY, note text, ts timestamptz DEFAULT now());
  INSERT INTO orphan_demo (note) VALUES ('written before cluster deletion');
  SELECT * FROM orphan_demo;
"
```

## Step 4: Delete the Cluster

```bash
kubectl delete cluster pg-orphan-demo
kubectl wait --for=delete pod/pg-orphan-demo-1 pod/pg-orphan-demo-2 pod/pg-orphan-demo-3 --timeout=120s
```

Confirm PVCs are gone and PVs are `Released` (not deleted):

```bash
kubectl get pvc -l cnpg.io/cluster=pg-orphan-demo   # should return nothing
kubectl get pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name'
# The 6 PVs for pg-orphan-demo should show: Released   pg-orphan-demo-N[-wal]
```

## Step 5: Prepare PVs for Rebinding

PVs in `Released` state still hold a `spec.claimRef` pointing to the deleted
PVCs. Kubernetes will not bind them to new PVCs until that reference is
cleared.

```bash
for pv in $(kubectl get pv -l cnpg.io/cluster=pg-orphan-demo -o jsonpath='{.items[*].metadata.name}'); do
  kubectl patch pv $pv --type=merge -p '{"spec":{"claimRef":null}}'
done

kubectl get pv -l cnpg.io/cluster=pg-orphan-demo -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
# All should show Available
```

> **Note:** the PVs provisioned by `rancher.io/local-path` are not labeled by
> the storage provisioner itself — the `cnpg.io/cluster` label above comes
> from CNPG's own PV labeling. If your PVs aren't labeled (e.g. an older CNPG
> version), select them by name instead:
> `kubectl get pv -o jsonpath='{.items[*].metadata.name}'` filtered to the
> ones whose `CLAIM` column matched `pg-orphan-demo-*` in the previous step.

## Step 6: Create the Target Namespace

> **Skip if restoring to the same namespace.**

```bash
kubectl create namespace pg-restored
```

## Step 7: Pre-create PVCs with Static PV Bindings

Create PVCs in the target namespace with:
- Names following `<new-cluster-name>-<serial>` /
  `<new-cluster-name>-<serial>-wal`
- All required CNPG labels and annotations
- `spec.volumeName` pointing at the specific PV (static binding bypasses
  dynamic provisioning)

> **Same cluster name:** keep the same name pattern and update only
> `NEW_CLUSTER` and `NEW_NS`.

```bash
# Edit NEW_CLUSTER, NEW_NS, and the serial->PV mapping to match your environment
python3 - <<'EOF' | kubectl apply -f -
import yaml

NEW_CLUSTER = "pg-orphan-restored"
NEW_NS      = "pg-restored"

# serial -> (instanceRole, data-pv-name, wal-pv-name)
# Get PV names from:
#   kubectl get pv -o custom-columns='NAME:.metadata.name,CLAIM:.spec.claimRef.name,NS:.spec.claimRef.namespace'
instances = {
    1: ("replica", "pvc-c6c15322-a836-4474-a15c-ec9152262cfe", "pvc-b2494d2d-ec70-4adc-b8b2-3a98a9f8909e"),
    2: ("primary", "pvc-83c5df7e-d1e1-47c3-ab75-6b893ffa4ee0", "pvc-0d08702d-fdea-4f03-9f0b-6bc1c6df6c44"),
    3: ("replica", "pvc-383e1172-f7bc-4005-ae5c-a8b083aa3e8a", "pvc-e9d38bad-ad21-4d60-ab1f-b79b45678b58"),
}

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
```

With `volumeBindingMode: WaitForFirstConsumer` some PVCs will stay `Pending`
until a pod is scheduled against them — that is expected.

```bash
kubectl get pvc -n pg-restored
# STATUS will be Bound or Pending (Pending is fine at this stage)
```

## Step 8: Create the New Cluster

Omit `bootstrap` — the orphan-reattach logic replaces it when it finds the
pre-created PVCs.

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-orphan-restored
  namespace: pg-restored
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
```

## Step 9: Watch the Operator Reattach

The restore logic fires within milliseconds of the first reconciliation.
Confirm in the operator logs:

```bash
kubectl logs -n cnpg-system deployment/cnpg-controller-manager --since=30s \
  | grep -i 'orphan\|restore'
```

You should see:

```
found orphan pvcs, trying to restore the cluster  pvcs=[pg-orphan-restored-1 ...]
Creating new Pod to reattach a PVC  pod=pg-orphan-restored-2  pvc=pg-orphan-restored-2
```

Watch the cluster reach healthy state (~30 seconds):

```bash
kubectl get cluster pg-orphan-restored -n pg-restored -w
```

## Step 10: Verify Data

```bash
kubectl cnpg psql pg-orphan-restored -n pg-restored -- -c "SELECT * FROM orphan_demo;"
```

The row written before cluster deletion should be present.

## What Happened Under the Hood

1. **StorageClass `Retain`** meant that when Kubernetes cascade-deleted the
   PVCs (via owner references on cluster deletion), the underlying PVs were
   kept in `Released` state rather than deleted.

2. **Clearing PV `claimRef`** moved PVs from `Released` -> `Available`,
   allowing Kubernetes to bind them to new PVCs.

3. **Pre-created PVCs** with `spec.volumeName` statically bound each PVC to
   a specific PV, bypassing dynamic provisioning. The CNPG labels and
   annotations (`cnpg.io/cluster`, `cnpg.io/nodeSerial`,
   `cnpg.io/instanceRole`, `cnpg.io/pvcStatus`) carried all the metadata the
   operator needs.

4. **`reconcileRestoredCluster`** fired on the first reconciliation of the
   new cluster (`status.latestGeneratedNode == 0`). It found the
   pre-created PVCs (matching `cnpg.io/cluster=pg-orphan-restored` in
   namespace `pg-restored`, no `ownerReferences`), read the serials and
   roles, patched `status.latestGeneratedNode = 3` and
   `status.targetPrimary = pg-orphan-restored-2`, then added owner
   references to all PVCs.

5. Normal reconciliation created pods against the existing volumes. No
   `initdb`, no restore from backup. Cluster healthy in ~28 seconds.

## Cleaning Up Released PVs

When a cluster is intentionally deleted, `Released` PVs should be removed
once you're confident the data is no longer needed. Use
`status.lastPhaseTransitionTime` — updated by Kubernetes whenever the PV
phase changes — to avoid deleting PVs that were only recently released and
might still be needed for recovery.

```bash
# Adjust THRESHOLD_SECONDS as needed: 3600 = 1 hour, 86400 = 1 day
kubectl get pv -o json | python3 -c "
import json, sys
from datetime import datetime, timezone
THRESHOLD_SECONDS = 600
now = datetime.now(timezone.utc)
print(*[
    pv['metadata']['name']
    for pv in json.load(sys.stdin)['items']
    if pv['status']['phase'] == 'Released'
    and (now - datetime.fromisoformat(pv['status']['lastPhaseTransitionTime'].replace('Z','+00:00'))).total_seconds() > THRESHOLD_SECONDS
])
" | xargs -r kubectl delete pv
```

To preview without deleting, drop the `| xargs -r kubectl delete pv` and the
names will be printed to stdout instead.

## Troubleshooting

**PVs stuck in Released, not Available**
The `claimRef` was not cleared (Step 5). Patch it:
```bash
kubectl patch pv <name> --type=merge -p '{"spec":{"claimRef":null}}'
```

**New cluster starts `initdb` instead of reattaching**
The restore logic only fires when `status.latestGeneratedNode == 0` AND
orphaned PVCs are found. Check that:
- PVCs exist in the **same namespace** as the cluster
- `cnpg.io/cluster` label matches the cluster name exactly
- PVCs have no `ownerReferences`
- PVCs have the `cnpg.io/nodeSerial` annotation

**Pods stuck in Pending after reattachment**
`local-path` storage pins volumes to specific nodes. If anti-affinity rules
can't place all pods on the nodes where the PVs are pinned, pods won't
schedule. Temporarily set `podAntiAffinityType: preferred` in the cluster
spec.

**PVCs stay Pending and never bind**
With `WaitForFirstConsumer`, PVCs bind when pods are scheduled. If the pod
is stuck (see above), the PVC stays Pending too — fix the pod scheduling
issue first.

## Cleanup

To remove everything created by this exercise (leaving `pg-eu` and `pg-us`
untouched):

```bash
cd ~/cnpg-playground
bash lab/exercise-10-orphan-pvc-reattach/cleanup.sh
```

This deletes the `pg-orphan-restored` cluster and the `pg-restored`
namespace, deletes any leftover `pg-orphan-demo`/`pg-orphan-restored` PVs,
and removes the `retain-local-path` StorageClass.

## Automation Script

After you have learned how the exercise works through the manual steps, the
automation script runs the full end-to-end recovery:

```bash
cd ~/cnpg-playground
bash lab/exercise-10-orphan-pvc-reattach/test-orphan-pvc-reattach.sh
```

The script automates all steps:
- Creates the `retain-local-path` StorageClass and the `pg-orphan-demo`
  cluster
- Writes test data
- Deletes the cluster and confirms the PVs are `Released`
- Clears `claimRef` on the retained PVs
- Creates the `pg-restored` namespace and pre-creates statically-bound PVCs
  for the renamed cluster
- Creates `pg-orphan-restored` and waits for the operator to reattach the
  volumes
- Verifies the test data survived

Output is logged to `orphan-pvc-reattach-test_<timestamp>.log`.
