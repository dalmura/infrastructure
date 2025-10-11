# Critical Bucket List

Things to implement before MVP.

* EQ14 nodes are bonded correctly
  * Figure out kernel args & switch configs

# Random Feature Bucket List

As the site approaches an MVP status just recording a list of stuff to eventually get done.

* Traefik
  * Refactor out the workloads repo and see if there's a helm chart instead?
  * Cut over to Gateway API instead of Ingress
  * Plugin version management via Renovate (custom)
  * Currently defined manually in Deployment args
* Cilium Network Policies
  * Can we isolate wave-5 onwards apps from each other/etc?
* CrowdSec integration
* ArgoCD
  * Automatic syncing for certain resource? Eg. cnpg image catalogue?
* MetalLB
  * BGP instead of L2
* cert-manager
  * Review if wildcard domain certs are better
* Longhorn
  * Validate backups & restore strategy
  * Create example app in wave-5 to verify
* Switchboard
  * Review if this can be eventually removed or not
* CloudNativePG
  * Validate backups & restore strategy
  * Create example app in wave-5 to verify
* k8s Dashboard
  * Verify if this can use Authentik proxy for auth?
  * Review https://headlamp.dev/ and see if it's worth changing
* Frigate
  * How to ensure Longhorn storage doesn't blow out?
* Renovate
  * Integrate workload repo, or deprecate and remove workload repo
  * Figure out how each site will run its own
  * Or figure out how to make it optional in wave-4 for other sites
* Authentik
  * Setup branding/etc
* Vault
  * Review OpenBao and migrate to it
