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

Enable the transit secret engine:
```
vault secrets enable transit

vault write -force transit/keys/vso-client-cache
```

Create a role that our VSO service account will use for transit encryption:
```
vault policy write vso-operator -<<EOF
path "encrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
path "decrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
EOF

vault write auth/kubernetes/role/auth-role-operator \
   bound_service_account_names=vault-secrets-operator-controller-manager \
   bound_service_account_namespaces=vault-secrets-operator-system \
   token_ttl=0 \
   token_period=120 \
   token_policies=vso-operator \
   audience=vault
```

Only after applying the above configuration will the `vault-secrets-operator-default-transit-auth` resource in ArgoCD sync correctly.

### Configuration for Example App
The below will need to be copied and customised for each workload app in the following waves.

Create a policy in vault that allows example-app to read its secrets:
```
vault policy write workload-reader-example-app -<<EOF
# Main secrets store
path "site/data/example-app/*" {
    capabilities = ["read", "list"]
}

# Optional sensitive secrets store
path "site-sensitive/data/example-app/*" {
    capabilities = ["read", "list"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-example-app \
   bound_service_account_names=example-app-sa \
   bound_service_account_namespaces=example-app \
   token_policies=workload-reader-example-app \
   audience=vault \
   ttl=24h
```
