# Provision dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `rpi4.8gb.arm` Worker nodes.

## Create the `rpi4.8gb.arm` Worker templates
Reuse the existing `metal-rpi_generic-arm64.raw.xz` from the previous Control Plane process.
```bash
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
RPI4_3_IP=
```

Using the config generated as part of the Control Plane bootstrap, we'll copy and configure the `templates/dal-indigo-core-1/worker.yaml` for each node (as we have unqiue node hostnames).

Apply the config for each node:
```bash
# Enter this then record HW ADDR for eth0, eg. e4:5f:01:1d:3c:a8
talosctl -n "${RPI4_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${RPI4_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'

# Repeat noting down the HW ADDR for each node
# Remove all ':' from the HW ADDR and you're left with:
RPI4_1_HW_ADDR='e45f019d4ca8'
RPI4_2_HW_ADDR='e45f019d4e19'
RPI4_3_HW_ADDR=''

# Copy the configs

# Create the per-device Worker configs with these overrides
cat templates/dal-indigo-core-1/worker.yaml | gsed "s/<HW_ADDRESS>/${RPI4_1_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_1_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/worker.yaml | gsed "s/<HW_ADDRESS>/${RPI4_2_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_2_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/worker.yaml | gsed "s/<HW_ADDRESS>/${RPI4_3_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_3_HW_ADDR}.yaml"

gsed -i 's/<NODE_INSTANCE_TYPE>/rpi4.8gb.arm64/g' nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-*
gsed -i 's/<K8S_NODE_GROUP>/rpi4-worker-pool/g' nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-*

talosctl apply-config --insecure -n "${RPI4_1_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_1_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${RPI4_2_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_2_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${RPI4_3_IP}" -f nodes/dal-indigo-core-1/worker-rpi4-8gb-arm64-${RPI4_3_HW_ADDR}.yaml

# If you want to watch the individual nodes bootstrap
talosctl -n "${RPI4_1_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
talosctl -n "${RPI4_2_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
talosctl -n "${RPI4_3_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
```

You will see the final few lines look like this:
```bash
192.168.77.151: user: warning: [2024-03-03T04:40:48.350286425Z]: [talos] task startAllServices (1/1): done, 30.781765505s
192.168.77.151: user: warning: [2024-03-03T04:40:48.358208425Z]: [talos] phase startEverything (16/16): done, 30.796017875s
192.168.77.151: user: warning: [2024-03-03T04:40:48.366214425Z]: [talos] boot sequence: done: 1m7.749942979s
192.168.77.151: user: warning: [2024-03-03T04:41:51.581880425Z]: [talos] machine is running and ready {"component": "controller-runtime", "controller": "runtime.MachineStatusController"}
```

Verify the nodes become Ready:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes
```

You can now quickly go back to the (Control Plane)[./INDIGO-CORE-1-CONTROL-PLANE.md] doco and verify Cilium's Hubble Relay & UI have come up correctly.

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* 3x rpi4.8gb.arm64 Worker nodes
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
