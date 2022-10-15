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

We are assuming you have separately:
* Upgraded the EEPROM for all Raspberry Pi's to the latest version
* Configured the EEPROM boot order to attempt SD Card, USB *and* Network Boot

This will form 2x k8s clusters:
| Cluster                          | Role          | Hardware        | Quantity |
|----------------------------------|---------------|-----------------|----------|
| dal-k8s-mgmt-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | rpi4.8gb.arm    |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | dell.r320.amd64 |        3 |

The process outlined below is a rough translation from: https://www.sidero.dev/v0.5/getting-started/

### Setup a local Sidero

Prerequisites:
* Ensure laptop is on the Servers VLAN and has a DHCP address from there
* Have Docker installed on the laptop
* Have kubectl, clusterctl and talosctl installed
  * As of the time of writing (2022-10-12) this is
  * kubectl v1.25.2
  * clusterapi v1.2.3
  * talosctl v1.2.4

Process to setup k8s:
```bash
# Record the laptop's IP address
# Substitute it below where you see ${LAPTOP_IP}
LAPTOP_IP='192.168.77.xx'

# Create the local k8s cluster
# UDP/69 is for TFTP (for PXE boot)
# TCP/8081 is a webserver for netboot artifacts/config
# TCP/51821 is the SideroLink Wireguard network
talosctl cluster create \
  --name indigo-local-sidero \
  -p 69:69/udp,8081:8081/tcp,51821:51821/udp \
  --workers 0 \
  --config-patch '[{"op": "add", "path": "/cluster/allowSchedulingOnMasters", "value": true}]' \
  --endpoint "${LAPTOP_IP}"

# Obtain the cluster creds for local use
talosctl kubeconfig ./indigo-local-sidero
```

Configure the DHCP server to reference the local laptop.

We need to configure the following aspects of the DHCP server for the Servers VLAN:
* IP address of the server to boot from (Option 66)
* Filename/URL of the file to boot (Option 76)

Mikrotik since v7.4 (and fixed properly in v7.6) have implemented the ability to selectively offer different options above based on client capabilities (arm64 vs amd64), this is called the 'Generic matcher'.

How to configure this can be found in [Mikrotik's documentation](https://help.mikrotik.com/docs/display/ROS/DHCP#DHCP-Genericmatcher)

```bash
/ip/dhcp-server/network/set boot-file-name="ipxe-arm64.efi" next-server="${LAPTOP_IP}" [find name="servers-dhcp"]

/ip/dhcp-server/matcher
add address-pool=servers-dhcp code=60 name=rpi-matcher value=abc123
```

Now when the rpi's boot, they'll:
* Attempt to Network Boot
* Obtain a DHCP lease
* DHCP lease will instruct them to attempt to boot from the laptop IP
* DHCP lease will instruct them to download the boot file from the laptop
* They will download the file and boot the Sidero bootloader
* And proceed with onboarding into a cluster...

### dal-k8s-mgmt-1

* Build the configs to provision 3x rpi4.4gb.arm Control Plane nodes for dal-k8s-mgmt-1, we need to configure:
  * Talos Linux is installed on the USB SSD
* Create the dal-k8s-mgmt-1 cluster
* Power on 3x rpi4.4gb.arm designated for dal-k8s-mgmt-1
* Ensure they attempt to PXE boot
* Accept them on the local Sidero on your laptop
* Allocate them to the dal-k8s-mgmt-1 cluster

### Tear down local Sidero

* Pivot from Sidero from your laptop over to dal-k8s-sidero-1

### dal-k8s-core-1

* Build the configs to provision 3x rpi4.4gb.arm Control Plane nodes for dal-k8s-core-1
* Build the configs to provision 3x rpi4.8gb.arm Worker nodes for dal-k8s-core-1

