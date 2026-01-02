# Provision the Wave 0 applications for dal-indigo-core-1

These are:
* [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/) for Secrets in-repo
* [Reloader](https://github.com/stakater/Reloader) for Reloading Pods on Secret/ConfigMap change

Also we manage these previously installed applications within ArgoCD too:
* [Cilium](https://github.com/cilium/cilium)
* [ArgoCD](https://github.com/argoproj/argo-cd/)

We assume you've followed the steps at:
* [`dal-indigo-core-1` Workers - ArgoCD](INDIGO-CORE-1-WORKERS-ARGOCD.md) and `argocd` is authenticated and has connectivity to the cluster

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-0/app/templates/

$ cat sealed-secrets.yaml
...
spec:
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-0/overlays/sealed-secrets
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-0/overlays/sealed-secrets?ref=HEAD'

# Go back to the site directory
popd
```

## Create the wave-0 parent app & deploy children
```bash
argocd app create wave-0 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-0/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Path above is for the git repo, not your local path

# Create the child applications
argocd app sync wave-0

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-0

# Verify the status via the Web UI, once it's Healthy you can continue
```

## Install kubeseal
```bash
# Mac or linux
brew install kubeseal
```

You can then test it out:
```bash
# Print out the public key of this server
kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 --fetch-cert
```

On to [INDIGO-CORE-1-APPS-WAVE-1.md](INDIGO-CORE-1-APPS-WAVE-1.md)!
