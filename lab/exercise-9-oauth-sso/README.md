# Exercise 8: SSO with Microsoft Entra ID

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Step 1: Register an Entra Application](#step-1-register-an-entra-application)
- [Step 2: Configure the pg-eu Cluster](#step-2-configure-the-pg-eu-cluster)
- [Step 3: Create the pgAdmin Proxy Certificate](#step-3-create-the-pgadmin-proxy-certificate)
- [Step 4: Create Your PostgreSQL Role](#step-4-create-your-postgresql-role)
- [Step 5: Deploy pgAdmin with Entra OAuth](#step-5-deploy-pgadmin-with-entra-oauth)
- [Step 6: Test psql OAuth Device Flow](#step-6-test-psql-oauth-device-flow)
- [Step 7: Test pgAdmin OAuth](#step-7-test-pgadmin-oauth)
- [Verifying Connections](#verifying-connections)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Cleaning Up](#cleaning-up)
- [Automation Script](#automation-script)

## Overview

This exercise demonstrates Single Sign-On (SSO) with Microsoft Entra ID (Azure AD)
for both PostgreSQL and pgAdmin. Human users authenticate once with their corporate
Entra identity and connect directly — no separate database passwords needed.

What you'll learn:

- How PostgreSQL 18's native OAuth device flow works with Entra ID
- How the `entra_validator` extension validates JWT tokens offline
- How pgAdmin can use your Entra identity to connect to PostgreSQL transparently
- How OAuth authentication coexists with mTLS for service accounts (Exercise 5)

## Prerequisites

- **Exercise 2** completed: pg-eu cluster running on `kind-k8s-eu`
- **Exercise 5** completed or cert-manager installed (needed for the pgAdmin proxy cert)
  - If you haven't done Exercise 5, install cert-manager first:
    ```bash
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager --create-namespace \
      --set crds.enabled=true
    ```
- **Free Microsoft account** (personal @outlook.com, @hotmail.com, or corporate)
  — a free Azure subscription is not required for Entra app registrations
- `kubectl`, `helm`, and `patch` in your PATH

All commands should be run from the CNPG playground root directory (`~/cnpg-playground`).

## Architecture

```
Path A: psql + Native OAuth Device Flow
─────────────────────────────────────────────────────────────────────────
  psql  ──────────────────────────────────────────────────► PostgreSQL
    │                                                            ▲
    │  1. Discover device_authorization_endpoint                  │
    ├──► Entra /.well-known/openid-configuration                  │
    │                                                             │
    │  2. Start device flow (show code + URL to user)             │
    ├──► POST /oauth2/v2.0/devicecode                             │
    │                                                             │
    │  3. User opens browser, signs in with Entra account         │
    │                                                             │
    │  4. Poll for token                                          │
    ├──► POST /oauth2/v2.0/token ──────────────────► JWT token    │
    │                                                             │
    │  5. Send token via SASL OAUTHBEARER ───────────────────────►│
    │                                                             │
    │  6. entra_validator verifies JWT (offline):                 │
    │     - Check iss == expected_issuer                          │
    │     - Extract preferred_username → authn_id                 │
    │     - Check roles[] contains required value                 │
    │                                                             │
    │  7. pg_ident maps UPN to PG role                            │
    └───────────────────────────────────────────────► Connected ✓ │


Path B: pgAdmin + OAuth Identity Passthrough
─────────────────────────────────────────────────────────────────────────
  Browser ──► pgAdmin ──────────────────────────────────► PostgreSQL
    │            │                                              ▲
    │            │  1. User clicks "Sign in with Microsoft"     │
    │  Redirect  │                                              │
    ├───────────►│◄─── Entra OAuth2 login (browser flow)        │
    │            │                                              │
    │            │  2. pgAdmin stores Entra session             │
    │            │     (preferred_username = user@company.com)  │
    │            │                                              │
    │            │  3. Connect to PG using proxy TLS cert       │
    │            │     CN=pgadmin-proxy (signed by CNPG CA)     │
    │            ├──────────────────────────────────────────────►
    │            │     pg_hba: cert map=pgadmin-proxy           │
    │            │     pg_ident: pgadmin-proxy → user@company.com
    │            │                                              │
    │            └──────────────────────────────────────────────► Connected as user@company.com ✓
```

Both paths use the same Entra app registration. mTLS service accounts from
Exercise 5 continue to work unchanged — pg_hba cert rules are evaluated first,
so OAuth is only attempted for human connections using `psql` with OAuth flags.

## Step 1: Register an Entra Application

You only need to do this once. The same app registration is used for both
psql device flow and pgAdmin browser login.

### 1.1 Create the App Registration

1. Go to [portal.azure.com](https://portal.azure.com) and sign in
2. Search for **"Entra ID"** → **App registrations** → **New registration**
3. Fill in:
   - Name: `pg-oauth-lab`
   - Supported account types: **Accounts in this organizational directory only**
     (single tenant) — or "personal Microsoft accounts only" for @outlook.com accounts
4. Click **Register**
5. **Note the values** on the Overview page:
   - **Application (client) ID** — you'll need this as `ENTRA_CLIENT_ID`
   - **Directory (tenant) ID** — you'll need this as `ENTRA_TENANT_ID`

### 1.2 Enable Device Flow (for psql)

1. In your app registration → **Authentication**
2. Under **Advanced settings** → **Allow public client flows** → toggle to **Yes**
3. Click **Save**

### 1.3 Add a Redirect URI (for pgAdmin)

1. Still in **Authentication** → **Add a platform** → **Web**
2. Redirect URI: `http://localhost:8091/oauth2/authorize`
3. Click **Configure**

### 1.4 Create a Client Secret (for pgAdmin)

1. **Certificates & secrets** → **New client secret**
2. Description: `pgadmin-lab`, Expires: 24 months
3. Click **Add**
4. **Copy the Value immediately** — you won't see it again
   - This is your `ENTRA_CLIENT_SECRET`

### 1.5 Expose an API (for psql scope)

1. **Expose an API** → **Add** (next to Application ID URI)
2. Accept the default URI (`api://APPLICATION_CLIENT_ID`) → **Save**
3. **Add a scope**:
   - Scope name: `pg_access`
   - Who can consent: **Admins and users**
   - Admin consent display name: `PostgreSQL access`
   - Click **Add scope**

### 1.6 Add App Roles (for role-based authorization)

1. **App roles** → **Create app role**
2. Fill in:
   - Display name: `Database User`
   - Allowed member types: **Users/Groups**
   - Value: `db_user`
   - Description: `Allows database access`
3. Click **Apply**
4. **Assign yourself**: Go to **Enterprise Applications** → find `pg-oauth-lab`
   → **Users and groups** → **Add user/group** → select your account → **db_user** role

### 1.7 Set Token Version to v2

1. **Manifest** (in your App Registration)
2. Find `"accessTokenAcceptedVersion": null` and change it to `"accessTokenAcceptedVersion": 2`
3. Click **Save**

## Step 2: Configure the pg-eu Cluster

Apply the patch that adds the `entra_validator` extension and OAuth pg_hba rules
to `pg-eu`. Substitute your actual Entra values before applying.

### Apply the patch

You can either apply the patch file directly:

```bash
patch -p1 < lab/exercise-9-oauth-sso/pg-eu-oauth.yaml.patch
sed -i \
  -e "s/ENTRA_TENANT_ID/<your-tenant-id>/g" \
  -e "s/ENTRA_APP_ID/<your-client-id>/g" \
  demo/yaml/eu/pg-eu.yaml
```

Or edit `demo/yaml/eu/pg-eu.yaml` by hand. The changes are:

**1. Add the `entra-validator` extension** (in the `postgresql.extensions` list,
after any existing extensions):

```yaml
      - name: entra-validator
        image:
          reference: ghcr.io/ardentperf/postgres-entra-oauth-validator:18-dev-trixie
        ld_library_path:
          - system
```

**2. Add `parameters`** (in the `postgresql` section, after `shared_preload_libraries`):

```yaml
    parameters:
      oauth_validator_libraries: "entra_validator"
      entra.expected_issuer: "https://login.microsoftonline.com/<ENTRA_TENANT_ID>/v2.0"
      entra.identity_claim: "preferred_username"
      entra.required_claim: "roles"
      entra.required_values: "db_user"
      entra.debug: "on"
```

**3. Add `pg_hba`** (in the `postgresql` section). If you completed Exercise 5,
the `pooler` and `pgbouncer` cert rules are already present — add only the
`pgadmin-proxy` and `oauth` lines:

```yaml
    pg_hba:
      # mTLS for app service accounts (Exercise 5) — cert rules first
      - hostssl all app       all cert map=pooler
      - hostssl all pgbouncer all cert
      # pgAdmin OAuth passthrough — cert auth using the proxy service cert
      - hostssl all all all cert map=pgadmin-proxy
      # Entra OAuth device flow for human users
      - "hostssl all all all oauth issuer=\"https://login.microsoftonline.com/<ENTRA_TENANT_ID>/v2.0\" scope=\"api://<ENTRA_CLIENT_ID>/pg_access\" validator=\"entra_validator\""
```

**4. Add `pg_ident`** (in the `postgresql` section). The `pooler` line is from
Exercise 5; the `pgadmin-proxy` line is new:

```yaml
    pg_ident:
      # From Exercise 5 (mTLS pgbouncer pooler map)
      - pooler pgbouncer app
      # pgAdmin OAuth passthrough: proxy cert CN maps to any PG username
      - "pgadmin-proxy pgadmin-proxy /^(.*)$/ \\1"
```

The `pg_hba` ordering matters: CNPG evaluates rules top-to-bottom, first match
wins. The cert rules for `app` and `pgbouncer` come before the `oauth` rule so
that mTLS service accounts are never asked to do OAuth. The `oauth` method only
triggers when the client initiates SASL OAUTHBEARER (i.e., when `psql` is given
`oauth_issuer`).

Verify the result:

```bash
git diff demo/yaml/eu/pg-eu.yaml
```

### Apply and wait for rolling restart

```bash
kubectl apply -f demo/yaml/eu/pg-eu.yaml
kubectl wait --timeout 10m --for=condition=Ready pod -l cnpg.io/cluster=pg-eu
kubectl wait --timeout 5m  --for=condition=Ready cluster/pg-eu
```

### Verify the extension loaded

```bash
kubectl exec pg-eu-1 -- psql -U postgres \
  -c "SHOW oauth_validator_libraries;"
```

You should see `entra_validator`.

## Step 3: Create the pgAdmin Proxy Certificate

The pgAdmin identity passthrough relies on a TLS client certificate with
`CN=pgadmin-proxy`, signed by the CNPG cluster's CA. cert-manager issues and
rotates it automatically.

```bash
kubectl apply -f lab/exercise-9-oauth-sso/pgadmin-proxy-cert.yaml
```

Wait for the certificate to be issued:

```bash
kubectl wait --timeout 2m \
  --for=condition=Ready certificate/pgadmin-proxy-cert
```

Verify the subject:

```bash
kubectl get secret pgadmin-proxy-cert \
  -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -dates
```

You should see `CN=pgadmin-proxy` and a validity period of ~1 year.

## Step 4: Create Your PostgreSQL Role

PostgreSQL needs a role matching your Entra identity. The `entra_validator`
extension extracts `preferred_username` from the JWT and `pg_ident` maps it
to a PG role. The mapping replaces `@` and `.` with `_` — for example,
`schneider@ardentperf.com` becomes `schneider_ardentperf_com`.

```bash
# Derive your PG username from your UPN
PG_USERNAME=$(echo "schneider@ardentperf.com" | tr '@.' '_')
# -> schneider_ardentperf_com
echo "PG username: $PG_USERNAME"
```

Create the role:

```bash
kubectl exec -i pg-eu-1 -- psql -U postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$PG_USERNAME') THEN
    CREATE USER "$PG_USERNAME" LOGIN;
    RAISE NOTICE 'Created role: $PG_USERNAME';
  END IF;
END
\$\$;
SQL
```

Verify:

```bash
kubectl exec pg-eu-1 -- psql -U postgres \
  -c "SELECT rolname FROM pg_roles WHERE rolname = '$PG_USERNAME';"
```

## Step 5: Deploy pgAdmin with Entra OAuth

The pgAdmin Helm chart uses a custom image with OAuth identity passthrough
support. Substitute your Entra values, then install:

```bash
helm install pgadmin4-oauth oci://docker.io/dpage/pgadmin4-helm \
  --kube-context kind-k8s-eu \
  -f lab/exercise-9-oauth-sso/pgadmin-oauth-values.yaml \
  --set-string "config_local.data=PLACEHOLDER" \
  --wait --timeout 3m
```

> **Note:** The values file contains `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, and
> `ENTRA_CLIENT_SECRET` placeholders. To substitute them before installing,
> write the substituted values to a temporary file:
>
> ```bash
> VALUES=$(mktemp --suffix=.yaml)
> sed \
>   -e "s/ENTRA_TENANT_ID/<your-tenant-id>/g" \
>   -e "s/ENTRA_CLIENT_ID/<your-client-id>/g" \
>   -e "s/ENTRA_CLIENT_SECRET/<your-client-secret>/g" \
>   lab/exercise-9-oauth-sso/pgadmin-oauth-values.yaml > "$VALUES"
>
> helm install pgadmin4-oauth oci://docker.io/dpage/pgadmin4-helm \
>   --kube-context kind-k8s-eu \
>   -f "$VALUES" \
>   --wait --timeout 3m
>
> rm -f "$VALUES"
> ```

Verify the pod is running:

```bash
kubectl get pods -l app=pgadmin4-oauth
```

## Step 6: Test psql OAuth Device Flow

Start a temporary pod with the PostgreSQL 18 client:

```bash
kubectl run -it --rm psql-test \
  --image=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie \
  --restart=Never -- bash
```

Inside the pod, connect using the OAuth device flow (replace the placeholders):

```bash
psql "host=pg-eu-rw \
  user=<your-pg-username> \
  dbname=postgres \
  oauth_issuer=https://login.microsoftonline.com/<ENTRA_TENANT_ID>/v2.0 \
  oauth_client_id=<ENTRA_CLIENT_ID> \
  oauth_scope=api://<ENTRA_CLIENT_ID>/pg_access"
```

Your PG username is your UPN with `@` and `.` replaced by `_` — for example,
`schneider@ardentperf.com` becomes `schneider_ardentperf_com`.

psql will display:

```
Visit https://microsoft.com/devicelogin and enter code: ABCD-1234
```

Open the URL in your browser, enter the code, sign in with your Entra account,
and approve the permission request. psql will automatically connect.

Verify your identity:

```sql
SELECT current_user, session_user;
```

## Step 7: Test pgAdmin OAuth

Port-forward pgAdmin:

```bash
kubectl --context kind-k8s-eu port-forward service/pgadmin4-oauth 8091:80 &
```

Open [http://localhost:8091](http://localhost:8091) and click **Sign in with
Microsoft**. Authenticate with your Entra account.

Register the pg-eu server with identity passthrough:

1. **Object → Register → Server**
2. **General**: Name = `pg-eu (Entra SSO)`
3. **Connection**: Host = `pg-eu-rw`, Port = `5432`, Database = `postgres`
   (leave Username and Password blank)
4. **Advanced**: Enable **"Use OAuth identity for database connection"**
5. Click **Save**

pgAdmin connects to PostgreSQL using the `pgadmin-proxy` TLS client certificate
and presents your Entra `preferred_username` as the PG username.

## Verifying Connections

Run this on the primary pod to see all active connections and their auth methods:

```sql
SELECT
  usename,
  application_name,
  ssl,
  client_dn,
  auth_method
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE backend_type = 'client backend'
ORDER BY pid;
```

Expected results:

| Connection | `auth_method` | `client_dn` | `usename` |
|---|---|---|---|
| psql OAuth | `oauth` | — | your PG username |
| pgAdmin | `cert` | `CN=pgadmin-proxy` | your PG username |
| app/pgbouncer (Ex 5) | `cert` | `CN=app` or similar | `app` |

## How It Works

### OAuth Device Flow (psql)

PostgreSQL 18 implements [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628)
(OAuth 2.0 Device Authorization Grant) in libpq. When you specify
`oauth_issuer` in the connection string:

1. libpq fetches `/.well-known/openid-configuration` to discover endpoints
2. Sends a device authorization request and displays the URL + code
3. Polls the token endpoint until you complete the browser login
4. Sends the JWT access token to PostgreSQL via SASL OAUTHBEARER

The `entra_validator` extension receives the token and:

1. Checks the `iss` claim matches `entra.expected_issuer`
2. Extracts the `preferred_username` claim as the identity (`authn_id`)
3. Checks the `roles` array contains any value in `entra.required_values`
4. Returns `authorized = true` and `authn_id = user@company.com`

PostgreSQL then uses `pg_ident` to map the UPN to a local PG role.

### OAuth Identity Passthrough (pgAdmin)

The custom pgAdmin image (`ghcr.io/ardentperf/pgadmin4:x-ai-ardentperf-oauth-passthrough-identity`)
adds the `OAUTH_PASSTHROUGH_SSL_CERT/KEY` feature:

- When a user logs in via Entra OAuth, pgAdmin stores their `preferred_username`
- When connecting to a server with "Use OAuth identity" enabled, pgAdmin:
  - Uses the proxy TLS client certificate (CN=`pgadmin-proxy`) for PG authentication
  - Sets the PG username to the stored Entra `preferred_username`
- PostgreSQL's `pg_hba.conf` allows the `pgadmin-proxy` cert to connect as any
  user via `pg_ident` wildcard mapping

The proxy certificate is signed by CNPG's own CA, so no external CA is needed.

## Troubleshooting

**psql: `authentication method "oauth" requires SASL OAUTHBEARER`**
- Make sure you're using a PostgreSQL 18 client (`psql --version`)
- The `libpq-oauth` package may need to be installed separately on some distros

**psql: `FATAL: token issuer "https://..." does not match expected "..."`**
- Check `entra.expected_issuer` in the cluster config matches your Tenant ID:
  ```bash
  kubectl get cluster pg-eu -o yaml | grep entra
  ```

**psql: `FATAL: authn_id not found in token`**
- The token is missing `preferred_username`; verify the Entra manifest has
  `"accessTokenAcceptedVersion": 2`
- Enable debug logging: set `entra.debug = on` in the cluster parameters
  and check `kubectl logs pg-eu-1`

**psql: `FATAL: token authorization failed`**
- Your account may not have the `db_user` App Role assigned
- Check: **Enterprise Applications** → `pg-oauth-lab` → **Users and groups**
- To disable role checking: set `entra.required_claim = ""` in the cluster parameters

**pgAdmin: certificate verify failed**
- The proxy certificate may not be ready yet:
  ```bash
  kubectl get certificate pgadmin-proxy-cert
  ```

**pgAdmin: `pg_ident` mapping not working**
- Check the `pgadmin-proxy` map is present:
  ```bash
  kubectl exec pg-eu-1 -- psql -U postgres \
    -c "SELECT * FROM pg_ident_file_mappings WHERE map_name = 'pgadmin-proxy';"
  ```

## Cleaning Up

```bash
# Remove pgAdmin
helm --kube-context kind-k8s-eu uninstall pgadmin4-oauth

# Remove cert-manager resources
kubectl --context kind-k8s-eu delete certificate pgadmin-proxy-cert
kubectl --context kind-k8s-eu delete issuer pg-eu-ca-issuer
kubectl --context kind-k8s-eu delete secret pgadmin-proxy-cert

# Restore pg-eu.yaml to remove OAuth config, then apply
git checkout demo/yaml/eu/pg-eu.yaml
kubectl --context kind-k8s-eu apply -f demo/yaml/eu/pg-eu.yaml
```

## Automation Script

After working through the exercise manually, you can validate the full setup
end-to-end with the automation script:

```bash
bash lab/exercise-9-oauth-sso/test-oauth-setup.sh
```

The script prompts for your Entra values and then automates all steps: applying
the cluster patch, waiting for the rolling restart, creating the proxy
certificate, creating your PostgreSQL role, and deploying pgAdmin.

Output is logged to `pgadmin-test_<timestamp>.log`.
