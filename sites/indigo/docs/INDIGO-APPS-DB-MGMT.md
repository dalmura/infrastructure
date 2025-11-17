# DB Management

Indigo site runs [CloudNativePG](https://cloudnative-pg.io/) as the preferred choice of cluster DB solution.

The current standard setup we have covers backup and restore and integration with Longhorn, along with examples to mount the DB credentials into application pods.

## Prerequisite AWS Credentials

Before we create the cluster, we need the backup/restore configuration.

This is defined as a set of k8s resources:
1. `ServiceAccount` (to let us authenticate to Vault)
2. `VaultDyanmicSecret` (to define how we talk to Vault)
3. `ExternalSecret` (to hold the AWS Creds we get from Vault)

The setup for the inputs to `VaultDyanmicSecret` and `ExternalSecret` is documented in [INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md](INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md), review that and ensure you create the appropriate roles as required.

Review [Forgejo](../clusters/dal-indigo-core-1/wave-5/overlays/forgejo/) as an example of the requires resources above.
