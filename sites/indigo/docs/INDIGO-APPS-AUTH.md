# Application Authentication

Indigo site runs [Authentik](https://goauthentik.io/) as it's Identity Provider (OIDC) for authentication and authorisation.

This means Authentik is the source of truth for users/passwords/etc, as well as who is allowed to access what within the site.

## Native OIDC Authentication

Apps that support OIDC providers will be able to integrate with Authentik directly and have application entitlements managed via Authentik.

## Reverse Proxy Authentication

Apps that do *not* support OIDC providers will instead rely on Authentik's reverse proxy to gate access to the application.

Optionally some applications support HTTP headers (eg. `X-Forwarded-User` and `X-Forwarded-Groups`) as a way to tell if a user is logged in and provide access to certain features (eg. Frigate relies on this).

## Configuration of a new OIDC Application

Within [Authentik](https://auth.indigo.dalmura.cloud) log in, under `Applications` => `Applications`:
* Click `Create with Provider`
* Name: Your Application
* Slug: your-application
* Optionally a Group if you want
 * Current groups are: security, developer
* Click `OAuth2/OpenID Provider`
* Leave Name as default: `Provider for XYZ`
* Authorization flow: Just pick `implicit-consent`
   * This removes an extra step when first signing in via Authentik
   * We are OK with this, as all applications are controlled and internal
* Client type: Confidential
* Note down the Client ID and Client Secret
* Set one or more Redirect URIs based on your applications doco
 * Eg forgejo: `https://forgejo.indigo.dalmura.cloud/user/oauth2/<auth-name>/callback`
* Under `Advanced protocol settings` => `Scopes` add `Application Entitlements`
* Click Next
* Bind existing policy/group/user, and select which groups get default access
* Save Binding
* Click Next
* Submit to save everything

Entitlements:
* Click your newly created Application, `Application Entitlements` tab
* Create a new entitlement, this is the name of a 'group' you want the user to be in the application (eg. 'admin' group, or 'viewers' group)
* Expand the chevron for your new entitlement and click `Bind existing Group / User` selecting the group you want to have this entitlement

You can navigate to `Applications` => `Providers`, click on your just created provider to review any details like the Client ID/Secret, or any URLs like the `.well-known` OIDC URL.

## Configuration of a new Reverse Proxy Application

The `wave-3` deployment will have created a generic [HTTP middleware](https://traefik-private.indigo.dalmura.cloud/dashboard/#/http/middlewares/authentik-authentik@kubernetescrd) that is available to use in both public and private Traefik ingress proxies.

Configure the applications Ingress resource to use the above middleware via annotations:
```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    ...
    traefik.ingress.kubernetes.io/router.middlewares: authentik-authentik@kubernetescrd
    ...
```

The middleware name is `$namespace-$middleware_name@$source` as [documented in Traefik](https://doc.traefik.io/traefik/reference/install-configuration/providers/overview/#provider-namespace).

Next up create a Proxy Provider under `Applications` => `Providers` in Authentik:
* Select Proxy Provider
* Name: `${APP} Proxy Provider`, eg `Frigate Proxy Provider`
* Authorization flow: default-provider-authorization-implicit-consent
* Select 'Forward Auth (single application)'
* External host: `https://${APP}.indigo.dalmura.cloud/`, eg `https://frigate.indigo.dalmura.cloud/`
* Token validity: `hours=24` (default)
* All other advanced settings as default

This will create the application specific proxy provider, and give you a warning that the provider is not assigned to any application.

Next up create an Application, eg Frigate, under `Applications` => `Applications` in Authentik:
* Click Create
* Name: `${APP}`, eg `Frigate`
* Slug: `${app}`, eg `frigate` (should autopopulate based on Name)
* Group: Your choice, eg `security`
* Provider: Select the one you just created, eg `Frigate Proxy Provider`
* No Backchannel Providers
* Policy engine mode: ANY (default)
* Launch URL: Default (empty), but override if required
* Icon: You can optionally upload an icon you want here
* Publisher: Blank
* Description: Something useful

Next up we need to assign the Application to the authentik Embedded Output:
* In Authentik navigate to `Applications` => `Outputs`
* Click the Edit button on the right of the `authentik Embedded Output`
* Select the newly created Application (eg `Frigate`) and move it over to Selected Applications

Finally within the newly created Application, assign users/groups:
* In Authentik click on the Frigate Application
* Go to `Policy / Group / User Bindings`
* Click `Bind existing policy/group/user`
* Click `Group` or `User` depending on what access you want to grant
* Ensure `Enabled` is selected
* Leave all other values default
* Click Create!

Now when you navigate to your app, eg `https://frigate.indigo.dalmura.cloud/` you will be redirected to Authentik to sign it (or if you're already signed in just use your existing session), validate you're assigned to the Application, then redirect you back and set an `authentik_proxy_XYZ` cookie for Traefik to validate via the Middleware.

### Optional Entitlements

Frigate has an optional config section to map HTTP header values to the `name` and `role` a user gets within Frigate:
```
proxy:
  separator: "|"
  header_map:
    user: x-authentik-name
    role: x-authentik-entitlements
```

And our Traefik Middleware is ensuring the above headers are being passed through to Frigate.

We just need to ensure the `x-authentik-entitlements` are being set correctly:
* In Authentik click on the Frigate Application
* Click the 'Application Entitlements' tab
* Click 'Create entitlement'
* Create a new entitlement called `admin` with no additional properties
* Expand the created `admin` entitlement and click the 'Bind existing Group / User'
* Bind the Group `site-admins` leaving everything default

### Protecting early site services
A few of the core site services run their own UI Ingress services, which are either unauthenticated or have their own authentication, because they were deployed _before_ Authentik was created (wave-1 and wave-2 were deployed before wave-3).

These are:
* [ArgoCD](https://argocd.indigo.dalmura.cloud) - Own authentication
* [Longhorn](https://longhorn.indigo.dalmura.cloud) - Unauthenticated
  * via Authentik Proxy Provider
* [Cilium Hubble](https://cilium-hubble) - Unauthenticated
  * via Authentik Proxy Provider
* [Traefik - Public](https://traefik-public.indigo.dalmura.cloud) - Unauthenticated
  * via Authentik Proxy Provider
* [Traefik - Private](https://traefik-private.indigo.dalmura.cloud) - Unauthenticated
  * via Authentik Proxy Provider
* [k8s Dashboard](https://kubernetes-dashboard.indigo.dalmura.cloud) - Own authentication
  * We'll leave this alone for now, pending TODO

For the unauthenticated endpoints we can inject the Authentik Traefik Middleware into the Ingress resource.

This adds the annotations for the above Authentik Proxy Providers:
```bash
# Patch the Longhorn Ingress with the new annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n longhorn-system annotate ingress longhorn-ui 'traefik.ingress.kubernetes.io/router.middlewares=authentik-authentik@kubernetescrd'

# Remove the Longhorn Ingress annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n longhorn-system annotate ingress longhorn-ui 'traefik.ingress.kubernetes.io/router.middlewares-'


# Patch the Cilium Hubble Ingress with the new annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n kube-system annotate ingress cilium-hubble-ui 'traefik.ingress.kubernetes.io/router.middlewares=authentik-authentik@kubernetescrd'

# Remove the Cilium Hubble Ingress annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n kube-system annotate ingress cilium-hubble-ui 'traefik.ingress.kubernetes.io/router.middlewares-'


# Patch the Traefik Public Ingress with the new annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n traefik-public annotate ingress traefik-public-ui 'traefik.ingress.kubernetes.io/router.middlewares=authentik-authentik@kubernetescrd'

# Remove the Traefik Public Ingress annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n traefik-public annotate ingress traefik-public-ui 'traefik.ingress.kubernetes.io/router.middlewares-'


# Patch the Traefik Private Ingress with the new annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n traefik-private annotate ingress traefik-private-ui 'traefik.ingress.kubernetes.io/router.middlewares=authentik-authentik@kubernetescrd'

# Remove the Traefik Private Ingress annotation
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n traefik-private annotate ingress traefik-private-ui 'traefik.ingress.kubernetes.io/router.middlewares-'
```

Doing this still requires you to follow the above `Configuration of a new Reverse Proxy Application` section and setup an application in Authentik.

For ArgoCD just follow [their documentation](https://integrations.goauthentik.io/infrastructure/argocd/) which just mimics the above `Native OIDC Authentication` section of this page.

The only deviation from their doco was around using Entitlements instead of Groups for the RBAC roles `Admin` and `Viewer`.

Get base64 encoded values:
```
echo -n "${AUTHENTIK_CLIENT_ID}" | base64
<encoded client id>

echo -n "${AUTHENTIK_CLIENT_SECRET}" | base64
<encoded client secret>
```

Patching the `argocd-secret` Secret:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd patch secret argocd-secret --patch '{"data": {"dex.authentik.clientId": "<encoded client id>"}}'
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd patch secret argocd-secret --patch '{"data": {"dex.authentik.clientSecret": "<encoded client secret>"}}'
```

Edit the `argocd-cm` ConfigMap:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd edit configmap argocd-cm
```

Adding the following:
```
data:
  ...
  url: https://argocd.indigo.dalmura.cloud
  dex.config: |
      connectors:
      - config:
          issuer: https://auth.indigo.dalmura.cloud/application/o/argo-cd/
          clientID: $dex.authentik.clientId
          clientSecret: $dex.authentik.clientSecret
          insecureEnableGroups: true
          scopes:
            - openid
            - profile
            - email
            - entitlements
          claimMapping:
            groups: "entitlements"
          overrideClaimMapping: true
        name: authentik
        type: oidc
        id: authentik
  ...
```

Edit the `argocd-rbac-cm` ConfigMap:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd edit configmap argocd-rbac-cm
```

Adding the following (adding the data key if it's not there):
```
metadata:
  ...
data:
  ...
  policy.csv: |
    g, Admin, role:admin
    g, Viewer, role:readonly
  ...
```

Then kill the ArgoCD `server` and `dex` pods first before login would work correctly (otherwise you'll get weird errors about token failing to validate.

You should now be able to log into ArgoCD correctly!

Using SSO to log into the ArgoCD CLI is supported as well, this will open a browser to perform the authentication:
```
argocd --grpc-web login argocd.indigo.dalmura.cloud --sso
```
