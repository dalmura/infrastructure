# Upgrading Talos Linux OS

Covering upgrading Talos Linux OS, which includes a new installer image.

Updating the underlying Talos Linux OS will *not* update Kubernetes, that's handled via [INDIGO-TALOS-K8S-UPGRADING.md](./INDIGO-TALOS-K8S-UPGRADING.md).

Always upgrade to the latest patch release of the current minor release before attempting a minor release upgrade.

Always ensure your local `talosctl` is running the latest available version before attempting any upgrades.

## Verify current Talos Linux version(s)
We can use `kubectl get nodes -o wide` to tell us the Talos Linux version info:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE         KERNEL-VERSION   CONTAINER-RUNTIME
talos-e45f019d4e19   Ready    control-plane   62d   v1.32.3   192.168.77.70   <none>        Talos (v1.9.5)   6.12.18-talos    containerd://2.0.3
talos-e45f019d4ca8   Ready    <none>          61d   v1.32.3   192.168.77.71   <none>        Talos (v1.9.5)   6.12.18-talos    containerd://2.0.3
talos-e45f019d4d95   Ready    <none>          61d   v1.32.3   192.168.77.72   <none>        Talos (v1.9.5)   6.12.18-talos    containerd://2.0.3
talos-e8ff1ed8884c   Ready    <none>          61d   v1.33.0   192.168.77.73   <none>        Talos (v1.9.4)   6.12.13-talos    containerd://2.0.2
```

Reviewing the `OS-IMAGE` above and deciding the upgrade path.

You can verify your local `talosctl` version by running
```
talosctl version --client
Client:
	Tag:         v1.10.3
	SHA:         dde2cebc
	Built:       
	Go version:  go1.24.3
	OS/Arch:     linux/amd64
```

Ideally you're running the latest available version, but at a minimum the version you're hoping to upgrade to.

## Plan Version Upgrade
In this example our above nodes are a mix of `1.9.4` and `1.9.5`, and we will upgrade them all to `1.10.3`.

The Talos Linux [release notes](https://github.com/siderolabs/talos/releases/tag/v1.10.3) don't mention anything specific to consider when upgrading.

The release notes for 1.10 outline a few things, but none of them apply to this sites specific setup.

The upgrade command itself is part of `talosctl` and looks something like:
```
talosctl upgrade --nodes 192.168.77.73 --image ghcr.io/siderolabs/installer:v1.10.3
```

With us specifying the node's IP as well as the Container Image URI. But we cannot use the default image above, we need customised ones that bake in all the extra kernel modules that we need.

### Perform the upgrades to the Worker Node(s)
First we need to generate the new installer images for each worker class.

Follow the docs for each worker class:
* [WORKERS-EQ14](INDIGO-CORE-1-WORKERS-EQ14.md)
* [WORKERS-RPI4](INDIGO-CORE-1-WORKERS-RPI4.md)
   * This actually references the image build from [CONTROL-PLANE](INDIGO-CORE-1-CONTROL-PLANE.md)

Once you have configured the relevant factory images, there will be a `Upgrading Talos Linux` section on the factory page, containing an image URI:
```
# Example URI for the EQ14 worker class
factory.talos.dev/metal-installer/78050f2d4149310e8e1a26f6433ff4b9932025c6420ddff8f71d3fec22fc809c:v1.10.3

# Generated via
https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-talos.halt_if_installed&cmdline-set=true&extensions=-&extensions=siderolabs%2Fi915&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Frealtek-firmware&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=undefined&target=metal&version=1.10.3

# Example URI for the RPI4 worker class
factory.talos.dev/metal-installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.10.3 

https://factory.talos.dev/?arch=arm64&board=rpi_generic&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=sbc&version=1.10.3

# Our Control Plane node is also an RPI4 worker class node for the purposes of the upgrade
# So we just use the above URI
```

From here can initiate the upgrade on each worker, *one by one*, ensuring *each upgrade finishes successfully before starting the next one*.

This is important as, when each node reboots, Longhorn will see node unavailability and possibly start failover processes for disks including increasing any under-replicated volumes. So rebooting multiple nodes at once may cause Longhorn to fail.

Upgrading `talos-e8ff1ed8884c` aka `192.168.77.73` which is an EQ14 worker:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig upgrade --nodes 192.168.77.73 --image factory.talos.dev/metal-installer/78050f2d4149310e8e1a26f6433ff4b9932025c6420ddff8f71d3fec22fc809c:v1.10.3
```

*Before* running the above, it can help to start up a `dmesg` console as well to the node to observe the upgrade process and any error logs:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 dmesg -f
```

The command will then log out its progress as it waits for the node to upgrade. This will take approx ~10 mins. For me it seems to hang initially on `validating $IMAGE_URI` then after on `unmounting filesystem $RANDOM_UUID`, after that it proceeds pretty quickly with the upgrade.

Eventually the node will reboot and the above `dmesg` command will exit, after a short while rerun it start the logs again with the rebooted node, eventually the following logs will show up:
```
192.168.77.73: user: warning: [2025-06-03T12:02:28.074421525Z]: [talos] machine is running and ready {"component": "controller-runtime", "controller": "runtime.MachineStatusController"}
192.168.77.73: user: warning: [2025-06-03T12:02:28.074509525Z]: [talos] removing fallback entry {"component": "controller-runtime", "controller": "runtime.DropUpgradeFallbackController"}
```

Which tell us the node has booted on the new OS and Talos has removed the 'fallback to the previous version' if the upgrade happend to fail on reboot.

Once the above returns successfully, we should be able to rerun our `kubectl get nodes -o wide` command from above and verify `talos-e8ff1ed8884c`'s `OS-IMAGE` is showing up as `1.10.3`!

When the above has been validated we can proceed to upgrade the other worker nodes *one-by-one* validating each time the `OS-IMAGE` field in our `get nodes` command is showing the corretly upgraded `1.10.3` version.

Upgrading `talos-e45f019d4d95` aka `192.168.77.72` which is an RPI4 worker:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig upgrade --nodes 192.168.77.72 --image factory.talos.dev/metal-installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.10.3
```

Perform usual post upgrade checks:
* `kubectl get nodes -o wide` showing upgrades as expected
* Longhorn reporting all volumes as Healthy

Upgrading `talos-e45f019d4ca8` aka `192.168.77.71` which is an RPI4 worker:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig upgrade --nodes 192.168.77.71 --image factory.talos.dev/metal-installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.10.3
```

Perform usual post upgrade checks:
* `kubectl get nodes -o wide` showing upgrades as expected
* Longhorn reporting all volumes as Healthy

### Perform the upgrades to the Control Plane node(s)
After all worker nodes are upgraded to `1.10.3` you can issue the upgrade for the CP nodes one-after-the-other.

Upgrading `talos-e45f019d4e19` aka `192.168.77.70` which is an RPI4 control plane:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig upgrade --nodes 192.168.77.70 --image factory.talos.dev/metal-installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.10.3
```

The `dmesg` output will be roughly the same compared to the worker nodes, with just additional pods being shutdown, specifically around `etcd`.

But the node should correctly turn everything off, upgrade, reboot and come back up properly.

Validate the following is correct:
* `kubectl get nodes -o wide` is showing the correct version
* The above command is showing `STATUS` == `Ready` for all nodes
* Longhorn is reporting all volumes are healthy

The new `kubectl get nodes -o wide` now looks like:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION   CONTAINER-RUNTIME
talos-e45f019d4ca8   Ready    <none>          69d   v1.32.3   192.168.77.71   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4d95   Ready    <none>          69d   v1.32.3   192.168.77.72   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4e19   Ready    control-plane   69d   v1.32.3   192.168.77.70   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e8ff1ed8884c   Ready    <none>          68d   v1.33.0   192.168.77.73   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
```

For some reason the EQ14 box upgraded its kubelet to `1.33.0`, not sure how that happened, but k8s upgrading anyway will resolve that quirk.

The OS upgrade has been completed successfully! Rinse and repeat as required to keep upgrading!
