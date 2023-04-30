# Provision the Phase 2 applications for dal-indigo-core-1

These are:
* [Keycloak](https://github.com/keycloak/keycloak) for Authentication

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 1 - Common](INDIGO-CORE-1-APPS-PHASE-1.md) and have all the precursor phases up, running and tested.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/phase-2-auth/app/templates/

% cat keycloak.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/phase-2-auth/overlays/keycloak
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-2-auth/overlays/keycloak?ref=HEAD'
```

## Create the phase-2 parent app
```bash
argocd app create phase-2-auth \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-2-auth/app

argocd app sync phase-2-auth
```

## Access Keycloak

You can find the IP Address that is being announced by MetalLB by checking the Ingress resource in ArgoCD's UI or by running:
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n keycloak get ingress
NAME       CLASS    HOSTS                ADDRESS          PORTS     AGE
keycloak   cilium   auth.dalmura.cloud   192.168.77.141   80, 443   19m
```

Ensure that you have a local /etc/hosts override pointing auth.dalmura.cloud => Address then navigate to auth.dalmura.cloud from your browser.
