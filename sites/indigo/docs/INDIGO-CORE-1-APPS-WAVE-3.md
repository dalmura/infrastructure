# Provision the Wave 3 applications for dal-indigo-core-1

These are:
* [Keycloak](https://github.com/keycloak/keycloak) for Authentication

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 2](INDIGO-CORE-1-APPS-WAVE-2.md) and have all the precursors up and running
* `argocd` is logged in
* Longorn is running w/default StorageClass
* Traefik ingress controller

## Create and seal the Secrets
Keycloak has a PostgreSQL DB via cnpg, which needs credentials to backup to S3.
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/wave-3/overlays'

# Secret 'keycloak-db-backup-secret' for keycloak
kubectl create secret generic \
  keycloak-db-backup-secret \
  --namespace keycloak \
  --dry-run=client \
  --from-literal 'ACCESS_KEY_ID=<your-access-key-id-here>' \
  --from-literal 'SECRET_ACCESS_KEY=<your-secret-access-key-here>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/keycloak/keycloak-db-backup-secret.sealed.yaml
```

Ensure you have committed and pushed the above credentials up into git as the below command (and final deployment) all rely on what's in git, not what's local.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-3/app/templates/

% cat keycloak.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-3/overlays/keycloak
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-3/overlays/keycloak?ref=HEAD'
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

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Access Keycloak

### Hostname & DNS
Temporarily Keycloak is on the Traefik Public ingress but its DNS entry is privately resolving for initial use cases.

When we want to make it public, the DNS entry will resolve to the Public IP of the site, and require traffic hairpin support or the below hack.

You can find the IP Address that is being announced by MetalLB by checking the Ingress resource in ArgoCD's UI or by running:
```bash
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n keycloak get ingress
NAME       CLASS            HOSTS                       ADDRESS         PORTS     AGE
keycloak   ingress-public   auth.indigo.dalmura.cloud   192.168.77.10   80, 443   71m
```

Ensure that you have a local `/etc/hosts` override pointing `auth.indigo.dalmura.cloud` => Above Address, then navigate to `auth.indigo.dalmura.cloud` from your browser.

Later when `auth.indigo.dalmura.cloud` is public and routable you can remove the `/etc/hosts` override.

### Initial Username & Password
You can retrieve the initial username and password from the `indigo-initial-admin` Secret created by the operator.

```bash
# Username
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n keycloak get secret indigo-initial-admin -o jsonpath='{.data.username}' | base64 -d | sed 's/$/\n/g'

# Password
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n keycloak get secret indigo-initial-admin -o jsonpath='{.data.password}' | base64 -d | sed 's/$/\n/g'
```

Immediately perform the following steps:
* Log in using the above credentials
* Create a new `site-admin` user via the web UI
* Set a password on the `site-admin` user
* Assign the `admin` role to the `site-admin` user
* Persist the new admin credentials into your password vault
* Log out and log in as the new admin user
* Delete the old temporary user

You cannot delete the `indigo-initial-admin` Secret as the operator will just recreate it. Deleting the user from Keycloak UI is the only way to ensure admin credentials are not just sitting there.

After this you can proceed to [Keycloak Configuration](INDIGO-CORE-1-APPS-WAVE-3-KEYCLOAK.md) for configuring Keycloak itself.
