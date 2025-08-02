# Provision the Wave 5 applications for dal-indigo-core-1

These are:
* [Frigate](https://frigate.video/) for Security NVR
* [Plex](https://www.plex.tv/) for Media Library Playback

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in
* Traefik ingress controller is running
* Vault is operational

## Create Vault Secret(s)

### Frigate Secrets
Frigate requires a detailed config file that outlines all the security camera settings, along with credentials for each camera. As such it doesn't make sense to commit some of the config into git, and some in Vault.

Instead we'll commit the entire config into vault and load that into Frigate!

Open up [Vault](https://vault.indigo.dalmura.cloud/), sign in as as user with the `site-admins` or `hub-power-users`, as we'll be saving the config under the `site/` path in Vault.

Copy the contents of the [frigate.yaml example file](examples/indigo-core-1-apps-wave-5-frigate.yaml) and save it into a secret with the path `site/wave-5/frigate/values` under the `config.yaml` key, and customise it to your liking.

Create a secret with the path `site/wave-5/frigate/env`, with the following keys:
* `PLUS_API_KEY` set to your Frigate Plus API key

After these have been created we need to create the workload specific vault roles to let the secrets be extracted from Vault by a Service Account within the Frigate namespace.

See [`dal-indigo-core-1` Apps - Wave 3 - Vault Secrets Operator](INDIGO-CORE-1-APPS-WAVE-3-VAULT-SECRETS-OPERATOR.md) for more context on this.

Paste the following into your logged in `vault` CLI:
```
vault policy write workload-reader-frigate-secrets -<<EOF
# Main secrets store
path "site/data/wave-5/frigate/*" {
    capabilities = ["read", "list"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-frigate-secrets \
   bound_service_account_names=frigate-secrets \
   bound_service_account_namespaces=frigate \
   token_policies=workload-reader-frigate-secrets \
   audience=vault \
   ttl=24h
```

We provision within [wave-5/overlays/frigate/](sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/frigate/):
* `ServiceAccount` and `VaultAuth` resources as that reference the above created 'auth role'
* `VaultStaticSecret` to reference the above created `site/wave-5/frigate/values` vault secret

The end result after deploying this will be a `frigate-values` Secret managed by VSO that will automatically update when the config is modified within Vault.

### Plex Secrets
Plex requires a `PLEX_CLAIM` environment variable that we need to securely pass into the Pod as a once-off activity. After that it's not required anymore. To avoid committing this into git and having someone else steal it for the few seconds it's visible but not used yet, we do it via a Vault secret.

Open up [Vault](https://vault.indigo.dalmura.cloud/), sign in as as user with the `site-admins` or `hub-power-users`, as we'll be saving the config under the `site/` path in Vault.

Create a secret under the `site` secret with the path `wave-5/plex/env` with the following keys:
* `PLEX_CLAIM`, with the value from https://account.plex.tv/en/claim

Note, this token expires after 5 minutes, if so, repeat these steps creating a new version of the secret in Vault, and delete the Secret in the `plex` namespace to have it recreated from Vault.

After these have been created we need to create the workload specific vault roles to let the secrets be extracted from Vault by a Service Account within the Plex namespace.

See [`dal-indigo-core-1` Apps - Wave 3 - Vault Secrets Operator](INDIGO-CORE-1-APPS-WAVE-3-VAULT-SECRETS-OPERATOR.md) for more context on this.

Paste the following into your logged in `vault` CLI:
```
vault policy write workload-reader-plex-secrets -<<EOF
# Main secrets store
path "site/data/wave-5/plex/*" {
    capabilities = ["read", "list"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-plex-secrets \
   bound_service_account_names=plex-plex-media-server \
   bound_service_account_namespaces=plex \
   token_policies=workload-reader-plex-secrets \
   audience=vault \
   ttl=24h
```

We provision within [wave-5/overlays/plex/](sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/plex/):
* `VaultAuth` to reference the above created 'auth role' (the Service Account is handled via the Helm chart)
* `VaultStaticSecret` to reference the above created `site/wave-5/plex/env` vault secret

The end result after deploying this will be a `plex-env` Secret managed by VSO that will automatically update when it's modified within Vault.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-5/app/templates/

% cat frigate.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/frigate
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/frigate?ref=HEAD'
```

## Create the wave-5 parent app & deploy children
```bash
argocd app create wave-5 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-5/app

# Create the child applications
argocd app sync wave-5

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-5
```

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Setup Frigate Config

The Frigate config deployed via the Helm chart will be empty, and cause the container to crash out. We need to then spin up a debug container, mounting in the config volume so we can copy in the correct config:
```bash
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n frigate
NAME                      READY   STATUS    RESTARTS   AGE
frigate-85887669f-zkxcc   0/1     Running   0          80s

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n frigate frigate-85887669f-zkxcc -c frigate -- /bin/bash
apt-get update
apt-get install vim

cd /config
vim config.yml
```

You can paste in the following example config and tweak to your needs:
```yaml
mqtt:
  # Initially, will be enabled later
  enabled: False

detectors:
  hailo8l:
    type: hailo8l
    device: PCIe

model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  model_type: ssd
  path: /config/model_cache/h8l_cache/ssd_mobilenet_v1.hef

record:
  enabled: true
  retain:
    days: 7
    mode: motion
  alerts:
    retain:
      days: 30
  detections:
    retain:
      days: 30

snapshots:
  enabled: true
  retain:
    default: 30

objects:
  track:
    - person
    - dog
    - cat

go2rtc:
  streams: []

cameras: {}

version: 0.15-1
```

For Frigate to work correctly, the kernel module version must match the library version bundled into the Friagte container. If not you will get `HAILO_INVALID_DRIVER_VERSION` errors in Frigate.

## Access Frigate

Should be accessible privately via https://frigate.indigo.dalmura.cloud/

## Access Plex

Should be accessible publically via https://plex.indigo.dalmura.cloud/
