# Wave 5 - Matrix Setup & Action Plan

This document outlines the setup steps required to initialize Vault roles, policies, secrets, and Authentik OIDC integration for Matrix Synapse on `dal-indigo-core-1` using the official Element Server Suite (ESS) Helm chart (`matrix-stack`).

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and [`Application Authentication`](INDIGO-APPS-AUTH.md).

---

## 1. Authentik OIDC Configuration

Log into [Authentik](https://auth.indigo.dalmura.cloud).

### Step 1.1: Create OAuth2/OpenID Provider
Navigate to **Applications** => **Providers** => **Create**:
* **Type**: `OAuth2/OpenID Provider`
* **Name**: `Provider for Matrix`
* **Authorization flow**: `implicit-consent` (or `default-provider-authorization-implicit-consent`)
* **Client type**: `Confidential`
* **Redirect URIs**: 
  ```text
  https://matrix.indigo.dalmura.cloud/_synapse/client/oidc/callback
  ```
* **Scopes**: Ensure `openid`, `email`, and `profile` are selected.
* **Subject mode**: `Based on the User's hashed ID` (default)
* Note down the generated **Client ID** and **Client Secret**.

### Step 1.2: Create Application
Navigate to **Applications** => **Applications** => **Create**:
* **Name**: `Matrix`
* **Slug**: `matrix`
* **Group**: `general` (or your preferred group)
* **Provider**: Select `Provider for Matrix`
* **Launch URL**: `https://matrix.indigo.dalmura.cloud/`
* Bind appropriate group/user policies (e.g. `spoke-users` or `site-admins`).

---

## 2. Vault Roles and Policies Setup

Log into your `vault` CLI environment.

### Step 2.1: Create Vault AWS IAM Role for CNPG Database Backups
Replace `<iam_vended_permissions.id>` with the IAM policy ARN from your network repository:

```bash
vault write aws/roles/matrix-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=matrix" \
    iam_tags="role=postgres"
```

### Step 2.2: Create Vault Workload Reader Policy & Kubernetes Auth Role
Run the following to grant the `matrix-sa` ServiceAccount in the `matrix` namespace access to S3 dynamic credentials and application secrets:

```bash
vault policy write workload-reader-matrix-secrets -<<EOF
path "aws/creds/matrix-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/matrix/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-matrix-secrets \
   bound_service_account_names=matrix-sa \
   bound_service_account_namespaces=matrix \
   token_policies=workload-reader-matrix-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

---

## 3. Store Application Secrets in Vault

Using the Vault CLI (or Web UI at `site/data/wave-5/matrix/config`), generate and store the required secrets:

```bash
vault kv put site/wave-5/matrix/config \
    registration_shared_secret="$(openssl rand -hex 32)" \
    macaroon_secret_key="$(openssl rand -hex 32)" \
    form_secret="$(openssl rand -hex 32)" \
    db_password="$(openssl rand -hex 24)" \
    oidc_client_id="<authentik-client-id-from-step-1>" \
    oidc_client_secret="<authentik-client-secret-from-step-1>"
```

---

## 4. Sync & Deploy via ArgoCD

Once the Authentik and Vault configurations are in place:

```bash
# Sync wave-5 parent app to create the matrix child application
argocd app sync wave-5

# Sync matrix child application
argocd app sync matrix
```

---

## 5. Verification & Client Configuration

1. **Verify Pod & DB Status**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods,cluster -n matrix
   ```

2. **Verify Synapse Endpoint**:
   ```bash
   curl -I https://matrix.indigo.dalmura.cloud/_matrix/client/versions
   ```
   You should receive a `HTTP/2 200 OK` response with supported Matrix protocol versions.

3. **Connecting Clients (Element / Element X / Cinny / FluffyChat)**:
   - In your mobile/desktop client, set the **Homeserver URL** to:
     ```text
     https://matrix.indigo.dalmura.cloud
     ```
   - Click **Sign in with Authentik** / **SSO** to log in using your Dalmura credentials.
   - Your user ID will be `@<authentik-username>:indigo.dalmura.cloud`.

4. **Creating Admin Users / Break-Glass Accounts**:
   If needed, you can register a local admin user via the Synapse pod CLI:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n matrix matrix-synapse-main-0 -c synapse -- register_new_matrix_user -c /conf/homeserver.yaml -u admin -a
   ```

---

## 6. Optional: Enabling Element Web or Workers Later

With the `matrix-stack` Helm chart, additional components can simply be enabled in `clusters/dal-indigo-core-1/wave-5/values/matrix/values.yaml`:

```yaml
elementWeb:
  enabled: true
  ingress:
    host: "chat.indigo.dalmura.cloud"
    className: "ingress-public"
```

---

## 7. Element Call & MatrixRTC (VoIP / Video Calling)

MatrixRTC native calling for Element X and modern Matrix clients is powered by the bundled LiveKit SFU and `lk-jwt-service` authorization backend:

* **Signaling & Tokens**: Exposed via `https://rtc-matrix.indigo.dalmura.cloud` through the `ingress-public` Traefik ingress (routing `/` to LiveKit SFU on port 7880, and `/get_token`, `/sfu/get`, `/delegate_delayed_leave` to authorization service on port 8080).
* **Media Traffic (WebRTC)**: Direct audio/video streams use MetalLB LoadBalancer services pinned to `192.168.77.12` on `servers-vlan`:
  * `rtcMuxedUdp`: UDP port `30002`
  * `rtcTcp`: TCP port `30001` (fallback)
* **Router Port Forwarding**:
  For calls to connect over external networks (e.g. mobile cellular), forward the following ports on your router:
  * `UDP 30002` ➔ `192.168.77.12`
  * `TCP 30001` ➔ `192.168.77.12`
* **Split-Brain DNS (Router)**:
  ```bash
  /ip dns static add name=rtc-matrix.indigo.dalmura.cloud address=192.168.77.11
  ```
  *(Signaling runs via Traefik on port 443 at `192.168.77.11`)*
* **Client Configuration**:
  Element X caches `.well-known/matrix/client` on initial login. After deploying MatrixRTC, restart the mobile app (or log out and log back in) so that Element X discovers the `org.matrix.msc4143.rtc_foci` configuration.

> [!NOTE]
> **Standalone Element Call & Public Guest Links**:
> Hosting a standalone web frontend (e.g. `call.indigo.dalmura.cloud`) for public "Zoom-style" links is not supported with this architecture:
> 1. **No OIDC / SSO Support in Web UI**: Standalone Element Call hardcodes legacy `m.login.password` and does not yet implement the OIDC redirect dance required by Matrix Authentication Service (MAS) and Authentik ([element-call#3699](https://github.com/element-hq/element-call/issues/3699)).
> 2. **No Anonymous Guest Access in Matrix 2.0**: In modern MAS-based setups, legacy anonymous guest registrations (`kind=guest`) have been removed in favor of strict OIDC authentication. Unregistered external participants cannot join without an Authentik account.
> 
> Native VoIP/video calling is therefore intended for use directly within **Element X** (mobile) and **Element Web** (desktop), where authenticated sessions handle the calls seamlessly.

