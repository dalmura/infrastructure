# Provision the Phase 3 applications for dal-indigo-core-1

These are:
* [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) for incoming connections to the cluster
* [CloudNative PG](https://cloudnative-pg.io/documentation/current/) for managed PostgreSQL clusters

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 2 - Storage](INDIGO-CORE-1-APPS-PHASE-2.md) and have all the precursors up and running, for example:
* `argocd` is logged in
* Longhorn is running

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself:
```bash
pushd clusters/dal-indigo-core-1/phase-3-gress/app/templates/

% cat traefik-public.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/phase-3-gress/overlays/traefik-public
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-3-gress/overlays/traefik-public?ref=HEAD'

# Because CloudNativePG is a helm chart we can't easily preview its resources
```

## Create the phase-3 parent app & deploy children
```bash
argocd app create phase-3-gress \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-3-gress/app

# Create the child applications
argocd app sync phase-3-gress

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=phase-3-gress
```
