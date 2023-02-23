# Provision extra configuration for dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've got dal-indigo-core-1's `rpi4.8gb.arm` Workers running and Ready according to `kubectl get nodes`!

## OpenEBS Jiva
```bash
talosctl -e 192.168.77.130 -n "${RPI4_1_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl -e 192.168.77.130 -n "${RPI4_2_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl -e 192.168.77.130 -n "${RPI4_3_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
```

After these have applied we need to force an upgrade to install the talos extensions:
```bash
talosctl -e 192.168.77.130 -n "${RPI4_1_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl -e 192.168.77.130 -n "${RPI4_2_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl -e 192.168.77.130 -n "${RPI4_3_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
```

You can verify the extension with:
```bash
# See if it's installed
talosctl -e 192.168.77.130 -n "${RPI4_1_IP}" get extensions

# See if it's running
talosctl -e 192.168.77.130 -n "${RPI4_1_IP}" services
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
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
