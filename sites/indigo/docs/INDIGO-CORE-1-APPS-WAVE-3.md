# Provision the Wave 3 applications for dal-indigo-core-1

These are:
* [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) for incoming connections to the cluster
* [CloudNative PG](https://cloudnative-pg.io/documentation/current/) for managed PostgreSQL clusters

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 2 - Storage](INDIGO-CORE-1-APPS-WAVE-2.md) and have all the precursors up and running, `argocd` is logged in and Longhorn is running

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself:
```bash
pushd clusters/dal-indigo-core-1/wave-3/app/templates/

% cat traefik-public.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-3/overlays/traefik-public
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-3/overlays/traefik-public?ref=HEAD'

# Because CloudNativePG is a helm chart we can't easily preview its resources
```

## Create the wave-3 parent app & deploy children
```bash
argocd app create wave-3 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-3/app

# Create the child applications
argocd app sync wave-3

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-3
```
