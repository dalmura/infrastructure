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

## Create the phase-0 parent app & deploy children
```bash
argocd app create phase-0-secrets \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/phase-0-secrets/app

# Create the child applications
argocd app sync phase-0-secrets

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=phase-0-secrets
```

## Install kubeseal
```bash
# Mac
brew install kubeseal

# Linux
KUBESEAL_VERSION='0.26.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
rm kubeseal
```

You can then test it out:
```bash
# Print out the public key of this server
kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 --fetch-cert
```
