# Provision Vault for dal-indigo-core-1

This guide covers the overall setup of the Vault instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Vault Terraform Provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Vault running
* [`dal-indigo-core-1` Apps - Wave 3 - Authentik](INDIGO-CORE-1-APPS-WAVE-3-AUTHENTIK.md`) and have Authentik up and the initial roles configured

## Create the unseal secrets and root token

When you first visit the [Vault UI](https://vault.indigo.dalmura.cloud/) you'll be presented with the bootstrap options to create the initial unseal secret along with the root access token.

The current configuration is:
* Total Shares: 3
* Threshold: 2

Which means there are 3 secrets that could unseal the vault. But only 2 of them are required at any unsealing event.

Could just make it 1/1, but I figured eventually 1 or 2 can remain in offline storage as the unseal events would be irregular at best.

After this you will be presented with a screen to copy down each individual unseal share, along with a root token.

The root token will let you authenticate to vault as an admin that can do anything. We will use this to setup Keycloak integration!

## Authentik Integration

In order to be able to log into Vault using Authentik we need to perform the following configuration.

### Authentik Configuration

Log into [Authentik](https://authentik.indigo.dalmura.cloud) as the `site-admin` user.

In `Applications` => `Applications`:
* Create with provider
* Name: `Vault`
* Slug: `Vault`
* Group: Empty
* Policy engine mode: Any
* UI Settings - Launch URL: `<TBD>`
* Click Next
* Select the `OAuth2/OpenID Provider`
* Click Next
* Leave the Name as-is
* Authorization flow: `default-provider-authorization-implicit-consent`
* Client Type: `Confidential`
* Note down the `Client ID`
* Note down the `Client Secret`
* Enter the following 3x `Strict` Redirect URIs:
   * `https://vault.indigo.dalmura.cloud/ui/vault/auth/oidc_authentik/oidc/callback`
   * `https://vault.indigo.dalmura.cloud/oidc_authentik/callback`
   * `http://localhost:8250/oidc/callback`
* All other settings can be left as default for now
* Click Next
* Click Bind existing policy/group/user
* Click Group and select the `spoke-users`, repeat with `hub-power-users` and repeat with `site-admins`
* Click Next and review the settings
* Click Create

Ensure you've noted down the `Client ID` and `Client Secret` from earlier.

If not, you can go to `Applications` => `Providers`, click the `edit` icon for the `Provider for Vault`, the `Client ID` and `Client Secret` will be there.

#### Entitlements
Entitlements are application specific roles that can be mapped to Authentik groups. This adds a layer of abstraction as it allows you to name these application specific roles like what the application is expecting.

To setup the entitlements themselves and map them to groups:
* Click `Applications` => `Applications` on the side menu and click/enter our new Vault application.
* Click on the `Application entitlements` tab header
* Create three new entitlements:
   * `administrator`
   * `power-user`
   * `basic-user`
* Expand each one and click `Bind existing Group / User` selecting:
   * `administrator` binds to Group `site-admins`
   * `power-user` binds to Authentik Group `hub-power-users`
   * `basic-user` binds to Authentik Group `spoke-users`

To configure the provider to allow the entitlements through the oauth token:
* Click `Applications` => `Providers`
* Edit the Vault provider
* Scroll down and expand the `Advanced protocol settings
* Under the `Scopes` section ensure the "authentik default OAuth Mapping: Application Entitlements" is added to the `Selected Scopes`


To verify the above setup, click through `Applications` => `Providers`, select our Vault provider, and click the `Preview` header tab.

Select a user in the text box you want to validate and ensure there is:
* The `preferred_username` field is populated
* The `roles` field is filled out with the correct groups

### Vault Configuration

Ensure the `vault` CLI tool is installed locally.

Authenticate to vault:
```
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
vault login -method=token

# Enter your root token from above
```

Create a few initial secret stores:
```
vault secrets enable -path=public -version=2 kv
vault secrets enable -path=site -version=2 kv
vault secrets enable -path=site-sensitive -version=2 kv
```

Create 3x policies, one for each of the Authentic Roles above:

`administrator` role:
```
vault policy write administrator -<<EOF
path "*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

`power-user` role:
```
vault policy write power-user -<<EOF
path "site/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

`basic-user` role:
```
vault policy write basic-user -<<EOF
path "public/+" {
  capabilities = ["read", "list"]

}

path "public/users/{{identity.entity.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

Policies will be additive and multiple assigned to users.

Eg a `spoke-users` group member will just get the `basic-user` vault role, but a `hub-power-users` group member will get both the `power-user` and `basic-user` roles.


Enable OIDC authentication:
```
vault auth enable oidc_authentik

vault write auth/oidc_authentik/config \
    oidc_discovery_url="https://authentik.indigo.dalmura.cloud/application/o/vault/" \
    oidc_client_id="<Client ID from above>" \
    oidc_client_secret="<Client Secret from above>" \
    default_role="default"

vault write auth/oidc_authentik/role/default \
    allowed_redirect_uris="https://vault.indigo.dalmura.cloud/ui/vault/auth/oidc_authentik/oidc/callback" \
    allowed_redirect_uris="https://vault.indigo.dalmura.cloud/oidc_authentik/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="preferred_username" \
    groups_claim="roles" \
    oidc_scopes="openid,profile,email,entitlements"
```

Create the external groups that will eventually map Authentik roles to the vault policies:
```
vault write identity/group \
    name="basic-user" \
    policies="basic-user,default" \
    type="external"

# id: 0f41c516-1176-73d6-e192-3116e0a3d326

vault write identity/group \
    name="power-user" \
    policies="power-user,basic-user,default" \
    type="external"

# id: 09623ddb-29be-ffb3-a4d5-57ea95c2570c

vault write identity/group \
    name="administrator" \
    policies="administrator,default" \
    type="external"

# id: 010641cc-629e-2f09-301f-d2d0f7c1cb68
```

Note down the returned `id` value for each of the above groups as we'll use them below.

Get the vault auth OIDC accessor 'id':
```
vault auth list -format json | jq -r '."oidc_authentik/".accessor'

# accessor: auth_oidc_a6ed9622
```

Create the group-aliases:
```
vault write identity/group-alias \
    name="basic-user" \
    mount_accessor="auth_oidc_a6ed9622" \
    canonical_id="0f41c516-1176-73d6-e192-3116e0a3d326"

vault write identity/group-alias \
    name="power-user" \
    mount_accessor="auth_oidc_a6ed9622" \
    canonical_id="09623ddb-29be-ffb3-a4d5-57ea95c2570c"

vault write identity/group-alias \
    name="administrator" \
    mount_accessor="auth_oidc_a6ed9622" \
    canonical_id="010641cc-629e-2f09-301f-d2d0f7c1cb68"
```

The `name` of these group-alias' need to match the Authentik Entitlements the user is associated with via their Authentik Groups.

A group-alias associates a role `name` from the ID token's group claim (found via the `mount_accessor` role, `default` in this case) to a Vault Group, represented by the `canonical_id`, which contains the Vault Policy(s) that apply.

Once a user signs in a Vault Entity (aka user) is created, along with an Entity Alias, linking that Vault Entity <=> OIDC Entity.

Users should now be able to autheticate with Vault via the OIDC authentication method (using the `default_authentik` profile).


## Keycloak Integration

### Keycloak Configuration

These steps will setup Keycloak:

Log into [Keycloak](https://auth.indigo.dalmura.cloud) as the `site-admin` user.

Select the `dalmura` realm, navigate to Clients, and click 'Create Client'.

Configure the client with the following settings:
* Client Type: OpenID Connect
* Client ID: `vault`
* Name: `Vault`
* Description: `Hashicorp Vault - Secret Management`
* Next
* Client authentication: On
* Untick 'Direct access grants'
* Leaving just 'Standard flow' ticked
* Next
* Root URL: `https://vault.indigo.dalmura.cloud/`
* Home URL: `https://vault.indigo.dalmura.cloud/`
* Valid redirect URIs: `https://vault.indigo.dalmura.cloud/ui/vault/auth/oidc/oidc/callback`
* Valid redirect URIs: `http://localhost:8250/oidc/callback`
* Valid post logout redirect URIs: `https://vault.indigo.dalmura.cloud/ui/`
* Web origins: `https://vault.indigo.dalmura.cloud/`
* Save

Click on the `Credentials` tab up top and note the `Client secret` field, we'll use that later.

Click on the `Roles` tab up top and create the following roles:

Administrator Role:
* Role name: `administrator`
* Description: `Read and write access to everything`

Power User Role:
* Role name: `power-user`
* Description: `Read access to most things, limited global write access`

Basic User Role:
* Role name: `basic-user`
* Description: `Limited access to their own private space`

Navigate back to the Client settings for the `vault` Client and click the `Client scopes` tab up top.

Click on the `vault-dedicated` client scope on the page.

Click 'Configure a new mapper', scrolling down and selecting `User Client Role` from the list.

Create a new mapper with the following settings:
* Name: `vault`
* Client ID: `vault`
* Ensure 'Multivalued' is On
* Token Claim Name: `roles`
* Claim JSON Type: `String`
* Add to userinfo: Off

Navigate back to the realm Groups and for each Group below setup:

`site-admins` Group:
* Click 'Role mapping' tab and 'Assign role' button
* Search for `vault` in the 'Search by role name' text box
* Select the `administrator` role and click 'Assign'

`hub-power-users` Group:
* Click 'Role mapping' tab and 'Assign role' button
* Search for `vault` in the 'Search by role name' text box
* Select the `power-user` role and click 'Assign'

`spoke-users` Group:
* Click 'Role mapping' tab and 'Assign role' button
* Search for `vault` in the 'Search by role name' text box
* Select the `basic-user` role and click 'Assign'

### Vault Configuration

Ensure the `vault` CLI tool is installed locally.

Authenticate to vault:
```
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
vault login -method=token

# Enter your root token from above
```

Create a few initial secret stores:
```
vault secrets enable -path=public -version=2 kv
vault secrets enable -path=site -version=2 kv
vault secrets enable -path=site-sensitive -version=2 kv
```

Create 3x policies, one for each of the Keycloak Client Roles above:

`administrator` role:
```
vault policy write administrator -<<EOF
path "*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

`power-user` role:
```
vault policy write power-user -<<EOF
path "site/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

`basic-user` role:
```
vault policy write basic-user -<<EOF
path "public/+" {
  capabilities = ["read", "list"]

}

path "public/users/{{identity.entity.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

Policies will be additive and multiple assigned to users.

Eg a `spoke-users` group member will just get the `basic-user` vault role, but a `hub-power-users` group member will get both the `power-user` and `basic-user` roles.

Enable OIDC authentication:
```
vault auth enable oidc

vault write auth/oidc/config \
    oidc_discovery_url="https://auth.indigo.dalmura.cloud/realms/dalmura" \
    oidc_client_id="vault" \
    oidc_client_secret="<keycloak client secret from above>" \
    default_role="default"

vault write auth/oidc/role/default \
    allowed_redirect_uris="https://vault.indigo.dalmura.cloud/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="preferred_username" \
    groups_claim="roles"
```
spoke-users
Create the external groups that will eventually map Keycloak roles to the vault policies:
```
vault write identity/group \
    name="basic-user" \
    policies="basic-user,default" \
    type="external"

# id: 0f41c516-1176-73d6-e192-3116e0a3d326


vault write identity/group \
    name="power-user" \
    policies="power-user,basic-user,default" \
    type="external"

# id: 09623ddb-29be-ffb3-a4d5-57ea95c2570c


vault write identity/group \
    name="administrator" \
    policies="administrator,default" \
    type="external"

# id: 010641cc-629e-2f09-301f-d2d0f7c1cb68
```

Note down the returned `id` value for each of the above groups as we'll use them below.

Get the vault auth OIDC accessor 'id':
```
vault auth list -format json | jq -r '."oidc/".accessor'

# accessor: auth_oidc_1bb7e06f
```

Create the group-aliases:
```
vault write identity/group-alias \
    name="basic-user" \
    mount_accessor="auth_oidc_1bb7e06f" \
    canonical_id="0f41c516-1176-73d6-e192-3116e0a3d326"

vault write identity/group-alias \
    name="power-user" \
    mount_accessor="auth_oidc_1bb7e06f" \
    canonical_id="09623ddb-29be-ffb3-a4d5-57ea95c2570c"

vault write identity/group-alias \
    name="administrator" \
    mount_accessor="auth_oidc_1bb7e06f" \
    canonical_id="010641cc-629e-2f09-301f-d2d0f7c1cb68"
```

The `name` of these group-alias' need to match the Keycloak Client Roles that you created earlier.

A group-alias associates a role `name` from the ID token's group claim (found via the `mount_accessor` role, `default` in this case) to a Vault Group, represented by the `canonical_id`, which contains the Vault Policy(s) that apply.

Once a user signs in a Vault Entity (aka user) is created, along with an Entity Alias, linking that Vault Entity <=> OIDC Entity.

Users should now be able to autheticate with Vault via the OIDC authentication method (using the `default` profile).
