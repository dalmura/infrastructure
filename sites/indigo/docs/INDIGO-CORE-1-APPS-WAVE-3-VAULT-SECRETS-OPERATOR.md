# Provision Vault Secrets Operator for dal-indigo-core-1

This guide covers the overall setup of the Vault Secrets Operator (VSO) deployed as part of `wave-3`.

The VSO manages syncing Vault Secrets with Kubernetes Secrets along with restarting related workloads.

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md) and have Vault running with OIDC authentication and the kv engines setup at the paths `site` and `site-sensitive`


## Setup Vault's Kubernetes Auth
Log into the Vault CLI:
```
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
vault login -method=token

# Enter your root token from above
```

Enable the kubernetes auth engine:
```
vault auth enable kubernetes

vault write auth/kubernetes/config \
   kubernetes_host="https://192.168.77.2:6443/"
```

Create a role that our VSO service account will use:
```
vault policy write vault-secrets-operator -<<EOF
path "site/data/*" {
    capabilities = ["read", "list"]
}

path "site-sensitive/data/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/vault-secrets-operator \
   bound_service_account_names=vault-secrets-operator \
   bound_service_account_namespaces=vault \
   token_policies=vault-secrets-operator \
   audience=vault \
   ttl=24h
```
