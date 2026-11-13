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

Backup/restore operations occur in the `s3://dal-site-backups/${site}/${app}/postgres/${cluster-name}` prefix, all files underneath this prefix is managed by CNPG itself (using [Barman](https://pgbarman.org/) via the `plugin-barman-cloud` sidecar).

The objects uploaded to this prefix are:
* `base/` contains the daily full backups
* `wal/` contains the Write Ahead Log

Both prefixes above follow the configured retention policy in the `ObjectStore` resource (eg. 3d, 7d, 10d history).

## Barman Cloud Plugin Architecture

Indigo deploys CNPG clusters configured with the `barman-cloud.cloudnative-pg.io` plugin.

1. **ObjectStore CRD (`barmancloud.cnpg.io/v1`)**:
   - Deployed in each application namespace (e.g. `object-store.yaml`).
   - Defines destination S3 bucket path, encryption/compression (`gzip`), AWS credentials reference, and `retentionPolicy`.
2. **Sidecar Container (`plugin-barman-cloud`)**:
   - The CNPG operator injects the `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar` into each PostgreSQL instance pod.
   - Handles continuous WAL archiving (`barman-cloud-wal-archive`) and ScheduledBackups (`barman-cloud-backup`).
   - Runs a maintenance cycle every 5 minutes on the primary instance pod:
     - Applies the backup retention policy (`barman-cloud-backup-delete --retention-policy ...`).
     - Scans the backup catalog (`barman-cloud-backup-list`).
     - Updates the `ObjectStore.status.serverRecoveryWindow` (`firstRecoverabilityPoint`, `lastSuccessfulBackupTime`).
3. **Network Policy**:
   - Postgres pods requiring S3 access must allow DNS egress to kube-dns (port 53) and HTTPS egress to S3 (`toEntities: world`, port 443).

## Troubleshooting Backup Retention & Failed Backups

### Alert: `PostgresBackupRetentionFailing`

VictoriaMetrics Alertmanager fires this warning alert when:
```promql
time() - barman_cloud_cloudnative_pg_io_first_recoverability_point > retention_window_seconds
```

#### Why It Occurs

1. **Barman Retention Policy Ignores Failed Backups**: When the sidecar executes `barman-cloud-backup-delete --retention-policy "RECOVERY WINDOW OF X DAYS"`, pgbarman evaluates only **valid, successful** backups to determine the recovery window. It completely ignores backups marked as `FAILED`.
2. **FirstRecoverabilityPoint Selection Bug**: In `plugin-barman-cloud`, the catalog evaluation calculates `FirstRecoverabilityPoint` by looking for the earliest backup that has both a begin and end timestamp. When a backup fails during data upload (e.g., transient network glitch or S3 connection timeout), Barman still writes `begin_time` and `end_time` into `backup.info` with `status: FAILED`.
3. **Stuck Status**: The plugin mistakenly picks up this failed backup as the cluster's earliest recoverability point. Because Barman's retention policy never prunes failed backups, the failed entry remains in S3 indefinitely, permanently pinning `firstRecoverabilityPoint` to the past and triggering the retention alarm once it exceeds the threshold.

#### Diagnostic & Remediation Steps

All commands below assume running from `sites/indigo` using `--kubeconfig kubeconfigs/dal-indigo-core-1`.

##### Step 1: Check Current Recoverability Windows
Inspect the status of all `ObjectStore` resources across the cluster:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get objectstore -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,RETENTION:.spec.retentionPolicy,FIRST_REC:.status.serverRecoveryWindow.*.firstRecoverabilityPoint,LAST_SUCCESS:.status.serverRecoveryWindow.*.lastSuccessfulBackupTime,LAST_FAILED:.status.serverRecoveryWindow.*.lastFailedBackupTime
```
Compare `FIRST_REC` against `RETENTION`. If `FIRST_REC` is significantly older than the retention policy, older backups (typically failed ones) are present in S3.

##### Step 2: List Backups in S3
Run `barman-cloud-backup-list` inside the cluster pod to check all backups stored in S3.

For services using Vault Dynamic Secrets (e.g. `emojirades`, `forgejo`, `matrix`, `reactive-resume`, `tandoor`):
```bash
NAMESPACE="emojirades"
APP="emojirades"
CLUSTER="emojirades-db"

kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n ${NAMESPACE} get secret ${APP}-db-backup -o json | \
  jq -r '"export AWS_ACCESS_KEY_ID=" + (.data.access_key | @base64d) + " AWS_SECRET_ACCESS_KEY=" + (.data.secret_key | @base64d)' | \
  kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -i -n ${NAMESPACE} ${CLUSTER}-1 -c postgres -- \
  sh -c "eval \$(cat); barman-cloud-backup-list --cloud-provider aws-s3 s3://dal-site-backups/indigo/${APP}/postgres/ ${CLUSTER}"
```

For Authentik (uses sealed secret with uppercase keys):
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n authentik get secret authentik-db-backup-secret -o json | \
  jq -r '"export AWS_ACCESS_KEY_ID=" + (.data.ACCESS_KEY_ID | @base64d) + " AWS_SECRET_ACCESS_KEY=" + (.data.SECRET_ACCESS_KEY | @base64d)' | \
  kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -i -n authentik authentik-db-1 -c postgres -- \
  sh -c 'eval $(cat); barman-cloud-backup-list --cloud-provider aws-s3 s3://dal-site-backups/indigo/authentik/postgres/ authentik-db'
```

Look for entries in the output where the `Archival Status` is `FAILED`.

##### Step 3: Delete Failed Backups from S3
Delete the specific failed backup ID using `barman-cloud-backup-delete -b <BACKUP_ID>`:

```bash
# Test first with --dry-run
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n ${NAMESPACE} get secret ${APP}-db-backup -o json | \
  jq -r '"export AWS_ACCESS_KEY_ID=" + (.data.access_key | @base64d) + " AWS_SECRET_ACCESS_KEY=" + (.data.secret_key | @base64d)' | \
  kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -i -n ${NAMESPACE} ${CLUSTER}-1 -c postgres -- \
  sh -c "eval \$(cat); barman-cloud-backup-delete --dry-run --cloud-provider aws-s3 -b <BACKUP_ID> s3://dal-site-backups/indigo/${APP}/postgres/ ${CLUSTER}"

# Perform actual deletion
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n ${NAMESPACE} get secret ${APP}-db-backup -o json | \
  jq -r '"export AWS_ACCESS_KEY_ID=" + (.data.access_key | @base64d) + " AWS_SECRET_ACCESS_KEY=" + (.data.secret_key | @base64d)' | \
  kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -i -n ${NAMESPACE} ${CLUSTER}-1 -c postgres -- \
  sh -c "eval \$(cat); barman-cloud-backup-delete --cloud-provider aws-s3 -b <BACKUP_ID> s3://dal-site-backups/indigo/${APP}/postgres/ ${CLUSTER}"
```

##### Step 4: Verify Status and Alert Resolution
Within 5 minutes, the sidecar's next maintenance cycle will re-list S3 backups, identify the new earliest valid backup, and update `FirstRecoverabilityPoint`:
```bash
# Check updated ObjectStore status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get objectstore -n ${NAMESPACE} ${APP}-postgres -o yaml

# Verify active firing alerts in VictoriaMetrics Alertmanager
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -n victoria-metrics deployment/victoria-metrics-alert-vma-alertmanager -- \
  wget -qO- http://localhost:9093/api/v2/alerts | jq .
```

## Restoring

Restoring from S3 cannot be done 'in-place', instead a *new* Cluster resource must be created referencing the S3 path of another Cluster. There is [discussion in Github](https://github.com/cloudnative-pg/cloudnative-pg/issues/5203) about this, but nothing has come from that yet.

This should only be done when the initial DB is beyond repair and unable to be recovered inplace, as the process involves deleting the original Cluster.

Because we are restoring into a *new* Cluster, after the restore is successful, we'll need to then go and update the application with the configuration and k8s resources of the new `Cluster`.

High level steps:
1. In k8s, delete the `ScheduledBackup` resource
2. In k8s, delete the `Cluster` resource
3. In git, update the `postgres.yaml`, changing:
  a. Cluster `metadata.name`
  b. Update `spec.bootstrap.recovery` pointing to the previous backup `ObjectStore` source
  c. ScheduledBackup `spec.cluster.name`
4. In ArgoCD, Refresh and Sync the new Cluster resource
5. Watch the Cluster resource events and wait for the restore to complete
6. Update the application with the new DB configuration
7. Delete the application pods to restart the application

## Upgrading

### Minor versions

Minor (patch) upgrades are driven by the `ClusterImageCatalog` named `postgresql-minimal-trixie` in `cnpg-system`. It is sourced from the upstream `main` branch ([`cloudnative-pg-image-catalog`](../clusters/dal-indigo-core-1/wave-2/app/templates/cloudnativepg-image-catalog.yaml)), so a new patch release published by the CNPG project reaches the cluster without any change in this repo. Each `Cluster` that uses `imageCatalogRef` then starts a rolling update: replicas first, primary last.

Because that would otherwise happen at an arbitrary time, the catalog Application is held to a nightly sync window defined on the `default` AppProject in [`wave-0/overlays/argocd/appproject-default.yaml`](../clusters/dal-indigo-core-1/wave-0/overlays/argocd/appproject-default.yaml):

* `allow`, `0 20 * * *` UTC, duration `1h` (07:00 AEDT / 06:00 AEST)
* scoped to the `cloudnativepg-image-catalog` Application only
* outside the window the Application reports `OutOfSync`; it syncs on its own when the window opens
* `manualSync: true`, so `argocd app sync cloudnativepg-image-catalog` still works at any time

Note that this only gates changes coming from the catalog. A change to `spec.resources`, to restart-requiring `postgresql.parameters`, or an operator upgrade will still roll the Clusters whenever it is applied.

### Image type and OS base

The catalog is the **`minimal`** image type on Debian **`trixie`** (13, current stable), taken from the signed `cloudnative-pg/artifacts` repo:

| Type | Approx. size (amd64) | Contents |
|---|---|---|
| `minimal` | 84 MB | PostgreSQL only |
| `standard` | 214 MB | + JIT, all locales, pgvector, pgaudit, failover slots |
| `system` | 258 MB | `standard` + in-core Barman Cloud binaries (**deprecated**) |

`minimal` is sufficient because every cluster currently uses only the `plpgsql` extension. If an application needs pgvector, pgaudit or JIT, switch to `postgresql-standard-trixie` (change the catalog resource in [the kustomization](../clusters/dal-indigo-core-1/wave-2/overlays/cloudnativepg-image-catalog/kustomization.yaml) and `spec.imageCatalogRef.name` on the affected Clusters).

This was previously `system` on Debian `bookworm` (12). `system` is deprecated now that backup runs through the Barman Cloud plugin, and bookworm passed its end-of-life on 2026-06-10, after which CNPG maintains those images on a best-effort basis only. Moving between OS bases within the same PostgreSQL major is an ordinary rolling update, no dump/restore. It is safe here because all databases use the `C` collation: a libc collation such as `en_US.utf8` can change sort order across a glibc upgrade and would require a `REINDEX`.

When changing the catalog, sync in this order, so that no `Cluster` ever references a catalog that does not exist:

1. Sync `cloudnativepg-image-catalog` while both the current and the new catalog are listed in its kustomization.
2. Sync the waves that own the `Cluster` resources (`wave-3`, `wave-5`), which updates `imageCatalogRef.name` and rolls the databases.
3. Remove the superseded catalog entry from the kustomization and sync again.



### Backup schedule

CNPG's `ScheduledBackup` has no `timeZone` field and the operator runs in UTC, so the schedules below are fixed in UTC and shift by an hour relative to local time across daylight saving. Keep the sync window clear of them — a restart or switchover during a `ScheduledBackup` aborts that backup, and the next attempt is 24 hours later.

| Time (UTC) | Job |
|---|---|
| 16:00 | `authentik-db-backup` |
| 16:05 | `emojirades-db-backup` |
| 16:10 | `forgejo-db-backup` |
| 16:15 | `matrix-db-backup` |
| 16:20 | `reactive-resume-db-backup`, `archestra-db-backup` |
| 16:25 | `tandoor-db-backup` |
| 17:00 | Longhorn `daily-default-backup` (`cluster-regular` PVCs) |
| 18:00 / 00:00 / 06:00 / 12:00 | `cnpg-failed-backup-cleaner` |
| 18:30 | descheduler |
| 20:00 | CNPG image catalog sync window |

In local time the CNPG backups run 02:00-02:25 AEST (03:00-03:25 AEDT), so a sync window placed around 03:00 local would collide with them for most of the year.

### Major versions

To upgrade to a newer version of Postgres with CNPG, the easiest way is simply to update the `spec.imageCatalogRef.major` version, this will perform an *offline* major upgrade which means:
* Cluster is shut down
* Upgrade is performed
* Cluster is turned back on

Ensure your application supports the new version of Postgres before upgrading, as rolling back isn't ideal, you will need to follow the Restoring steps above and create a new cluster using the previous backups.
