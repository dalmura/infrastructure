# Setting up MetalLB on dal-k8s-mgmt-1

MetalLB is a Layer 2 ARP based Load Balancer that we'll use to offer Sidero (and any other) services from within the cluster to the wider network.

MetalLB supports a number of installation methods, but given this process is before most of our normal deployment tooling is ready, we'll stick with Helm for now.

Following https://metallb.universe.tf/installation/#installation-with-helm

```bash
% helm --kubeconfig kubeconfigs/dal-k8s-mgmt-1 version
version.BuildInfo{Version:"v3.11.0", GitCommit:"472c5736ab01133de504a826bd9ee12cbe4e7904", GitTreeState:"clean", GoVersion:"go1.19.5"}

# If you've not added before
% helm --kubeconfig kubeconfigs/dal-k8s-mgmt-1 repo add metallb https://metallb.github.io/metallb
"metallb" has been added to your repositories

# Alternatively if you've added a while ago
% helm --kubeconfig kubeconfigs/dal-k8s-mgmt-1 repo update

# Create the namespace with our extra PodSecurity labels
# Helm can do this automatically but we need a few custom labels, so do this separately
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f patches/dal-k8s-mgmt-1-metallb-namespace.yaml
namespace/metallb-system created

% helm --kubeconfig kubeconfigs/dal-k8s-mgmt-1 --namespace metallb-system install metallb metallb/metallb
NAME: metallb
LAST DEPLOYED: Sun Dec 18 14:13:43 2022
NAMESPACE: metallb-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
MetalLB is now running in the cluster.

Now you can configure it via its CRs. Please refer to the metallb official docs
on how to use the CRs.

# Should take about 30s to get into a Running state
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -n metallb-system
NAME                                  READY   STATUS    RESTARTS   AGE
metallb-controller-5b89f7554c-4tqnl   1/1     Running   0          56s
metallb-speaker-wjt8s                 1/1     Running   0          56s
```

MetalLB is now running in the cluster under our new `metallb-system` namespace!

We need to now 'configure' MetalLB by creating a few new resources in k8s for our:
* IP Range(s) that MetalLB will offer from
* L2Advertisement(s) that MetalLB will listen on

We configure these for the 2x VLANs that this cluster listens on: `SERVERS` and `SERVERS_STAGING`

```bash
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f patches/dal-k8s-mgmt-1-metallb-config.yaml
ipaddresspool.metallb.io/servers-vlan created
l2advertisement.metallb.io/servers-vlan created
ipaddresspool.metallb.io/servers-staging-vlan created
l2advertisement.metallb.io/servers-staging-vlan created
```

If you get any errors like:
```
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f patches/dal-k8s-mgmt-1-metallb-config.yaml
Error from server (InternalError): error when creating "patches/dal-k8s-mgmt-1-metallb-config.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.110.207.211:443: connect: connection refused
....
```

Then the admission webhook is still being setup, so just give it another minute or two until it starts working.

And now when a Service of `type: LoadBalancer` inside the k8s cluster is created, MetalLB will listen and forward traffic to this service!
