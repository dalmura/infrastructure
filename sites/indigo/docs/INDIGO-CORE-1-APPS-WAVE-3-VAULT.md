# Provision Vault for dal-indigo

This guide covers the overall setup of the Vault instance deployed as part of `wave-3`.

Eventually this configuration will be moved into the likes of the [Vault Terraform Provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs), but for now it's here!

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Vault running, but nothing done with it.

## Create the unseal secrets and root token

When you first visit the [Vault UI](https://vault.indigo.dalmura.cloud/) you'll be presented with the bootstrap options to create the initial unseal secret along with the root access token.

The current configuration is:
* Total Shares: 3
* Threshold: 2

Which means there are 3 secrets that could unseal the vault. But only 2 of them are required at any unsealing event.

Could just make it 1/1, but I figured eventually one or two can remain in offline storage as the unseal events would be irregular at best.

After this you will be presented with a screen to copy down each individual unseal share, along with a root token.

The root token will let you authenticate to vault as an admin that can do anything. We will use this to setup Keycloak integration!

## Keycloak Integration

todo
