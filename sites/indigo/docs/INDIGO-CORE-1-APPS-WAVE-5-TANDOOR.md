# Wave 5 - Tandoor Setup & Action Plan

This document outlines the setup steps required to initialize Vault roles, policies, and secrets for **Tandoor** (recipe management) before deploying it into the `dal-indigo-core-1` cluster.

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md).

---

## 1. Vault Roles and Policies Setup

Log into your logged-in `vault` CLI environment.

### Step 1.1: Create Vault AWS IAM Role for CNPG Database Backups
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

### Step 1.2: Create Vault Workload Reader Policy & Kubernetes Auth Role
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

## 2. Store Application Secret in Vault

Using the Vault Web UI (or CLI), navigate to the `site` KV secret engine:

1. Path: `wave-5/tandoor/config`
2. Key / Value pairs:
   - `secret_key`: `<generate_random_secret_key>`

Alternatively, via Vault CLI:
```bash
vault kv put site/wave-5/tandoor/config secret_key="$(openssl rand -hex 32)"
```

---

## 3. Sync & Deploy via ArgoCD

Once the Vault steps are completed, sync `wave-5` to pick up the new Tandoor child application:

```bash
# Sync wave-5 parent app
argocd app sync wave-5

# Sync tandoor child application
argocd app sync tandoor
```

---

## 4. Verification

1. **Verify Pod Status**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n tandoor
   ```
2. **Access Web Application**:
   Navigate to [https://tandoor.indigo.dalmura.cloud/](https://tandoor.indigo.dalmura.cloud/) on private ingress.
