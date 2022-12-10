# Setting up Sidero on dal-k8s-mgmt-1

Following https://www.sidero.dev/v0.5/guides/sidero-on-rpi4/#installing-sidero

Configure the `SERVERS_STAGING` DHCP server to reference dal-k8s-mgmt-1's VIP: `192.168.77.130`

We need to configure the following aspects of the DHCP server to respond with:
* Hardcoded string the rPi requires "Raspberry Pi Boot" (Option 43)
* IP address of the server to boot from (Option 66)
* Filename/URL of the file to boot (Option 67)

Mikrotik since v7.4 (and fixed properly in v7.6) have implemented the ability to selectively offer different options above based on client capabilities (arm64 vs amd64), this is called the 'Generic matcher'.

How to configure this can be found in [Mikrotik's documentation](https://help.mikrotik.com/docs/display/ROS/DHCP#DHCP-Genericmatcher)

There is also a [thread here](https://forum.mikrotik.com/viewtopic.php?t=188290) and a [thread here](https://forum.mikrotik.com/viewtopic.php?t=95674) on Mikrotik's forum covering the finer details of this (as their doco is currently lacking)

```bash
/ip/dhcp-server/matcher
add name="arch-rpi4"   code=93 value="0x0000" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-rpi4-default
#add name="arch-rpi4"   code=60 value="'PXEClient:Arch:00000:UNDI:002001'" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-rpi4-default
add name="arch-arm64"  code=93 value="0x000b" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-arm64-default
add name="arch-uefi64" code=93 value="0x0007" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-uefi64-default
add name="arch-uefi32" code=93 value="0x0006" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-uefi32-default

/ip/dhcp-server/option/sets
add name="arch-rpi4-default"   options=boot-rpi4-43,boot-rpi4-60,boot-rpi4-66,boot-rpi4-67
add name="arch-arm64-default"  options=boot-arm66-66,boot-arm66-67
add name="arch-uefi64-default" options=boot-uefi64-66,boot-uefi64-67
add name="arch-uefi32-default" options=boot-uefi32-66,boot-uefi32-67
add name="arch-bios-default"   options=boot-bios-66,boot-bios-67

/ip/dhcp-server/option
add name="boot-rpi4-43" code=43 value="'Raspberry Pi Boot'"
add name="boot-rpi4-60" code=60 value="'PXEClient'"
add name="boot-rpi4-66" code=66 value="192.168.77.130"
add name="boot-rpi4-67" code=67 value="'ipxe.efi'"

add name="boot-arm64-66" code=66 value="192.168.77.130"
add name="boot-arm64-67" code=67 value="'ipxe-arm64.efi'"

add name="boot-uefi64-66" code=66 value="192.168.77.130"
add name="boot-uefi64-67" code=67 value="'ipxe64.efi'"

add name="boot-uefi32-66" code=66 value="192.168.77.130"
add name="boot-uefi32-67" code=67 value="'ipxe.efi'"

add name="boot-bios-66" code=66 value="192.168.77.130"
add name="boot-bios-67" code=67 value="'ipxe.pxe'"
```

Now we install Sidero dal-k8s-mgmt-1:
```bash
export SIDERO_CONTROLLER_MANAGER_HOST_NETWORK=true
export SIDERO_CONTROLLER_MANAGER_API_ENDPOINT="192.168.77.130"
export SIDERO_CONTROLLER_MANAGER_SIDEROLINK_ENDPOINT="192.168.77.130"

clusterctl init --kubeconfig=kubeconfigs/dal-k8s-mgmt-1 -b talos -c talos -i sidero

# You'll see the following logs
Fetching providers
Installing cert-manager Version="v1.9.1"
Waiting for cert-manager to be available...
Installing Provider="cluster-api" Version="v1.2.5" TargetNamespace="capi-system"
Installing Provider="bootstrap-talos" Version="v0.5.5" TargetNamespace="cabpt-system"
Installing Provider="control-plane-talos" Version="v0.4.10" TargetNamespace="cacppt-system"
Installing Provider="infrastructure-sidero" Version="v0.5.6" TargetNamespace="sidero-system"

Your management cluster has been initialized successfully!

You can now create your first workload cluster by running the following:

  clusterctl generate cluster [name] --kubernetes-version [version] | kubectl apply -f -
```
Now dal-k8s-mgmt-1 is a Sidero management cluster, able to support PXE booting!


## Setting up Sidero to support Raspberry Pi 4 servers

This guide follows https://www.sidero.dev/v0.5/guides/rpi4-as-servers/

RPi4's are special in that they have a fixed 'folder structure' they attempt to network boot from, as well as not fully supporting a PXE boot client. So this means we need to:
* Patch Sidero to offer the right 'folder structure'
* Offer a PXE Client to network boot from, which *then* PXE boots Sidero's image

You'll need to go and [follow the steps in here](https://www.sidero.dev/v0.5/guides/rpi4-as-servers/#uefi--rpi4) which should result in a `RPI_EFI.fd` file (binary) that you'll be able to copy into your below image.

```
# Before building the pkgs image, ensure your laptop/pc is setup
docker buildx create --use

# Ensure this works for your Personal Access Token with packages:write
CR_PAT='mySecretToken'
echo $CR_PAT | docker login ghcr.io -u <github username> --password-stdin

# Clone the pkgs repo
git clone git@github.com:siderolabs/pkgs.git siderolabs-pkgs
cd siderolabs-pkgs

# Find the commit of the talos version we'll boot
# Go to https://github.com/siderolabs/talos/blob/v1.2.7/Makefile#L17
# Find: PKGS ?= v1.2.0-20-g23c0dfd
# Commit ID is '23c0dfd'
git checkout 23c0dfd

# Build the pkgs image and push to our ghcr org
# This step fails if you're on a different architecture and you've not done the 'buildx' above
make PLATFORM=linux/arm64 USERNAME=dalmura PUSH=true TARGETS=raspberrypi4-uefi

# Will be available as:
docker pull ghcr.io/dalmura/raspberrypi4-uefi:v1.2.0-20-g23c0dfd
```

Build the sidero patch
```
spec:
  template:
    spec:
      volumes:
        - name: tftp-folder
          emptyDir: {}
      initContainers:
      - image: ghcr.io/dalmura/raspberrypi4-uefi:v1.2.0-19-g23c0dfd
        imagePullPolicy: Always
        name: tftp-folder-setup
        command:
          - cp
        args:
          - -r
          - /tftp
          - /var/lib/sidero/
        volumeMounts:
          - mountPath: /var/lib/sidero/tftp
            name: tftp-folder
      containers:
      - name: manager
        volumeMounts:
          - mountPath: /var/lib/sidero/tftp
            name: tftp-folder
```

This is available in `patches/dal-k8s-mgmt-1-sidero.yaml`

# Apply patch to existing Sidero install:
```
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 -n sidero-system patch deployments.apps sidero-controller-manager --patch "$(cat patches/dal-k8s-mgmt-1-sidero.yaml)"
deployment.apps/sidero-controller-manager patched
```

Because it's host networking you'll need to delete the existing one
```
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A
NAMESPACE       NAME                                         READY   STATUS    RESTARTS      AGE
...
sidero-system   sidero-controller-manager-5d6754fcfb-rrzlr   4/4     Running   9 (34h ago)   34h
sidero-system   sidero-controller-manager-cf7bb88db-ksmwb    0/4     Pending   0             2m48s
...


kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 describe pod sidero-controller-manager-cf7bb88db-ksmwb -n sidero-system
....
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  3m3s  default-scheduler  0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.


kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 delete pod sidero-controller-manager-5d6754fcfb-rrzlr -n sidero-system
```

You should now have a patched Sidero that supports RPi4's
