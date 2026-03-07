#!/usr/bin/env bash
# Exercise 8: Entra ID OAuth SSO setup script
#
# This script configures the pg-eu cluster for Entra ID OAuth authentication
# and deploys pgAdmin with OAuth identity passthrough.
#
# Usage: bash lab/exercise-8-oauth-sso/test-oauth-setup.sh
#
# What it does:
#   1. Checks prerequisites
#   2. Prompts for Entra ID values
#   3. Creates the pgAdmin proxy certificate (cert-manager)
#   4. Patches pg-eu.yaml with Entra GUCs and pg_hba rules
#   5. Creates PostgreSQL roles for your Entra user
#   6. Deploys pgAdmin with Entra OAuth
#   7. Prints manual testing steps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$REPO_DIR/k8s/kube-config.yaml}"
CONTEXT="${KUBE_CONTEXT:-kind-k8s-eu}"

export KUBECONFIG

echo "============================================"
echo "  Exercise 8: Entra ID OAuth SSO Setup"
echo "============================================"
echo ""

# ── Prerequisite checks ────────────────────────────────────────────────────────
echo "Checking prerequisites..."

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' is required but not found in PATH" >&2
        exit 1
    fi
}

check_cmd kubectl
check_cmd helm
check_cmd patch

# Check cluster is accessible
if ! kubectl --context "$CONTEXT" get nodes &>/dev/null; then
    echo "ERROR: Cannot reach Kubernetes context '$CONTEXT'" >&2
    echo "  Run: bash scripts/setup.sh eu" >&2
    exit 1
fi

# Check pg-eu is running
if ! kubectl --context "$CONTEXT" get cluster pg-eu &>/dev/null; then
    echo "ERROR: CNPG cluster 'pg-eu' not found in context '$CONTEXT'" >&2
    echo "  Run: bash scripts/setup.sh eu" >&2
    exit 1
fi

# Check cert-manager is installed
if ! kubectl --context "$CONTEXT" get crd certificates.cert-manager.io &>/dev/null; then
    echo "ERROR: cert-manager is not installed" >&2
    echo "  cert-manager is required for the pgAdmin proxy certificate." >&2
    echo "  It is installed as part of Exercise 5." >&2
    exit 1
fi

# Check pg-eu-ca secret exists (created by CNPG)
if ! kubectl --context "$CONTEXT" get secret pg-eu-ca &>/dev/null; then
    echo "ERROR: Secret 'pg-eu-ca' not found." >&2
    echo "  This secret is created automatically by CNPG when the cluster bootstraps." >&2
    exit 1
fi

echo "  All prerequisites satisfied."
echo ""

# ── Collect Entra values ───────────────────────────────────────────────────────
echo "You will need the following values from your Entra app registration:"
echo "  - Tenant ID (Directory ID)"
echo "  - Application (Client) ID"
echo "  - Client Secret"
echo "  - Your Entra User Principal Name (e.g., user@company.com)"
echo ""
echo "See the README for step-by-step Entra app registration instructions."
echo ""

read -rp "Entra Tenant ID: " ENTRA_TENANT_ID
read -rp "Entra Application (Client) ID: " ENTRA_CLIENT_ID
read -rsp "Entra Client Secret: " ENTRA_CLIENT_SECRET
echo ""
read -rp "Your Entra UPN (e.g. user@company.com): " ENTRA_UPN

# Derive a safe PostgreSQL username from the UPN
# e.g., user@company.com -> user_company_com
PG_USERNAME=$(echo "$ENTRA_UPN" | tr '@.' '_')
echo ""
echo "PostgreSQL username will be: $PG_USERNAME"
echo "(mapped from UPN via pg_ident)"
echo ""

# ── Step 1: Apply pgAdmin proxy certificate ────────────────────────────────────
echo "==> Creating pgAdmin proxy certificate..."
kubectl --context "$CONTEXT" apply -f "$SCRIPT_DIR/pgadmin-proxy-cert.yaml"

# Wait for certificate to be ready
echo "    Waiting for certificate to be issued..."
for i in $(seq 1 30); do
    STATUS=$(kubectl --context "$CONTEXT" get certificate pgadmin-proxy-cert \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$STATUS" == "True" ]]; then
        echo "    Certificate ready."
        break
    fi
    sleep 2
    if [[ $i -eq 30 ]]; then
        echo "ERROR: Certificate was not issued within 60 seconds" >&2
        kubectl --context "$CONTEXT" describe certificate pgadmin-proxy-cert >&2
        exit 1
    fi
done

# ── Step 2: Patch pg-eu.yaml ───────────────────────────────────────────────────
echo "==> Patching pg-eu.yaml for Entra OAuth..."

PG_EU_YAML="$REPO_DIR/demo/yaml/eu/pg-eu.yaml"
PATCH_FILE="$SCRIPT_DIR/pg-eu-oauth.yaml.patch"

# Apply the patch (allows re-running idempotently by checking if already applied)
if patch --dry-run --forward -r /dev/null "$PG_EU_YAML" "$PATCH_FILE" &>/dev/null; then
    # Create a temporary patched file with Entra values substituted
    TEMP_YAML=$(mktemp)
    patch --forward -r /dev/null -o "$TEMP_YAML" "$PG_EU_YAML" "$PATCH_FILE"
    sed -i \
        -e "s/ENTRA_TENANT_ID/${ENTRA_TENANT_ID}/g" \
        -e "s/ENTRA_APP_ID/${ENTRA_CLIENT_ID}/g" \
        "$TEMP_YAML"
    cp "$TEMP_YAML" "$PG_EU_YAML"
    rm -f "$TEMP_YAML"
    echo "    Patch applied with Entra values."
else
    echo "    Patch already applied (or conflicts detected)."
    echo "    Substituting Entra values in place..."
    sed -i \
        -e "s/ENTRA_TENANT_ID/${ENTRA_TENANT_ID}/g" \
        -e "s/ENTRA_APP_ID/${ENTRA_CLIENT_ID}/g" \
        "$PG_EU_YAML"
fi

# Apply the updated cluster manifest
kubectl --context "$CONTEXT" apply -f "$PG_EU_YAML"

# Wait for rolling restart to complete
echo "    Waiting for pg-eu cluster to become healthy (rolling restart may take ~2 min)..."
for i in $(seq 1 60); do
    READY=$(kubectl --context "$CONTEXT" get cluster pg-eu \
        -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "0")
    INSTANCES=$(kubectl --context "$CONTEXT" get cluster pg-eu \
        -o jsonpath='{.spec.instances}' 2>/dev/null || echo "3")
    if [[ "$READY" == "$INSTANCES" ]]; then
        echo "    Cluster healthy: $READY/$INSTANCES instances ready."
        break
    fi
    sleep 5
    if [[ $i -eq 60 ]]; then
        echo "WARNING: Cluster may not be fully ready yet. Check with: kubectl get cluster pg-eu"
    fi
done

# ── Step 3: Create PostgreSQL role ─────────────────────────────────────────────
echo "==> Creating PostgreSQL role for '$ENTRA_UPN'..."

# Find primary pod
PRIMARY_POD=$(kubectl --context "$CONTEXT" get pods \
    -l "cnpg.io/cluster=pg-eu,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$PRIMARY_POD" ]]; then
    echo "ERROR: Could not find primary pod for pg-eu" >&2
    exit 1
fi

kubectl --context "$CONTEXT" exec -i "$PRIMARY_POD" -- psql -U postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$PG_USERNAME') THEN
    CREATE USER "$PG_USERNAME" LOGIN;
    RAISE NOTICE 'Created role: $PG_USERNAME';
  ELSE
    RAISE NOTICE 'Role already exists: $PG_USERNAME';
  END IF;
END
\$\$;
SQL

echo "    Role '$PG_USERNAME' ready."

# ── Step 4: Deploy pgAdmin with Entra OAuth ────────────────────────────────────
echo "==> Deploying pgAdmin with Entra OAuth..."

# Build values with substituted secrets
VALUES_FILE=$(mktemp --suffix=.yaml)
sed \
    -e "s/ENTRA_TENANT_ID/${ENTRA_TENANT_ID}/g" \
    -e "s/ENTRA_CLIENT_ID/${ENTRA_CLIENT_ID}/g" \
    -e "s/ENTRA_CLIENT_SECRET/${ENTRA_CLIENT_SECRET}/g" \
    "$SCRIPT_DIR/pgadmin-oauth-values.yaml" > "$VALUES_FILE"

# Install or upgrade pgAdmin
if helm --kube-context "$CONTEXT" status pgadmin4-oauth &>/dev/null; then
    helm upgrade pgadmin4-oauth oci://docker.io/dpage/pgadmin4-helm \
        --kube-context "$CONTEXT" \
        -f "$VALUES_FILE" \
        --wait --timeout 3m
else
    helm install pgadmin4-oauth oci://docker.io/dpage/pgadmin4-helm \
        --kube-context "$CONTEXT" \
        -f "$VALUES_FILE" \
        --wait --timeout 3m
fi
rm -f "$VALUES_FILE"

echo "    pgAdmin deployed."

# ── Step 5: Print instructions ─────────────────────────────────────────────────
cat <<EOF

============================================
  Setup complete!
============================================

Your Entra values:
  Tenant ID:  $ENTRA_TENANT_ID
  Client ID:  $ENTRA_CLIENT_ID
  UPN:        $ENTRA_UPN
  PG role:    $PG_USERNAME

─────────────────────────────────────────
Path A: psql with Entra OAuth device flow
─────────────────────────────────────────

1. Start a test pod with PostgreSQL 18 client:

   kubectl --context $CONTEXT run -it --rm psql-test \\
     --image=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie \\
     --restart=Never -- bash

2. Inside the pod, install libpq-oauth (if not included):

   apt-get update && apt-get install -y libpq-oauth postgresql-client

3. Connect with OAuth device flow:

   psql "host=pg-eu-rw \\
     user=$PG_USERNAME \\
     dbname=postgres \\
     oauth_issuer=https://login.microsoftonline.com/$ENTRA_TENANT_ID/v2.0 \\
     oauth_client_id=$ENTRA_CLIENT_ID \\
     oauth_scope=api://$ENTRA_CLIENT_ID/pg_access"

4. psql will display a URL and code. Open the URL in your browser,
   sign in with your Entra account ($ENTRA_UPN), and approve.
   psql will automatically connect.

5. Verify your identity:
   SELECT current_user, session_user;

─────────────────────────────────────────
Path B: pgAdmin with Entra SSO
─────────────────────────────────────────

1. Port-forward pgAdmin:

   kubectl --context $CONTEXT port-forward service/pgadmin4-oauth 8091:80 &

2. Open http://localhost:8091 in your browser.

3. Click "Sign in with Microsoft" and authenticate with $ENTRA_UPN.

4. Register a server:
   - Object → Register → Server
   - General: Name = "pg-eu (OAuth)"
   - Connection: Host = pg-eu-rw, Port = 5432, Database = postgres
   - Advanced: Enable "Use OAuth identity for database connection"
   - Click Save

5. Connect to the server. pgAdmin will use your Entra identity and
   the proxy certificate to authenticate as $PG_USERNAME.

6. Verify in PG:
   SELECT usename, ssl, client_dn
   FROM pg_stat_ssl JOIN pg_stat_activity USING (pid)
   WHERE application_name = 'pgAdmin 4';

─────────────────────────────────────────
Troubleshooting
─────────────────────────────────────────

Check entra_validator debug logs (on primary pod):
  kubectl --context $CONTEXT logs $PRIMARY_POD | grep entra:

Check pg_hba is correct:
  kubectl --context $CONTEXT exec $PRIMARY_POD -- psql -U postgres \\
    -c "SELECT * FROM pg_hba_file_rules WHERE auth_method IN ('oauth','cert');"

Check cert is present and valid:
  kubectl --context $CONTEXT get certificate pgadmin-proxy-cert
  kubectl --context $CONTEXT get secret pgadmin-proxy-cert -o jsonpath='{.data.tls\\.crt}' \\
    | base64 -d | openssl x509 -noout -subject -dates

─────────────────────────────────────────
To clean up:
─────────────────────────────────────────

  helm --kube-context $CONTEXT uninstall pgadmin4-oauth
  kubectl --context $CONTEXT delete certificate pgadmin-proxy-cert
  kubectl --context $CONTEXT delete issuer pg-eu-ca-issuer
  kubectl --context $CONTEXT delete secret pgadmin-proxy-cert
  # Restore pg-eu.yaml: git checkout demo/yaml/eu/pg-eu.yaml
  # Then: kubectl --context $CONTEXT apply -f demo/yaml/eu/pg-eu.yaml

EOF
