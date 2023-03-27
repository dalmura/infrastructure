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
  * Built-in Ingress Controller
* [OpenEBS Jiva](https://openebs.io/docs/concepts/jiva)
  * Replicated container volumes
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
  * Deployment tool managing all other applications
* [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/)
  * Ability to store secrets for all workloads in-repo
* [MetalLB](https://metallb.universe.tf/)
  * Load Balancing into the Cluster itself
* [cert-manager](https://cert-manager.io/docs/)
  * TLS Certificate management (mainly internal hosted websites)
* [ExternalDNS](https://github.com/kubernetes-sigs/external-dns)
  * AWS Route53 record management

## Configuration

* [`Site hardware`](docs/INDIGO-HARDWARE.md)
* [`dal-indigo-core-1` Control Plane](docs/INDIGO-CORE-1-CONTROL-PLANE.md)
* [`dal-indigo-core-1` Workers](docs/INDIGO-CORE-1-WORKERS.md)
  * [`dal-indigo-core-1` Workers - OpenEBS Jiva](docs/INDIGO-CORE-1-WORKERS-JIVA.md)
  * [`dal-indigo-core-1` Workers - ArgoCD](docs/INDIGO-CORE-1-WORKERS-ARGOCD.md)
* [`dal-indigo-core-1` Apps - Phase 0 - Secrets](docs/INDIGO-CORE-1-APPS-PHASE-0.md)
* [`dal-indigo-core-1` Apps - Phase 1 - Common](docs/INDIGO-CORE-1-APPS-PHASE-1.md)
* [`dal-indigo-core-1` Apps - Phase 2 - Ingress](docs/INDIGO-CORE-1-APPS-PHASE-2.md)
