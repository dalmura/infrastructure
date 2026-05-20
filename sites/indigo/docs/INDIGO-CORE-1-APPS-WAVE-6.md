# Provision the Wave 6 applications for dal-indigo-core-1

These are:
* [Tailscale Kubernetes Operator](https://tailscale.com/docs/features/kubernetes-operator) exposing cluster networking to a Tailscale tailnet
* [CrowdSec Hardening](INDIGO-CORE-1-APPS-WAVE-6-CROWDSEC.md) providing collaborative security automation

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and have a few applications you want to expose via Tailscale
* `vault` is logged in (see [dynamic user docs](INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md) if not)

## Crowdsec Setup

We will need to setup crowdsec along with integration into the public Traefik ingress.

This will require:
* Creating a Secret in both the `traefik-public` and `crowdsec` namespaces for the bouncer key
* Creating a Secret in the `crowdsec` namespace with other credentials
* Restarting the `traefik-public` Deploymnet

First let's create the various secrets:
```
YOUR_BOUNCER_KEY=$(openssl rand -base64 32)

# Must be greater than 64 chars
YOUR_CS_LAPI_SECRET=$(openssl rand -base64 128)

# Must be greater than 48 chars
YOUR_REGISTRATION_TOKEN=$(openssl rand -base64 64)
```

You can get the Enrollment Key from the [Crowdsec Website](https://app.crowdsec.net/security-engines?distribution=kubernetes) and clicking the 'Enroll command' and copying the key from the 'Kubernetes' tab.

### Setup Vault Integration
Open up [Vault](https://vault.indigo.dalmura.cloud/) and create the following secrets:

Shared bouncer secret at `site/wave-6/crowdsec/bouncer` with the following keys:
* `key`: `<YOUR_BOUNCER_KEY>`

Crowdsec creds secret at `site/wave-6/crowdsec/secrets` with the following keys:
* `csLapiSecret`: `<YOUR_CS_LAPI_SECRET>`
* `registrationToken`: `<YOUR_REGISTRATION_TOKEN>`
* `enrollmentKey`: `<Copied from Crowdsec website>`
* `enrollmentInstanceName`: `dal-indigo-core-1`
* `enrollmentTags`: `dalmura indigo k8s`

You need to allow the Crowdsec ServiceAccount to read these secrets. Execute the following in your Vault CLI:

```bash
# Create the Vault permissions policy
vault policy write workload-reader-crowdsec -<<EOF
path "site/data/wave-6/crowdsec/*" {
    capabilities = ["read", "list"]
}
EOF

# Create the role that ESO will use to access Vault
vault write auth/kubernetes/role/workload-reader-crowdsec \
   bound_service_account_names=crowdsec \
   bound_service_account_namespaces=crowdsec \
   token_policies=workload-reader-crowdsec \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

We have already provisioned the `SecretStore` and `ExternalSecret` in the `wave-6` overlays to automatically sync these into the required Kubernetes Secrets.

## Tailscale Webfinger Setup

To setup the Tailscale account you must deploy the WebFinger parts of this app first, and configure a `tailscale` application (w/OIDC provider) within Authentik, you can refer to [Authentik's guide](https://integrations.goauthentik.io/networking/tailscale/) on this along with the [Tailscale documentation on custom OIDC](https://tailscale.com/docs/integrations/identity/custom-oidc#webfinger-setup).

### Custom OIDC / WebFinger Setup
Tailscale requires WebFinger to discover your Authentik OIDC issuer when using a custom domain like `your-email@dalmura.cloud`.

#### Setup Authentik
*   Create an Application w/OAuth2/OpenID Provider
*   Redirect URI: `https://login.tailscale.com/a/oauth_callback`
*   Slug: `tailscale` (resulting in an issuer URL of `https://auth.indigo.dalmura.cloud/application/o/tailscale/`)

#### Setup Vault Integration
Open up [Vault](https://vault.indigo.dalmura.cloud/) and create the following secrets:

WebFinger content at `site/wave-6/tailscale/webfinger` with a key `content`:
```json
{
  "subject": "acct:your-email@dalmura.cloud",
  "links": [
    {
      "rel": "http://openid.net/specs/connect/1.0/issuer",
      "href": "https://auth.indigo.dalmura.cloud/application/o/tailscale/"
    }
  ]
}
```

You need to allow the Tailscale ServiceAccount to read these secrets. Execute the following in your Vault CLI:
```bash
# Create the Vault permissions policy
vault policy write workload-reader-tailscale -<<EOF
path "site/data/wave-6/tailscale/*" {
    capabilities = ["read", "list"]
}
EOF

# Create the role that ESO will use to access Vault
vault write auth/kubernetes/role/workload-reader-tailscale \
   bound_service_account_names=operator \
   bound_service_account_namespaces=tailscale \
   token_policies=workload-reader-tailscale \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

#### Geoblock Bypass (Authentik)
Tailscale needs to access a few different endpoints within Authentik from its global infra. This means we need to lift a few of our restrictions based on path.

We have `wave-3/overlays/authentik/ingress-tailscale-bypass.yaml` which exposes the following paths:
* `/application/o/tailscale/.well-known/openid-configuration`
* `/application/o/tailscale/jwks/`
* `/application/o/token/`
* `/application/o/userinfo/`


#### AWS Permissions
Once the Webfinger ingress is provisioned, you'll need to perform the following 'hacks':
* Log into AWS and create an `A` record with the sites Public IP address
   * So Tailscale will resolve `dalmura.cloud` to your IP
* The existing port forward for TCP/443 => Ingress Public should be fine
* Update the IAM Policy attached to `dal-indigo-k8s-dns-updater` allowing changes to
   * `*.dalmura.cloud`
   * `dalmura.cloud`

This should allow `cert-manager` to create the correct DNS challenge entries to provision a `dalmura.cloud` certificate.

#### Webfinger Teardown
Once you have a Tailscale account created you don't need the Webfinger setup anymore, so we can modify the `wave-6/overlays/tailscale-operator/kustomization.yaml` and comment out the relevant `*-webfinger.yaml` files.

You must also roll back the above AWS permissions by removing the additional domains above, ensuring just `*.indigo.dalmura.cloud` is the only entry.

You must also roll back the manual `A` record on `dalmura.cloud` pointing to the sites Public IP.

You can reverse these steps if you ever need to set it up again.

## Tailscale Operator Setup
Once you have a Tailscale account you can proceed with deploying the operator itself, first within your Tailscale account you need to follow the [instructions](https://tailscale.com/docs/features/kubernetes-operator) and note down the OAuth Client ID and Secret output.

Also create the following tags:
* `k8s-indigo` (with `k8s-operator` as the owner)

### Vault Settings
Operator credentials at `site/wave-6/tailscale/operator`:
* `client_id`: `<YOUR_CLIENT_ID>`
* `client_secret`: `<YOUR_CLIENT_SECRET>`

We have already provisioned the required `SecretStore` and `ExternalSecret`(s) in the `wave-6` overlays to automatically sync these into a Kubernetes Secrets.

## Create the wave-6 parent app & deploy children
```bash
argocd app create wave-6 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-6/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-6

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-6
```

## Tailscale Validation
Check the status of the operator pods:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n tailscale
```

Once running, you can expose services to your tailnet using the `tailscale.com/expose: "true"` annotation or by creating `TailnetDevice` resources.


## Crowdsec Validation
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -n crowdsec deployment/crowdsec -- cscli bouncers list
```

You should see `traefik-bouncer` listed as "Valid".

### Collection Synchronization
Because the `lapi` pod has a PV setup, the entrypoint script skips the automatic download of any newly defined COLLECTIONS defined in `values.yaml`. If you add new collections you will need to manually sync them in the `lapi` pod with:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -n crowdsec deployment/crowdsec-lapi -- cscli collections install <collection-name>
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -n crowdsec deployment/crowdsec-lapi -- cscli collections upgrade --all
```

The `appsec` pod doesn't have a PV, so that will 'just work' when the pod restarts after a change.

### Remediation Behavior (In-Band vs Out-of-Band)
The AppSec container operates in two modes depending on the collection/rule configuration:
* In-Band (Blocking): The request is scanned *before* it reaches the application. If an attack is detected, Traefik returns a `403 Forbidden` immediately
* Out-of-Band (Detection): The request is allowed to pass to the application immediately to minimize latency. AppSec scans it in the background and will trigger a ban for subsequent requests if an attack is found.

#### Verification Examples
Trigger a 403 (In-Band):
Most patterns are configured for immediate blocking:
```bash
# XSS test
curl -I "https://anubis.indigo.dalmura.cloud/?q=<script>alert(1)</script>"

# Wordpress PHP upload test
curl -I "https://anubis.indigo.dalmura.cloud/wp-content/uploads/malicious.php"
```
