# Feature Bucket List

Stuff to eventually get around to.

* Alertmanager
  * Longhorn volume >90% over 5 minutes alert
  * App Postgres DB unhealthy/errors
  * Node Disk >90% over 5 minutes alert
  * Node CPU >90% over 5 minutes alert
* CrowdSec integration
* Cilium Network Policies
  * Can we isolate wave-5 onwards apps from each other/etc by default?
* Investigate Authentik federation with other sites
  * Wait for another site to have Authentik running
* Longhorn
  * Validate backups & restore strategy
  * Create example app in wave-9 to verify
* CloudNativePG
  * Validate backups & restore strategy
  * Create example app in wave-9 to verify
* Renovate
  * Figure out how each site will run its own
  * Or figure out how to make it optional in wave-4 for other sites
* MetalLB
  * BGP instead of L2
* Vault
  * Review OpenBao and migrate to it
* Traefik
  * Wait for cert-manager to implement: https://github.com/cert-manager/cert-manager/issues/7473
  * Cut over to Gateway API instead of Ingress
* Switchboard
  * Deprecate when Gateway API is being used
