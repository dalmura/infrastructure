# Configuring Sidero to onboard new Servers

## Servers
There is a unique instance for every piece of hardware that Sidero has booted and knows about.

These first need to be 'accepted' before they are able to be allocated to clusters.

```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 edit server 00d03115-0000-0000-0000-e45f019d4e19

# Update
accepted: true
```

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
      - version: D03115
  bootFromDiskMethod: ipxe-sanboot
```

Unfortunately we cannot differentiate between 4GB RAM models and 8GB RAM models easily in Sidero v0.5 due to lack of comprehensive attributes exposed, but that will change with v0.6 having a lot more attributes available.

We use the `version` key above and build a list of all 8GB versions, then another `ServerClass` with a list of 4GB versions, but it'd be weird if some other manufacturer started populating a similar `Version` field for another product entirely...

## Environments
Determine the kernel args that are send to the device, which version of Talos to boot and the kernel args sent to it, architecture specific.

The `default` Environment is specific to the amd64 architecture. So we've get a 'arm64' variant as well, specialised for the rpi hardware.

In order to find the specific RPi args, I simply burn an sdcard with the right Talos image then looked at the `grub/grub.cfg` in the 3rd partition of the sdcard.

```
apiVersion: metal.sidero.dev/v1alpha1
kind: Environment
metadata:
  name: rpi-arm64
  namespace: sidero
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
      - version: D03115
  bootFromDiskMethod: ipxe-sanboot
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
