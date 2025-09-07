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

TBD
