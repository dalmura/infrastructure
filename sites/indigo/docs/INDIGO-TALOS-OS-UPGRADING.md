# Upgrading Talos Linux OS

Covering upgrading Talos Linux OS, which includes a new installer image.

Updating the underlying Talos Linux OS will *not* update Kubernetes, that's handled via [INDIGO-TALOS-K8S-UPGRADING.md](./INDIGO-TALOS-K8S-UPGRADING.md).

Always upgrade to the latest patch release of the current minor release before attempting a minor release upgrade.

Always ensure your local `talosctl` is running the latest available version before attempting any upgrades.

## Verify current Talos OS version(s)
We can use `kubectl get nodes -o wide` to tell us the Talos OS version info:
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
	Tag:         v1.10.2
	SHA:         1cf5914b
	Built:
	Go version:  go1.24.3
	OS/Arch:     linux/amd64
```

Ideally you're running the latest available version, but at a minimum the version you're hoping to upgrade to.

## Patch version bump
In this example our above nodes are a mix of `1.9.4` and `1.9.5`, and we will upgrade them all to `1.9.6`.

The Talos OS [release notes](https://github.com/siderolabs/talos/releases/tag/v1.9.6) don't mention anything specific to consider when upgrading.

The upgrade command itself is part of `talosctl` and looks something like:
```
talosctl upgrade --nodes 10.20.30.40 --image ghcr.io/siderolabs/installer:v1.10.0
```

With us specifying the Node IP as well as the Container Image URI.


### Perform the upgrades to the Worker Node(s)
First we need to generate the new installer images for each worker class.

Follow the docs for each worker class:
* [WORKERS-EQ14](INDIGO-CORE-1-WORKERS-EQ14.md)
* [WORKERS-RPI4](INDIGO-CORE-1-WORKERS-RPI4.md)
   * This actually references the image build from [CONTROL-PLANE](INDIGO-CORE-1-CONTROL-PLANE.md)

Once you have configured the relevant factory images, there will be a `Upgrading Talos Linux` section on the factory page, containing an image URI:
```
# Example URI for the EQ14 worker class
factory.talos.dev/installer/9ba0b24a91c2b56085dceb616daaf013f0453bcf2f2036814be062733e583806:v1.9.6

# Example URI for the RPI4 worker class
factory.talos.dev/installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.9.6

# Our Control Plane node is also an RPI4 worker class node for the purposes of the upgrade
# So we just use the above URI
```

From here can initiate the upgrade on each worker, *one by one*, ensuring *each upgrade finishes successfully before starting the next one*.

This is important as, when each node reboots, Longhorn will see node unavailability and possibly start failover processes for disks including increasing any under-replicated volumes. So rebooting multiple nodes at once may cause Longhorn to fail.

Upgrading `talos-e8ff1ed8884c` aka `192.168.77.73` which is an EQ14 worker:
```
talosctl upgrade --nodes 192.168.77.73 --image factory.talos.dev/installer/9ba0b24a91c2b56085dceb616daaf013f0453bcf2f2036814be062733e583806:v1.9.6
```

Once the above returns successfully, we should be able to rerun our `kubectl get nodes -o wide` command from above and verify `talos-e8ff1ed8884c`'s `OS-IMAGE` is showing up as `1.9.6`!

When the above has been validated we can proceed to upgrade the other worker nodes *one-by-one* validating each time the `OS-IMAGE` field in our `get nodes` command is showing the corretly upgraded `1.9.6` version.

Upgrading `talos-e45f019d4d95` aka `192.168.77.72` which is an RPI4 worker:
```
talosctl upgrade --nodes 192.168.77.72 --image factory.talos.dev/installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.9.6
```

Upgrading `talos-e45f019d4ca8` aka `192.168.77.71` which is an RPI4 worker:
```
talosctl upgrade --nodes 192.168.77.71 --image factory.talos.dev/installer/f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d:v1.9.6
```

### Perform the upgrades to the Control Plane node(s)
TODO: Upgrading the Control Plane node for a patch release


## Minor version bump
TODO: Anything different?
