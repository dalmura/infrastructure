# Provision dal-k8s-mgmt-1

## Form the k8s cluster
Have kubectl, clusterctl and talosctl installed:
  * As of the time of writing (2022-10-12) this is
  * kubectl v1.25
  * clusterapi v1.2
  * talosctl v1.2

Double check the [compatibility of Sidero and Talos](https://github.com/siderolabs/sidero#compatibility-with-cluster-api-and-kubernetes-versions) and ensure you choose the [latest Sidero](https://github.com/siderolabs/sidero/releases/latest) and the [latest supported Talos](https://github.com/siderolabs/talos/releases). At the time of writing Sidero v0.5 supports Talos v1.2.

Download the `metal-rpi_4-arm64.img.xz` artifact from the latest supported Talos release from above, and burn it onto 3x SD cards.

Boot the 3x rpi4.4gb.arm nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
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
    --output-dir templates/dal-k8s-mgmt-1/
```

`192.168.77.2` will be our [Virtual IP](https://www.talos.dev/v1.2/talos-guides/network/vip/) that is advertised between all management nodes in the cluster, see the [network repo](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yml#L52) for assignment of this IP.

`patches/dal-k8s-mgmt-1-controlplane.yaml` contains the following tweaks:
* Allow scheduling regular pods on Control Plane nodes
* Changes the disk install to /dev/mmcblk0 (SD Card for rpi's)
* Configures the networking to move the node into the static ranges (off DHCP)

You will now need to 'hydrate' these files to be per-server:
```bash
mkdir nodes
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-rpi4-1.yaml
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-rpi4-2.yaml
cp templates/dal-k8s-mgmt-1/controlplane.yaml nodes/dal-k8s-mgmt-1-rpi4-3.yaml
```

Get the MAC Address of eth0:
```bash
# YAML
talosctl get links --insecure --nodes 192.168.77.150 --output yaml | yq 'select(.metadata.id == "eth0").spec.hardwareAddr'
e4:5f:01:9d:4c:a8

# JSON
talosctl get links --insecure --nodes 192.168.77.150 --output json | jq -r 'select(.metadata.id == "eth0").spec.hardwareAddr'
e4:5f:01:9d:4c:a8

# The above would translate into the following device selector:
machine:
  network:
    interfaces:
      - deviceSelector:
          hardwareAddr: e4:5f:01:9d:4c:a8
          driver: bcmgenet  # rpi specific
```

Gather the disk info:
```bash
$ talosctl disks --insecure --nodes 192.168.77.150
DEV            MODEL              SERIAL       TYPE   UUID   WWID   MODALIAS      NAME    SIZE     BUS_PATH
/dev/mmcblk0   -                  0x7420dc5b   SD     -      -      -             SM32G   32 GB    /platform/emmc2bus/fe340000.mmc/mmc_host/mmc0/mmc0:aaaa/
/dev/sda       SSD 870 EVO 250G   -            SSD    -      -      scsi:t-0x00   -       250 GB   /platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb4/4-2/4-2:1.0/host0/target0:0:0/0:0:0:0/

# The above would translate into the following if you wanted to install onto the SSD
machine:
  install:
    diskSelector:
      model: SSD 870 EVO 250G
```

Within each file you will need to make the following changes:
* Replace `${NODE_INTERFACE_MAC}` with this nodes eth0 MAC address (ensure it's lowercase)
* Replace `${NODE_STATIC_IP}` with this nodes eth0 IP address (preserve the CIDR prefix)
* Replace `machine.install.disk`'s value with a diskSelector populated from above if you have an SSD/etc

An example of the `machine.network` could look like:
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
            - 192.168.77.1
            - 192.168.77.129
```

Now we will provision a single node and bootstrap it to form a cluster, after that we will add the other two nodes.

Apply the config for the first node:
```bash
talosctl apply-config --insecure -n <dhcp ip of dal-k8s-mgmt-1-rpi4-1> -f nodes/dal-k8s-mgmt-1-rpi4-1.yaml
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
```

And finally bootstrap the etcd cluster:
```bash
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
```

# Verify you can ping the floating Virtual IP (VIP)
ping 192.168.77.2

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
* 3x rpi4.4gb.arm control plane nodes
* Able to schedule workloads on them
* Floating VIPs
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN


# Upgrading

Going from v1.2.6 => v.1.2.7
```
# --preserve=true is required for a single node cluster
# Otherwise the node is wiped and rejoins the cluster

talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig upgrade --nodes 192.168.77.20 --image ghcr.io/siderolabs/installer:v1.2.7 --preserve=true
NODE            ACK                        STARTED
192.168.77.20   Upgrade request received   2022-11-26 19:22:45.079607 +1100 AEDT m=+56.434870596

# Can use DMESG to keep an eye on progress/etc
# Wait for the reboot and when the node's back

talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig apply-config -n 192.168.77.20 -f nodes/dal-k8s-mgmt-1-rpi4-1.yaml
Applied configuration without a reboot

# There's a possible kubelet bug w/Talos's static pods where you need to restart kubelet after a reboot
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig -n 192.168.77.20 services kubelet restart
```
