# Provision External Secrets for dal-indigo-core-1

This guide covers the overall setup of External Secrets (ES), deployed as part of `wave-3`.

External Secrets manages syncing (but not limited to) Vault Secrets with Kubernetes Secrets along with restarting related workloads.

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3 - Vault](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md) and have Vault running with OIDC authentication and the kv engines setup at the paths `public`, `site` and `site-sensitive`


## Setup Vault's Kubernetes Auth
Log into the Vault CLI:
```
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
vault login -method=token

# Enter your root token from earlier
# Or authenticate via OIDC with an admin role
```

Enable the kubernetes auth engine:
```
vault auth enable kubernetes

vault write auth/kubernetes/config \
   kubernetes_host="https://192.168.77.2:6443/"
```

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
   audience="https://192.168.77.2:6443/" \
   ttl=24h
```

To get the above audience we need to wait until the SA above is created then manually generate a token and decode that:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 create token example-app-sa -n example-app | cut -d '.' -f2 | base64 -d
# The output is broken up into 3 base64 strings separated by a '.'
# The second one contains the JWT itself, including the `aud` audience
```

Once the above is done you can ensure the following overlays are created in your app:
```

```
