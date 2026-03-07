# Exercise 9: SSO with Microsoft Entra ID

This exercise demonstrates Single Sign-On (SSO) with Microsoft Entra ID (Azure AD)
for both PostgreSQL and pgAdmin. Human users authenticate once with their corporate
Entra identity and connect directly — no separate database passwords needed.

---

## What You'll Learn

- How PostgreSQL 18's native OAuth device flow works with Entra ID
- How the `entra_validator` extension validates JWT tokens offline
- How pgAdmin can use your Entra identity to connect to PostgreSQL transparently
- How OAuth authentication coexists with mTLS for service accounts (Exercise 5)

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

---

## Prerequisites

- **Exercise 2** completed: pg-eu cluster running on `kind-k8s-eu`
- **Exercise 5** completed or cert-manager installed (needed for proxy cert)
  - If you haven't done Exercise 5, install cert-manager:
    ```bash
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager --create-namespace \
      --set crds.enabled=true
    ```
- **Free Microsoft account** (personal @outlook.com, @hotmail.com, or corporate)
  — a free Azure subscription is not required for Entra app registrations
- `kubectl`, `helm`, `patch` in your PATH

---

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

---

## Step 2: Run the Setup Script

The setup script handles all configuration automatically:

```bash
bash lab/exercise-9-oauth-sso/test-oauth-setup.sh
```

It will prompt for your Entra values, then:
- Create the pgAdmin proxy certificate
- Patch `pg-eu.yaml` with Entra GUCs and pg_hba rules
- Wait for the cluster rolling restart
- Create your PostgreSQL role
- Deploy pgAdmin with Entra OAuth

---

## Step 3: Test psql OAuth Device Flow

```bash
# Start a temporary test pod with PG 18 client
kubectl --context kind-k8s-eu run -it --rm psql-test \
  --image=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie \
  --restart=Never -- bash
```

Inside the pod:

```bash
# Connect using OAuth device flow
psql "host=pg-eu-rw \
  user=<your-pg-username> \
  dbname=postgres \
  oauth_issuer=https://login.microsoftonline.com/ENTRA_TENANT_ID/v2.0 \
  oauth_client_id=ENTRA_CLIENT_ID \
  oauth_scope=api://ENTRA_CLIENT_ID/pg_access"
```

Replace `<your-pg-username>` with the username shown by the setup script
(your UPN with `@` and `.` replaced by `_`).

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

---

## Step 4: Test pgAdmin OAuth

1. Port-forward pgAdmin:
   ```bash
   kubectl --context kind-k8s-eu port-forward service/pgadmin4-oauth 8091:80 &
   ```

2. Open [http://localhost:8091](http://localhost:8091)

3. Click **Sign in with Microsoft** and authenticate with your Entra account

4. Register the pg-eu server:
   - **Object → Register → Server**
   - **General**: Name = `pg-eu (Entra SSO)`
   - **Connection**: Host = `pg-eu-rw`, Port = `5432`, Database = `postgres`
     (leave Username and Password blank)
   - **Advanced**: Enable **"Use OAuth identity for database connection"**
   - Click **Save**

5. pgAdmin will connect to PostgreSQL using:
   - Your Entra `preferred_username` as the PG username
   - The `pgadmin-proxy` TLS client certificate for authentication

---

## Verifying Connections

On the primary pod:

```sql
-- Who is connected and how?
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
- psql OAuth connections: `auth_method = oauth`, `usename = <your-pg-username>`
- pgAdmin connections: `auth_method = cert`, `client_dn = CN=pgadmin-proxy`,
  `usename = <your-pg-username>`
- Service account connections (from Ex 5): `auth_method = cert`,
  `usename = app` or `pgbouncer`

---

## How It Works

### OAuth Device Flow (psql)

PostgreSQL 18 implements [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628)
(OAuth 2.0 Device Authorization Grant) in libpq. When you specify
`oauth_issuer` in the connection string:

1. libpq fetches `/.well-known/openid-configuration` to discover endpoints
2. Sends a device authorization request and shows you the URL + code
3. Polls the token endpoint until you complete the browser login
4. Sends the JWT access token to PostgreSQL via SASL OAUTHBEARER

The `entra_validator` extension receives the token and:
1. Checks the `iss` claim matches `entra.expected_issuer`
2. Extracts the `preferred_username` claim as the identity
3. Checks the `roles` array contains `db_user` (or any value in `entra.required_values`)
4. Returns `authorized = true` and `authn_id = user@company.com`

PostgreSQL then uses `pg_ident` to map the UPN to a local PG role.

### OAuth Identity Passthrough (pgAdmin)

The custom pgAdmin image (`ghcr.io/ardentperf/pgadmin4:x-ai-ardentperf-oauth-passthrough-identity`)
adds the `OAUTH_PASSTHROUGH_SSL_CERT/KEY` feature:

- When a user logs into pgAdmin via Entra OAuth, pgAdmin stores their `preferred_username`
- When connecting to a server with "Use OAuth identity" enabled, pgAdmin:
  - Uses the proxy TLS client certificate (CN=`pgadmin-proxy`) for PG authentication
  - Sets the PG username to the Entra `preferred_username` value
- PostgreSQL's `pg_hba.conf` allows the `pgadmin-proxy` cert to connect as any user
  via `pg_ident`

The proxy certificate is signed by CNPG's CA, so no external CA is needed.

---

## Troubleshooting

**psql: `authentication method "oauth" requires SASL OAUTHBEARER`**
- Make sure you're using PostgreSQL 18 client (`psql --version`)
- The `libpq-oauth` package may need to be installed separately

**psql: `FATAL: token issuer "https://..." does not match expected "..."`**
- Check `entra.expected_issuer` in `postgresql.conf` matches your Tenant ID
- View the cluster config: `kubectl get cluster pg-eu -o yaml | grep entra`

**psql: `FATAL: authn_id not found in token`**
- The token doesn't contain `preferred_username`; check your Entra manifest
  has `"accessTokenAcceptedVersion": 2`
- Try setting `entra.debug = on` and check PostgreSQL logs

**psql: `FATAL: token authorization failed`**
- Your Entra account may not have the `db_user` App Role assigned
- Check **Enterprise Applications** → `pg-oauth-lab` → **Users and groups**
- Or set `entra.required_claim =` (empty) to disable role check

**pgAdmin: certificate verify failed**
- The proxy certificate may not be ready yet; check with:
  ```bash
  kubectl get certificate pgadmin-proxy-cert
  ```

**pgAdmin: `pg_ident` mapping not working**
- Check that the `pgadmin-proxy` map is in `pg_ident.conf`:
  ```bash
  kubectl exec pg-eu-1 -- psql -U postgres -c "SELECT * FROM pg_ident_file_mappings;"
  ```

---

## Cleaning Up

```bash
# Remove pgAdmin
helm --kube-context kind-k8s-eu uninstall pgadmin4-oauth

# Remove cert-manager resources
kubectl --context kind-k8s-eu delete certificate pgadmin-proxy-cert
kubectl --context kind-k8s-eu delete issuer pg-eu-ca-issuer
kubectl --context kind-k8s-eu delete secret pgadmin-proxy-cert

# Restore pg-eu.yaml to remove OAuth config
git checkout demo/yaml/eu/pg-eu.yaml
kubectl --context kind-k8s-eu apply -f demo/yaml/eu/pg-eu.yaml
```
