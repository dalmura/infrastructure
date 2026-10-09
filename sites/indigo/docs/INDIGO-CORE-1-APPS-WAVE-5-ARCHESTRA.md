# Wave 5 - Archestra Setup & Action Plan

This document outlines the setup steps required to initialize Vault roles, policies, and secrets for [Archestra](https://archestra.ai/) enterprise Model Context Protocol (MCP) and LLM management platform.

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and [`DB Management`](INDIGO-APPS-DB-MGMT.md).

---

## 1. Vault Roles and Policies Setup

Log into your `vault` CLI environment.

### Step 1.1: Create Vault AWS IAM Role for CNPG Database Backups
Replace `<iam_vended_permissions.id>` with the IAM policy ARN from your network repository:

```bash
vault write aws/roles/archestra-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=archestra" \
    iam_tags="role=postgres"
```

### Step 1.2: Create Vault Workload Reader Policy & Kubernetes Auth Role
Run the following to grant the `archestra-sa` ServiceAccount in the `archestra` namespace access to S3 dynamic credentials and application secrets:

```bash
vault policy write workload-reader-archestra-secrets -<<EOF
path "aws/creds/archestra-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/archestra/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-archestra-secrets \
   bound_service_account_names=archestra-sa \
   bound_service_account_namespaces=archestra \
   token_policies=workload-reader-archestra-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

---

## 2. Store Application Secrets in Vault

Using the Vault CLI (or Web UI at `site/data/wave-5/archestra/config`), store the authentication secrets and initial admin password:

```bash
vault kv put site/wave-5/archestra/config \
    auth_secret="$(openssl rand -hex 32)" \
    session_secret="$(openssl rand -hex 32)" \
    secrets_encryption_secret="$(openssl rand -hex 32)" \
    admin_password="<secure-initial-admin-password>"
```

> [!NOTE]
> `auth_secret`, `session_secret`, and `secrets_encryption_secret` are persistent encryption keys. Preserve these keys across backups, upgrades, and restores.

---

## 3. Sync & Deploy via ArgoCD

Once the Vault configuration is in place:

```bash
# Sync wave-5 parent app to discover archestra child application
argocd app sync wave-5

# Sync archestra child application
argocd app sync archestra
```

---

## 4. Verification

### Step 4.1: Verify Pods & CNPG Database Status
```bash
# Check all pods in the archestra namespace
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n archestra

# Check CNPG database status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get cluster -n archestra archestra-db

# Confirm pgvector extension is installed in the database
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n archestra exec archestra-db-1 -c postgres -- \
  psql -U archestra -d archestra -c "\dx"
```

### Step 4.2: Access Web UI
Navigate to [https://archestra.indigo.dalmura.cloud/](https://archestra.indigo.dalmura.cloud/) in your browser.
* Sign in using email `admin@example.com` and the `admin_password` configured in Vault.
* Navigate to settings to confirm the database and platform status are healthy.

### Step 4.3: Verify Routing
* The web UI and authentication endpoints route to the frontend port `3000`.
* The LLM Proxy and MCP Gateway route to the backend port `9000` via `/v1` and `/v2`.
* Verify backend health directly through ingress:
  ```bash
  curl -fsSL https://archestra.indigo.dalmura.cloud/health
  ```
