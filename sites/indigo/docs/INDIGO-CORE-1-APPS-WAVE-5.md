# Provision the Wave 5 applications for dal-indigo-core-1

These are:
* [Frigate](https://frigate.video/) for Security NVR
* [Plex](https://www.plex.tv/) for Media Library Playback
* [Forgejo](https://forgejo.org/) as a Github replacement
* [Photoprism](https://github.com/photoprism/photoprism) for Photo management

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in
* `vault` is logged in (see [dynamic user docs](INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md) if not)
* Traefik's Ingress Controller is working and you can access ArgoCD/Longhorn/etc UI's
* Vault is operational

## Obtain AWS IAM Policy ARN
You can get the required IAM Policy from the `dalmura/network` repo, the README.md contains the instructions how to get them.

## Forgejo Vault Configuration
Forgejo's CNPG instance requires an AWS credentials in order to backup to S3 correctly.

We need to integrate with Vault and ESO in order to vend this IAM User correctly.

This requires two configurations be deployed into Vault:

Create the Vault AWS Role (aka IAM User Template) for Forgejo:
```bash
vault write aws/roles/forgejo-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=forgejo" \
    iam_tags="role=postgres"
```

Next we need to create the workload specific vault role to let the AWS Credentials be extracted from Vault by a Service Account within the Forgejo namespace.

See [`dal-indigo-core-1` Apps - Wave 3 - Vault Secrets Operator](INDIGO-CORE-1-APPS-WAVE-3-VAULT-SECRETS-OPERATOR.md) for more context on this.

Create the Vault permission policy and k8s role:
```
vault policy write workload-reader-forgejo-secrets -<<EOF
# App specific credentials path
path "aws/creds/forgejo-db-backup" {
    capabilities = ["read"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-forgejo-secrets \
   bound_service_account_names=forgejo-sa \
   bound_service_account_namespaces=forgejo \
   token_policies=workload-reader-forgejo-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

## Plex Secrets
Plex requires a `PLEX_CLAIM` environment variable that we need to securely pass into the Pod as a once-off activity. After that it's not required anymore. To avoid committing this into git and having someone else steal it for the few seconds it's visible but not used yet, we do it via a Vault secret.

Open up [Vault](https://vault.indigo.dalmura.cloud/), sign in as as user with the `site-admins` or `hub-power-users`, as we'll be saving the config under the `site/` path in Vault.

Create a secret under the `site` secret with the path `wave-5/plex/env` with the following keys:
* `PLEX_CLAIM`, with the value from https://account.plex.tv/en/claim

Note, this token expires after 5 minutes, if it does expire, repeat these steps creating a new version of the secret in Vault, and delete the Secret in the `plex` namespace to have it recreated from Vault.

After these have been created we need to create the workload specific vault roles to let the secrets be extracted from Vault by a Service Account within the Plex namespace.

See [`dal-indigo-core-1` Apps - Wave 3 - Vault Secrets Operator](INDIGO-CORE-1-APPS-WAVE-3-VAULT-SECRETS-OPERATOR.md) for more context on this.

Paste the following into your logged in `vault` CLI:
```
vault policy write workload-reader-plex-secrets -<<EOF
# Main secrets store
path "site/data/wave-5/plex/*" {
    capabilities = ["read", "list"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-plex-secrets \
   bound_service_account_names=plex-plex-media-server \
   bound_service_account_namespaces=plex \
   token_policies=workload-reader-plex-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

We provision within [wave-5/overlays/plex/](sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/plex/):
* `SecretStore` to reference the above created role
* `ExternalSecret` to reference the secret data to mount into the container

The end result after deploying this will be a `plex-env` Secret managed by ESO that will refresh when it's modified within Vault.

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-5/app/templates/

% cat frigate.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/frigate
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-5/overlays/frigate?ref=HEAD'
```

## Create the wave-5 parent app & deploy children
```bash
argocd app create wave-5 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-5/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-5

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-5
```

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Setup Frigate Config

Initially we need to populate the config PVC:
```bash
# Scale the deployment to 0
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n frigate scale deploy frigate --replicas=0

# Start a small debug pod
echo "
apiVersion: v1
kind: Pod
metadata:
  name: pvc-frigate-debug
  namespace: frigate
spec:
  volumes:
    - name: frigate
      persistentVolumeClaim:
        claimName: frigate-config
  containers:
    - name: debugger
      image: busybox
      command: ['sleep', '3600']
      volumeMounts:
        - mountPath: '/config'
          name: frigate
" | kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -f -

# Then access the pod
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n frigate exec -it pvc-frigate-debug -- sh

cd /config
vim config.yml

# After you're done delete it
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n frigate delete pod pvc-frigate-debug

# After you're done scale the deployment
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n frigate scale deploy frigate --replicas=1
```

For Frigate to work correctly, the kernel module version must match the library version bundled into the Friagte container. If not you will get `HAILO_INVALID_DRIVER_VERSION` errors in Frigate.

After saving the above the container should restart and pick up the changes, and if Frigate is a higher version than that from the config, automatically 'update' the config file to the latest schema.


## Initial Forgejo Setup

The below commands that run `gitea` assume you have a shell in the main pod:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n forgejo

kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n forgejo forgejo-9cbdc888d-xnnh5 -c forgejo -- /bin/bash
```

### Reset Admin Password
Forgejo will be able to be accessed via https://forgejo.indigo.dalmura.cloud/ but the initial admin user has a random password.

We could set this up as a secret and all that, but it's just easier as a once-off to reset the password manually:
```
$ gitea admin user list --admin
$ gitea admin user change-password --username 'user-from-above' --password 'my-example-password' --must-change-password=false
```

You can then go to the web interface and sign in.

### OIDC Configuration
Initially follow the [Authentik OIDC Configuration](./INDIGO-APPS-AUTH.md) and create your Application/Provider combination.

Configuring OIDC via the Forgejo UI:
* Log into the UI with the reset admin password from above
* Navigate to `Site administration` => `Identity & access` => `Authentication sources`
* Add a new Authentication Source
 * Authentication type: OAuth2
 * Authentication name: indigo-auth
 * OAuth2 provider: OpenID Connect (scroll down)
 * Client ID: `<paste from authentik>`
 * Client Secret: `<paste from authentik>`
 * OpenID Connect Auto Discovery URL: `<paste from authentik>`
   * Ensure the above uses the Authentik cluster service URL not the ingress URL
   * Eg. `http://authentik-server.authentik.svc.cluster.local/application/o/forgejo/.well-known/openid-configuration`
   * There's a Network Policy on the Authentik server that allows this
 * Additional scopes: email profile entitlements
 * Required claim name: entitlements
 * Required claim value: user
 * Claim name providing group names: entitlements
 * Group claim value for admin users: admin
* Save the Authentication Source

Within Authentik you can override the Application URL to be `https://forgejo.indigo.dalmura.cloud/user/oauth2/indigo-auth` which should also auto-login the user instead of just sending them to the default home page.


## Access Frigate

Should be accessible privately via https://frigate.indigo.dalmura.cloud/

## Access Plex

Should be accessible publically via https://plex.indigo.dalmura.cloud/

## Photoprism Setup

Configured for OIDC login, follow the usual steps in Authentik to create an Application with an OIDC provider. See the `external-secret.yaml` in the overlays for what parameters it expects.

If you ever get locked out of the instance and need to reset the `admin` password:
```bash
# Shell into the photoprism container
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n photoprism photoprism-5c59758d8b-r5j7v -- /bin/bash

# Reset the admin users password
photoprism passwd admin
```

## Plex Setup

You can add libraries as normal, they will be mounted into the container via NFS available under `/data`.

Remote access will work, but will require these additional settings:
* Settings => Remote Access
   * Manually specify public port: 32406
* Settings => Network
   * Client Network: IPv4 Only
   * Custom server access URLs: `https://plex.indigo.dalmura.cloud:32406/`

After setting the above you can go back to Settings => Remote Access and click Retry.
