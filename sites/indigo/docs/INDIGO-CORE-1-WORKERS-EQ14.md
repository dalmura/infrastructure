# Provision dal-indigo-core-1's `eq14.16gb.amd64` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `eq14.16gb.amd64` Worker nodes.

## Prepare image and boot nodes
Navigate to the [Talos Image Factory](https://factory.talos.dev/):
1. Select 'Bare-metal Machine'
2. Select the Talos Version from above
3. Select 'amd64', ensuring SecureBoot is *not* selected
4. Select the following System Extensions:
   * siderolabs/iscsi-tools
   * siderolabs/util-linux-tools
   * siderolabs/intel-ucode
   * siderolabs/i915
   * siderolabs/realtek-firmware
   * siderolabs/hailort
5. Provide the following Kernel command line option: `-talos.halt_if_installed`
6. Download the linked *ISO* `metal-amd64.iso`
   6.1 The download may take some time to start as the Talos Image Factory generates the assets in the backend

Note down the following attributes:
```
SCHEMATIC_ID='69478eaae753eb198b027db189f1b9aac3a2ee37ae7d8955a474478e4b9cd4a1'

FACTORY_URL='https://factory.talos.dev/?arch=amd64&cmdline=-talos.halt_if_installed&cmdline-set=true&extensions=-&extensions=siderolabs%2Fhailort&extensions=siderolabs%2Fi915&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Frealtek-firmware&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=metal&version=1.11.0-rc.0'

# From the `Initial Installation` section
export INSTALLER_IMAGE_URI='factory.talos.dev/metal-installer/69478eaae753eb198b027db189f1b9aac3a2ee37ae7d8955a474478e4b9cd4a1:v1.11.0-rc.0'
```

Write the `metal-amd64.iso` out to a USB as we'll boot off it to start up maintenance mode, Talos will install itself onto the SSD on the EQ14, the USB is temporary.

We've deliberately removed `talos.halt_if_installed` as Talos OS refuses to boot off a USB if it detects Talos OS already installed on the system disk.

```bash
# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
sudo dd if=metal-amd64.iso of=/dev/sdb conv=fsync bs=4M status=progress
sync

# Mac
# Just use Raspberry Pi Imager tool
```

Boot the 3x `eq14.16gb.amd64` nodes with the above USB, ensuring to boot from the USB. F7 from a locally attached keyboard will bring up the boot menu.

TODO: Optionally wipe the existing NVME drive as Talos doesn't like an existing Talos install existing

Once booted, record the IP Addresses that DHCP assigns from the SERVERS_STAGING VLAN, for example:
```bash
EQ14_1_IP=192.168.77.199
EQ14_2_IP=
EQ14_3_IP=
```

## Create the `eq14.16gb.amd64` Worker templates

We assume you have a working directory that contains the `secrets.yaml` that was used to create the cluster initially as part of the control plane setup, and also have the following environment variables set:
* TALOS_VERSION

First we need to create the worker config for the eq14 worker class:
```bash
talosctl gen config \
    dal-indigo-core-1 \
    'https://192.168.77.2:6443/' \
    --with-secrets secrets.yaml \
    --with-docs=false \
    --with-examples=false \
    --install-disk='' \
    --talos-version "${TALOS_VERSION}" \
    --with-cluster-discovery=false \
    --with-kubespan=false \
    --additional-sans 'core-1.indigo.dalmura.cloud' \
    --config-patch @patches/dal-indigo-core-1-all-init.yaml \
    --config-patch-worker @patches/dal-indigo-core-1-worker-eq14-init.yaml \
    --output-dir templates/dal-indigo-core-1/ \
    --output-types worker

mv templates/dal-indigo-core-1/worker.yaml templates/dal-indigo-core-1/worker-eq14.yaml
```

We then need to specialise `worker-eq14.yaml` for each node.

Apply the config for each node:
```bash
# Enter this then record HW ADDR for eth0, eg. e4:5f:01:1d:3c:a8
# These will print out 2x MAC Addresses for each of the ports
# Find the correct one by looking at the DHCP leases to see which one is active
talosctl -n "${EQ14_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enp")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enp")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enp")) | .spec.hardwareAddr' -r | tr -d ':'

# Repeat noting down the HW ADDR for each node
# Remove all ':' from the HW ADDR and you're left with:
EQ14_1_HW_ADDR='e8ff1ed8884c'
EQ14_2_HW_ADDR=''
EQ14_3_HW_ADDR=''

# Copy the configs

# Create the per-device Worker configs with these overrides
cat templates/dal-indigo-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_1_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_1_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_2_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_2_HW_ADDR}.yaml"
cat templates/dal-indigo-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_3_HW_ADDR}/g" > "nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_3_HW_ADDR}.yaml"

sed -i 's/<NODE_INSTANCE_TYPE>/eq14.16gb.amd64/g' nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-*
sed -i 's/<K8S_NODE_GROUP>/eq14-worker-pool/g' nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-*
sed -i "s|<INSTALLER_IMAGE_URI>|${INSTALLER_IMAGE_URI}|g" nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-*

talosctl apply-config --insecure -n "${EQ14_1_IP}" -f nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_1_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${EQ14_2_IP}" -f nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_2_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${EQ14_3_IP}" -f nodes/dal-indigo-core-1/worker-eq14-16gb-amd64-${EQ14_3_HW_ADDR}.yaml

# It will initially take some time to download the image and get the node booted
# Once it's booted into the new image (about 3-5 mins), you can tail the logs:
talosctl -n "${EQ14_1_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
talosctl -n "${EQ14_2_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
talosctl -n "${EQ14_3_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
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

# Match the hostnames the HW_ADDR's to know which ones which
```

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
* 3x eq14.16gb.amd64 Worker nodes

If this is the first group of workers for this cluster, you can now quickly go back to the [Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) doco and verify Cilium's Hubble Relay & UI have come up correctly.

You can proceed to onboard [other worker classes](INDIGO-CORE-1-WORKERS-RPI4.md) or proceed to [deploying application wave management](INDIGO-CORE-1-APPS-ARGOCD.md).
