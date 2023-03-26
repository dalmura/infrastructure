# Provision the Phase 2 applications for dal-indigo-core-1

These are:
* [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) for Ingress

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 1 - Common](INDIGO-CORE-1-APPS-PHASE-1.md) and have all the precursor phases up, running and tested.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/phase-2-ingress/app/templates/

% cat ingress.yaml
...
  source:
    repoURL: https://github.com/dalmura/workloads.git
    path: ingress
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/workloads.git/ingress?ref=HEAD'
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
