# Provision extra configuration for dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've got dal-indigo-core-1's `rpi4.8gb.arm` Workers running and Ready according to `kubectl get nodes`!

Export the worker nodes:
```bash
RPI4_1_IP=192.168.77.155
RPI4_2_IP=192.168.77.161
RPI4_3_IP=192.168.77.162
```

## OpenEBS Jiva
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_2_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_3_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml

# The output will look something like this
patched MachineConfigs.config.talos.dev/v1alpha1 at the node 192.168.77.161
Applied configuration without a reboot
```

After these have applied we need to force an upgrade to install the talos extensions:
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_2_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_3_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"

# The output will look something like this (as the node prepares itself)
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: waiting for actor ID

# It will then move through a series of 'tasks' (as the node upgrades)
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: task: upgrade action: START

# This will take a good like ~5 minutes, so hold tight
# Eventually the node will reboot like this
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: unavailable, retrying...

# This will also take a good few minutes, so hold tight
# And eventually move to (when the node finishes booting)
watching nodes: [192.168.77.161]
    * 192.168.77.161: post check passed
```

You can verify the extension with:
```bash
# See if it's installed on RPI4_1_IP
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" get extensions
NODE             NAMESPACE   TYPE              ID                                          VERSION   NAME          VERSION
192.168.77.161   runtime     ExtensionStatus   000.ghcr.io-siderolabs-iscsi-tools-v0.1.1   1         iscsi-tools   v0.1.1

# See if it's running on RPI4_1_IP
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" services
NODE             SERVICE      STATE     HEALTH   LAST CHANGE         LAST EVENT
192.168.77.161   apid         Running   OK       3m12s ago           Health check successful
192.168.77.161   containerd   Running   OK       466018h31m58s ago   Health check successful
192.168.77.161   cri          Running   OK       3m18s ago           Health check successful
192.168.77.161   ext-iscsid   Running   ?        3m17s ago           Started task ext-iscsid (PID 3538) for container ext-iscsid
192.168.77.161   ext-tgtd     Running   ?        3m17s ago           Started task ext-tgtd (PID 3480) for container ext-tgtd
192.168.77.161   kubelet      Running   OK       2m12s ago           Health check successful
192.168.77.161   machined     Running   OK       466018h32m4s ago    Health check successful
192.168.77.161   udevd        Running   OK       466018h31m55s ago   Health check successful
```

We then install the helm chart:
```bash
helm repo add openebs-jiva https://openebs.github.io/jiva-operator
helm repo update
helm upgrade --install --create-namespace --namespace openebs --version 3.4.0 openebs-jiva openebs-jiva/jiva
```

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
* 3x rpi4.8gb.arm64 Worker nodes
  * OpenEBS Jiva configured as a CSI Storage Class
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
