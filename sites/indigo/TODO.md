# Critical Bucket List

Things to implement before MVP.

* Cilium Network Policies
  * Ensuring Private and Public are separated

# Random Feature Bucket List

As the site approaches an MVP status just recording a list of stuff to eventually get done.

* Traefik plugin version management via Renovate (custom)
* Cilium Network Policies
  * Can we isolate wave-5 onwards apps from each other/etc?
* CrowdSec integration
  * Replace the fail2ban middleware
* ArgoCD
  * Automatic syncing for certain resource? Eg. cnpg image catalogue?
  * Slack Notifications when something is out of sync?
* MetalLB
  * BGP instead of L2
* cert-manager
  * Review if wildcard domain certs are better
* Longhorn
  * Validate backups & restore strategy
* Switchboard
  * Review if this can be eventually removed or not
* CloudNativePG
  * Validate backups & restore strategy
* k8s Dashboard
  * Verify if this can use Authentik proxy for auth?
  * Review https://headlamp.dev/ and see if it's worth changing
* Authentik
  * Any cool branding?
* Frigate
  * How to ensure Longhorn storage doesn't blow out?
* Forgejo
  * See if SSH access is required or not, MetalLB can be used to expose TCP/22
* Renovate
  * Integrate workload repo, or deprecate and remove workload repo
  * Figure out how each site will run its own
  * Or figure out how to make it optional in wave-4 for other sites
