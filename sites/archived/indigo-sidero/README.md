# Site Information

Instructions on how to setup and run the Indigo site.

This site is one of the core sites that run services for the rest of the WAN.

At a high level the site is comprised of two Kubernetes clusters:
* Management Cluster (dal-k8s-mgmt-1)
  * responsible for privisioning other clusters
  * manages the hardware lifecycle of clusters and their nodes
* Core Cluster (dal-k8s-core-1)
  * runs applications to support the site and the WAN

We use the following [Sidero Labs](https://www.siderolabs.com/) products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes-focused distribution for the clusters
* [Sidero Metal](https://www.sidero.dev/) to run the cluster management/lifecycle functionality

## Configuration

* [`Site hardware`](docs/HARDWARE.md)
* [`Setup dal-k8s-mgmt-1 cluster`](docs/CLUSTER-MGMT-BOOTSTRAP.md)
* [`Configure dal-k8s-mgmt-1 with MetalLB`](docs/CLUSTER-MGMT-METALLB.md)
* [`Configure dal-k8s-mgmt-1 for RPi4's`](docs/CLUSTER-MGMT-SIDERO.md)
* [`Configure dal-k8s-mgmt-1 Sidero`](docs/CLUSTER-MGMT-SIDERO-CONFIGURE.md)
* [`Setup dal-k8s-core-1`](docs/CLUSTER-CORE-BOOTSTRAP.md)
