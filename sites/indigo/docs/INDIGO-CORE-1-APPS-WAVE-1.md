# Provision the Wave 1 applications for dal-indigo-core-1

These are:
* [MetalLB](https://metallb.universe.tf/) for Load Balancing
* [cert-manager](https://cert-manager.io/docs/) for TLS certificates
* [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) for Route53 record management
* [Longhorn](https://longhorn.io/docs/latest/what-is-longhorn/) for persistent, distributed, replicated and backed up Block and Object storage

We assume you've followed the steps at:
* [`dal-indigo-core-1` Workers - ArgoCD](INDIGO-CORE-1-WORKERS-ARGOCD.md) and `argocd` is authenticated and has connectivity to the cluster
* [`dal-indigo-core-1` Apps - Wave 0](INDIGO-CORE-1-APPS-WAVE-0.md) and have all the precursor waves up, running and tested, especially `kubeseal`

## Obtain AWS Credentials
You can get the required AWS Credentials from the `dalmura/network` repo, the README.md contains the instructions how to get them.

## Create and seal the Secrets
A few resources require secrets to be created and committed into the repo
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/wave-1/overlays'

# Secret 'aws-route53-credentials-secret' for cert-manager
kubectl create secret generic \
  aws-route53-credentials-secret \
  --namespace cert-manager \
  --dry-run=client \
  --from-literal 'ACCESS_KEY_ID=<k8s_dns_updater_key.id>' \
  --from-literal 'SECRET_ACCESS_KEY=<k8s_dns_updater_key.secret>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/cert-manager/aws-route53-credentials-secret.sealed.yaml

# Secret 'iam-credentials' for external-dns
echo -e '[default]\naws_access_key_id = <k8s_dns_updater_key.id>\naws_secret_access_key = <k8s_dns_updater_key.secret>' \
  | kubectl create secret generic \
  iam-credentials \
  --namespace external-dns \
  --dry-run=client \
  --from-file 'credentials=/dev/stdin' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/external-dns/credentials.sealed.yaml

# Secret 'aws-s3-credentials-secret' for longhorn
kubectl create secret generic \
  aws-s3-credentials-secret \
  --namespace longhorn-system \
  --dry-run=client \
  --from-literal 'AWS_ACCESS_KEY_ID=<k8s_backups_key.id>' \
  --from-literal 'AWS_SECRET_ACCESS_KEY=<k8s_backups_key.secret>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/longhorn/aws-s3-credentials-secret.sealed.yaml
```

Ensure you have committed and pushed the above credentials up into git as the below command (and final deployment) all rely on what's in git, not what's local.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-1/app/templates/

% cat metallb.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-1/overlays/metallb
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-1/overlays/metallb?ref=HEAD'

# Other wave-1 apps
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-1/overlays/external-dns?ref=HEAD'

kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-1/overlays/cert-manager?ref=HEAD'

# Go back to original dir
popd
```

Longhorn uses Helm to deploy, which we integrate into ArgoCD's Application CRD, so there's no easy way to render this locally apart from building the `helm template` command locally.

## Create the wave-1 parent app & deploy children
```bash
argocd app create wave-1 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-1/app

# Create the child applications
argocd app sync wave-1

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-1
```

You may see the following error from the child apps deploy:
```bash
cert-manager:
Failed     SyncFailed    Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/validate?timeout=30s": dial tcp 10.111.122.49:443: connect: operation not permitted

metallb:
OutOfSync  Missing        Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.108.178.78:443: connect: operation not permitted
```

This is because we are deploying resources that have a Validating Webhook that's run by the application itself, and it hasn't yet created the container to validate the webhook. So just wait a minute and just rerun the deployment again and it'll work. Nothing to be worried about!

If you don't see the errors above but other errors, it possibly can help to wait some minutes anyway and rerun the above deployment to see if it was temporary or some other ordering issue within the deployment apps.

If you get any errors around SealedSecrets and 'no key found to decrypt' maybe you forgot to commit and push the steps earlier that updated the sealed secret credentials?

Longhorn will take a couple of minutes, but after that you can setup a kube proxy before we deploy the ingress controllers:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n longhorn-system port-forward svc/longhorn-frontend 8081:80
```

Once you can run the deployment command without any errors, and you've validated in the ArgoCD web UI that all apps are green/synced/healthy, we can move on.

## Validation
### cert-manager
You can just check that the pod(s) are up and running, nothing much to check here yet, once we start minting certificates later on we'll be able to validate.
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace cert-manager get pods
```

### external-dns
You can just check that the pod(s) are up and running, nothing much to check here yet, once we start creating web services later on we'll be able to validate.
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace external-dns get pods
```

### MetalLB
You can just check that the pod(s) are up and running, nothing much to check here yet, once we start
creating web services later on we'll be able to validate.
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace metallb-system get pods

# You can also check some of the CRD resources to ensure the configuration matches our overlay values:
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get -A ipaddresspools
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get -A l2advertisements
```

### Longhorn
Longhorn will deploy itself as the default StorageClass on the cluster, later on we can validate that Longhorn is correctly provisioning PVs.
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get storageclass
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 describe storageclass longhorn
```
