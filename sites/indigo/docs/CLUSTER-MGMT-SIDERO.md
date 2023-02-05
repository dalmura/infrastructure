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
/ip/dhcp-server/option
add name="boot-rpi4-43" code=43 value="s'Raspberry Pi Boot'"
add name="boot-rpi4-60" code=60 value="s'PXEClient'"
add name="boot-rpi4-66" code=66 value="s'192.168.77.130'"
add name="boot-rpi4-67" code=67 value="s'ipxe.efi'"

/ip/dhcp-server/option/sets
add name="boot-rpi4" options=boot-rpi4-43,boot-rpi4-60,boot-rpi4-66,boot-rpi4-67

/ip/dhcp-server/matcher
add name="arch-rpi4-native"    code=93 value="0x0000"                           server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=boot-rpi4
add name="arch-rpi4-pxeclient" code=60 value="PXEClient:Arch:00000:UNDI:002001" server=servers-staging-dchp address-pool=servers-staging-dhcp option-set=boot-rpi4
```

Now we install Sidero dal-k8s-mgmt-1:
```bash
export SIDERO_CONTROLLER_MANAGER_AUTO_BMC_SETUP=false
export SIDERO_CONTROLLER_MANAGER_API_ENDPOINT="192.168.77.140"
export SIDERO_CONTROLLER_MANAGER_SIDEROLINK_ENDPOINT="192.168.77.140"

% clusterctl init --kubeconfig=kubeconfigs/dal-k8s-mgmt-1 -b talos -c talos -i sidero
Fetching providers
Installing cert-manager Version="v1.10.1"
Waiting for cert-manager to be available...
Installing Provider="cluster-api" Version="v1.3.1" TargetNamespace="capi-system"
Installing Provider="bootstrap-talos" Version="v0.5.6" TargetNamespace="cabpt-system"
Installing Provider="control-plane-talos" Version="v0.4.11" TargetNamespace="cacppt-system"
Installing Provider="infrastructure-sidero" Version="v0.5.7" TargetNamespace="sidero-system"

Your management cluster has been initialized successfully!

You can now create your first workload cluster by running the following:

  clusterctl generate cluster [name] --kubernetes-version [version] | kubectl apply -f -

```

Wait until you see the `sidero-controller-manager` pods come up
```bash
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A
NAMESPACE       NAME                                         READY   STATUS              RESTARTS      AGE
...
sidero-system   sidero-controller-manager-5d6754fcfb-drv4h   0/4     ContainerCreating   0             51s
...

# You'll notice the k8s API Server stop responding around this time
# This is some of the talos static pods inc the kube-apiserver being updated
# It will cause a few pods to restart... just wait a minute!

% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A
NAMESPACE       NAME                                         READY   STATUS    RESTARTS      AGE
...
sidero-system   caps-controller-manager-fd48bf9b4-xvsqm      1/1     Running   3 (43s ago)   2m24s
sidero-system   sidero-controller-manager-5d6754fcfb-drv4h   4/4     Running   9 (46s ago)   2m23s
...
```

Sidero is now running, but it's isolated to inside the cluster, we now need to expose it via a k8s Service and MetalLB!

```bash
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 apply -f patches/dal-k8s-mgmt-1-sidero-service.yaml
service/sidero-controller-manager created
```

Now dal-k8s-mgmt-1 is a Sidero management cluster, able to support PXE booting!

You can verify this by attemping to download the ipxe file directly from Sidero.

```bash
% curl -I http://192.168.77.140:8081/tftp/ipxe-arm64.efi
HTTP/1.1 200 OK
Accept-Ranges: bytes
Content-Length: 1029632
Content-Type: application/octet-stream
Last-Modified: Sat, 17 Dec 2022 03:29:30 GMT
Date: Sun, 18 Dec 2022 05:47:09 GMT
```

You should now be able to at least get an rpi4 able to attempt to network boot from Sidero now (it won't work properly until you do the below, but you should see logs in the sidero-controller-manager pod)

```bash
% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get pods -A | grep 'sidero-controller-manager'
sidero-system    sidero-controller-manager-54cd5d79f4-hcmrf   4/4     Running   0              115m

% kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 logs -f sidero-controller-manager-54cd5d79f4-hcmrf -n sidero-system
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

```bash
# Before building the pkgs image, ensure your laptop/pc is setup
% docker buildx create --use

# Ensure this works for your Personal Access Token with packages:write
% CR_PAT='mySecretToken'
% echo $CR_PAT | docker login ghcr.io -u <github username> --password-stdin

# Clone the pkgs repo
% git clone git@github.com:siderolabs/pkgs.git siderolabs-pkgs
% cd siderolabs-pkgs

# Find the commit of the talos version we'll boot
# Go to https://github.com/siderolabs/talos/blob/v1.3.3/Makefile#L17
# Find: PKGS ?= v1.3.0-10-g6f6a030
# Commit ID is '6f6a030'
% git checkout 6f6a030

# The below is largely following the guide linked above
% mkdir -p raspberrypi4-uefi/serials

% vim raspberrypi4-uefi/pkg.yaml
# Copy in the contents from the linked guide with the following changes
# url: https://github.com/pftf/RPi4/releases/download/v1.34/RPi4_UEFI_Firmware_v1.34.zip
# destination: RPi4_UEFI_Firmware.zip
# sha256: ff4f5ce208f49f50e38e9517430678f3b6a10327d3fd5ce4ce434f74d08d5b76
# sha512: f095d6419066e9042f71716865ea495991a4cc4d149ecb514348f397ae2c617de481aead6e507b7dcec018864c6f941b020903c167984accf25bf261010385f7

# Burn RPi4_UEFI_Firmware.zip to an SD Card and boot the rpi4(s) you plan to use as nodes for dal-k8s-core-1 cluster
# Get to the main main and:
# 1. Device Manager => Raspberry Pi Configuration => CPU Configuration => Max
# 2. Device Manager => Raspberry Pi Configuration => Display Configuration => Only select Virtual 800x600
# 3. Device Manager => Raspberry Pi Configuration => Advanced Configuration => Limit RAM to 3 GB => Disabled
# 4. Boot Maintenance Manager => Boot Options => Delete Boot Option => Delete all apart from UEFI PXEv4
# 5. reset => Turn off rpi and put SDCARD back in laptop

# Extract `RPI_EFI.fd` from the SDCARD and store it in `raspberrypi4-uefi/serials/<device serial>/RPI_EFI.fd
# You can find the serial from your sidero-controller-manager logs from above!
mkdir raspberrypi4-uefi/serials/09b92bda/
cp /Volumes/SDCARD/RPI_EFI.fd raspberrypi4-uefi/serials/09b92bda/

# Build the pkgs image and push to our ghcr org
# This step fails if you're on a different architecture and you've not done the 'buildx' above
make PLATFORM=linux/arm64 USERNAME=dalmura PUSH=true TARGETS=raspberrypi4-uefi

# Will be available at
docker pull ghcr.io/dalmura/raspberrypi4-uefi:v1.3.0-10-g6f6a030
```

Update the patch `patches/dal-k8s-mgmt-1-sidero-rpi4.yaml` with the latest image tag from above:
```
spec:
  template:
    spec:
      volumes:
        - name: tftp-folder
          emptyDir: {}
      initContainers:
      - image: ghcr.io/dalmura/raspberrypi4-uefi:v1.3.0-10-g6f6a030
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

# Apply patch to existing Sidero install:
```
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 -n sidero-system patch deployments.apps sidero-controller-manager --patch-file patches/dal-k8s-mgmt-1-sidero-rpi4.yaml
deployment.apps/sidero-controller-manager patched
```

You should now have a patched Sidero that supports rpi4s!

This will allow the rpi4 to:
* Recieve information from the DHCP server about where to boot from
* Download & boot the PXEClient from our Sidero server
* Use the PXEClient and attempt to boot the Sidero agent

To double check it's all working, when the node successfully downloads the Sidero agent and reboots you should be able to see the new Server via:
```bash
kubectl --kubeconfig kubeconfigs/dal-k8s-mgmt-1 get servers -o wide
NAME                                   HOSTNAME         BMC IP   ACCEPTED   CORDONED   ALLOCATED   CLEAN   POWER   AGE
00d03115-0000-0000-0000-e45f019d4e19   192.168.77.157            false                                     on      52m
```

You can now start creating workload clusters!
