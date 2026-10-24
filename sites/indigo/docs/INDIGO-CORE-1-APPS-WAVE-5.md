# Provision the Wave 5 applications for dal-indigo-core-1

These are:
* [Frigate](https://frigate.video/) for Security NVR
* [Plex](https://www.plex.tv/) for Media Library Playback
* [Forgejo](https://forgejo.org/) as a Github replacement
* [Forgejo Runner](https://git.erwanleboucher.dev/eleboucher/runner-k8s-plugin) for running Forgejo Actions jobs as Kubernetes pods
* [Actions Runner Controller](https://github.com/actions/actions-runner-controller) for running GitHub Actions jobs as Kubernetes pods
* [Photoprism](https://github.com/photoprism/photoprism) for Photo management
* [Emojirades](https://emojirades.io) runs Slack based Emoji Charades
* [Tandoor](https://tandoor.dev/) for Recipe management
* [Reactive Resume](https://rxresu.me/) for Resume management
* [Matrix Synapse](https://matrix.org/) for Chat and Messaging
* [Archestra](https://archestra.ai/) for MCP and LLM Agent Gateway

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
   ttl=31d
```

The above 31d is required as the ttl here sets the lifetime of the IAM Users that are vended by Vault.

We also need to configure a location to store the Forgejo Runner token details (to let the runners authenticate).

Paste the following into your logged in `vault` CLI:
```
vault policy write workload-reader-forgejo-runner-secrets -<<EOF
# Main secrets store
path "site/data/wave-5/forgejo-runner/*" {
    capabilities = ["read", "list"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-forgejo-runner-secrets \
   bound_service_account_names=forgejo-runner-sa \
   bound_service_account_namespaces=forgejo-runner \
   token_policies=workload-reader-forgejo-runner-secrets \
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

This will take a solid 3-5 mins as the Pods come up and the certificates are issued.

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

For Frigate to work correctly, the kernel module version must match the library version bundled into the Frigate container. If not you will get `HAILO_INVALID_DRIVER_VERSION` errors in Frigate.

If the above `HAILO_INVALID_DRIVER_VERSION` error happens, there are two choices:
* Maintain a custom Talos image with the version Frigate uses
* Maintain a custom Frigate image with the version Talos uses

The slightly easier option is to maintain a custom Frigate image:
* Ensure https://github.com/frigate-nvr/hailort/ has a release for the version Talos is using
* `git clone https://github.com/blakeblackshear/frigate/`
* Run `git tag`, locate the latest stable version
* Run `git checkout <tag>` eg `git checkout v0.17.2`
* Edit `docker/main/install_hailort.sh` and set `hailo_version` to what Talos has (eg 4.24.0)
* Run `make local` for your local docker to have `frigate:latest` image built
* Go to github and create a classic PAT with `write:packages` scope (just 7 days expiry)
* Log into github container registry: `docker login ghcr.io -u <your github user>`
* You can then tag it: `docker tag frigate:latest ghcr.io/dalmura/frigate:v0.17.2`
* Push up the image `docker push ghcr.io/dalmura/frigate:v0.17.2`
   * It'll be like ~5GB so it will take _some time_
* Update the github package settings to public visibility (once off action)
* Then ensure any frigate image is using the above `ghcr.io/dalmura/frigate:v0.17.2`

After saving the above the container should restart and pick up the changes, and if Frigate is a higher version than that from the config, automatically 'update' the config file to the latest schema.

Follow the steps in [INDIGO-APPS-AUTH.md](INDIGO-APPS-AUTH.md) and configure Frigate in Authentik before you access it via the UI.

You will need to follow the 'Reverse Proxy' setup flow as Frigate doesn't offer native OIDC authentication.

Once authentication is configured, it should be accessible privately via https://frigate.indigo.dalmura.cloud/

With Frigate's MQTT integration, your config block should include something like:
```
mqtt:
  enabled: true
  host: "mosquitto.mosquitto.svc.cluster.local"
  port: 1883
  user: "frigate"
  password: "your_password_here"
```

## Forgejo Setup

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
Initially follow the [Native OIDC Configuration](./INDIGO-APPS-AUTH.md) and create your Application/Provider combination.

Extra context for the above:
* Callback URL: `https://forgejo.indigo.dalmura.cloud/user/oauth2/indigo-auth/callback`
* Ensure you add the 'entitlements' scope from the doco
* Bind the `spoke-users` group, order 0
* Create the following Application entitlements:
   * `user` - bind to `spoke-users` group
   * `admin` - bind to `site-admins` group
   * If you forget this step Forgejo will claim your account is 'restricted' and you cannot log in

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
   * Eg. `https://auth.indigo.dalmura.cloud/application/o/forgejo/.well-known/openid-configuration`
 * Additional scopes: email profile entitlements
 * Required claim name: entitlements
 * Required claim value: user
 * Claim name providing group names: entitlements
 * Group claim value for admin users: admin
* Save the Authentication Source

Within Authentik you can override Forgejo's "Launch URL" to be `https://forgejo.indigo.dalmura.cloud/user/oauth2/indigo-auth` which should also auto-login the user instead of just sending them to the default home page.

## Forgejo Runner Setup

[Forgejo Runner](https://git.erwanleboucher.dev/eleboucher/runner-k8s-plugin) runs Forgejo Actions jobs as native Kubernetes pods. The runner and the `runner-k8s-plugin` sidecar run in the `forgejo-runner` namespace, and each job runs in its own pod in that same namespace. The plugin creates job pods through the Kubernetes API; it does not use Docker or a Docker socket. The namespace enforces the `baseline` Pod Security Standard, and neither the runner nor the plugin runs privileged.

### Registration details

The chart runs `forgejo-runner daemon` with a fixed runner UUID and runner token. In Forgejo open `Site administration` => `Actions` => `Runners` => `Create new runner`, enter a name, and copy the **UUID** and **Token** shown on the setup page. The token is displayed only once.

Store both in Vault at `site/wave-5/forgejo-runner/config`:

```bash
vault kv put site/wave-5/forgejo-runner/config \
   uuid="<runner-uuid>" \
   token="<runner-token>"
```

External Secrets syncs `uuid` and `token` into the `forgejo-runner-secrets` Secret, which the chart mounts. The older registration-token / `.runner` flow is not required for this chart.

To rotate the token, edit the runner in Forgejo, tick **Regenerate token**, save, and copy the new token; update `token` in Vault (the UUID stays the same). The ExternalSecret refreshes hourly by default; to apply a change immediately, annotate it to force a sync:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n forgejo-runner \
   annotate externalsecret forgejo-runner-secrets force-sync="$(date +%s)" --overwrite
```

If the runner logs `unregistered runner`, the `uuid` or `token` no longer matches Forgejo; regenerate the token or create a new runner and update Vault.

### Runner labels

| Label | Meaning | Job pod |
|---|---|---|
| `ubuntu-24.04` | Environment | Ubuntu 24.04 job pod on an amd64 worker (`podspec-default.yaml`) |
| `indigo` | Site | Same job pod, but only on the Indigo runner |

Use `runs-on: ubuntu-24.04` for site-agnostic jobs and `runs-on: [ubuntu-24.04, indigo]` when a job must run in Indigo. Labels are ANDed: every label in `runs-on` must be declared by the same runner. There is no preference or fallback — if no Indigo runner is available, the job waits.

Job pods are pinned to `kubernetes.io/arch: amd64`, so they run on the eq14 or macmini2014 workers and never on the arm64 Raspberry Pi nodes. The runner pod itself has no architecture constraint; both runner images are multi-arch, and it only creates and execs into the job pods. Site targeting only selects the runner; job pods still have no Kubernetes API access.

GitHub-style labels such as `ubuntu-latest`, `self-hosted`, `linux`, `x64`, `amd64`, and `default` are not declared, so workflows using them stay queued until changed to one of the labels above.

If you later add runners in other sites, give each one `ubuntu-24.04` plus its site label (`navy`, etc.). Jobs using only `ubuntu-24.04` can run on any site; jobs using `[ubuntu-24.04, <site>]` are pinned to that site. Multiple runners in the same site should declare the same labels so Forgejo can distribute jobs across them; add a unique label only when a workflow must target one specific runner.

### Verifying

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n forgejo-runner get deploy,role,rolebinding,externalsecret
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n forgejo-runner logs deploy/forgejo-runner -c runner --tail=50
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n forgejo-runner logs deploy/forgejo-runner -c k8s-plugin --tail=50
```

The runner should appear as idle in Forgejo's runner list. Jobs create `forgejo-runner-task-*` Jobs and pods in the `forgejo-runner` namespace, which are garbage-collected shortly after finishing.


## GitHub Runner Setup

[Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) runs GitHub Actions jobs as Kubernetes pods. It is independent of the Forgejo runner: it has its own namespaces, credentials, RBAC, and `runs-on` labels. The ARC controller runs in `arc-systems`; the runner scale set runs in `arc-runners`.

Without `containerMode`, each job gets a fresh ephemeral runner pod and the workflow steps run inside that pod. This supports ordinary `run:` steps and JavaScript actions, but not `container:` jobs, `services:`, or Docker actions. See [Container jobs and Docker actions](#container-jobs-and-docker-actions) if you need those.

The ARC controller Application is `arc-controller` and the scale set Application is `github-runner`. Sync `arc-controller` first so the `actions.github.com` CRDs exist before the scale set is applied.

These steps assume `dalmura` is a GitHub organization. GitHub cannot attach an organization runner to a personal account; if `dalmura` is a user, use a repository-scoped App and `githubConfigUrl: https://github.com/dalmura/<repo>`, with one scale set per repository.

### 1. Create the GitHub App

Create a GitHub App in the `dalmura` organization:

1. Open `https://github.com/organizations/dalmura/settings/apps/new`.
2. Set the name to something recognisable, for example `indigo-arc-runner`, and any Homepage URL.
3. Disable the webhook; this setup does not use webhook-driven scaling.
4. Set these permissions:
   * Repository permissions:
     * Actions: Read-only
     * Metadata: Read-only (mandatory)
   * Organization permissions:
     * Self-hosted runners: Read and write
5. Create the App and note the **App ID**.
6. Generate a private key and keep the `.pem` file secure.
7. Install the App on the `dalmura` organization and grant it access to the repositories that should use the runner.
8. Copy the **Installation ID** from the installation URL, which ends in `/settings/installations/<installation-id>`.

For a repository-scoped runner instead, set `githubConfigUrl` to `https://github.com/dalmura/<repo>` and use Repository permissions `Actions: Read-only`, `Administration: Read and write`, and `Metadata: Read-only`. That needs one scale set per repository. GitHub self-hosted runners cannot be scoped to a personal account; use an organization or one scale set per repository.

### 2. Store the credentials in Vault

Store the App credentials at `site/wave-5/github-runner/github-app`:

```bash
vault kv put site/wave-5/github-runner/github-app \
   github_app_id="<app-id>" \
   github_app_installation_id="<installation-id>" \
   github_app_private_key=@/path/to/private-key.pem
```

Create the Vault policy and Kubernetes auth role:

```bash
vault policy write workload-reader-github-runner-secrets - <<EOF
path "site/data/wave-5/github-runner/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-github-runner-secrets \
   bound_service_account_names=github-runner-sa \
   bound_service_account_namespaces=arc-runners \
   token_policies=workload-reader-github-runner-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

External Secrets syncs `github_app_id`, `github_app_installation_id`, and `github_app_private_key` into the `github-runner-github-app` Secret in `arc-runners`. The scale set references that Secret by name.

To rotate the private key, generate a new key in the GitHub App settings, update Vault, and force a refresh:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-runners \
   annotate externalsecret github-runner-github-app force-sync="$(date +%s)" --overwrite
```

GitHub keeps multiple private keys valid during rotation, so delete the old key after the listener reconnects.

### 3. Deploy

```bash
argocd app sync arc-controller
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-systems \
   rollout status deploy/arc-controller-gha-rs-controller --timeout=3m
argocd app sync github-runner
```

If you sync all wave-5 children at once, `github-runner` can fail once because the CRDs from `arc-controller` are not established yet. Re-sync `github-runner` after the controller is healthy.

`arc-controller` sets `ServerSideApply=true` because the ARC CRDs are several hundred kilobytes each, which is too large for client-side apply's `last-applied-configuration` annotation.

### Runner label

The scale set is named `indigo-github`, which is the `runs-on:` label:

```yaml
runs-on: indigo-github
```

GitHub also applies the implicit `self-hosted`, `linux`, and `x64` labels. Workflows can use `runs-on: indigo-github` or `runs-on: [self-hosted, linux, x64, indigo-github]`. The scale set is scoped to the `dalmura` organization, so any repository the App can access can use it. This label is separate from the Forgejo runner's `ubuntu-24.04` and `indigo` labels.

In the default configuration (no `containerMode`), runner pods are pinned to `kubernetes.io/arch: amd64` and have `automountServiceAccountToken: false`. `minRunners: 0` scales to zero when idle; `maxRunners: 3` caps concurrent jobs on the N150 workers.

### Container jobs and Docker actions

The initial deployment leaves `containerMode` unset. If workflows use `container:`, `services:`, or Docker actions, enable the Kubernetes hooks in `values/github-runner/values.yaml`:

```yaml
containerMode:
  type: kubernetes-novolume
```

Then remove `automountServiceAccountToken: false` from the runner pod template, or set it to `true`. The hooks use the `indigo-github-gha-rs-kube-mode` ServiceAccount to create, exec into, and clean up job pods; without the mounted token they fail with `Unauthorized`.

`kubernetes-novolume` uses [actions/runner-container-hooks](https://github.com/actions/runner-container-hooks) to run the job in a separate pod and copy the workspace between pods. It needs no PVC, Docker daemon, or privileged container. The hook template ConfigMap in `overlays/github-runner/hook-template.yaml` is already mounted into the runner pod, so job pods are pinned to `kubernetes.io/arch: amd64` and have `automountServiceAccountToken: false`.

Both modes set `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=true`, so every job must have a container image; jobs without `container:` fail with `Jobs without a job container are forbidden on this runner`.

Keep `REQUIRE_JOB_CONTAINER=true` when hooks are enabled. Setting it to `false` runs non-container jobs inside the runner pod, which can read the hook ServiceAccount token and create pods, exec into them, and read secrets.

If novolume workspace copying is too slow or flaky for large repositories, switch to the PVC-backed mode:

```yaml
containerMode:
  type: kubernetes
  kubernetesModeWorkVolumeClaim:
    accessModes: ["ReadWriteOnce"]
    storageClassName: cluster-nobackup
    resources:
      requests:
        storage: 1Gi
```

The ReadWriteOnce PVC keeps the job pod on the same node as the runner pod, so it stays on amd64. `cluster-nobackup` avoids Longhorn backup churn for ephemeral workspaces. Longhorn binds RWO volumes immediately, so the job pod can occasionally wait on a multi-attach error before the scheduler retries; novolume avoids that.

The network policy already includes a rule for the hook ServiceAccount and a rule for hook-created job pods (`runner-pod` label). Runner and job pods can reach DNS and the internet on ports 80 and 443 only. If a job needs an in-cluster service, a private registry on another port, or SSH git, extend `overlays/github-runner/network-policy.yaml`.

### Verifying

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-systems get deploy,pods
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-runners \
   get autoscalingrunnerset,ephemeralrunnerset,pods,externalsecret
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-runners \
   logs -l app.kubernetes.io/component=runner-scale-set-listener --tail=50
```

In GitHub, open the organization's `Settings` => `Actions` => `Runners` and confirm the `indigo-github` scale set is present. The `github-runner-github-app` ExternalSecret should report `Ready=True`:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n arc-runners \
   get externalsecret github-runner-github-app \
   -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Listener logs `failed to get access token` or `401` | App ID, installation ID, or private key mismatch, or the App is not installed on the organization |
| Listener logs `Resource not accessible by integration` | Missing `Actions: Read` or `Self-hosted runners: Read and write` permission |
| Listener logs `not found` | `githubConfigUrl` points at the wrong scope (organization vs repository) |
| Jobs stay queued | Workflow `runs-on` does not match `indigo-github`; check the scale set name and repository access |
| Hooks fail with `Unauthorized` after enabling `containerMode` | `automountServiceAccountToken: false` is still set on the runner pod |
| `Jobs without a job container are forbidden` | `containerMode` is enabled and the job has no `container:`; add one or disable the hooks |


## Photoprism Setup

### OIDC Authentication
See [secret-store-site.yaml](../clusters/dal-indigo-core-1/wave-5/overlays/photoprism/secret-store-site.yaml) and [external-secret.yaml](../clusters/dal-indigo-core-1/wave-5/overlays/photoprism/external-secret.yaml) for the required inputs into the below config.

Additional settings:
* Redirect URI: `https://photos.indigo.dalmura.cloud/api/v1/oidc/redirect`
* Bind `spoke-users` to allow anyone to log in, photos are scoped to each user account
   * Order: 0
* TBC: Entitlements

Follow the steps in [INDIGO-APPS-AUTH.md](INDIGO-APPS-AUTH.md) for 'Configuration of a new OIDC Application', as Photoprism supports OIDC.

After the Authentik side is setup, follow the steps in [INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md](INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md) with the following additional configuration:
* Reader Role: `workload-reader-photoprism`
* Service Account: `photoprism-sa`
* Secret Engine: `site`
* Secret Path: `wave-5/photoprism/config`

Setting the following key and values:
* `admin_password`: Whatever you want
* `oidc_client`: <Client ID value from above Authentik config>
* `oidc_secret`: <Client Secret value from above Authentic config>

### Reset admin password
If you ever get locked out of the instance:
```bash
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n photoprism
NAME                          READY   STATUS    RESTARTS   AGE
photoprism-85f94f89dd-g7628   1/1     Running   0          24m

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n photoprism photoprism-85f94f89dd-g7628 -- /bin/bash

# Reset the admin users password
$ photoprism passwd admin
```

### Upgrade a new OIDC user
Users when initially logging in will be a 'Guest' and unable to see anything.

You'll need to get a shell on the photoprism container and run the following:
```
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n photoprism
NAME                          READY   STATUS    RESTARTS   AGE
photoprism-85f94f89dd-g7628   1/1     Running   0          24m

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n photoprism photoprism-85f94f89dd-g7628 -- /bin/bash

# Look at current users
$ photoprism users ls

# Find the user and then update them to (Super)Admin role with WebDAV access
$ photoprism users mod --role admin --superadmin --webdav <username from above>
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

Plex should then be accessible publically via `https://plex.indigo.dalmura.cloud:32406/`

If you want to poke around the Plex container filesystem:
```
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n plex
NAME                       READY   STATUS    RESTARTS   AGE
plex-plex-media-server-0   1/1     Running   0          24m

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n plex plex-plex-media-server-0 -- /bin/bash
```

Interesting directories:
* `/config/Library/Application\ Support/Plex\ Media\ Server/`

## Emojirades Setup

Assuming you've setup all the normal vault/etc settings, ensure the ttl is set to 31d and not 24h due to IAM user DB vending.

If postgres is empty/fresh you'll need to init it, assuming you have a local emojirades checkout with the basic dev env setup:
```
# Port forward the postgres db
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 port-forward svc/emojirades-db-rw -n emojirades 5432:5432

# Get the DB URI
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get secret emojirades-db-app -n emojirades -o json | jq -r '.data."fqdn-uri"' | base64 -d; echo

# Ensure you replace the hostname with 'localhost' from the port-forward above
emojirades -vv init --db-uri "<get DB uri from secret emojirades-db-app in namespace>"
```

## Obsidian Livesync (CouchDB) Setup

Follow the steps in [INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md](INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md) with the following additional configuration:
* Reader Role: `workload-reader-obsidian-livesync-secrets`
* Service Account: `obsidian-livesync-couchdb`
* Secret Engine: `site`
* Secret Path: `wave-5/obsidian-livesync/couchdb-secrets`

Setting the following key and values:
* `ADMIN_USERNAME`: Something other than `admin`
* `ADMIN_PASSWORD`: Generate yourself
* `COOKIE_AUTH_SECRET_KEY`: Generate yourself (a-zA-Z0-9)
* `ERLANG_COOKIE_KEY`: Generate yourself (a-zA-Z0-9)

This should result in the following vault snippets:
```
vault policy write workload-reader-obsidian-livesync-secrets -<<EOF                                    
# Site secrets store for Obsidian Livesync - CouchDB
path "site/data/wave-5/obsidian-livesync/couchdb-secrets" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-obsidian-livesync-secrets \
   bound_service_account_names=obsidian-livesync-couchdb \
   bound_service_account_namespaces=obsidian-livesync \
   token_policies=workload-reader-obsidian-livesync-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h

```

## Tandoor Setup

See dedicated setup guide: [INDIGO-CORE-1-APPS-WAVE-5-TANDOOR.md](INDIGO-CORE-1-APPS-WAVE-5-TANDOOR.md)

### Vault Configuration

1. Create the Vault AWS Role (AKA IAM User Template) for Tandoor CNPG backups:
```bash
vault write aws/roles/tandoor-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=tandoor" \
    iam_tags="role=postgres"
```

2. Create the Vault policy and Kubernetes auth role:
```bash
vault policy write workload-reader-tandoor-secrets -<<EOF
path "aws/creds/tandoor-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/tandoor/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-tandoor-secrets \
   bound_service_account_names=tandoor-sa \
   bound_service_account_namespaces=tandoor \
   token_policies=workload-reader-tandoor-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

3. Create the application secret in Vault (`site/data/wave-5/tandoor/config`):
   - `secret_key`: `<random_django_secret_key>`
   - `oidc_client_id`: `<authentik_client_id>`
   - `oidc_client_secret`: `<authentik_client_secret>`

### Deploy & Verify

Sync the application via ArgoCD:
```bash
argocd app sync wave-5
argocd app sync tandoor
```

Tandoor will be accessible privately via:
`https://tandoor.indigo.dalmura.cloud/`


## Reactive Resume Setup

See dedicated setup guide: [INDIGO-CORE-1-APPS-WAVE-5-REACTIVE-RESUME.md](INDIGO-CORE-1-APPS-WAVE-5-REACTIVE-RESUME.md)

### Vault Configuration

1. Create the Vault AWS Role (AKA IAM User Template) for Reactive Resume CNPG backups:
```bash
vault write aws/roles/reactive-resume-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=reactive-resume" \
    iam_tags="role=postgres"
```

2. Create the Vault policy and Kubernetes auth role:
```bash
vault policy write workload-reader-reactive-resume-secrets -<<EOF
path "aws/creds/reactive-resume-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/reactive-resume/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-reactive-resume-secrets \
   bound_service_account_names=reactive-resume-sa \
   bound_service_account_namespaces=reactive-resume \
   token_policies=workload-reader-reactive-resume-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

3. Create the application secret in Vault (`site/data/wave-5/reactive-resume/config`):
   - `auth_secret`: `<random_32byte_hex>`
   - `oidc_client_id`: `<authentik_client_id>`
   - `oidc_client_secret`: `<authentik_client_secret>`

### Deploy & Verify

Sync the application via ArgoCD:
```bash
argocd app sync wave-5
argocd app sync reactive-resume
```

Reactive Resume will be accessible privately via:
`https://resume.indigo.dalmura.cloud/`


## Matrix Synapse Setup

See dedicated setup guide: [INDIGO-CORE-1-APPS-WAVE-5-MATRIX.md](INDIGO-CORE-1-APPS-WAVE-5-MATRIX.md)

### Vault Configuration

1. Create the Vault AWS Role (AKA IAM User Template) for Matrix Synapse CNPG backups:
```bash
vault write aws/roles/matrix-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=matrix" \
    iam_tags="role=postgres"
```

2. Create the Vault policy and Kubernetes auth role:
```bash
vault policy write workload-reader-matrix-secrets -<<EOF
path "aws/creds/matrix-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/matrix/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-matrix-secrets \
   bound_service_account_names=matrix-sa \
   bound_service_account_namespaces=matrix \
   token_policies=workload-reader-matrix-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

3. Create the application secret in Vault (`site/data/wave-5/matrix/config`):
   - `registration_shared_secret`: `<random_32byte_hex>`
   - `macaroon_secret_key`: `<random_32byte_hex>`
   - `form_secret`: `<random_32byte_hex>`
   - `db_password`: `<random_24byte_hex>`
   - `oidc_client_id`: `<authentik_client_id>`
   - `oidc_client_secret`: `<authentik_client_secret>`

### Deploy & Verify

Sync the application via ArgoCD:
```bash
argocd app sync wave-5
argocd app sync matrix
```

Matrix Synapse will be accessible publicly via:
`https://matrix.indigo.dalmura.cloud/`


## Archestra Setup

See dedicated setup guide: [INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md](INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md)

### Vault Configuration

1. Create the Vault AWS Role (AKA IAM User Template) for Archestra CNPG backups:
```bash
vault write aws/roles/archestra-db-backup \
    credential_type=iam_user \
    policy_arns='<iam_vended_permissions.id>' \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=archestra" \
    iam_tags="role=postgres"
```

2. Create the Vault policy and Kubernetes auth role:
```bash
vault policy write workload-reader-archestra-secrets -<<EOF
path "aws/creds/archestra-db-backup" {
    capabilities = ["read"]
}
path "site/data/wave-5/archestra/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-archestra-secrets \
   bound_service_account_names=archestra-sa \
   bound_service_account_namespaces=archestra \
   token_policies=workload-reader-archestra-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=31d
```

3. Create the application secrets in Vault (`site/data/wave-5/archestra/config`):
   - `auth_secret`: `<random_32byte_hex>`
   - `session_secret`: `<random_32byte_hex>`
   - `secrets_encryption_secret`: `<random_32byte_hex>`
   - `admin_password`: `<secure_initial_admin_password>`

### Deploy & Verify

Sync the application via ArgoCD:
```bash
argocd app sync wave-5
argocd app sync archestra
```

Archestra will be accessible privately via:
`https://archestra.indigo.dalmura.cloud/`
