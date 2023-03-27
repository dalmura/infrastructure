# Provision dal-indigo-core-1's Control Plane

Set a few basic config vars for below
```bash
export TALOS_VERSION=v1.3.5
export CILIUM_VERSION=1.13.0
```

## Form the k8s cluster
Have kubectl and talosctl installed with their latest compatible versions

Download the `metal-rpi_generic-arm64.img.xz` artifact from the latest supported Talos release from above, and `dd` it onto the 128 GB USB Flash Drives via another machine:
```bash
# Download the latest supported release
wget "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-rpi_generic-arm64.img.xz"

# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `rpi4.4gb.arm64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.157
RPI4_2_IP=192.168.77.167
RPI4_3_IP=192.168.77.168
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
    --additional-sans 'core-1.indigo.dalmura.cloud' \
    --dns-domain 'core-1.indigo.dalmura.cloud' \
    --config-patch @patches/dal-indigo-core-1-all-init.yaml \
    --config-patch-control-plane @patches/dal-indigo-core-1-controlplane-init.yaml \
    --config-patch-worker @patches/dal-indigo-core-1-worker-init.yaml \
    --output-dir templates/dal-indigo-core-1/
```

You can also use the above to just generate new `talosconfig` files with `--output-types talosconfig`

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.3/talos-guides/network/vip/) that is advertised between all controlplane nodes in the cluster, see the [Dalmura Network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yml#L52) for assignment of this specific IP.

`--with-secrets secrets.yaml` loads our own previously generated secrets bundle, this allows for regeneration of files on other user devices

`--with-docs=false` and `--with-examples=false` just disable verbose configs, just refer to the online doco instead

`--talos-version` needs to be consistent across regeneration of files, as the config generated is minor version specific

`--with-cluster-discovery=false` because `dal-indigo-core-1` is not participating in KubeSpan there's no point enabling this

`--additional-sans` eventually the cluster will be accessed via these hostnames

`--dns-domain` internal domain all pods use, not required, but nice to have set

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

# Enter this then record HW ADDR for eth0, eg. e4:5f:01:1d:3c:a8
talosctl -n "${RPI4_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id=="eth0") | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id=="eth0") | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id=="eth0") | .spec.hardwareAddr' -r | tr -d ':'

# Repeat noting down the HW ADDR for each node from above, for example:
RPI4_1_HW_ADDR='e45f019d4ca8'
RPI4_2_HW_ADDR='e45f019d4e19'
RPI4_3_HW_ADDR='e45f019d4d95'

# Copy the configs
cp templates/dal-indigo-core-1/controlplane.yaml "nodes/dal-indigo-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"
cp templates/dal-indigo-core-1/controlplane.yaml "nodes/dal-indigo-core-1/control-plane-${RPI4_2_HW_ADDR}.yaml"
cp templates/dal-indigo-core-1/controlplane.yaml "nodes/dal-indigo-core-1/control-plane-${RPI4_3_HW_ADDR}.yaml"

# Edit and set:
# machine.network.hostname: "talos-<HW_ADDRESS>" => "talos-${RPI4_X_HW_ADDR}"
# (mac is gsed, linux is sed)
gsed -i "s/<HW_ADDRESS>/${RPI4_1_HW_ADDR}/g" "nodes/dal-indigo-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"
gsed -i "s/<HW_ADDRESS>/${RPI4_2_HW_ADDR}/g" "nodes/dal-indigo-core-1/control-plane-${RPI4_2_HW_ADDR}.yaml"
gsed -i "s/<HW_ADDRESS>/${RPI4_3_HW_ADDR}/g" "nodes/dal-indigo-core-1/control-plane-${RPI4_3_HW_ADDR}.yaml"
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
192.168.77.158: user: warning: [2023-03-06T11:00:58.84029738Z]: [talos] task labelNodeAsControlPlane (1/1): done, 1m16.097862012s
192.168.77.158: user: warning: [2023-03-06T11:00:58.85223238Z]: [talos] phase labelControlPlane (20/22): done, 1m16.118437632s
192.168.77.158: user: warning: [2023-03-06T11:00:58.86377438Z]: [talos] phase uncordon (21/22): 1 tasks(s)
192.168.77.158: user: warning: [2023-03-06T11:00:58.87140838Z]: [talos] task uncordonNode (1/1): starting

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

% export KUBERNETES_API_SERVER_ADDRESS=192.168.77.2
% export KUBERNETES_API_SERVER_PORT=6443

% helm install cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=strict \
    --set enableXTSocketFallback=false \
    --set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set=cgroup.autoMount.enabled=false \
    --set=cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost="${KUBERNETES_API_SERVER_ADDRESS}" \
    --set k8sServicePort="${KUBERNETES_API_SERVER_PORT}" \
    --set ingressController.enabled=true \
    --set ingressController.default=true \
    --set ingressController.loadbalancerMode=shared \
    --set ingressController.service.annotations.external-dns\.alpha\.kubernetes\.io/target=indigo.dalmura.cloud

# To upgrade/change the above you can
% helm upgrade cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-indigo-core-1 \
    --namespace kube-system \
    --reuse-values \
    # Provide new values below, remember to update the above too
    --set ingressController.enabled=false \

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
...
192.168.77.162: kern:    info: [2023-03-05T09:01:29.260535383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): cilium_net: link becomes ready
192.168.77.162: kern:    info: [2023-03-05T09:01:29.269130383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): cilium_host: link becomes ready
192.168.77.162: kern:    info: [2023-03-05T09:02:09.753480383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): lxc_health: link becomes ready
192.168.77.162: kern:    info: [2023-03-05T09:02:23.617665383Z]: eth0: renamed from tmp450b6
192.168.77.162: kern:    info: [2023-03-05T09:02:23.660361383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): eth0: link becomes ready
192.168.77.162: kern:    info: [2023-03-05T09:02:23.668475383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): lxce6f8cf488dfa: link becomes ready
192.168.77.162: kern:    info: [2023-03-05T09:02:24.546442383Z]: eth0: renamed from tmp69ebb
192.168.77.162: kern:    info: [2023-03-05T09:02:24.585055383Z]: IPv6: ADDRCONF(NETDEV_CHANGE): lxc27818c5af043: link becomes ready
192.168.77.162: user: warning: [2023-03-05T09:04:53.187945002Z]: [talos] task uncordonNode (1/1): done, 8m29.482576827s
192.168.77.162: user: warning: [2023-03-05T09:04:53.196419002Z]: [talos] phase uncordon (21/22): done, 8m29.498662815s
192.168.77.162: user: warning: [2023-03-05T09:04:53.204620002Z]: [talos] phase bootloader (22/22): 1 tasks(s)
192.168.77.162: user: warning: [2023-03-05T09:04:53.212291002Z]: [talos] task updateBootloader (1/1): starting
192.168.77.162: user: warning: [2023-03-05T09:04:53.269665002Z]: [talos] task updateBootloader (1/1): done, 57.382106ms
192.168.77.162: user: warning: [2023-03-05T09:04:53.277062002Z]: [talos] phase bootloader (22/22): done, 72.47031ms
192.168.77.162: user: warning: [2023-03-05T09:04:53.284080002Z]: [talos] boot sequence: done: 11m27.904096412s

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes

# And confirm coredns is Running
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace kube-system get pods
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
