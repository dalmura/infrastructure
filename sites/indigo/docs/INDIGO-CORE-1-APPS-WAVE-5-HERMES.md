# Wave 5 - Hermes Agent Setup & Action Plan

This document outlines the setup steps required to initialize Authentik OIDC, Vault roles, policies, and secrets for [Hermes Agent](https://github.com/NousResearch/hermes-agent), routed through the in-cluster [Archestra](INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md) LLM gateway and reachable via Slack Socket Mode and the private web dashboard (`https://hermes.indigo.dalmura.cloud`).

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md), [`Application Authentication`](INDIGO-APPS-AUTH.md), and [`Archestra Setup`](INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md).

---

## 1. Authentik OIDC Configuration

Log into [Authentik](https://auth.indigo.dalmura.cloud).

> [!IMPORTANT]
> Hermes Agent's built-in dashboard OIDC provider does not maintain its own email or group allowlist; any identity issued a token for the client can sign in and access the agent workspace. **Access control must be enforced in Authentik via group binding on the Application.**

### Step 1.1: Create OAuth2/OpenID Provider
Navigate to **Applications** => **Providers** => **Create**:
* **Type**: `OAuth2/OpenID Provider`
* **Name**: `Provider for Hermes`
* **Authorization flow**: `implicit-consent` (or `default-provider-authorization-implicit-consent`)
* **Client type**: `Public` (Hermes dashboard uses OIDC with PKCE)
* **Redirect URIs**:
  ```text
  https://hermes.indigo.dalmura.cloud/auth/callback
  ```
* **Scopes**: Ensure `openid`, `email`, and `profile` are selected.
* **Subject mode**: `Based on the User's hashed ID` (default)
* Note down the generated **Client ID**.

### Step 1.2: Create Application & Bind Group
Navigate to **Applications** => **Applications** => **Create**:
* **Name**: `Hermes`
* **Slug**: `hermes`
* **Group**: `general` (or your preferred group)
* **Provider**: Select `Provider for Hermes`
* **Launch URL**: `https://hermes.indigo.dalmura.cloud/`
* Open the **Policy / Group / User Bindings** tab on the newly created `Hermes` application and **bind a restricted group** (e.g. `site-admins` or a dedicated `hermes-users` group). Do **not** leave the application unbound.

---

## 2. Vault Roles and Policies Setup

Log into your `vault` CLI environment.

### Step 2.1: Create Vault Workload Reader Policy & Kubernetes Auth Role
Run the following to grant the `hermes` ServiceAccount in the `hermes` namespace read access to `site/data/wave-5/hermes/*`:

```bash
vault policy write workload-reader-hermes-secrets -<<EOF
path "site/data/wave-5/hermes/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-hermes-secrets \
   bound_service_account_names=hermes \
   bound_service_account_namespaces=hermes \
   token_policies=workload-reader-hermes-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

---

## 3. Store Application Secrets in Vault

Before storing secrets, create a **standard Virtual API Key** in Archestra (**Virtual Keys**) and map it to the provider key(s) Hermes needs. Hermes uses the OpenAI-compatible Unified Model API at `/v1/unified-model`, and the default model is `deepseek:deepseek-flash`, so at minimum map the **DeepSeek** provider key. The model ID must match an entry returned by `GET /v1/unified-model/models`.

Using the Vault CLI (or Web UI at `site/data/wave-5/hermes/config`), store the Archestra virtual key, Authentik OIDC Client ID, and Slack Socket Mode credentials:

```bash
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg archestra_key '<archestra-virtual-api-key>' \
  --arg oidc_client_id '<authentik-client-id-from-step-1>' \
  --arg slack_bot_token 'xoxb-...' \
  --arg slack_app_token 'xapp-...' \
  --arg slack_allowed_users '<comma-separated-slack-member-ids>' \
  '{
    ARCHESTRA_API_KEY: $archestra_key,
    HERMES_DASHBOARD_OIDC_CLIENT_ID: $oidc_client_id,
    SLACK_BOT_TOKEN: $slack_bot_token,
    SLACK_APP_TOKEN: $slack_app_token,
    SLACK_ALLOWED_USERS: $slack_allowed_users
  }' >"$tmp"

vault kv put site/wave-5/hermes/config @"$tmp"
```

> [!NOTE]
> Every key listed under `externalSecret.data` in `values/hermes/values.yaml` must exist in `site/wave-5/hermes/config` or External Secrets Operator will report `SecretSyncedError`.

---

## 4. Sync & Deploy via ArgoCD

Once Authentik and Vault are configured:

```bash
# Sync traefik-private and archestra so the new Cilium ingress/egress rules are active
argocd app sync traefik-private
argocd app sync archestra

# Sync wave-5 parent app to discover the hermes child application
argocd app sync wave-5

# Sync hermes child application
argocd app sync hermes
```

---

## 5. Verification

1. **Verify ExternalSecret & Pod Status**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get pods,svc,ingress,pvc,externalsecret,secretstore

   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get externalsecret hermes-env \
     -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
   ```
2. **Verify PostSync Helm Test Job**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get jobs,pods -l app.kubernetes.io/component=test
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     logs job/hermes-test --tail=-1
   ```
3. **Verify Dashboard & Authentik SSO**:
   * Navigate to [https://hermes.indigo.dalmura.cloud/](https://hermes.indigo.dalmura.cloud/).
   * Confirm unauthenticated requests redirect to Authentik (`https://auth.indigo.dalmura.cloud/application/o/authorize/...`).
   * Confirm a member of the bound Authentik group can sign in and view sessions/status/logs, while a non-member is denied by Authentik.

---

## 6. Operations & Maintenance Notes

* **Persistent Config (`bootstrap.overwrite`)**: The chart seeds `/opt/data/config.yaml` only on first boot (`bootstrap.overwrite: false`) so runtime changes made through the dashboard or CLI persist across restarts. If you later change `dashboard.publicUrl`, `dashboard.trustedProxies`, or `config.*` in `values/hermes/values.yaml`, temporarily set `bootstrap.overwrite: true` for one sync (or update `/opt/data/config.yaml` on the PVC), then revert `bootstrap.overwrite` to `false`.
* **Storage & Backups**: `/opt/data` (`HERMES_HOME`) uses a `10Gi` `cluster-regular` Longhorn block volume, which is covered by the `daily-default-backup` recurring S3 job and protected with `Delete=false` / `helm.sh/resource-policy: keep`.
* **Single Replica Only**: Hermes uses SQLite in WAL mode under `/opt/data`; keep `replicaCount: 1` with `Recreate` strategy.
