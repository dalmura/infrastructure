# Provision the Wave 5 applications for dal-indigo-core-1

These are:
* [Frigate](https://frigate.video/) for Security NVR
* [Plex](https://www.plex.tv/) for Media Library Playback

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in
* Traefik ingress controller is running

## Create Vault Secret(s)

Frigate requires a detailed config file that outlines all the security camera settings, along with credentials for each camera. As such it doesn't make sense to commit some of the config into git, and some in Vault.

Instead we'll commit the entire config into vault and load that into Frigate!

Open up [Vault](https://vault.indigo.dalmura.cloud/), sign in as as user with the `site-admins` or `hub-power-users`, as we'll be saving the config under the `site/` path in Vault.


Copy the contents of the [frigate.yaml example file](examples/indigo-core-1-apps-wave-5-frigate.yaml) and save it into a secret with the path `site/wave-5/frigate/values` under the `config.yaml` key, and customise it to your liking.

Create a secret with the path `site/wave-5/frigate/env`, with the following keys:
* `PLUS_API_KEY` set to your Frigate Plus API key

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

## Access Frigate

Should be accessible via https://frigate.indigo.dalmura.cloud
