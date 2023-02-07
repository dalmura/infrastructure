# Provision dal-k8s-mgmt-1

## Form the k8s cluster
Have kubectl, clusterctl and talosctl installed:
  * As of the time of writing (2023-02-05) this is
  * kubernetes v1.26
  * clusterapi v1.3
  * talos v1.3

Double check the [compatibility of Sidero and Talos](https://github.com/siderolabs/sidero#compatibility-with-cluster-api-and-kubernetes-versions) and ensure you choose the [latest Sidero](https://github.com/siderolabs/sidero/releases/latest) and the [latest supported Talos](https://github.com/siderolabs/talos/releases). At the time of writing Sidero v0.5 supports Talos v1.3.

Download the `metal-rpi_generic-arm64.img.xz` artifact from the latest supported Talos release from above, and `dd` it onto the SSD's via another machine:
```bash
# Download the latest supported release
wget https://github.com/siderolabs/talos/releases/download/v1.3.3/metal-rpi_generic-arm64.img.xz

# Linux, SSD is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x rpi4.4gb.arm64 nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.150
RPI4_2_IP=192.168.77.151
RPI4_3_IP=192.168.77.152
```

Generate a config to bootstrap k8s on that node:
```bash
talosctl gen config \
    dal-k8s-mgmt-1 \
    https://192.168.77.2:6443/ \
    --config-patch-control-plane @patches/dal-k8s-mgmt-1-controlplane.yaml \
    --output-types controlplane,talosconfig \
    --output-dir templates/dal-k8s-mgmt-1/
```

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.3/talos-guides/network/vip/) that is advertised between all controlplane nodes in the cluster, see the [Dalmura Network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yml#L52) for assignment of this specific IP.

`patches/dal-k8s-mgmt-1-controlplane.yaml` contains the following tweaks:
* Allow scheduling regular pods on Control Plane nodes
* Configures the networking to move the node into the static ranges (off DHCP)

`--output-types controlplane,talosconfig` skips generating a worker config as this cluster is control plane only!

You will now need to 'hydrate' these files to be per-server:
```bash
mkdir nodes
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-cp-1.yaml
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-cp-2.yaml
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-cp-3.yaml
```

Get the MAC Address of eth0:
```bash
# YAML
talosctl get links --insecure --nodes 192.168.77.150 --output yaml | yq 'select(.metadata.id == "eth0").spec.hardwareAddr'
e4:5f:01:9d:4d:95

# JSON
talosctl get links --insecure --nodes 192.168.77.150 --output json | jq -r 'select(.metadata.id == "eth0").spec.hardwareAddr'
e4:5f:01:9d:4d:95

# The above would translate into the following device selector:
machine:
  network:
    interfaces:
      - deviceSelector:
          hardwareAddr: e4:5f:01:9d:4d:95
          driver: bcmgenet  # <- rpi specific
```

Within each file you will need to make the following changes:
* Replace `NODE_INTERFACE_MAC` with this nodes eth0 MAC address (ensure it's lowercase)
* Replace `NODE_SERVERS_STATIC_IP` with this nodes eth0 IP address (preserve the CIDR prefix)

Some quick commands to replace some of the above:
```bash
sed -i 's/NODE_INTERFACE_MAC/e4:5f:01:9d:4d:95/g' nodes/dal-k8s-mgmt-1-rpi4-1.yaml
sed -i 's/NODE_SERVERS_STATIC_IP/192.168.77.20/g' nodes/dal-k8s-mgmt-1-rpi4-1.yaml
```

An example of the `machine.network` would then look like:
```bash
machine:
    network:
        interfaces:
            -
              deviceSelector:
                hardwareAddr: e4:5f:01:9d:4e:19
                driver: bcmgenet
              vlans:
                -
                  addresses:
                    - 192.168.77.20/25
                  routes:
                    - network: 0.0.0.0/0
                      gateway: 192.168.77.1
                  vlanId: 103
                  vip:
                    ip: 192.168.77.2

              vip:
                ip: 192.168.77.130

        nameservers:
            - 192.168.77.129
            - 192.168.77.1
```

Now we will provision a single node and bootstrap it to form a cluster, after that we will add the other two nodes.

Apply the config for the first node:
```bash
talosctl apply-config --insecure -n 192.168.77.150 -f nodes/dal-k8s-mgmt-1-cp-1.yaml
```

Update your local device with the new credentials to talk to the cluster:
```bash
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config endpoints 192.168.77.20
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config nodes 192.168.77.20
```

First we verify if the Talos API is running on the node:
```bash
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig version

# Look at the logs
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig dmesg --follow

# Wait until you see something like 
192.168.77.20: user: warning: [2022-12-11T04:27:28.724547918Z]: [talos] task startAllServices (1/1): service "etcd" to be "up", service "kubelet" to be "up"

# This tells us we're waiting for "etcd" to come online
# Bootstrap the etcd cluster
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig bootstrap

# Wait for the cluster to settle down
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig dmesg --follow

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
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig kubeconfig kubeconfigs/dal-k8s-mgmt-1

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get nodes

# The node's status should become Ready when you see a bunch of `cni0` related logs appear after the above
```

Now we onboard the other nodes into the cluster:
```bash
talosctl apply-config --insecure -n <dhcp ip of dal-k8s-mgmt-1-rpi4-2> -f nodes/dal-k8s-mgmt-1-rpi4-2.yaml
talosctl apply-config --insecure -n <dhcp ip of dal-k8s-mgmt-1-rpi4-3> -f nodes/dal-k8s-mgmt-1-rpi4-3.yaml

talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config endpoints 192.168.77.20 192.168.77.21 192.168.77.22
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config nodes 192.168.77.20 192.168.77.21 192.168.77.22
```

Wait until all nodes become `Ready`:
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get nodes
```

You now have a basic k8s cluster running with:
* 3x rpi4.4gb.arm64 control plane nodes
* Able to schedule workloads on them
* Floating VIPs for easy k8s control plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN


# Upgrading

Going from v1.3.0 => v.1.3.1
```
# --preserve=true is required for a single node cluster
# Otherwise the node is wiped and rejoins the cluster
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig upgrade --nodes 192.168.77.20 --image ghcr.io/siderolabs/installer:v1.3.1 --preserve=true

# By default the upgrade process with talosctl will block and wait until it's done
# Eventually assuming all goes well you'll see
watching nodes: [192.168.77.20]
    * 192.168.77.20: post check passed

# You can use DMESG to keep an eye on progress/etc
# Wait for the reboot and when the node's back

# There's a possible kubelet bug w/Talos's static pods where you need to restart kubelet after a reboot (pods like the API Server won't actually be running)
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig -n 192.168.77.20 services kubelet restart
```
