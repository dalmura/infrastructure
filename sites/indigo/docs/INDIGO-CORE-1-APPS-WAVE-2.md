# Provision the Wave 2 applications for dal-indigo-core-1

These are:
* [Traefik Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) for incoming connections to the cluster
* [CloudNative PG](https://cloudnative-pg.io/documentation/current/) for managed PostgreSQL clusters

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 1](INDIGO-CORE-1-APPS-WAVE-1.md) and have all the precursors up and running, `argocd` is logged in and Longhorn is running

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself:
```bash
pushd clusters/dal-indigo-core-1/wave-2/app/templates/

% cat traefik-public.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-2/overlays/traefik-public
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-2/overlays/traefik-public?ref=HEAD'

# Because CloudNativePG is a helm chart we can't easily preview its resources
# All ingress UI apps can be validated the same way as Traefik above
```

## Create the wave-2 parent app & deploy children
```bash
argocd app create wave-2 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-2/app

# Create the child applications
argocd app sync wave-2

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-2
```

## Testing Ingress rules
The following URLs should be browsable:
* [ArgoCD UI](https://argocd.indigo.dalmura.cloud/)
* [Cilium Hubble UI](https://cilium-hubble.indigo.dalmura.cloud/)
* [Longhorn UI](https://longhorn.indigo.dalmura.cloud/)
* [Kubernetes Dashboard](https://kubernetes-dashboard.indigo.dalmura.cloud/)
* [Traefik Dashboard - Private](https://traefik-private.indigo.dalmura.cloud/dashboard/)
* [Traefik Dashboard - Public](https://traefik-public.indigo.dalmura.cloud/dashboard/)

ArgoCD via CLI:
```
argocd --grpc-web login argocd.indigo.dalmura.cloud
```
