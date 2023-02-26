# Provision dal-indigo-core-1's Control Plane

## Form the k8s cluster
Have kubectl and talosctl installed with their latest compatible versions

Download the `metal-rpi_generic-arm64.img.xz` artifact from the latest supported Talos release from above, and `dd` it onto the 128 GB USB Flash Drives via another machine:
```bash
# Download the latest supported release
wget https://github.com/siderolabs/talos/releases/download/v1.3.5/metal-rpi_generic-arm64.img.xz

# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Set a few basic config vars for below
```bash
export TALOS_VERSION=v1.3.5
```

Boot the 3x `rpi4.4gb.arm64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.150
RPI4_2_IP=192.168.77.151
RPI4_3_IP=192.168.77.152
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
    --talos-version "${TALOS_VERSION}" \
    --with-cluster-discovery=false \
    --additional-sans 'indigo.dalmura.cloud' \
    --config-patch @patches/dal-indigo-core-1-all-init.yaml \
    --config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml \
    --config-patch-worker @patches/dal-indigo-core-1-worker-init.yaml \
    --output-dir templates/dal-indigo-core-1/
```

You can also use the above to just generate new `talosconfig` files with `--output-types talosconfig`

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.3/talos-guides/network/vip/) that is advertised between all controlplane nodes in the cluster, see the [Dalmura Network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yml#L52) for assignment of this specific IP.

`--from-secrets secrets.yaml` loads our own previously generated secrets bundle, this allows for regeneration of files on other user devices

`--talos-version` needs to be consistent across regeneration of files, as the config generated is minor version specific

`--with-cluster-discovery false` because `dal-indigo-core-1` is not participating in KubeSpan there's no point enabling this

`--additional-sans` eventually the cluster will be accessed via these hostnames

`--config-patch @patches/dal-indigo-core-1-all-init.yaml` contains:
* General node labels for this site
* Configures the network including VLANs & routes

`--config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml` contains:
* Configures the VIPs on all interfaces

`--config-patch-worker @patches/dal-indigo-core-1-worker-init.yaml` contains:
* Configures further node labels for node groups

The above will output general `controlplane.yaml` and `worker.yaml` config files. Fortunately `controlplane.yaml` doesn't need any further customisation and can be applied directly, but `worker.yaml` will need to be specialised for each node group, we will do that later though.

Now we will provision a single node and bootstrap it to form a cluster, after that we will add the other two Control Plane nodes.

Apply the config for the first node:
```bash
talosctl apply-config --insecure -n "${RPI4_1_IP}" -f templates/dal-indigo-core-1/controlplane.yaml
```

Update your local device with the new credentials to talk to the cluster:
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config endpoints "${RPI4_1_IP}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config nodes "${RPI4_1_IP}"
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
192.168.77.20: user: warning: [2022-11-19T01:39:08.487418318Z]: [talos] phase labelControlPlane (17/19): done, 1m43.004679272s
192.168.77.20: user: warning: [2022-11-19T01:39:08.497915318Z]: [talos] phase uncordon (18/19): 1 tasks(s)
192.168.77.20: user: warning: [2022-11-19T01:40:11.102102078Z]: [talos] task uncordonNode (1/1): done, 1m2.212281572s
192.168.77.20: user: warning: [2022-11-19T01:40:11.110591078Z]: [talos] phase uncordon (18/19): done, 1m2.228608374s
192.168.77.20: user: warning: [2022-11-19T01:40:11.118872078Z]: [talos] phase bootloader (19/19): 1 tasks(s)
192.168.77.20: user: warning: [2022-11-19T01:40:11.126706078Z]: [talos] task updateBootloader (1/1): starting
192.168.77.20: user: warning: [2022-11-19T01:40:11.187985078Z]: [talos] task updateBootloader (1/1): done, 61.278313ms
192.168.77.20: user: warning: [2022-11-19T01:40:11.195462078Z]: [talos] phase bootloader (19/19): done, 76.612441ms
192.168.77.20: user: warning: [2022-11-19T01:40:11.202824078Z]: [talos] boot sequence: done: 4m26.855228102s

# Verify you can ping the floating Virtual IP (VIP)
ping 192.168.77.2
```

Verify the node is Ready and we can onboard new nodes:
```bash
mkdir kubeconfigs

# Extract the creds to talk via kubectl
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig kubeconfig kubeconfigs/dal-indigo-core-1

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes

# The node's status should become Ready when you see a bunch of `cni0` related logs appear after the above
```

Now we onboard the other nodes into the cluster:
```bash
talosctl apply-config --insecure -n "${RPI4_2_IP}" -f templates/dal-indigo-core-1/controlplane.yaml
talosctl apply-config --insecure -n "${RPI4_3_IP}" -f templates/dal-indigo-core-1/controlplane.yaml

talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config endpoints "${RPI4_1_IP}" "${RPI4_2_IP}" "${RPI4_3_IP}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig config nodes "${RPI4_1_IP}" "${RPI4_2_IP}" "${RPI4_3_IP}"
```

Wait until all nodes become `Ready`:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes
```

You now have a basic k8s cluster running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
