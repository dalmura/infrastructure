# Site Information

Instructions on how to setup and run the Indigo site.

This site is one of the core sites that run services for the rest of the WAN.

At a high level the site is comprised of the following Kubernetes clusters:
* dal-indigo-core-1
  * runs applications to support the site & the WAN
  * nodes are local to the site

We use the following [Sidero Labs](https://www.siderolabs.com/) products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes-focused distribution for the clusters

Cluster management/lifecycle functionality like [Omni](https://omni.siderolabs.com/) or [Sidero Metal](https://www.sidero.dev/) won't be used due to high cost and hardware incompatibilities respectively. See [archived/indigo-sidero](/sites/archived/indigo-sidero/) for an initial attempt at getting Sidero Metal working, but ultimately failing due to hardware incompatibilites.

## Cluster Composition

* [Cilium CNI](https://cilium.io/get-started/)
  * Network Policies
  * kube-proxy replacement
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
  * Deployment tool managing all other applications
* ArgoCD - Wave 0
   * [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/)
      * Ability to store secrets for all workloads in-repo
* ArgoCD - Wave 1
   * [MetalLB](https://metallb.universe.tf/)
      * Load Balancing into the Cluster itself
   * [cert-manager](https://cert-manager.io/docs/)
      * TLS Certificate management (mainly internal hosted websites)
   * [ExternalDNS](https://github.com/kubernetes-sigs/external-dns)
      * AWS Route53 record management
   * [Longhorn](https://longhorn.io/docs/latest/what-is-longhorn/)
      * PVC Storage Class
      * Replicated container volumes & block storage
      * Offsite S3 backups
* ArgoCD - Wave 2
   * [Traefik as an Ingress Controller](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
      * Ingress Controller
   * [CloudNativePG](https://cloudnative-pg.io/documentation/current/)
      * PostgreSQL Cluster Operator
   * Ingress resources for various management UI
      * Cilium
      * ArgoCD
      * Longhorn
* ArgoCD - Wave 3
   * [Keycloak](https://www.keycloak.org/)
      * OIDC Identity Provider
   * [Hashicorp Vault](https://developer.hashicorp.com/vault#what-is-vault)
      * Cluster Secrets Management

## Configuration

Here is the overall process to bringing up the k8s cluster and deploying all the required applications (via waves).

Follow this list in order:
* [`Site hardware`](docs/INDIGO-HARDWARE.md)
* [`dal-indigo-core-1` Control Plane](docs/INDIGO-CORE-1-CONTROL-PLANE.md)
* [`dal-indigo-core-1` Workers - `rpi4.8gb.arm`](docs/INDIGO-CORE-1-WORKERS-RPI4.md)
* [`dal-indigo-core-1` Workers - `eq14.16gb.amd64`](docs/INDIGO-CORE-1-WORKERS-EQ14.md)
* [`dal-indigo-core-1` Apps - ArgoCD](docs/INDIGO-CORE-1-APPS-ARGOCD.md)
* [`dal-indigo-core-1` Apps - Wave 0](docs/INDIGO-CORE-1-APPS-WAVE-0.md)
* [`dal-indigo-core-1` Apps - Wave 1](docs/INDIGO-CORE-1-APPS-WAVE-1.md)
* [`dal-indigo-core-1` Apps - Wave 2](docs/INDIGO-CORE-1-APPS-WAVE-2.md)
* [`dal-indigo-core-1` Apps - Wave 3](docs/INDIGO-CORE-1-APPS-WAVE-3.md)
* [`dal-indigo-core-1` Apps - Wave 4](docs/INDIGO-CORE-1-APPS-WAVE-4.md)
