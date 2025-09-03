# Provision dal-indigo-core-1's `rpi4.4gb.arm` Control Plane

Set a few basic config vars for below
```bash
export TALOS_VERSION=v1.11.0
export CILIUM_VERSION=1.18.1
```

Have kubectl and talosctl installed with their latest compatible versions. Talos have a [Support Matrix](https://www.talos.dev/latest/introduction/support-matrix/) to help out here.

## Prepare image and boot nodes
Navigate to the [Talos Image Factory](https://factory.talos.dev/):
1. Select 'Single Board Computer'
2. Select the Talos Version from above
3. Select 'Raspberry Pi Series'
4. Select the following System Extensions:
   * siderolabs/iscsi-tools
   * siderolabs/util-linux-tools
5. Skip the Kernel command line or overlay options
6. Download the linked *Disk Image* `metal-arm64.raw.xz`
   6.1 The download may take some time to start as the Talos Image Factory generates the assets in the backend

Note down the following attributes:
```
SCHEMATIC_ID='f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d'

FACTORY_URL='https://factory.talos.dev/?arch=arm64&board=rpi_generic&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=sbc&version=1.11.0'

# From the `Initial Installation` section
export INSTALLER_IMAGE_URI='factory.talos.dev/metal-installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.11.0'
```

You can then `dd` it onto the SSD Drives, via the USB Adaptors, from another machine:
```bash
# Linux
sudo lsblk

# Note down the drive device path from above, eg. /dev/sdb
xz -dc metal-arm64.raw.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
sync

# Mac
# Use the Disk Utility to identify the Device name, eg. disk3

# Write the file to the SSD
xz -dc metal-arm64.raw.xz | sudo dd of=/dev/disk3 conv=fsync bs=4M status=progress

# Or just use Raspberry Pi Imager tool
# It is compatible with metal-arm64.raw.xz files
```

Boot the 3x `rpi4.4gb.arm64` nodes for the control plane, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.196
RPI4_2_IP=
RPI4_3_IP=
```

## Generate secrets and cluster configuration
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

Generate the control plane config and the initial talosctl config file:
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
    --with-kubespan=false \
    --additional-sans 'core-1.indigo.dalmura.cloud' \
    --config-patch @patches/dal-indigo-core-1-all-init.yaml \
    --config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml \
    --output-dir templates/dal-indigo-core-1/ \
    --output-types controlplane,talosconfig
```

You can also use the above to just generate new `talosconfig` files with `--output-types talosconfig` for when certificates expire. This assumes you've got the original `secrets.yaml` used to generate the original configs (they hold the CA PKI credentials).

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.9/talos-guides/network/vip/) that is advertised between all controlplane nodes in the cluster, see the [Dalmura Network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yaml#L54) for assignment of this specific IP.

`--with-secrets secrets.yaml` loads our own previously generated secrets bundle, this allows for regeneration of files on other user devices

`--with-docs=false` and `--with-examples=false` just disable verbose configs, just refer to the online doco instead

`--install-disk=''` removes the default /dev/sda entry as we use disk-selector (see config for example)

`--talos-version` needs to be consistent across regeneration of files, as the config generated is minor version specific

`--with-cluster-discovery=false` and `--with-kubespan=false` because `dal-indigo-core-1` is not participating in KubeSpan there's no point enabling this

`--additional-sans` eventually the cluster will be accessed via these hostnames

`--config-patch @patches/dal-indigo-core-1-all-init.yaml` contains:
* General node labels for this site
* Configures the default network interface with dhcp

`--config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml` contains:
* Configures the VIPs on all interfaces and configures VLANs

`--output-dir templates/dal-indigo-core-1/` writes the outputs into the templates file, these cannot be directly applied and must be rendered first (see below)

`--output-types controlplane,talosconfig` don't write the workers out yet as we will write per-worker-class configs later

The above will output a generic `controlplane.yaml` config file along with a `talosconfig` file we can use to authenticate to the Talos API on the cluster (once it's bootstrapped).

Configure each control plane nodes config file:
```bash
mkdir -p nodes/dal-indigo-core-1/

# Since Talos now uses predictable network interfaces, for rpi's this means all ethernet interfaces are named like `enx<HW_MAC_ADDR>` eg. a MAC address of `e4:5f:01:9d:4d:95` results in `enxe45f019d4d95`

# Use these commands to discover the interface names and mac addresses
talosctl -n "${RPI4_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id == "end0") | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id == "end0") | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id == "end0") | .spec.hardwareAddr' -r | tr -d ':'

# Note down the HW ADDR for each node from above, for example:
RPI4_1_HW_ADDR='e45f019d4e19'
RPI4_2_HW_ADDR=''
RPI4_3_HW_ADDR=''

# Create the per-device Control Plane configs with these overrides
cat templates/dal-indigo-core-1/controlplane.yaml | sed "s/<HW_ADDRESS>/${RPI4_1_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/controlplane.yaml | sed "s/<HW_ADDRESS>/${RPI4_2_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_2_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/controlplane.yaml | sed "s/<HW_ADDRESS>/${RPI4_3_HW_ADDR}/g" > "nodes/dal-indigo-core-1/control-plane-${RPI4_3_HW_ADDR}.yaml"
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
# We should see the server version printed as well, matching the Talos version you selected when generating the image at the factory website
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig version

# Look at the logs and see the progress
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow

# Wait until you see something like
192.168.77.20: user: warning: [2022-12-11T04:27:28.724547918Z]: [talos] task startAllServices (1/1): service "etcd" to be "up", service "kubelet" to be "up"

# This tells us we're waiting for "etcd" to come online
# Bootstrap the etcd cluster
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig bootstrap

# Wait for the cluster to settle down
# It will just keep repeating the same similar messages
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow

# Verify you can ping the floating Virtual IP (VIP)
# This assumes you're on a network segment that can do this!
ping 192.168.77.2
```

The node (aka cluster) should be in a state where it's now waiting for the CNI to be installed!

We can verify this by connecting to the k8s API and checking the Node status:
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
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

# To upgrade/change the above you can
% helm repo update
% helm upgrade cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    --reuse-values \
    # Provide new values below, remember to update the above too
    # And remove this comment when running
    # For example, let's remove the ingressController
    --set ingressController.enabled=false

# If you get errors about 'nil pointer evaluating interface {}.foo'
# This is because new required default values are required
# You'll need to not provide --reuse-values
# and instead copy them all from the install section

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    rollout restart deployment/cilium-operator
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    rollout restart ds/cilium

# Check the progress of the CNI install
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n kube-system get pods
NAMESPACE     NAME                                         READY   STATUS     RESTARTS       AGE
kube-system   cilium-d4wbv                                 0/1     Init:0/5   0              54s
kube-system   cilium-operator-5c6c66956-q2wm8              1/1     Running    0              54s
kube-system   cilium-operator-5c6c66956-vmzr5              0/1     Pending    0              54s

# Wait until these become Ready

# You should then see the following (might take a minute, be patient)
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
```
...
192.168.77.150: user: warning: [2024-03-03T00:46:36.779201095Z]: [talos] machine is running and ready {"component": "controller-runtime", "controller": "runtime.MachineStatusController"}
...

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes

# Wait until coredns pods status goes to Running
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace kube-system get pods
```

If it's still just a single node/CP only you will need to edit the `hubble-relay` and `hubble-ui` Deployments and set in `spec.template.spec`:
```yaml
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane

```

This will allow the hubble UI and Relay's to run on the CP nodes.

A *better* way would also be to remove the NoSchedule control-plane taint:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 taint nodes "talos-${RPI4_1_HW_ADDR}" node-role.kubernetes.io/control-plane:NoSchedule-
```

But ideally you just wait and let it report a few errors until you onboard some worker nodes run Hubble Relay & Hubble UI

## Install Cilium CLI

See the [doco here](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) and follow the steps to install.

Verify Cilium is running:
```bash
export KUBECONFIG='kubeconfigs/dal-indigo-core-1'

# Report on the setup status
cilium status

# If you're proceeding with 1x Control Plane node without removing the taint/etc
# Expect the Operator to be 1/2, and the Relay and Hubble to be unavailable

# Open Hubble and verify
# Assuming you've got it running on the current node(s) setup
# Or just check later once it's available
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

You now have a k8s cluster with just Control Plane nodes running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN

Before deploying any workloads you will need to deploy one or more Worker nodes:
* [Raspberry Pi 4 nodes aka `rpi4.8gb.arm`](INDIGO-CORE-1-WORKERS-RPI4.md)
* [Beelink EQ14 nodes aka `eq14.16gb.amd64`](INDIGO-CORE-1-WORKERS-EQ14.md)
