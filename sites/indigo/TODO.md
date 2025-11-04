# Critical Bucket List

Things to implement before MVP.

* EQ14 nodes are bonded correctly
  * Figure out kernel args & switch configs

# Random Feature Bucket List

As the site approaches an MVP status just recording a list of stuff to eventually get done.

* Traefik
  * Cut over to Gateway API instead of Ingress
* Switchboard
  * Deprecate when Gateway API is being used
* Frigate
  * How to ensure Longhorn storage doesn't blow out?
* Cilium Network Policies
  * Can we isolate wave-5 onwards apps from each other/etc?
* CrowdSec integration
* cert-manager
  * Review if wildcard domain certs are better
* Longhorn
  * Validate backups & restore strategy
  * Create example app in wave-5 to verify
* CloudNativePG
  * Validate backups & restore strategy
  * Create example app in wave-5 to verify
* Renovate
  * Figure out how each site will run its own
  * Or figure out how to make it optional in wave-4 for other sites
* k8s Dashboard
  * Verify if this can use Authentik proxy for auth?
  * Review https://headlamp.dev/ and see if it's worth changing
* Authentik
  * Setup branding/etc
* Vault
  * Review OpenBao and migrate to it
* MetalLB
  * BGP instead of L2
