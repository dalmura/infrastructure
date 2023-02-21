# Site Information

Instructions on how to setup and run the Indigo site.

This site is one of the core sites that run services for the rest of the WAN.

At a high level the site is comprised of the following Kubernetes clusters:
* dal-indigo-core-1
  * runs applications to support the site
  * nodes are local to the site
* dal-shared-core-1
  * runs applications to support the WAN
  * nodes are distributed across the sites

We use the following [Sidero Labs](https://www.siderolabs.com/) products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes-focused distribution for the clusters
* [Omni](https://omni.siderolabs.com/) to run the cluster management/lifecycle functionality

## Configuration

* [`Site hardware`](docs/HARDWARE.md)
