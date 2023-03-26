# Provision the Phase 0 applications for dal-indigo-core-1

These are:
* [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/) for Secrets in-repo

We assume you've followed the steps at [`dal-indigo-core-1` Workers - ArgoCD](INDIGO-CORE-1-WORKERS-ARGOCD.md) and `argocd` is authenticated and has connectivity to the cluster.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/phase-0-secrets/app/templates/

% cat sealed-secrets.yaml
...
  source:
    repoURL: https://github.com/dalmura/workloads.git
    path: sealed-secrets
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/workloads.git/sealed-secrets?ref=HEAD'
```

## Create the phase-0 parent app
```bash
argocd app create phase-0-secrets \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-0-secrets/app

argocd app sync phase-0-secrets
```
