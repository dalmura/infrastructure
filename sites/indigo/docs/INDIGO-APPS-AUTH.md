# Application Authentication

Indigo site runs [Authentik](https://goauthentik.io/) as it's Identity Provider (OIDC) for authentication and authorisation.

This means Authentik is the source of truth for users/passwords/etc, as well as who is allowed to access what within the site.

## Native OIDC Authentication

Apps that support OIDC providers will be able to integrate with Authentik directly and have application entitlements managed via Authentik.

## Reverse Proxy Authentication

Apps that do *not* support OIDC providers will instead rely on Authentik's reverse proxy to gate access to the application.

Optionally some applications support HTTP headers (eg. `X-Forwarded-User` and `X-Forwarded-Groups`) as a way to tell if a user is logged in and provide access to certain features.

## Configuration of a new OIDC Application

TBD

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
* External host: `https://${APP}.indigo.dalmura.cloud/`, eg `htts://frigate.indigo.dalmura.cloud/`
* Token validity: `hours=24` (default)
* All other advanced settings as default

This will create the application specific proxy provider, and give you a warning that the provider is not assigned to any application.

Next up create an Application, eg Frigate, under `Applications` => `Applications` in Authentik:
* Click Create
* Name: `${APP}`, eg `Frigate`
* Slug: `${app}`, eg `frigate`
* Group: Your choice, eg `security`
* Provider: Select the one you just created, eg `Frigate Proxy Provider`
* No Backchannel Providers
* Policy engine mode: ANY (default)
* Launch URL: Default (empty), but override if required
* Icon: You can go to [Font Awesome](https://fontawesome.com/search) and put in `fa://<icon-name>`
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
