# Feature Bucket List

Stuff to eventually get around to.

* Alertmanager
  * CNPG DB unhealthy/errors
  * Node Disk >90% over 5 minutes alert (via Node Exporter)
  * Node CPU >90% over 5 minutes alert (via Node Exporter)
* Validate Backup & Restore Strategy
  * Longhorn
  * CloudNativePG
  * Create example apps in wave-9 to verify
* MetalLB
  * BGP instead of L2
* Vault
  * Review OpenBao and migrate to it
* Investigate Authentik federation with other sites
  * Wait for another site to have Authentik running
* Traefik
  * Wait for cert-manager to implement: https://github.com/cert-manager/cert-manager/issues/7473
  * Cut over to Gateway API (when ListenerSets are supported and stable) instead of Ingress
* Switchboard
  * Deprecate when Gateway API is being used
