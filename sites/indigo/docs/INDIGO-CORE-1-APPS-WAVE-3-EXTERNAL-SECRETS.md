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

### Configuration for 'Example App'
This section covers when you are creating an example app that needs one or more k8s Secrets created that are synced with a Vault secret.

The below will need to be copied and customised for each workload app in the following waves.

The example below covers our Example App, this app:
* Lives in `wave-5` of ArgoCD
* Lives in the namespace `example-app`
* Doesn't create it's own Service Account
* Requires a k8s Secret providing an `API_KEY` environment variable

Double check first that your application has a k8s Service Account (SA), if not, you can copy/paste this one into the `overlays` folder for your app:
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: example-app-sa
```

The below examples will reference this 'example-app-sa', but if your app already has a SA, substitute it instead.

First we create a policy in Vault that defines the permissions the above 'example-app-sa' will have in Vault, aka, the secrets it will be allowed to read.

It's best to correctly namespace the secrets in Vault so each wave/app is separated out to avoid any collisions/confusion.

Currently the secret hierarchy is: `secret-container/wave-X/app-name/secret-name`

Broken down:
* `secret-container` is either `public`, `site` or `site-sensitive`
  * `public` is for general cross-site secrets
    * All users in Authentik are able to access this
  * `site` is for site specific secrets, everything mostly lives here
    * Only hub-power-users in Authentik are able to access this
  * `site-sensitive` is for site specific secrets we *really* don't want leaking, like AWS access keys
    * Only site-admins in Authentik are able to access this
* `wave-X` is the ArgoCD wave the app lives in
* `app-name` is the name of the application in is slug-ified form
  * Eg `Frigate` => `frigate`, `Sealed Secrets` => `sealed-secrets`
* `secret-name` is something contextual to the contents

Firstly, we create a Policy and Role elements underneath the Kubernetes auth engine we enabled in Vault. This will allow our `example-app-sa` to authenticate to Vault and extract the required secrets. Our Policy and Role elements always start with `workload-reader-` then have the application name appended on. Eg. `workload-reader-example-app`

Creating the policy and role:
```
vault policy write workload-reader-example-app -<<EOF
# Site secrets store for Example App
path "site/data/wave-5/example-app/*" {
    capabilities = ["read", "list"]
}

# Optional sensitive secrets store
path "site-sensitive/data/wave-5/example-app/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-example-app \
   bound_service_account_names=example-app-sa \
   bound_service_account_namespaces=example-app \
   token_policies=workload-reader-example-app \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

To get the above audience we need to wait until the SA above is created then manually generate a token and decode that:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 create token example-app-sa -n example-app | cut -d '.' -f2 | base64 -d
# The output is broken up into 3 base64 strings separated by a '.'
# The second one contains the JWT itself, including the `aud` audience
```

This should stay consistent across service accounts, as the audience is the k8s cluster IP, but just incase it changes the above will tell you how to get the new audience.

Next we need to create a `SecretStore` instance for each `secret-container` you need to use (`public`, `site` or `site-sensitive`).

Example app referencing the `site` `secret-container`:
```
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: site
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "site"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "workload-reader-example-app"

          serviceAccountRef:
            name: "example-app-sa"
```

Once the SecretStore(s) are created, we can now create one or more `ExternalSecret` resources referencing the `SecretStore` resources.

Example `ExternalSecret` referencing the above site `SecretStore`:
```
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example-app-env
spec:
  secretStoreRef:
    name: secret-container-site
    kind: SecretStore

  refreshPolicy: Periodic
  refreshInterval: 1h

  data:
  - secretKey: API_TOKEN
    remoteRef:
      key: wave-5/example-app/env
      property: API_TOKEN
```

The above will then create (and refresh every hour) the following k8s Secret:
```
apiVersion: v1
kind: Secret
metadata:
  name: example-app-env
type: Opaque
data:
  API_TOKEN: "Value From site/data/wave-5/example-app/env => API_TOKEN"
```
