# Provision Keycloak for dal-indigo

This guide covers the overall setup of the Keycloak instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Keycloak Terraform Provider](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Keycloak running with your own admin user

## Create the `dalmura` Realm

Create the `dalmura` Realm via the UI, ensure the `dalmura` Realm is chosen in the drop-down in the top left.

Realm settings are below, unless specified settings are left as default.

## `dalmura` Configuration - Realm Settings
### General
```
Display name: Dalmura
```

### Email
Ensure your `site-admin` user has an email address setup.

So for this we'll need to ensure the right SMTP settings/etc are configured against `dalmura.cloud`.

You can get the required AWS Credentials from the `dalmura/network` repo, the README.md contains the instructions how to get them.

Details:
```
From: indigo+auth@dalmura.cloud
From display name: Dalmura Indigo Authentication
Envelope from: indigo+auth@dalmura.cloud

Host: email-smtp.us-east-1.amazonaws.com
Port: 465
Enable SSL: true
Enable Authentication: true
Username: <k8s_email_sender_key.id>
Password: <k8s_email_sender_key.ses_smtp_password_v4>
```

You can click the `Test connection` button and it should work.

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

## `dalmura` Configuration - Authentication

### Policies

Password policy:
```
Minimum length: 8
```

## `dalmura` Management - Groups
We'll just setup a couple of initial groups, more will be added later as we go.

The high level concept is:
* Users are assigned to Groups
* Client Roles are assigned to Groups
* So, Users are indirectly assigned to Client Roles via Groups
* Mappers in a Client, will map Client Roles into the oauth token for OIDC apps to manage internal roles

Create the following Groups as defined below.

### `spoke-users` Group
General users, they get access to a set of user friendly applications, with basic permissions within these apps if supported.

### `spoke-users-media` Group
General users, this group is specific to media management applications, providing additional permissions to manually manage media.

### `hub-power-users` Group
Technical users, they get access to most apps, with admin permissions, but maybe not certain site specific privileged apps.

### `site-admins` Group
Owners of the site, default access to everything, along with admin permissions within all apps where possible.

## `dalmura` Management - Users
Create whatever initial users you'd like. Their email is their username.

Ideally at least 1x User, assigned to the `site-admins` Group.

## Finally
You can now proceed with setting up Vault: [`dal-indigo-core-1` Apps - Wave 3 - Vault Configuration](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md)
