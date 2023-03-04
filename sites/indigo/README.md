# Site Information

Instructions on how to setup and run the Indigo site.

This site is one of the core sites that run services for the rest of the WAN.

At a high level the site is comprised of the following Kubernetes clusters:
* dal-indigo-core-1
  * runs applications to support the site & the WAN
  * nodes are local to the site

We use the following [Sidero Labs](https://www.siderolabs.com/) products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes-focused distribution for the clusters

Cluster management/lifecycle functionality like [Omni](https://omni.siderolabs.com/) or [Sidero](https://www.sidero.dev/) won't be used due to high cost and hardware incompatibilities respectively. See [archived/indigo-sidero](/sites/archived/indigo-sidero/) for an initial attempt at getting Sidero working, but ultimately failing due to hardware incompatibilites.

## Configuration

* [`Site hardware`](docs/INDIGO-HARDWARE.md)
* [`dal-indigo-core-1` Control Plane](docs/INDIGO-CORE-1-CONTROL-PLANE.md)
* [`dal-indigo-core-1` Workers](docs/INDIGO-CORE-1-WORKERS.md)
  * [`dal-indigo-core-1` Workers - OpenEBS Jiva](docs/INDIGO-CORE-1-WORKERS-JIVA.md)
