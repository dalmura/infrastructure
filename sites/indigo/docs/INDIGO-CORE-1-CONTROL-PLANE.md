# Provision dal-indigo-core-1's Control Plane

Set a few basic config vars for below
```bash
export TALOS_VERSION=v1.6.5
export CILIUM_VERSION=1.15.1
```

## Form the k8s cluster
Have kubectl and talosctl installed with their latest compatible versions.

Navigate to the [Talos Image Factory](https://factory.talos.dev/) and build the following image:
1. Select the Talos Version from above
2. Select the following System Extensions
   * siderolabs/iscsi-tools
   * siderolabs/util-linux-tools
3. Provide the extra kernel command line argument: `todo`
4. Download the `metal-rpi_generic-arm64.raw.xz` by copying one of the asset links and changing the asset name (filename in the URL) to the one mentioned here
   4.1 The download may take some time to start as the Talos Image Factory generates the assets on the backend

You can then `dd` it onto the 128 GB USB Flash Drives via another machine:
```bash
# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `rpi4.4gb.arm64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.150
RPI4_2_IP=192.168.77.253
RPI4_3_IP=192.168.77.254
```

Generate the cluster `secrets.yaml` we'll need to durably and securely store long term:
```bash
talosctl gen secrets \
  --output-file secrets.yaml \
  --talos-version "${TALOS_VERSION}"
```

TODO: Steps to encrypt secrets.yaml with the GPG key
```bash
gpg --output secrets.yaml.gpg \
    --recipient 'network.public.key.alias' \
    --encrypt secrets.yaml
```

TODO: Steps to decrypt a previously encrypted secrets.yaml
```bash
gpg --output secrets.yaml \
    --decrypt secrets.yaml.gpg
```

Generate a config to bootstrap k8s on that node:
```bash
talosctl gen config \
    dal-indigo-core-1 \
    'https://192.168.77.2:6443/' \
    --with-secrets secrets.yaml \
    --with-docs=false \
    --with-examples=false \
    --install-disk='' \
    --talos-version "${TALOS_VERSION}" \
    --with-cluster-discovery=false \
    --additional-sans 'core-1.indigo.dalmura.cloud' \
    --config-patch @patches/dal-indigo-core-1-all-init.yaml \
    --config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml \
    --config-patch-worker @patches/dal-indigo-core-1-worker-init.yaml \
    --output-dir templates/dal-indigo-core-1/
```

You can also use the above to just generate new `talosconfig` files with `--output-types talosconfig` for when certificates expire.

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.3/talos-guides/network/vip/) that is advertised between all controlplane nodes in the cluster, see the [Dalmura Network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yaml#L54) for assignment of this specific IP.

`--with-secrets secrets.yaml` loads our own previously generated secrets bundle, this allows for regeneration of files on other user devices

`--with-docs=false` and `--with-examples=false` just disable verbose configs, just refer to the online doco instead

`--install-disk=''` removes the default /dev/sda entry as we use disk-selector (see config for example)

`--talos-version` needs to be consistent across regeneration of files, as the config generated is minor version specific

`--with-cluster-discovery=false` because `dal-indigo-core-1` is not participating in KubeSpan there's no point enabling this

`--additional-sans` eventually the cluster will be accessed via these hostnames

`--config-patch @patches/dal-indigo-core-1-all-init.yaml` contains:
* General node labels for this site
* Configures the default network interface with dhcp

`--config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml` contains:
* Configures the VIPs on all interfaces and configures VLANs

`--config-patch-worker @patches/dal-indigo-core-1-worker-init.yaml` contains:
* Configures further node labels for node groups and configures VLANs

The above will output generic `controlplane.yaml` and `worker.yaml` config files. Unfortunately these are both unable to be directly applied, we need to specialise each of these for each node (as we have unique node hostnames). We'll do the `controlplane.yaml` and `worker.yaml` later on.

Configure each nodes config file:
```bash
mkdir -p nodes/dal-indigo-core-1/

# Since Talos now uses predictable network interfaces, for rpi's this means all ethernet interfaces are named like `enx<HW_MAC_ADDR>` eg. a MAC address of `e4:5f:01:1d:3c:a8` results in `enxe45f019d4d95`

# Use these commands to discover the interface names and mac addresses
talosctl -n "${RPI4_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'

# Repeat noting down the HW ADDR for each node from above, for example:
RPI4_1_HW_ADDR='e45f019d4d95'
RPI4_2_HW_ADDR='e45f019d4e95'
RPI4_3_HW_ADDR='e45f019d4ca8'

# Create the per-device Control Plane configs with these overrides
cat templates/dal-indigo-core-1/controlplane.yaml | gsed "s/<HW_ADDRESS>/${RPI4_1_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/controlplane.yaml | gsed "s/<HW_ADDRESS>/${RPI4_2_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_2_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/controlplane.yaml | gsed "s/<HW_ADDRESS>/${RPI4_3_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_3_HW_ADDR}.yaml"
```

Now we will provision a single node and bootstrap it to form a cluster, after that we will add the other two Control Plane nodes.

Apply the config for the first node:
```bash
talosctl apply-config --insecure -n "${RPI4_1_IP}" -f "nodes/dal-indigo-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"
```

Update your local device with the new credentials to talk to the cluster:
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config endpoints "${RPI4_1_IP}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config nodes "${RPI4_1_IP}"
# From now on our talosctl commands just talk to RPI4_1_IP only
```

First we verify if the Talos API is running on the node:
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig version

# Look at the logs
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow

# Wait until you see something like
192.168.77.20: user: warning: [2022-12-11T04:27:28.724547918Z]: [talos] task startAllServices (1/1): service "etcd" to be "up", service "kubelet" to be "up"

# This tells us we're waiting for "etcd" to come online
# Bootstrap the etcd cluster
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig bootstrap

# Wait for the cluster to settle down
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow

# Keep an eye until you see the following logs fly past:
192.168.77.150: user: warning: [2024-03-03T01:03:59.13141591Z]: [talos] created /v1/ConfigMap/coredns {"component": "controller-runtime", "controller": "k8s.ManifestApplyController"}
192.168.77.150: user: warning: [2024-03-03T01:03:59.58673191Z]: [talos] created apps/v1/Deployment/coredns {"component": "controller-runtime", "controller": "k8s.ManifestApplyController"}
192.168.77.150: user: warning: [2024-03-03T01:03:59.97196491Z]: [talos] created /v1/Service/kube-dns {"component": "controller-runtime", "controller": "k8s.ManifestApplyController"}
192.168.77.150: user: warning: [2024-03-03T01:04:00.33167191Z]: [talos] created /v1/ConfigMap/kubeconfig-in-cluster {"component": "controller-runtime", "controller": "k8s.ManifestApplyController"}

# Verify you can ping the floating Virtual IP (VIP)
# This assumes you're on a network segment that can do this!
ping 192.168.77.2
```

Verify the node is Ready and we can onboard new nodes:
```bash
mkdir kubeconfigs

# Extract the creds to talk via kubectl
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig kubeconfig kubeconfigs/dal-indigo-core-1

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes

# This will be NotReady until we apply the CNI
```

## Setup Cilium CNI
```bash
% helm repo add cilium https://helm.cilium.io/
% helm repo update

% export KUBERNETES_API_SERVER_ADDRESS=localhost
% export KUBERNETES_API_SERVER_PORT=7445
# localhost & 7445 is for KubePrism
# 192.168.77.2 & 6443 is for the external VIP endpoint

% helm install \
    cilium \
    cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set=cgroup.autoMount.enabled=false \
    --set=cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost="${KUBERNETES_API_SERVER_ADDRESS}" \
    --set k8sServicePort="${KUBERNETES_API_SERVER_PORT}" \
    --set ingressController.enabled=true \
    --set ingressController.loadbalancerMode=dedicated \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

# To upgrade/change the above you can
% helm upgrade cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    --reuse-values \
    # Provide new values below, remember to update the above too
    # And remove this comment when running
    --set ingressController.enabled=false

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    rollout restart deployment/cilium-operator
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    rollout restart ds/cilium

# Check the progress of the CNI install
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -A
NAMESPACE     NAME                                         READY   STATUS     RESTARTS       AGE
kube-system   cilium-d4wbv                                 0/1     Init:0/5   0              54s
kube-system   cilium-operator-5c6c66956-q2wm8              1/1     Running    0              54s
kube-system   cilium-operator-5c6c66956-vmzr5              0/1     Pending    0              54s

# Wait until these become Ready

# You should then see the following
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
```
...
192.168.77.150: user: warning: [2024-03-03T00:46:36.779201095Z]: [talos] machine is running and ready {"component": "controller-runtime", "controller": "runtime.MachineStatusController"}
...

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes

# And confirm coredns is Running
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace kube-system get pods
```

If it's still just a single node/CP only you will need to edit the `hubble-relay` and `hubble-ui` Deployments and set in `spec.template.spec`:
```yaml
tolerations:
  - effect: NoSchedule
  key: node-role.kubernetes.io/control-plane

```

This will allow the hubble UI and Relay's to run on the CP nodes.


## Install Cilium CLI

See the [doco here](https://docs.cilium.io/en/v1.15/gettingstarted/k8s-install-default/#install-the-cilium-cli) and follow the steps to install.

Verify Cilium is running:
```bash
export KUBECONFIG='kubeconfigs/dal-indigo-core-1'

# Report on the setup status
cilium status --wait

# Open Hubble and verify
cilium hubble ui
```

## Onboard the other Control Plane nodes
```bash
talosctl apply-config --insecure -n "${RPI4_2_IP}" -f nodes/dal-indigo-core-1/control-plane-${RPI4_2_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${RPI4_3_IP}" -f nodes/dal-indigo-core-1/control-plane-${RPI4_3_HW_ADDR}.yaml

talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config endpoints "${RPI4_1_IP}" "${RPI4_2_IP}" "${RPI4_3_IP}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config nodes "${RPI4_1_IP}" "${RPI4_2_IP}" "${RPI4_3_IP}"
# From now on our talosctl commands can talk to all 3x RPI4_(1|2|3)_IP nodes
```

Wait until all nodes become `Ready`:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes
```

You now have a basic k8s cluster running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
