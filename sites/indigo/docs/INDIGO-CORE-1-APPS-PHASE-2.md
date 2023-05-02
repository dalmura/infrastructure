# Provision the Phase 2 applications for dal-indigo-core-1

These are:
* [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) for incoming connections to the cluster

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 1 - Common](INDIGO-CORE-1-APPS-PHASE-1.md) and have all the precursor phases up, running and tested.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/phase-2-auth/app/templates/

% cat traefik.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/phase-2-ingress/overlays/traefik
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-2-ingress/overlays/traefik?ref=HEAD'
```

## Create the phase-2 parent app
```bash
argocd app create phase-2-ingress \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-2-ingress/app

argocd app sync phase-2-ingress
```
