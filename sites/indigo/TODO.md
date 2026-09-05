# Feature Bucket List

Stuff to eventually get around to.

* Update Authentik to deny superuser login not on private IP range
  * https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/deny/
  * Must be in like 192.168.0.0/16
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
* Forgejo Runner
  * Waiting for native k8s support
  * https://codeberg.org/forgejo/discussions/issues/66
* Post-maintenance Workload Rebalancing
  * Rolling node drains leave the last upgraded node mostly empty (`kube-scheduler` doesn't rebalance running pods)
  * Solutions:
    * Deploy [Kubernetes Descheduler](https://github.com/kubernetes-sigs/descheduler) (runs periodically with `LowNodeUtilization`)
    * Run post-upgrade rolling restarts: `kubectl rollout restart deployment -A`

