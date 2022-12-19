# Configuring Sidero to onboard new Servers

First before onboarding anything, we need to figure out `ServerClasses`. These are groupings of server hardware that are of a common spec.

A few examples of these are:
* `rpi4.4gb.arm`, `rpi4.8gb.arm`, `dell.r320.amd64` are examples of ServerClasses that target specific hardwre
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
  name: rpi4.8gb.arm
spec:
  qualifiers:
    systemInformation:
      - version: D03115
  bootFromDiskMethod: ipxe-sanboot
```

Unfortunately we cannot differentiate between 4GB RAM models and 8GB RAM models easily in Sidero v0.5 due to lack of comprehensive attributes exposed, but that will change with v0.6 having a lot more attributes available.

We could use the `version` key and build a list of all 8GB versions, then another `ServerClass` with a list of 4GB versions, but it'd be weird if some other manufacturer started populating a similar `Version` field for another product entirely...
