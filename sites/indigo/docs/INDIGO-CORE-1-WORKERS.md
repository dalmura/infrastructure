# Provision dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `rpi4.8gb.arm` Worker nodes.

## Create the `rpi4.8gb.arm` Worker templates
Download the `metal-rpi_generic-arm64.img.xz` artifact matching the same Talos version you used for the Control Plane step, and `dd` it onto the 128 GB USB Flash Drives via another machine:
```bash
# Download the version used when setting up the Control Plane nodes
wget "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-rpi_generic-arm64.img.xz"

# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
xz -dc metal-rpi_generic-arm64.img.xz | sudo dd of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `rpi4.8gb.arm64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
RPI4_1_IP=192.168.77.151
RPI4_2_IP=192.168.77.155
RPI4_3_IP=192.168.77.159
```

Using the config generated as part of the Control Plane bootstrap, we'll copy and configure the `templates/dal-indigo-core-1/worker.yaml` for each node (as we have unqiue node hostnames).

Apply the config for each node:
```bash
# Enter this then record HW ADDR for eth0, eg. e4:5f:01:1d:3c:a8
talosctl -n "${RPI4_1_IP}" get links --insecure -o json

# Repeat noting down the HW ADDR for each node
# Remove all ':' from the HW ADDR and you're left with:
RPI4_1_HW_ADDR='e45f019d4ca8'
RPI4_2_HW_ADDR='e45f019d4d95'
RPI4_3_HW_ADDR='e45f019d4e19'

# Copy the configs
cp templates/dal-indigo-core-1/worker.yaml "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_1_HW_ADDR}.yaml"
cp templates/dal-indigo-core-1/worker.yaml "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_2_HW_ADDR}.yaml"
cp templates/dal-indigo-core-1/worker.yaml "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_3_HW_ADDR}.yaml"

# Edit and set:
# machine.network.hostname:         "talos-<HW_ADDRESS>" => "talos-${RPI4_X_HW_ADDR}"
# k8s.dalmura.cloud/nodegroup:      "<TO POPULATE>"      => "rpi4-worker-pool"
# node.kubernetes.io/instance-type: "<TO POPULATE>"      => "rpi4.8gb.arm64"

talosctl apply-config --insecure -n "${RPI4_1_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_1_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${RPI4_2_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_2_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${RPI4_3_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_3_HW_ADDR}.yaml
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
