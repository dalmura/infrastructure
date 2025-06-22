# Adding a new Kernel Module to Talos

## HailoRT Driver

This module supports the Hailo-8L AI Accelerator M.2 PCIe device.

Hailo provide a [Github repo](https://github.com/hailo-ai/hailort-drivers) that contains the source to build the kernel module along with supporting files.

### Talos `pkgs` repo

This repo contains (among other things) the Linux kernel, and all the Linux kernel modules. All modules loaded into the Talos Linux kernel are required to be signed by the same key, which is created at 'build time' and discarded after.

Due to this, we cannot easily build a new kernel module in isolation, we need to build the 'whole package' aka the Talos Linux kernel, and all required kernel modules. Referencing them all together when setting up a new node w/Talos Linux.

PR to add in Hailo-8L kernel module pkg: https://github.com/siderolabs/pkgs/pull/1262

Once the above PR was merged, the [`hailort-pkg`](https://github.com/siderolabs/pkgs/pkgs/container/hailort-pkg) is now built and included in the underlying kernel modules for Talos Linux. You can see all available version (image tags), which will all be linked to a Linux kernel build!

For example:
* `kernel`'s version [v1.11.0-alpha.0-35-g0aaa07a](https://github.com/siderolabs/pkgs/pkgs/container/kernel/435163959?tag=v1.11.0-alpha.0-35-g0aaa07a)
* `hailort-pkg`'s version [v1.11.0-alpha.0-35-g0aaa07a](https://github.com/siderolabs/pkgs/pkgs/container/hailort-pkg/435164997?tag=v1.11.0-alpha.0-35-g0aaa07a)

Both the above are built together and signed with the same key, thus compatible when being loaded on a node.

### Talos `extension` repo

This repo contains the extension images that can be baked into a [Talos Linux Image Factory](https://factory.talos.dev/) 'Talos Linux' release.

For a kernel module, the extension config in here will need to reference the `pkgs` repo's entry. Specifically referencing the image tags over in the `pkgs` repo for the kernel/modules/etc.

This is the reason why we can't just build the kernel module in the `extension` repo by itself and skip the `pkgs` repo, because the kernel is built over there, not here.

For example, in the above factory, when you select Talos Linux 1.10 and the `i915` extension, it needs to pull in the version of the `i915` extension that was built with the kernel that is used in Talos Linux 1.10, it cannot be any other instance of the `i915` extension.

PR to add in the Hailo-8L kernel module extension: https://github.com/siderolabs/extensions/pull/731

### Setup the new module in `pkgs` repo

Fork and checkout the repo:
```bash
# Fork on github

git clone https://github.com/your-user/your-pkgs-fork-name.git talos-pkgs
cd talos-pkgs
```

Create a new folder for your module in the root of the repo, eg. `hailort`
```
mkdir hailort
cd hailort
```

Create a `pkg.yaml` file in that with the steps to build the kernel module:
```
$ cat pkg.yaml
name: hailort-pkg
variant: scratch
shell: /bin/bash
dependencies:
  - stage: base
  - stage: kernel-build
steps:
  - sources:
      - url: https://github.com/hailo-ai/hailort-drivers/archive/refs/tags/v{{ .hailort_version }}.tar.gz
        destination: hailort-driver.tar.gz
        sha256: "{{ .hailort_sha256 }}"
        sha512: "{{ .hailort_sha512 }}"
    env:
      ARCH: {{ if eq .ARCH "aarch64"}}arm64{{ else if eq .ARCH "x86_64" }}x86_64{{ else }}unsupported{{ end }}
    prepare:
      - |
        tar xf hailort-driver.tar.gz --strip-components=1
      - |
        mkdir -p /rootfs/usr/lib/modules/$(cat /src/include/config/kernel.release) /rootfs/etc/udev/rules.d/
    build:
      - |
        cd linux/pcie
        make -j $(nproc) KERNEL_DIR=/src/ all
    install:
      - |
        cd linux/pcie
        make -j $(nproc) -C /src M=$(pwd) modules_install INSTALL_MOD_PATH=/rootfs/usr INSTALL_MOD_DIR=kernel/drivers/misc INSTALL_MOD_STRIP=1
        cp 51-hailo-udev.rules /rootfs/etc/udev/rules.d/51-hailo-udev.rules
    test:
      - |
        # https://www.kernel.org/doc/html/v4.15/admin-guide/module-signing.html#signed-modules-and-stripping
        find /rootfs/usr/lib/modules -name '*.ko' -exec grep -FL '~Module signature appended~' {} \+
      - |
        fhs-validator /rootfs
finalize:
  - from: /rootfs
    to: /
```

The above steps happen as part of a bigger process where the underlying kernel has already been build and its artifacts (and crypto signing key) are all available locally on the build machine.

My assumptions from reading around are:
* The `/rootfs` folder is the new container image produced for our kernel module, to be used when building the system extension later on.
* The `/src` folder contains the (already built) kernel build artifacts
* The `/` directory (aka $PWD) is the current temporary build context for these build steps, and won't be included in any final outputs

The above script should be creating in the `/rootfs` directory structure:
* The '.ko' kernel module
* A `udev` rules file to correctly set the permissions on the device for everyone to use

Apart from the above set also update the following files:
* `.kres.yaml`
   * Insert our package name after `kernel` list item
* `Makefile`
   * Updating the TARGETS to include our `hailort-pkg` package in the default build process
* `Pkgfile`
   * This controls the version of the HailoRT drivers to use
   * We've got a comment controlling Renovate to raise PRs to keep the dependency up to date

After setting up all of the above in a branch on your fork, you're ready to setup the build environment and start building.

See the [HailoRT PR](https://github.com/siderolabs/pkgs/pull/1262) for more context around the files and their contents.
And the [follow up PR](https://github.com/siderolabs/pkgs/pull/1267) fixing the missing firmware blob.

### Setting up build environment

You'll need to have docker installed, I don't think there's much leeway in choosing your container toolset.

Setup buildx:
```
docker buildx create --driver docker-container  --driver-opt network=host --name local1 --buildkitd-flags '--allow-insecure-entitlement security.insecure' --use
```

You can test this has worked by building `talosctl`:
```
git clone git@github.com:siderolabs/talos.git
cd talos
make talosctl
```

Start a local registry for all the intermediate container images:
```
docker run -d -p 5005:5000 --restart always --name local registry:2
```

Should now be setup to start building the various bits and pieces!

### Build the `pkgs` kernel and module

Ensure your local fork/repo/checkout of `pkgs` contains the new module.

Build the kernel and your module:
```
make kernel hailort-pkg REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64
```

The above will build the Linux kernel as well as the HailoRT module, this will result in 2x container images pushed into the local registry.
Assuming you have checked out the main branch of your pkgs fork, it should have a git tag already attached.

Make note of the container URIs:
```
KERNEL_URI='127.0.0.1:5005/michael-robbins/kernel:v1.11.0-alpha.0-38-g4ac3fee@sha256:42be987c65f2b239069e10e791994c8afac29958b59784d8aadc1a870cdd7c1a'
HAILORT_PKG_URI='127.0.0.1:5005/michael-robbins/hailort-pkg:v1.11.0-alpha.0-38-g4ac3fee@sha256:ae80f805b0b7cf537f6ba96a4ef47a399d994d60962c159a5e0ef4846351c8ce'
```

Now we've built the base kernel, and our Hailo package. Now we need to build the 'extension' that will use the built Hailo package.

Note, once the pkgs PR merges, the above URIs can also be updated to reference the proper siderolabs pkg URIs:
```
# eg. for an alpha 1.11 build
# note, you *must* use the same version tags between kernel and hailort due to crypto signing
KERNEL_URI='ghcr.io/siderolabs/kernel:v1.11.0-alpha.0-38-g4ac3fee'
HAILORT_PKG_URI='ghcr.io/siderolabs/hailort-pkg:v1.11.0-alpha.0-38-g4ac3fee'
```

### Build the `extensions`... extension!

Fork and checkout the repo:
```bash
# Fork on github

git clone https://github.com/your-user/your-extensions-fork-name.git talos-extensions
cd talos-extensions
```

The `hailort` extension will live in the `drivers/` folder of this repo.

Create a new folder for your module in the right subfolder, eg. `drivers/hailort`
```
cd drivers/

mkdir hailort
cd hailort
```

We'll need to create 4x files in here:
* `manifest.yaml`
   * Contains the extension metadata for the build system
* `pkg.yaml`
   * Contains the build steps for the extension
   * This is what will copy the built kernel module/etc out of our previous built image
* `README.md`
   * Explains the extension, including steps to verify it's working
* `vars.yaml`
   * Version of the kernel module image we built before

Along with these files, we'll need to modify these existing files in the repo root:
* `.kres.yaml`
   * Adding our extension into the default list to build
* `Makefile`
   * Adding our extension into the default list to build
* `Pkgfile`
   * The version of the kernel module we'll build against from the pkgs repo

See the [HailoRT PR](https://github.com/siderolabs/extensions/pull/731) for an overview of the file contents.

Note: `$HAILORT_PKG_URI` should be substituted with your above URI you noted down earlier

And to finally build the extension:
```
make hailort REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 PKGS_PREFIX=127.0.0.1:5005/michael-robbins PKGS=v1.11.0-alpha.0-38-g4ac3fee
```

The above sets the following extra vars:
* `PKGS_PREFIX` which is the 'source' of the PKGS images we use to build the extension
* `PKGS` is the tag (aka version) of the PKGS we build with, in this case it's the tag of the earlier `PKGS` build we did

Alternatively, if you've already merged the `pkgs` PR and you have an existing siderolabs/pkgs URIs for the kernel and new module, you can ignore the `PKGS_PREFIX` and use sideros main repo:
```
make hailort REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 PKGS=v1.11.0-alpha.0-38-g4ac3fee
```

This will give us an EXTENSION URI from the line 'pushing manifest for ...' to our local registry we set up earlier:
```
EXTENSION_URI='127.0.0.1:5005/michael-robbins/hailort:4.21.0@sha256:657da4fcd5d4b3b015f51ea3ffa82338461dc69657485a376cd39109d73fe17b'
```

You can then validate the above contains our kernel module and udev rules file by:
```
# The below uses podman, if you don't have that you'll need to google for a way to mount an image's FS locally...

# Ensure the below is set so podman can work with a local http registry
cat /etc/containers/registries.conf.d/localhost.conf

[[registry]]
location = "127.0.0.1:5005"
insecure = true

# Pull and mount the image
sudo podman pull "${EXTENSION_URI}"
sudo podman image mount "${EXTENSION_URI}"

# Which will print out a directory, save this
BASE_IMAGE_DIR='/var/lib/containers/storage/overlay/96533d82dce3373331b5555167e5b5506838f267242f9507afa8fd73b1725ffb/merged'

# Then you can easily explore it
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/

# Verify the `hailo_pci.ko` file exists, first checking the right kernel version
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/modules/
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/modules/6.12.31-talos/kernel/drivers/misc/

# Verify the `hailo8.fw` file exists
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/firmware/hailo/

# Verify the `51-hailo-udev.rules` file exists
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/udev/rules.d/
```

Checkout talos repo
```
git clone .... talos
cd talos
```

Build the `installer-base` and `imager` when building from scratch:
```
make installer-base imager PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PKG_KERNEL=${KERNEL_URI} PKGS=v1.11.0-alpha.0-38-g4ac3fee PUSH=true TAG=v1.11.0-alpha.0-38-g4ac3fee
```

The above PKGS and TAG are just the randomly picked 'latest available' from eg. https://github.com/siderolabs/pkgs/pkgs/container/fhs

Build the `installer-base` and `imager` when building from prebuilt:
```
make installer-base imager PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PKGS=v1.11.0-alpha.0-35-g0aaa07a PUSH=true TAG=v1.11.0-alpha.0-35-g0aaa07a
```

This will build the initial 'talos' installer image containing the kernel from the PKGS above. Ensure `TAG` above is set, otherwise the Makefile will default to tagging the image with the hash or another tag that will cause the below `make image-installer` command to fail.

The above will create 2x images, `installer-base` and `imager`:
* We'll save the `installer-base` below, minus the sha extension as it didn't match for some reason
* And `imager` will be derived as part of the next `make` command

Outputs:
```
BASE_TALOS_URI='127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-37-gfadf1e2'
```

Using the imager we'll build our system extension:
```
make image-installer REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins TAG=v1.11.0-alpha.0-37-gfadf1e2 IMAGER_ARGS="--base-installer-image=${BASE_TALOS_URI} --system-extension-image=${EXTENSION_URI}"
```

We need to specify the same username & tag as provided to `make installer-base imager` above as this `make image-installer` attempts to pull the produced `imager` image down and it all needs to match.

You can include multiple system extension images above by repeating the `--system-extension-image=${OTHER_EXTENSION_URI}` CLI flag as many times as required, remember other kernel modules must have been built with the same kernle/PKGS string, if not they won't work.

This will produce `_out/installer-amd64.tar`, this file is an image that we need to import back into docker and push to a registry we can test with.

If you're just quickly testing against a node immediately, you could use `ttl.sh` as your registry, otherwise ensure you have a registry you can write to.

For example if you want an ephemeral image to reference for 1h:
```
docker load -i _out/installer-amd64.tar

# Note down the image URI of the imported image from the output, eg:
$ docker load -i _out/installer-amd64.tar
810a8db95f85: Loading layer [==================================================>]  24.94MB/24.94MB
eaea0b97c0bf: Loading layer [==================================================>]  100.5MB/100.5MB
Loaded image: 127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-37-gfadf1e2

# Generate the UUID for the ttl.sh image
IMAGE_NAME=$(uuidgen)

# Tag and push the above $IMAGE_NAME with 1h time-to-live
docker tag 127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-37-gfadf1e2 ttl.sh/${IMAGE_NAME}:1h
docker push ttl.sh/${IMAGE_NAME}:1h
```

Note down the final URI of your image:
```
INSTALLER_URI='ttl.sh/f6fb22ab-6e45-4339-82d6-18d6413f6f2e:1h'
```

### Upgrade our node with the new image and check our module loaded
Hop over to the infrastructure repo site folder and perform the upgrade
```
cd sites/indigo/

# Find the node we want
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get nodes -o wide

# Upgrade the node
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 upgrade --image "${INSTALLER_URI}"

# Look at the logs to verify your module loaded
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 dmesg -f

# Check it's showing up here
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 read /proc/modules | grep hailo
hailo_pci 135168 0 - Live 0xffffffffc0674000 (O)

# Ensure it's in /dev
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /dev/ | grep hailo
192.168.77.73   Dcrw-rw-rw-   0     0     0         Jun 22 20:49:59   system_u:object_r:device_t:s0        hailo0

# Verify that the udev rule is showing up
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /usr/lib/udev/rules.d/ | grep hailo
192.168.77.73   -rwxr-xr-x   0     0     84        Jun 14 04:54:05   system_u:object_r:unlabeled_t:s0    51-hailo-udev.rules

# Verify that the .ko file exists in the `misc` folder
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /usr/lib/modules/6.12.31-talos/kernel/drivers/misc/ | grep hailo
192.168.77.73   -rw-r--r--   0     0     341930    Jun 14 04:54:05   system_u:object_r:unlabeled_t:s0   hailo_pci.ko
```
