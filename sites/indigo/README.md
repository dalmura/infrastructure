# Usage

Instructions on how to setup the Indigo site.

At a high level the site is comprised of two Kubernetes clusters:
* a management cluster
  * responsible for privisioning other clusters
  * manages the hardware lifecycle of clusters
* a core cluster
  * runs the applications to support the site

We use the following Sidero Labs products:
* [Talos Linux](https://www.talos.dev/) as the Kubernetes distribution for both clusters
* [Sidero Metal](https://www.sidero.dev/) to run the management functionality

## Bootstrap

In order to bootstrap the Indigo site you will need:
* 6x rpi4.4gb.arm
* 3x rpi4.8gb.arm
* 3x dell.r320.amd64

Standard accessories assumed included for all Raspberry Pi's are:
* Raspberry Pi PoE+ Hat
* 32GB SD Card
* 128GB SSD Drive w/USB adaptor

Rack accessories include:
* [UCTRONICS 5x rpi4 + SSDs 1U rack (SKU U6264)](https://www.uctronics.com/cluster-and-rack-mount/uctronics-19-1u-raspberry-pi-rackmount-ssd-bracket-for-any-2-5-ssds.html)
* [UCTRONICS SATA to USB 3.0 Adaptor (SKU U6193)](https://www.uctronics.com/uctronics-sata-usb-adapter-cable-sata-hard-drive-disk-converter.html)
* M2.5 x 15mm bolts to thread the POE+ hat => rpi4 board => rack caddy

We are assuming you have separately:
* Upgraded the EEPROM for all Raspberry Pi's to the latest version
* Update the boot order depending on the cluster in question
  * Boot order is [documented here](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#BOOT_ORDER)
* For dal-k8s-mgmt-1 leave the EEPROM boot order to `0xf41`
  * Boot order: SD Card, USB Drive
  * As these nodes have Talos installed directly
* For dal-k8s-core-1 update the EEPROM boot order to `0xf21`
  * Boot order: SD Card, Network (Sidero will then attempt USB as necessary)
  * As these nodes are PXE booted from Sidero

This will form 2x k8s clusters:
| Cluster                          | Role          | Hardware        | Quantity |
|----------------------------------|---------------|-----------------|----------|
| dal-k8s-mgmt-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | rpi4.8gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | dell.r320.amd64 |        3 |

### Provision dal-k8s-mgmt-1 k8s cluster

* Have kubectl, clusterctl and talosctl installed
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
```

Verify the node is Ready and we can onboard new nodes:
```bash
mkdir kubeconfigs

# Extract the creds to talk via kubectl
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig kubeconfig kubeconfigs/dal-k8s-mgmt-1

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get nodes

# Verify you can ping the floating Virtual IP (VIP)
ping 192.168.77.2
```

Now we onboard the other nodes into the cluster:
```bash
talosctl apply-config --insecure -n <dhcp ip of dal-k8s-mgmt-1-rpi4-2> -f nodes/dal-k8s-mgmt-1-rpi4-2.yaml
talosctl apply-config --insecure -n <dhcp ip of dal-k8s-mgmt-1-rpi4-3> -f nodes/dal-k8s-mgmt-1-rpi4-3.yaml

talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config endpoints 192.168.77.20 192.168.77.21 192.168.77.22
talosctl --talosconfig templates/dal-k8s-mgmt-1/talosconfig config nodes 192.168.77.20 192.168.77.21 192.168.77.22
```

Verify all nodes are Ready:
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get nodes
```

You now have a basic k8s cluster running with:
* 3x rpi4.4gb.arm control plane nodes
* Able to schedule workloads on them
* Floating VIPs
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN

### Install Sidero on dal-k8s-mgmt-1

Configure the `SERVERS_STAGING` DHCP server to reference dal-k8s-mgmt-1's VIP: `192.168.77.130`

We need to configure the following aspects of the DHCP server to respond with:
* Hardcoded string the rPi requires "Raspberry Pi Boot" (Option 43)
* IP address of the server to boot from (Option 66)
* Filename/URL of the file to boot (Option 67)

Mikrotik since v7.4 (and fixed properly in v7.6) have implemented the ability to selectively offer different options above based on client capabilities (arm64 vs amd64), this is called the 'Generic matcher'.

How to configure this can be found in [Mikrotik's documentation](https://help.mikrotik.com/docs/display/ROS/DHCP#DHCP-Genericmatcher)

There is also a [thread here](https://forum.mikrotik.com/viewtopic.php?t=188290) and a [thread here](https://forum.mikrotik.com/viewtopic.php?t=95674) on Mikrotik's forum covering the finer details of this (as their doco is currently lacking)

```bash
# Shouldn't be required
#/ip/dhcp-server/network/set boot-file-name="ipxe-arm64.efi" next-server="192.168.77.130" [find comment="SERVERS_STAGING_VLAN"]

/ip/dhcp-server/matcher
add name="arch-rpi4"   code=?? value=??       server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-rpi4-default
add name="arch-arm64"  code=93 value="0x000b" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-arm64-default
add name="arch-uefi64" code=93 value="0x0007" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-uefi64-default
add name="arch-uefi32" code=93 value="0x0006" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-uefi32-default


/ip/dhcp-server/option/sets
add name="arch-rpi4-default"   options=boot-rpi4
add name="arch-arm64-default"  options=boot-arm64
add name="arch-uefi64-default" options=boot-uefi64
add name="arch-uefi32-default" options=boot-uefi32
add name="arch-bios-default"   options=boot-bios

/ip/dhcp-server/option
add name="boot-rpi4" code=43 value="'Raspberry Pi Boot'"
add name="boot-rpi4" code=66 value="192.168.77.130"
add name="boot-rpi4" code=67 value="'ipxe.efi'"

add name="boot-arm64" code=66 value="192.168.77.130"
add name="boot-arm64" code=67 value="'ipxe-arm64.efi'"

add name="boot-uefi64" code=66 value="192.168.77.130"
add name="boot-uefi64" code=67 value="'ipxe64.efi'"

add name="boot-uefi32" code=66 value="192.168.77.130"
add name="boot-uefi32" code=67 value="'ipxe.efi'"

add name="boot-bios" code=66 value="192.168.77.130"
add name="boot-bios" code=67 value="'ipxe.pxe'"
```

Now we install Sidero dal-k8s-mgmt-1:
```bash
export SIDERO_CONTROLLER_MANAGER_HOST_NETWORK=true
export SIDERO_CONTROLLER_MANAGER_API_ENDPOINT="192.168.77.2"
export SIDERO_CONTROLLER_MANAGER_SIDEROLINK_ENDPOINT="192.168.77.2"

clusterctl init --kubeconfig=kubeconfigs/dal-k8s-mgmt-1 -b talos -c talos -i sidero
```
Now dal-k8s-mgmt-1 is a Sidero management cluster, able to support PXE booting!


### Setup Sidero for dal-k8s-core-1

* Build the configs to provision 3x rpi4.4gb.arm Control Plane nodes for dal-k8s-core-1
* Build the configs to provision 3x rpi4.8gb.arm Worker nodes for dal-k8s-core-1
