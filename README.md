# The Dalmura Infrastructure

Consists of a series of sites that comprimise the WAN.

This repository contains all the required configuration to bootstrap and run the infrastructure at each site.

For further information, see the:
* [Indigo site](sites/indigo/) for an example of a site running k8s


## Dependency Management

Renovate operates on this repo from [renovate.json](./renovate.json). Secrets like the github token are managed from the [indigo site folder](sites/indigo/clusters/dal-indigo-core-1/wave-4/overlays/renovate/cronjob.yaml) as the Indigo site actually runs renovate for all the sites.

In order for your site to be correctly handled, you will need to add it into the `packageRules` section.
