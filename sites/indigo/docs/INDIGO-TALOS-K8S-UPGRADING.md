# Upgrading Kubernetes on Talos Linux OS

Covering upgrading Kubernetes on Talos Linux OS.

This assumes you've upgrades Talos Linux OS up to its latest current version. This is kinda required as Talos internally keeps track of what Kubernetes versions are supported on what Talos Linux OS versions.

So usually to upgrade k8s you'll need to upgrade Talos first.

We assume you've already done this via [INDIGO-TALOS-OS-UPGRADING.md](./INDIGO-TALOS-OS-UPGRADING.md).

## Verify current Kubernetes version(s)
This is tracked via the VERSION attribute that's returned via `kubectl get nodes -o wide`:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION   CONTAINER-RUNTIME
talos-e45f019d4ca8   Ready    <none>          69d   v1.32.3   192.168.77.71   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4d95   Ready    <none>          69d   v1.32.3   192.168.77.72   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4e19   Ready    control-plane   69d   v1.32.3   192.168.77.70   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e8ff1ed8884c   Ready    <none>          69d   v1.33.3   192.168.77.73   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
```

Here we can see:
* Talos Linux is running v1.10.3 across all nodes
* Kubenetes is running version v1.32.3 across all nodes

We can then visit the Talos Linux [support matrix page](https://www.talos.dev/v1.10/introduction/support-matrix/) for v1.10, and note the supported k8s versions are 1.28 through to 1.33.

Which means we should be able to upgrade our nodes to k8s 1.33! Specifically, 1.33.1 as the latest patch release of 1.33 branch.

Given we are on k8s 1.32 at the moment, we should review the [release notes for k8s 1.33](https://kubernetes.io/blog/2025/04/23/kubernetes-v1-33-release/) to understand if there's any deprecations or removals that would impact the upgrade. If so _we should attempt to mitigate these now_ by upgrading resource API versions/etc.

Talos does a bit of a job at double checking the k8s upgrade won't break the cluster, but it isn't foolproof. Checking and mitigating now is the best option.

The process is outlined here: https://www.talos.dev/v1.10/kubernetes-guides/upgrading-kubernetes/

## Performing the upgrade
This is performed on the entire cluster all at once, and is non-distruptive to workloads.

Talos offers the `talosctl upgrade-k8s` CLI command that manages the entire process for us, so once you are ready, we just need to run:
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig --nodes 192.168.77.70 upgrade-k8s --to 1.33.1
```

As always, you can open `talosctl dmesg` on another terminal on the CP nodes 192.168.77.70 to keep tabs on the progress (it's just for that node, but works as an overall progress indicator too, even though the CLI command will tell you as well):
```
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.70 dmesg -f
```

The upgrade process is roughly:
* Pre-pull all the required images onto each node
   * So the upgrade itself doesn't need to wait
* Upgrade each k8s component one by one!
* The longest part of the process seems to be this FS unmount step that takes a few minutes, the rest is pretty quick
* After upgrading all the container images it updates a few manifests
* All done!

You can now verify the version across all your nodes:
```
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION   CONTAINER-RUNTIME
talos-e45f019d4ca8   Ready    <none>          69d   v1.33.1   192.168.77.71   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4d95   Ready    <none>          69d   v1.33.1   192.168.77.72   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e45f019d4e19   Ready    control-plane   69d   v1.33.1   192.168.77.70   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
talos-e8ff1ed8884c   Ready    <none>          69d   v1.33.1   192.168.77.73   <none>        Talos (v1.10.3)   6.12.28-talos    containerd://2.0.5
```

Rince and repeat as required to keep upgrading. Ensure you review the release notes for any breaking changes that require fixing before the upgrade!
