# Provision Authentik for dal-indigo

This guide covers the overall setup of the Authentik instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Authentik Terraform Provider](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Authentik running with your own admin user

## Email Configuration

Install this:
https://docs.goauthentik.io/docs/add-secure-apps/flows-stages/flow/examples/flows#recovery-with-email-verification

Edit the above created flow and set 'no authentication' to 'no requirement', there's a bug.

Update the brand's 'recovery flow' to reference the above installed flow thingy.

This will allow you/users to send password recovery emails.

## General

Under `Customization` => `Policies` open the `default-password-change-password-policy` policy and review the password strength configuration.

## Users & Groups

We'll setup a few initial groups and add more as part of the other apps configuration steps.

High level concept it:
* Users are assigned to Groups
* Roles are assigned to Groups
* Users are indirecetly assinged to Roles via Groups
* Permissions within/access to Applications is granted to Roles

Create the following Groups:
* `spoke-users`
   * Access to a broad set of user friendly applications
* `spoke-users-media`
   * Access to media managements applications
* `hub-power-users`
   * Access to most apps across the site at the highest privilege level
* `site-admins`
   * Access to everything at the highest privilege level by default

Create whatever initial User(s) you'd like and assign them as required to the above Group(s).


## Finally
You can now proceed with setting up Vault: [`dal-indigo-core-1` Apps - Wave 3 - Vault Configuration](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md)
