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

## Captcha on login
Just to add some extra initial hurdles to anyone brute forcing their way in. This process will use Cloudflare Turnstile. But you can substitute in anything you want.

Cloudflare Steps:
* Log into your Cloudflare Account and go to the Turnstile product page
* Click Add Widget
* Widget name: indigo-captcha
* Add hostname: authentik.indigo.dalmura.cloud
* Add hostname: auth.indigo.dalmura.cloud
* Widget Mode: Managed (seems fine, recommended)
* Pre-clearance: No

Note down the `Site Key` and `Secret Key` as we'll use them in the step below. You can always go back to the Cloudflare Dashboard to the Turnstile page to view these values again.

Process:
* Go to `Flows and Stages` => `Stages` and click `Create`
* Select Captcha Stage
* Name: indigo-captcha
* Public Key: `Site Key` from before
* Private Key: `Secret Key` from before
* Interactive: Enabled
* Expand `Advanced settings`
* JS URL: https://challenges.cloudflare.com/turnstile/v0/api.js
* API URL: https://challenges.cloudflare.com/turnstile/v0/siteverify
* Click Finish

Now we integrate the above stage into the Username stage:
* Go to `Flows and Stages` => `Stages`
* Select `default-authentication-identification` and click Edit
* Captcha stage: Select `indigo-captcha`
* Click Update

Before logging out, open a new incognito tab and verify the login logic still works, otherwise you risk locking yourself out.

## Finally
You can now proceed with setting up Vault: [`dal-indigo-core-1` Apps - Wave 3 - Vault Configuration](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md)
