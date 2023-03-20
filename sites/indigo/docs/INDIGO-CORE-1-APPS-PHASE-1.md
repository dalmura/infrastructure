# Provision the Phase 1 applications for dal-indigo-core-1

These are:
* [MetalLB](https://metallb.universe.tf/) for Load Balancing
* [cert-manager](https://cert-manager.io/docs/) for TLS certificates
* [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) for Route53 record management

We assume you've followed the steps at [`dal-indigo-core-1` Workers - ArgoCD](INDIGO-CORE-1-WORKERS-ARGOCD.md) and `argocd` is authenticated and has connectivity to the cluster.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/phase-1-common/app/templates/

% cat metallb.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/phase-1-common/overlays/metallb
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-1-common/overlays/metallb?ref=HEAD'

# Other phase-1 apps
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-1-common/overlays/externaldns?ref=HEAD'

kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/phase-1-common/overlays/cert-manager?ref=HEAD'
```

## Create the phase-1 parent app
```bash
argocd app create phase-1-common \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-1-common/app

argocd app sync phase-1-common
```
