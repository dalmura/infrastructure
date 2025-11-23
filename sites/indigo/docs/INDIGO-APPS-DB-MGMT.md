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

After setting this up your namespace will have a Secret, being refreshed regularly, containing valid AWS Credentials used to backup to, and restore from, S3.

## Cluster

The cluster itself is created and owned by the `Cluster` resource in the namespace. It manages the Pods, PVCs, Services, etc that form the cluster.

The k8s StorageClass we use is `cluster-nobackup` as we don't want Longhorn managing the backups to S3, we will do it ourselves.

Backup/restore operations occur in the `s3://dal-site-backups/${site}/${app}/postgres/${cluster-name}` prefix, all files underneath this prefix is managed by CNPG itself (using [Barman](https://pgbarman.org/)).

The objects uploaded to this prefix are:
* `base/` contains the daily full backups
* `wal/` contains the Write Ahead Log

Both prefixes above follow the configured retention policy in the backups (eg. 10 days history).

## Restoring

Restoring from S3 cannot be done 'in-place', instead a *new* Cluster resource must be created referencing the S3 path of another Cluster. There is [discussion in Github](https://github.com/cloudnative-pg/cloudnative-pg/issues/5203) about this, but nothing has come from that yet.

This should only be done when the initial DB is beyond repair and unable to be recovered inplace, as the process involves deleting the original Cluster.

Because we are restoring into a *new* Cluster, after the restore is successful, we'll need to then go and update the application with the configuration and k8s resources of the new `Cluster`.

High level steps:
1. In k8s, delete the `ScheduledBackup` resource
2. In k8s, delete the `Cluster` resource
3. In git, update the `postgres.yaml`, changing:
  a. Cluster `metadata.name`
  b. Cluster `spec.backup.barmanObjectStore.tags.db`
  c. ScheduledBackup `spec.cluster.name`
4. In ArgoCD, Refresh and Sync the new Cluster resource
5. Watch the Cluster resource events and wait for the restore to complete
6. Update the application with the new DB configuration
7. Delete the application pods to restart the application

## Upgrading

Upgrading minor versions is handled automatically by CNPG, whenever it detects a new minor version it will immediately start upgrading all Clusters.

To upgrade to a newer version of Postgres with CNPG, the easiest way is simply to update the `spec.imageCatalogRef.major` version, this will perform an *offline* major upgrade which means:
* Cluster is shut down
* Upgrade is performed
* Cluster is turned back on

Ensure your application supports the new version of Postgres before upgrading, as rolling back isn't ideal, you will need to follow the Restoring steps above and create a new cluster using the previous backups.
