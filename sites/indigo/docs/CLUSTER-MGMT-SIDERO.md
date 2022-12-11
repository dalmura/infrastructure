# Setting up Sidero on dal-k8s-mgmt-1

Following https://www.sidero.dev/v0.5/guides/sidero-on-rpi4/#installing-sidero

We need to configure the following aspects of the DHCP server to respond with:
* Hardcoded string the rPi requires "Raspberry Pi Boot" (Option 43)
* Hardcoded string not strictly required but best practice "PXEClient" (Option 60)
* IP address of the server to boot from (Option 66)
* Filename/URL of the file to boot (Option 67)

Mikrotik since v7.4 (and fixed properly in v7.6) have implemented the ability to selectively offer different options above based on client capabilities (arm64 vs amd64), this is called the 'Generic matcher'.

How to configure this can be found in [Mikrotik's documentation](https://help.mikrotik.com/docs/display/ROS/DHCP#DHCP-Genericmatcher)

There is also a [thread here](https://forum.mikrotik.com/viewtopic.php?t=188290) and a [thread here](https://forum.mikrotik.com/viewtopic.php?t=95674) on Mikrotik's forum covering the finer details of this (as their doco is currently lacking)

```bash
/ip/dhcp-server/matcher
add name="arch-rpi4"   code=93 value="0x0000" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-rpi4-default
#add name="arch-rpi4"   code=60 value="'PXEClient:Arch:00000:UNDI:002001'" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=arch-rpi4-default

/ip/dhcp-server/option/sets
add name="boot-rpi4" options=boot-rpi4-43,boot-rpi4-60,boot-rpi4-66,boot-rpi4-67

/ip/dhcp-server/option
add name="boot-rpi4-43" code=43 value="s'Raspberry Pi Boot'"
add name="boot-rpi4-60" code=60 value="s'PXEClient'"
add name="boot-rpi4-66" code=66 value="s'192.168.77.130'"
add name="boot-rpi4-67" code=67 value="s'ipxe.efi'"
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

Wait until you see the `sidero-controller-manager` pods come up
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A
NAMESPACE       NAME                                         READY   STATUS              RESTARTS      AGE
...
sidero-system   sidero-controller-manager-5d6754fcfb-drv4h   0/4     ContainerCreating   0             51s
...

# You'll notice the k8s API Server stop responding
# This is the sidero-controller-manager joining the host network
# It will cause a few pods to restart... just wait a minute!

kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A
NAMESPACE       NAME                                         READY   STATUS    RESTARTS      AGE
...
sidero-system   caps-controller-manager-fd48bf9b4-xvsqm      1/1     Running   3 (43s ago)   2m24s
sidero-system   sidero-controller-manager-5d6754fcfb-drv4h   4/4     Running   9 (46s ago)   2m23s
...
```

Now dal-k8s-mgmt-1 is a Sidero management cluster, able to support PXE booting!

You should now be able to at least get an rpi4 able to attempt to network boot from Sidero now (it won't work properly until you do the below, but you should see logs in the sidero-controller-manager pod)

```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 logs -f sidero-controller-manager-5d6754fcfb-drv4h -n sidero-system
Defaulted container "manager" out of: manager, siderolink, serverlogs, serverevents
1.6707336924300556e+09	INFO	controller-runtime.metrics	Metrics server is starting to listen	{"addr": "127.0.0.1:8080"}
1.6707336924350235e+09	INFO	setup	starting TFTP server
1.6707336924351463e+09	INFO	setup	starting iPXE server
...
2022/12/11 04:44:35 HTTP GET /boot.ipxe 127.0.0.1:35448
2022/12/11 04:44:45 HTTP GET /boot.ipxe 127.0.0.1:35462  <--- these are healthchecks
2022/12/11 04:44:45 HTTP GET /boot.ipxe 127.0.0.1:35448
...
2022/12/11 04:56:55 open /var/lib/sidero/tftp/09b92bda/start4.elf: no such file or directory   <--- these are the rpi4 attempting to network boot!
2022/12/11 04:56:55 open /var/lib/sidero/tftp/09b92bda/start.elf: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/config.txt: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/pieeprom.sig: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/recover4.elf: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/recovery.elf: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/start4.elf: no such file or directory
2022/12/11 04:56:55 open /var/lib/sidero/tftp/start.elf: no such file or directory
```

You'll notice a specific pattern of folder structures the rpi4 follows when attemping to network boot. If you don't see the rpi4 logs above please double check your DHCP settings.


## Setting up Sidero to support Raspberry Pi 4 servers

This guide follows https://www.sidero.dev/v0.5/guides/rpi4-as-servers/

RPi4's are special in that they have a fixed 'folder structure' they attempt to network boot from, as well as not fully supporting a PXE boot client. So this means we need to:
* Patch Sidero to offer the right 'folder structure' (see above logs for what this looks like!)
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

# Will be available at
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
pod "sidero-controller-manager-5d6754fcfb-rrzlr" deleted
```

You should now have a patched Sidero that supports RPi4s!
