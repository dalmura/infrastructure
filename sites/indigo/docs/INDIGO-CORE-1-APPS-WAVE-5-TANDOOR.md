# Wave 5 - Tandoor Setup & Action Plan

This document outlines the setup steps required to initialize Vault roles, policies, and secrets for Tandoor with Authentik Native OIDC Integration.

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and [`Application Authentication`](INDIGO-APPS-AUTH.md).

---

## 1. Authentik OIDC Configuration

Log into [Authentik](https://auth.indigo.dalmura.cloud).

### Step 1.1: Create OAuth2/OpenID Provider
Navigate to **Applications** => **Providers** => **Create**:
* **Type**: `OAuth2/OpenID Provider`
* **Name**: `Provider for Tandoor`
* **Authorization flow**: `implicit-consent` (or `default-provider-authorization-implicit-consent`)
* **Client type**: `Confidential`
* **Redirect URIs**: 
  ```text
  https://tandoor.indigo.dalmura.cloud/accounts/oidc/authentik/login/callback/
  ```
* **Scopes**: Ensure `openid`, `email`, `profile`, and `Application Entitlements` are selected.
* **Subject mode**: `Based on the User's hashed ID` (default)
* Note down the generated **Client ID** and **Client Secret**.

### Step 1.2: Create Application
Navigate to **Applications** => **Applications** => **Create**:
* **Name**: `Tandoor`
* **Slug**: `tandoor`
* **Group**: `general` (or your preferred group)
* **Provider**: Select `Provider for Tandoor`
* **Launch URL**: `https://tandoor.indigo.dalmura.cloud/accounts/oidc/authentik/login/`
* Bind appropriate group/user policies (e.g. `spoke-users` or `site-admins`).

---

## 2. Vault Roles and Policies Setup

Log into your `vault` CLI environment.

### Step 2.1: Create Vault AWS IAM Role for CNPG Database Backups
Replace `<iam_vended_permissions.id>` with the IAM policy ARN from your network repository:

```bash
vault write aws/roles/tandoor-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=tandoor" \
    iam_tags="role=postgres"
```

### Step 2.2: Create Vault Workload Reader Policy & Kubernetes Auth Role
Run the following to grant the `tandoor-sa` ServiceAccount in the `tandoor` namespace access to S3 dynamic credentials and application secrets:

```bash
vault policy write workload-reader-tandoor-secrets -<<EOF
path "aws/creds/tandoor-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/tandoor/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-tandoor-secrets \
   bound_service_account_names=tandoor-sa \
   bound_service_account_namespaces=tandoor \
   token_policies=workload-reader-tandoor-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

---

## 3. Store Application Secrets in Vault

Using the Vault CLI (or Web UI at `site/data/wave-5/tandoor/config`), store the application secret key and Authentik OIDC credentials:

```bash
vault kv put site/wave-5/tandoor/config \
    secret_key="$(openssl rand -hex 32)" \
    oidc_client_id="<authentik-client-id-from-step-1>" \
    oidc_client_secret="<authentik-client-secret-from-step-1>"
```

---

## 4. Sync & Deploy via ArgoCD

Once the Authentik and Vault configurations are in place:

```bash
# Sync wave-5 parent app
argocd app sync wave-5

# Sync tandoor child application
argocd app sync tandoor
```

---

## 5. Verification

1. **Verify Pod Status**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n tandoor
   ```
2. **Access Web Application & Test SSO**:
   Navigate to [https://tandoor.indigo.dalmura.cloud/](https://tandoor.indigo.dalmura.cloud/). You should see an **Authentik** login button. Clicking it will redirect to Authentik for single sign-on and automatically create and link your user space in Tandoor.


There is a break-glass setup by navigating to: https://tandoor.indigo.dalmura.cloud/accounts/login/?form=1

You will be able to log in as the initially configured admin account.
