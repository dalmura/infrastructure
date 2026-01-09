# Provision Authentik for dal-indigo

This guide covers the overall setup of the Authentik instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Authentik Terraform Provider](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Authentik running, with your own admin user, and available via its Ingress

## Email Configuration

* Download the flow file from:
https://docs.goauthentik.io/docs/add-secure-apps/flows-stages/flow/examples/flows#recovery-with-email-verification
* Navigate to 'Flows and Stages' => 'Flows'
* Click 'Import' and select the file from above
* This will be created as `default-recovery-flow`
* Edit the above creeated flow and set 'no authentication' to 'no requirement', there's a bug
* Navigate to 'System' => 'Brands'
* Edit the `authentik-default` brand's 'recovery flow' and select the only option `default-recovery-flow`
* Click Update to save the configuration

Next we'll tweak the Password Recovery email a little bit:
* Navigate to 'Flows and Stages' => 'Flows'
* Click the `default-recovery-flow`
* Click the 'Stage Bindings' tab
* Edit the `default-recovery-email` stage
* Change the Subject field: Password Reset

This will allow you/users to send password recovery emails.

## General

Under `Customization` => `Policies` open the `default-password-change-password-policy` policy and review the password strength configuration.

Currently these are enabled:
* Check static rules
  * 8 characters minimum
  * At least 1 of upper, lower, digit, symbol
* Cannot appear on `haveibeenpwned.com`
* Must have a reasonably complex password according to [zxcvbn](https://github.com/dropbox/zxcvbn#readme)

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
   * Set the parent group as `spoke-users`
* `hub-power-users`
   * Access to most apps across the site at the highest privilege level
   * Set the parent group as `spoke-users`
* `site-admins`
   * Access to everything at the highest privilege level by default
   * Set the parent group as `hub-power-users`

Create whatever initial User(s) you'd like and assign them as required to the above Group(s).

## Captcha on login
Just to add some extra initial hurdles to anyone brute forcing their way in. This process will use Cloudflare Turnstile. But you can substitute in anything you want.

Cloudflare Steps:
* Log into your Cloudflare Account and go to the Turnstile product page
* Click Add Widget
* Widget name: indigo-captcha
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
* Captcha stage: `indigo-captcha`
* Click Update
* Select `default-recovery-identification` and click Edit
* Captcha stage: `indigo-captcha`
* Click Update

Before logging out, open a new incognito tab and verify the login logic still works, otherwise you risk locking yourself out.

## Finally
You can now proceed with setting up Vault: [`dal-indigo-core-1` Apps - Wave 3 - Vault Configuration](INDIGO-CORE-1-APPS-WAVE-3-VAULT.md)
