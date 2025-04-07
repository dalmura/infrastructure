# Provision Keycloak for dal-indigo

This guide covers the overall setup of the Keycloak instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Keycloak Terraform Provider](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Keycloak running with your own admin user

## Create the `dalmura` Realm

Realm settings are below, unless specified settings are left as default.

### General
```
Display name: Dalmura
```

### Login
```
Remember me: true
Email as username: true
Login with email: true    (was set by default, including anyway)
```

### Security defenses
Brute force detection:
```
Brute Force Mode: Lockout temporarily
Max login failures: 5
Wait increment: 5
Max wait: 30
```

### Sessions
```
SSO Session Idle: 1 Hours
```

## Configure Authentication

### Policies

Password policy:
```
Minimum length: 8
```

## Setup Users
Create whatever initial users you'd like. Their email is their username.
