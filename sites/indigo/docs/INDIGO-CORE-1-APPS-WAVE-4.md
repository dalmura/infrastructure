# Provision the Wave 4 applications for dal-indigo-core-1

These are:
* [Renovate](https://docs.renovatebot.com/) for automated dependency management

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in

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
