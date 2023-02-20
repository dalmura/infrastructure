# Configuring Sidero to onboard new Servers

## Server Classes
First before onboarding anything, we need to figure out `ServerClasses`. These are groupings of server hardware that are of a common spec.

A few examples of these are:
* `rpi4.4gb.arm64`, `rpi4.8gb.arm64`, `dell.r320.amd64` are examples of ServerClasses that target specific hardwre
* `t4.small`, `m5.xlarge`, `r6a.6xlarge` are examples of ServerClasses that are more generic

In order for a Server to match to a ServerClass it needs to have a common attribute in the ServerClass' `qualifiers` and `selectors`.

An example Server's available qualifiers might look like:
```
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 describe server 00d03115-0000-0000-0000-e45f019d4e19 | yq .Spec
Accepted: false
Cpu:
  Manufacturer: Broadcom
  Version: BCM2711 (ARM Cortex-A72)
Hostname: 192.168.77.157
System:
  Family: Raspberry Pi
  Manufacturer: Raspberry Pi Foundation
  Product Name: Raspberry Pi 4 Model B
  Serial Number: 0000E45F019D4E19
  Sku Number: 0000000000D03115
  Version: D03115
```

This would allow us to build a ServerClass with the following `qualifiers` to match the above:
```
apiVersion: metal.sidero.dev/v1alpha1
kind: ServerClass
metadata:
  name: rpi4.8gb.arm64
spec:
  qualifiers:
    systemInformation:
      - productName: Raspberry Pi 4 Model B
        version: D03115
```

Unfortunately we cannot differentiate between 4GB RAM models and 8GB RAM models easily in Sidero v0.5 due to lack of comprehensive attributes exposed, but that will change with v0.6 having a lot more attributes available.

We use the `productName` above to ensure our `version` list is correct, to avoid if another manufacturer decided to use the name `version` value(s). We end up having 2x ServerClasses with 8gb and 4gb versions.

## Environments
Determine the kernel args that are send to the device, which version of Talos to boot and the kernel args sent to it, architecture specific.

The `default` Environment is specific to the amd64 architecture. So we've get a 'arm64' variant as well, specialised for the rpi hardware.

In order to find the specific RPi args, I simply burn an sdcard with the right Talos image then looked at the `grub/grub.cfg` in the 3rd partition of the sdcard.

```
apiVersion: metal.sidero.dev/v1alpha1
kind: Environment
metadata:
  name: rpi-arm64
spec:
  kernel:
    url: https://github.com/siderolabs/talos/releases/download/v1.3.0/vmlinuz-arm64
    args:
      - talos.platform=metal
      ...
      other kernel args
      ...
      - talos.board=rpi_generic
  initrd:
    url: https://github.com/siderolabs/talos/releases/download/v1.3.0/initramfs-arm64.xz
```

The Environment is set from the ServerClass so expanding on the above example:
```
apiVersion: metal.sidero.dev/v1alpha1
kind: ServerClass
metadata:
  name: rpi4.8gb.arm64
spec:
  qualifiers:
    systemInformation:
      - productName: Raspberry Pi 4 Model B
        version: D03115
  environmentRef:
    name: rpi-arm64
```

## Applying Everything
```bash
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f sidero/environments.yaml
environment.metal.sidero.dev/rpi-arm64 created

% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f sidero/serverclasses.yaml
serverclass.metal.sidero.dev/rpi4.4gb.arm64 created
serverclass.metal.sidero.dev/rpi4.8gb.arm64 created
```

## Servers
There is a unique instance for every piece of hardware that Sidero has booted and knows about.

These first need to be 'accepted' before they are able to be allocated to clusters.

We also at this stage label the servers with any additional metadata. To do this we save the servers state out to the git repo and keep track of it there.

```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get servers -o wide
NAME                                   HOSTNAME         BMC IP   ACCEPTED   CORDONED   ALLOCATED   CLEAN   POWER   AGE
00d03115-0000-0000-0000-e45f019d4ca8   192.168.77.151            true                              true    on      20h
00d03115-0000-0000-0000-e45f019d4e19   192.168.77.152            true                              true    on      19h


# We can then save individual servers to files
mkdir sidero/servers/
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get server 00d03115-0000-0000-0000-e45f019d4ca8 -o yaml > sidero/servers/00d03115-0000-0000-0000-e45f019d4ca8.yaml
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get server 00d03115-0000-0000-0000-e45f019d4e19 -o yaml > sidero/servers/00d03115-0000-0000-0000-e45f019d4e19.yaml
```

From there you'll want to prune down the files to just contain the below bits that we want to change.

Accept the server so Sidero will wipe and make it available for allocation:
```yaml
spec:
  accepted: true
```

Apply any labels base on, eg. region, zone, etc
```yaml
metadata:
  labels:
    region: au-mel
    zone: indigo
    serial: 653b9d59
```

This will result in a file looking roughly like this:
```yaml
metadata:
  labels:
    region: au-mel
    zone: indigo
    serial: 653b9d59
spec:
  accepted: true
```

These can the be patched back to the Server:
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 patch server 00d03115-0000-0000-0000-e45f019d4ca8 --patch-file sidero/servers/00d03115-0000-0000-0000-e45f019d4ca8.yaml --type merge
server.metal.sidero.dev/00d03115-0000-0000-0000-e45f019d4ca8 patched

kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 patch server 00d03115-0000-0000-0000-e45f019d4e19 --patch-file sidero/servers/00d03115-0000-0000-0000-e45f019d4e19.yaml --type merge
server.metal.sidero.dev/00d03115-0000-0000-0000-e45f019d4e19 patched
```

You can validate the Servers have been correctly grouped by ServerClass:
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get serverclasses
NAME             AVAILABLE                                                                         IN USE   AGE
any              ["00d03115-0000-0000-0000-e45f019d4ca8","00d03115-0000-0000-0000-e45f019d4e19"]   []       2d
rpi4.4gb.arm64   []                                                                                []       45h
rpi4.8gb.arm64   ["00d03115-0000-0000-0000-e45f019d4ca8","00d03115-0000-0000-0000-e45f019d4e19"]   []       45h
```

Here we can see there is 2x `AVAILABLE` Servers both matching the `rpi4.8gb.arm64` ServerClass.

You now have one or more servers available to use in creating new k8s clusters!
