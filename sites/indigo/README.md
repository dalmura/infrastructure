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

Omni now supports a [self hosted non-production deployment](https://docs.siderolabs.com/omni/infrastructure-and-extensions/self-hosted/overview), so at some point that will be investigated and possibly used.

## Cluster Composition

* [Cilium CNI](https://cilium.io/get-started/)
  * Network Policies
  * kube-proxy replacement
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
  * Deployment tool managing all other applications
* ArgoCD - Wave 0
   * [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/)
      * Ability to store secrets for all workloads in-repo
   * [Cilium](https://cilium.io/get-started/)
      * Management of above Cilium deployment within ArgoCD
   * [Reloader](https://github.com/stakater/Reloader)
      * Reload Deployments when a Secret/ConfigMap changes
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
      * Fail2ban Middleware
      * Geoblock Middleware
      * Anubis Middleware
   * [Anubis](https://anubis.techaro.lol/)
      * Slow down scrapers/crawlers
   * [Switchboard](https://github.com/borchero/switchboard/)
      * Integrates `cert-manager` and `ExternalDNS` with Traefik's `IngressRoute`
   * [CloudNativePG](https://cloudnative-pg.io/documentation/current/)
      * PostgreSQL Cluster Operator
   * [k8s Dashboard](https://github.com/kubernetes/dashboard)
      * Kuberetes Overview UI
   * `Ingress`/`IngressRoute` resources for various management UI
      * ArgoCD w/CLI support
      * Cilium
      * Longhorn
* ArgoCD - Wave 3
   * [Authentik](https://goauthentik.io/)
      * OIDC Identity Provider
      * w/CNPG PostgreSQL DB
   * [Hashicorp Vault](https://developer.hashicorp.com/vault#what-is-vault)
      * Cluster Secrets Management
   * [External Secrets Operator](https://external-secrets.io/latest/)
      * Syncronise Vault secrets with k8s secrets
* ArgoCD - Wave 4
   * [Renovate](https://docs.renovatebot.com/)
      * Automated Dependency Management
   * [VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/)
      * Lightweight Prometheus replacement
      * Scrapes metrics from the cluster
   * [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
      * Lightweight Loki replacement
      * Scrapes container logs from the cluster via the Collector
   * Not Implemented Yet
      * [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
         * Client alerting
         * Pushed to from VictoriaMetrics based alert rules
      * [Grafana](https://grafana.com/docs/grafana/latest/)
         * Dashboards for above Metrics & Logs
* ArgoCD - Wave 5
   * [Frigate](https://github.com/blakeblackshear/frigate)
      * Home security camera NVR w/object detection
   * [Plex](https://hub.docker.com/r/linuxserver/plex)
      * Media Playback
   * [Forgejo](https://forgejo.org/)
      * Git server
   * [Emojirades](https://emojirades.io/)
      * Emoji based guessing game
   * Not Implemented Yet
      * [Reactive Resume](https://rxresu.me/)
         * Resume builder
      * [Tandoor](https://tandoor.dev/)
         * Recipe management
      * [Github Runner](https://github.com/actions/actions-runner-controller)
         * Github Actions runner management
      * [Bookstack](https://www.bookstackapp.com/)
         * Wiki Knowledge Base
      * [Home Assistant](https://www.home-assistant.io/)
         * Home Automation
      * [Matrix Comms](https://matrix.org/)
         * Chat/comms
      * [PeerTube](https://joinpeertube.org/)
         * Videos

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
   * [`dal-indigo-core-1` Apps - Wave 3 - Authentik](docs/INDIGO-CORE-1-APPS-WAVE-3-AUTHENTIK.md)
   * [`dal-indigo-core-1` Apps - Wave 3 - Vault](docs/INDIGO-CORE-1-APPS-WAVE-3-VAULT.md)
   * [`dal-indigo-core-1` Apps - Wave 3 - Dynamic AWS Users](docs/INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md)
* [`dal-indigo-core-1` Apps - Wave 4](docs/INDIGO-CORE-1-APPS-WAVE-4.md)
* [`dal-indigo-core-1` Apps - Wave 5](docs/INDIGO-CORE-1-APPS-WAVE-5.md)

## Ongoing Maintenance

Review [MAINTENANCE.md](MAINTENANCE.md) for maintenance schedule.

## Kernel Modules

If you need to support a new piece of hardware via an out-of-tree kernel module. Talos Linux requires a bit of a song and dance to build and use a new kernel module.

This process has been [documented here](docs/INDIGO-TALOS-KERNEL-MODULE.md).

Word of warning, it's complicated, there's a lot of moving parts, and to get your module to land in Talos Linux will require PRs and time. If you don't want to wait, the documentation covers building custom images as well to test with, but there's nothing stopping you maintaining your own 'fork' of Talos Linux to use in the mean time.
