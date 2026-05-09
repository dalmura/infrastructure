# Provision the Wave 6 applications for dal-indigo-core-1

These are:
* [Tailscale Kubernetes Operator](https://tailscale.com/docs/features/kubernetes-operator) exposing cluster networking to a Tailscale tailnet

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and have a few applications you want to expose via Tailscale
* `vault` is logged in (see [dynamic user docs](INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md) if not)


## Tailscale Operator Setup

Assuming you already have a Tailscale account and have created an OAuth Client in the Tailscale admin console with `devices` (write) and `operator` scopes. Note down the OAuth Client ID and Secret.

### Store credentials in Vault
Open up [Vault](https://vault.indigo.dalmura.cloud/) and create a secret at `site/wave-6/tailscale/operator` with the following keys:
* `client_id`: `<YOUR_CLIENT_ID>`
* `client_secret`: `<YOUR_CLIENT_SECRET>`

### Configure Vault Permissions
You need to allow the Tailscale ServiceAccount to read these secrets. Execute the following in your Vault CLI:

```bash
# Create the Vault permissions policy
vault policy write workload-reader-tailscale -<<EOF
path "site/data/wave-6/tailscale/*" {
    capabilities = ["read", "list"]
}
EOF

# Create the role that ESO will use to access Vault
vault write auth/kubernetes/role/workload-reader-tailscale \
   bound_service_account_names=tailscale-operator \
   bound_service_account_namespaces=tailscale \
   token_policies=workload-reader-tailscale \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

We have already provisioned the `SecretStore` and `ExternalSecret` in the `wave-6` overlays to automatically sync these into a Kubernetes Secret named `operator-oauth`.

## Create the wave-6 parent app & deploy children
```bash
argocd app create wave-6 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-6/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-6

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-6
```

## Validation
Check the status of the operator pods:
```bash
kubectl get pods -n tailscale
```

Once running, you can expose services to your tailnet using the `tailscale.com/expose: "true"` annotation or by creating `TailnetDevice` resources.
