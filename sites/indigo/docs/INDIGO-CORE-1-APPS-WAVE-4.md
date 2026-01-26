# Provision the Wave 4 applications for dal-indigo-core-1

These are:
* [Renovate](https://docs.renovatebot.com/) for automated dependency management
* [VictoriaLogs Single](https://docs.victoriametrics.com/helm/victoria-logs-single/)
* [VictoriaLogs Collector](https://docs.victoriametrics.com/helm/victoria-logs-collector/)
* [VictoriaMetrics Single](https://docs.victoriametrics.com/helm/victoria-metrics-single/)

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` and `vault` are logged in

## Renovate Secret
Renovate requires a 'config.js' secret to be created to confirm the initial configuration that contains github tokens/etc.

Go to [Github Tokens](https://github.com/settings/tokens):
* Create a token named `indigo-cloud-renovate`
* Give it the whole `repo` scope
* Ensure there is 'No expiration' set on the token
* Note down the token value, you cannot see it again

Open up [Vault](https://vault.indigo.dalmura.cloud/), sign in as as user with the `site-admins` or `hub-power-users`, as we'll be saving the config under the `site/` path in Vault.

Create a secret under the `site` secret with the path `wave-4/renovate/config` with the following `config.js` key.

The contents of the `config.js` key:
```
module.exports = {
  token: '<your github token from above>',
  platform: 'github',
  onboardingConfig: {
    extends: ['config:recommended'],
  },
  repositories: ['dalmura/infrastructure'],
};
```

We've already configured the 'ExternalSecret' resource in the wave-4 renovate application to reference the above secret correctly.

## Victoria Metrics/Logs Helm Chart Versions

You can look at the latest version of the charts with:
```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/

helm repo update
helm search repo vm/

NAME                             	CHART VERSION	APP VERSION	DESCRIPTION
...
vm/victoria-logs-collector       	0.2.7        	v1.43.1    	VictoriaLogs Collector - collects logs from Kub...
vm/victoria-logs-single          	0.11.24      	v1.43.1    	The VictoriaLogs single Helm chart deploys Vict...
vm/victoria-metrics-single       	0.29.0       	v1.134.0   	VictoriaMetrics Single version - high-performan...
...

You can then copy them into the app template file.
```

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-4/app/templates/

% cat renovate.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-4/overlays/renovate
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-4/overlays/renovate?ref=HEAD'
```

## Create the wave-4 parent app & deploy children
```bash
argocd app create wave-4 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-4/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-4

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-4
```

## Renovate Configuration
By default the `ExternalSecret` and `SecretStore` resources will be broken until we deploy the correct Vault and ESO integration for Renovate.

We'll need to follow the steps in [INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md](INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md) specifically setting up the Vault config.

Use the following context to substitute in:
* Namespace: `renovate`
* ServiceAccount: `renovate-sa`
* Reader Role: `workload-reader-renovate`
* Vault Secret Engine: `site`
* Vault Secret Path: `site/data/wave-4/renovate/*`

This should result in:
```
# Create the Vault permissions policy
vault policy write workload-reader-renovate -<<EOF
path "site/data/wave-4/renovate/*" {
    capabilities = ["read", "list"]
}
EOF

# Create the role that ESO will use to access Vault
vault write auth/kubernetes/role/workload-reader-renovate \
   bound_service_account_names=renovate-sa \
   bound_service_account_namespaces=renovate \
   token_policies=workload-reader-renovate \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

After the above are applied you can recreate the `SecretStore` and then `ExternalSecret` resources in the renovate app in ArgoCD.

## Grafana Access

Once DNS propagates Grafana will be available via it's [Ingress Resource](https://grafana.indigo.dalmura.cloud/)

You can get the default admin credentials via:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get secret grafana -n grafana -o json | jq -r '.data."admin-user"' | base64 -d; echo

kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get secret grafana -n grafana -o json | jq -r '.data."admin-password"' | base64 -d; echo
```

If the above is wrong/out of sync, you can manually reset the admin password via the Pod's CLI:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n grafana grafana-78c77f8d86-skkl7 -- /bin/bash

$ grafana-cli admin reset-admin-password <your-password-here>
```

Either way you will be prompted to change the password on first login.

Once logged in we need to setup OIDC Authentication from Authentik.

Follow [INDIGO-APPS-AUTH.md](./INDIGO-APPS-AUTH.md)'s 'Native OIDC Authentication' steps providing the following:
* Redirect URI: `https://grafana.indigo.dalmura.cloud/login/generic_oauth`
* Logout URI: `https://grafana.indigo.dalmura.cloud/logout'
* Logout Method: `Front-chanel`
* Ensuring 'Application Entitlements' scope is added
* Binding `hub-power-users` (order 0) and `site-admins` (order 1)

After creating the above, navigate to the Grafana application and create the following entitlements:
* `Grafana Admins` bound to `site-admin`
* `Grafana Editors` bound to `hub-power-users`

Now in Grafana go to `Administration` => `Authentication` and configure `Generic OAuth`.

General settings:
* Display Name: Dalmura SSO
* Client ID from Authentik
* Client Secret from Authentik
* Scopes: `openid`, `profile`, `email`, `entitlements`
* OpenID Connect Discovery URL: `https://auth.indigo.dalmura.cloud/application/o/grafana/.well-known/openid-configuration`
* Sign out redirect URL: `https://auth.indigo.dalmura.cloud/application/o/grafana/end-session/'

User mapping:
* Name attribute path: `name`
* Login attribute path: `preferred_username`
* Role attribute path: `contains(entitlements[*], 'Grafana Admins') && 'Admin' || contains(entitlements[*], 'Grafana Editors') && 'Editor' || 'Viewer'`


## Grafana Configuration

Open `Connections` and install the following new connection plugins:
* `VictoriaLogs`
* `VictoriaMetrics`

Navigate to `Data sources` and add the following:
* VictoriaLogs
   * HTTP URL: `http://victoria-logs-single-vls-server.victoria-logs.svc.cluster.local:9428/`
* VictoriaMetrics
   * HTTP URL: `http://victoria-metrics-single-vms-server.victoria-metrics.svc.cluster.local:8428/`
