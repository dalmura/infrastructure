# Provision dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `rpi4.8gb.arm` Worker nodes.

## Create the `rpi4.8gb.arm` Worker templates
Download the `metal-rpi_generic-arm64.img.xz` artifact matching the same Talos version you used for the Control Plane step, and `dd` it onto the 128 GB USB Flash Drives via another machine:
```bash
# Download the version used when setting up the Control Plane nodes
wget https://github.com/siderolabs/talos/releases/download/v1.3.5/metal-rpi_generic-arm64.img.xz

# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `rpi4.8gb.arm64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.153
RPI4_2_IP=192.168.77.154
RPI4_3_IP=192.168.77.155
```

Using the config generated as part of the Control Plane bootstrap, we'll copy and configure the `templates/dal-indigo-core-1/worker.yaml`.

Apply the config for each node:
```bash
# Copy the config
mkdir -p nodes/dal-indigo-core-1/

cp templates/dal-indigo-core-1/worker.yaml nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64.yaml

# Edit and set:
# node.kubernetes.io/instance-type: "<TO POPULATE>"
# to
# node.kubernetes.io/instance-type: "rpi4.8gb.arm64"
#
# Edit and set:
# k8s.dalmura.cloud/nodegroup: "<TO POPULATE>"
# to
# k8s.dalmura.cloud/nodegroup: "rpi4-worker-pool"

talosctl apply-config --insecure -n "${RPI4_1_IP}" -f templates/dal-indigo-core-1/worker-rpi4-8gb-arm64.yaml
talosctl apply-config --insecure -n "${RPI4_2_IP}" -f templates/dal-indigo-core-1/worker-rpi4-8gb-arm64.yaml
talosctl apply-config --insecure -n "${RPI4_3_IP}" -f templates/dal-indigo-core-1/worker-rpi4-8gb-arm64.yaml
```

Verify the nodes become Ready:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes
```

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
* 3x rpi4.8gb.arm64 Worker nodes
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
