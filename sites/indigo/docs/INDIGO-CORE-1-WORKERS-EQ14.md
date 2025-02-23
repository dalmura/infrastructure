# Provision dal-indigo-core-1's `eq14.16gb.amd64` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `eq14.16gb.amd64` Worker nodes.

## Prepare image and boot nodes
Navigate to the [Talos Image Factory](https://factory.talos.dev/):
1. Select 'Bare-metal Machie'
2. Select the Talos Version from above
3. Select 'amd64', ensuring SecureBoot is *not* selected
4. Select the following System Extensions:
   * siderolabs/iscsi-tools
   * siderolabs/util-linux-tools
   * siderolabs/intel-ucode
   * siderolabs/i915
   * siderolabs/realtek-firmware (TODO: need to confirm this)
5. Skip the Kernel command line or overlay options
6. Download the linked *ISO* `metal-amd64.iso`
   6.1 The download may take some time to start as the Talos Image Factory generates the assets in the backend

Note down the following attributes:
```
SCHEMATIC_ID='249d9135de54962744e917cfe654117000cba369f9152fbab9d055a00aa3664f'

FACTORY_URL='https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fi915&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=metal&version=1.9.4'
```

Write the `metal-amd64.iso` out to a USB as we'll boot off it to start up maintenance mode, Talos will install itself onto the SSD on the EQ14, the USB is temporary.

```bash
# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
sudo dd if=metal-amd64.iso of=/dev/sdb conv=fsync bs=4M status=progress
flush

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `eq14.16gb.amd64` nodes, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
EQ14_1_IP=192.168.77.153
EQ14_2_IP=192.168.77.154
EQ14_3_IP=192.168.77.155
```

## Create the `eq14.16gb.amd64` Worker templates

Using the config generated as part of the Control Plane bootstrap, we'll copy and configure the `templates/dal-indigo-core-1/worker.yaml` for each node (as we have unqiue node hostnames).

Apply the config for each node:
```bash
# Enter this then record HW ADDR for eth0, eg. e4:5f:01:1d:3c:a8
talosctl -n "${EQ14_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enx")) | .spec.hardwareAddr' -r | tr -d ':'

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

You can now quickly go back to the [Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) doco and verify Cilium's Hubble Relay & UI have come up correctly.

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* 3x rpi4.8gb.arm64 Worker nodes
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
