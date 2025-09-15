# Site Maintenance

Details the overall maintenance plan of the site. What actions need to be taken on what schedule.

## dal-indigo-core-1

### Every 3 Months
* Review workload updates
  * cert-manager
  * sealed-secrets
  * traefik-ingress-cluster
  * traefik-ingress-controller
* CloudNativePG
  * Review ClusterImageCatalogue updates
  * Updates will immediately trigger all clusters to reroll
* [Longhorn Storage](https://longhorn.indigo.dalmura.cloud/#/node)
  * Review Longhorn Node storage utilisation
  * Capacity management
* Rotate and reseal app credentials
  * [external-dns](clusters/dal-indigo-core-1/wave-1/overlays/external-dns/credentials.sealed.yaml)
  * [Longhorn](clusters/dal-indigo-core-1/wave-1/overlays/longhorn/aws-s3-credentials-secret.sealed.yaml)
  * [cert-manager](clusters/dal-indigo-core-1/wave-1/overlays/cert-manager/aws-route53-credentials-secret.sealed.yaml)
  * [Authentik db-backup-secret](clusters/dal-indigo-core-1/wave-3/overlays/authentik/authentik-db-backup-secret.sealed.yaml)
  * [Authentik email-secrets](clusters/dal-indigo-core-1/wave-3/overlays/authentik/authentik-email-secrets.sealed.yaml)
  * [Authentik secret-key](clusters/dal-indigo-core-1/wave-3/overlays/authentik/authentik-secret-key.sealed.yaml)

Last performed: Unknown

### Every 6 Months
* [Longhorn Engine Image](https://longhorn.indigo.dalmura.cloud/#/engineimage)
  * Each volume should upgrade automatically to the latest engine image but worth checking
* [ArgoCD ReplicatSet leftovers](https://argocd.indigo.dalmura.cloud/applications)
  * Just do a sweep of all the applications cleaning up old ReplicaSet instances
* [Frigate](https://frigate.indigo.dalmura.cloud/)
  * Review of disk usage and retention policies
* [Longhorn S3 Backups](https://longhorn.indigo.dalmura.cloud/#/backup)
  * Review S3 storage size and costing

Last performed: Unknown

### Every 12 Months
* Anubis
  * Review policies and difficulty
* Authentik
  * Review best practices

Last performed: 2025-09-15
