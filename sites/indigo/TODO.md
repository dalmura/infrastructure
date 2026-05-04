# Feature Bucket List

Stuff to eventually get around to.

* Cilium Network Policies
  * Keep going and isolate all waves/apps/etc
  * Eg. Web UIs should only interact via Traefik
* Reloader
  * Look into what Cert/Config => Deployment relationships we have
  * Work to wire them up and be redeployed on change
* Alertmanager
  * CNPG DB unhealthy/errors
  * Node Disk >90% over 5 minutes alert (via Node Exporter)
  * Node CPU >90% over 5 minutes alert (via Node Exporter)
* CrowdSec integration
* Investigate Authentik federation with other sites
  * Wait for another site to have Authentik running
* Validate Backup & Restore Strategy
  * Longhorn
  * CloudNativePG
  * Create example apps in wave-9 to verify
* MetalLB
  * BGP instead of L2
* Vault
  * Review OpenBao and migrate to it
* Traefik
  * Wait for cert-manager to implement: https://github.com/cert-manager/cert-manager/issues/7473
  * Cut over to Gateway API (when ListenerSets are supported and stable) instead of Ingress
* Switchboard
  * Deprecate when Gateway API is being used
