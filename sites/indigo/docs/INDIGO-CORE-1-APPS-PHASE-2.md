# Provision the Phase 2 applications for dal-indigo-core-1

These are:
* [[Longhorn](https://longhorn.io/docs/latest/what-is-longhorn/) for persistent, distributed, replicated and backed up Block and Object storage

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 1 - Common](INDIGO-CORE-1-APPS-PHASE-1.md) and have all the precursor phases up, running and tested.

## Verifying apps

Longhorn uses Helm to deploy, which we integrate into ArgoCD's Application CRD, so there's no easy way to render this locally apart from building the `helm template` command locally.

## Create the phase-2 parent app & deploy children
```bash
argocd app create phase-2-storage \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-2-storage/app

# Create the child applications
argocd app sync phase-2-storage

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=phase-2-storage
```

This will take a couple of minutes, but after that you can setup a kube proxy before we deploy the ingress controllers:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n longhorn-system port-forward svc/longhorn-frontend 8081:80
```
