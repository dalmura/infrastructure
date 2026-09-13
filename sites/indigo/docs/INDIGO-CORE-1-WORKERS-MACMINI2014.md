# Provision dal-indigo-core-1's `macmini2014.16gb.amd64` Workers

We assume you've followed the steps at [`dal-indigo-core-1` Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) and are ready to onboard the `macmini2014.16gb.amd64` Worker nodes.

## Prepare image and boot nodes

Talos since v1.13 stopped supporting this hardware, details can be found in [talos-mac-installer](https://github.com/mebezac/talos-mac-installer) repo.

So instead the above repo has provided a custom build with a single-line tweak to enable support again. Hopefully they keep it up to date, but if not we should be able to clone the repo and setup the build pipeline ourselves if needed.

Navigate to [talos-mac-installer releases](https://github.com/mebezac/talos-mac-installer/releases) and either:
* Download the `metal-amd64.iso`, `dd` to a USB and run
* Reference the image in GHCR and use for a Talos upgrade

This build has these System Extensions bundled in (we can't customse them later):
* siderolabs/i915
* siderolabs/intel-ucode
* siderolabs/iscsi-tools
* siderolabs/util-linux-tools

```bash
# Linux, eg. USB Flash Drive is /dev/sdb
sudo lsblk
sudo dd if=metal-amd64.iso of=/dev/sdb conv=fsync bs=4M status=progress
sync

# Mac
# Just use Raspberry Pi Imager tool
```

Book the Mac Mini 2014's with the USB.

You will need to hold Alt (aka Option) to force the bootloader to prompt you to pick the boot media.

Optionally, if you have an existing Talos install, after selecting the USB drive to boot from, in the Talos bootloader menu, you can choose to wipe the existing install.

Once booted, record the IP Addresses that DHCP assigns from the `SERVERS_STAGING` VLAN, for example:
```bash
MACMINI2014_1_IP=192.168.77.196
```

## Create the `macmini2014.16gb.amd64` Worker templates

We assume you have a working directory that contains the `secrets.yaml` that was used to create the cluster initially as part of the control plane setup, and also have the following environment variables set:
* `TALOS_VERSION`

First we need to create the worker config for the macmini2014 worker class:
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
  --config-patch-worker @patches/dal-indigo-core-1-worker-macmini2014-init.yaml \
  --output-dir templates/dal-indigo-core-1/ \
  --output-types worker

mv templates/dal-indigo-core-1/worker.yaml templates/dal-indigo-core-1/worker-macmini2014.yaml
```

We then need to specialise `worker-macmini2014.yaml` for each node.

Apply the config for each node:
```bash
# Enter this then record HW ADDR for enx<MAC>, eg. 785536031758
talosctl -n "${MACMINI2014_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("enp")) | .spec.hardwareAddr' -r | tr -d ':'

# Note: Even though the ethernet interfaces here are enp***
# Talos will rename them to be 'predictable'
# See: https://docs.siderolabs.com/talos/latest/networking/predictable-interface-names
# In the config below we template them to enx<MAC>

# Repeat noting down the HW ADDR for each node:
MACMINI2014_1_HW_ADDR='787b8aae3cc5'

# Copy the configs

# Create the per-device Worker configs with these overrides
# We statically allocate the Node & VLAN IPs now
cat templates/dal-indigo-core-1/worker-macmini2014.yaml | \
    sed "s/<HW_ADDRESS>/${MACMINI2014_1_HW_ADDR}/g" | \
    sed "s/<NODE_IP>/192.168.77.196/g" | \
    sed "s/<VLAN_IP>/192.168.77.71/g" > "nodes/dal-indigo-core-1/worker-macmini2014-16gb-amd64-${MACMINI2014_1_HW_ADDR}.yaml"

sed -i 's/<NODE_INSTANCE_TYPE>/macmini2014.16gb.amd64/g' nodes/dal-indigo-core-1/worker-macmini2014-16gb-amd64-*

sed -i 's/<K8S_NODE_GROUP>/macmini2014-worker-pool/g' nodes/dal-indigo-core-1/worker-macmini2014-16gb-amd64-*

sed -i "s|<INSTALLER_IMAGE_URI>|${INSTALLER_IMAGE_URI}|g" nodes/dal-indigo-core-1/worker-macmini2014-16gb-amd64-*

talosctl apply-config --insecure -n "${MACMINI2014_1_IP}" -f nodes/dal-indigo-core-1/worker-macmini2014-16gb-amd64-${MACMINI2014_1_HW_ADDR}.yaml

# It will initially take some time to download the image and get the node booted
# Once it's booted into the new image (about 3-5 mins), you can tail the logs:
talosctl -n "${MACMINI2014_1_IP}" --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow
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
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide

# Match the hostnames the HW_ADDR's to know which ones which
```

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
  * Cilium in Strict Mode as the CNI
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
* 3x eq14.16gb.amd64 Worker nodes
* ?x macmini2014.16gb.amd64 Worker nodes

If this is the first group of workers for this cluster, you can now quickly go back to the [Control Plane](INDIGO-CORE-1-CONTROL-PLANE.md) doco and verify Cilium's Hubble Relay & UI have come up correctly.

You can proceed to onboard [other worker classes](INDIGO-CORE-1-WORKERS-RPI4.md) or proceed to [deploying application wave management](INDIGO-CORE-1-APPS-ARGOCD.md).
