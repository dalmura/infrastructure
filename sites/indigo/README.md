# Usage

Instructions on how to setup the Indigo site.

At a high level the site is comprised of two Kubernetes clusters:
* Management Cluster (dal-k8s-mgmt-1)
  * responsible for privisioning other clusters
  * manages the hardware lifecycle of clusters
* Core Cluster (dal-k8s-core-1)
  * runs the applications to support the site

We use the following Sidero Labs products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes distribution for both clusters
* [Sidero Metal](https://www.sidero.dev/) to run the management functionality

## Instructions

* [`Site hardware`](docs/HARDWARE.md)
* [`Setup dal-k8s-mgmt-1 cluster`](docs/CLUSTER-MGMT.md)
* [`Configure dal-k8s-mgmt-1 for RPi4's`](docs/CLUSTER-MGMT-SIDERO.md)
