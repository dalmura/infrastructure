# Provision the Phase 2 applications for dal-indigo-core-1

These are:
* [[Longhorn](https://longhorn.io/docs/latest/what-is-longhorn/) for persistent, distributed, replicated and backed up Block and Object storage

We assume you've followed the steps at [`dal-indigo-core-1` Workers - ArgoCD](INDIGO-CORE-1-WORKERS-ARGOCD.md) and `argocd` is authenticated and has connectivity to the cluster.

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Phase 0 - Secrets](INDIGO-CORE-1-APPS-PHASE-0.md) and have all the precursor phases up, running and tested, especially `kubeseal`.

## Create and seal the Secrets
A few resources require secrets to be created and committed into the repo
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/phase-2-storage/overlays'

# Secret 'aws-s3-credentials-secret' for longhorn
kubectl create secret generic \
  aws-s3-credentials-secret \
  --namespace longhorn-system \
  --dry-run=client \
  --from-literal 'AWS_ACCESS_KEY_ID=<your-access-key-id-here>' \
  --from-literal 'AWS_SECRET_ACCESS_KEY=<your-secret-access-key-here>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/longhorn/aws-s3-credentials-secret.sealed.yaml

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

## Validation

Longhorn will deploy itself as the default StorageClass on the cluster, this can be checked via:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get storageclass
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 describe storageclass longhorn
```
