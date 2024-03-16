# Provision the Wave 4 applications for dal-indigo-core-1

These are:
* [Keycloak](https://github.com/keycloak/keycloak) for Authentication

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in
* Longorn is running w/default StorageClass
* Traefik ingress controller

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-4/app/templates/

% cat keycloak.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-4/overlays/keycloak
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-4/overlays/keycloak?ref=HEAD'
```

## Create the wave-4 parent app & deploy children
```bash
argocd app create wave-4 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-4/app

# Create the child applications
argocd app sync wave-4

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-4

```

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Access Keycloak

You can find the IP Address that is being announced by MetalLB by checking the Ingress resource in ArgoCD's UI or by running:
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n keycloak get ingress
NAME       CLASS    HOSTS                ADDRESS          PORTS     AGE
keycloak   cilium   auth.dalmura.cloud   192.168.77.141   80, 443   19m
```

Ensure that you have a local `/etc/hosts` override pointing `auth.dalmura.cloud` => Above Address, then navigate to `auth.dalmura.cloud` from your browser.

Later when `auth.dalmura.cloud` is public you can remove the `/etc/hosts` override.
