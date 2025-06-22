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

Make note of the container URIs:
```
KERNEL_URI='127.0.0.1:5005/michael-robbins/kernel:a358137@sha256:0dd225a56b52c84ebe823614d64bb754359ac5f98f7718cca34b388544a7cfe4'
HAILORT_URI='127.0.0.1:5005/michael-robbins/hailort-pkg:a358137@sha256:54c090fccbf9bbd29a68e219b57cdf40784249fd2d2bf588f797d3729e242999'
```

Now we've built the base kernel, and our Hailo package. Now we need to build the 'extension' that will use the built Hailo package.

Note, once the pkgs PR merges, the above URIs can also be updated to reference the proper siderolabs pkg URIs:
```
# eg. for an alpha 1.11 build
# note, you *must* use the same version tags between kernel and hailort due to crypto signing
KERNEL_URI='ghcr.io/siderolabs/kernel:v1.11.0-alpha.0-35-g0aaa07a'
HAILORT_URI='ghcr.io/siderolabs/hailort-pkg:v1.11.0-alpha.0-35-g0aaa07a'
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

To build the extension we need to temporarily override the `image` line in `drivers/hailort/pkg.yaml` with the following:
```
# Template:
  - image: "$HAILORT_URI"

# For example:
  - image: "127.0.0.1:5005/michael-robbins/hailort-pkg:a358137@sha256:54c090fccbf9bbd29a68e219b57cdf40784249fd2d2bf588f797d3729e242999"
```

Note: `$HAILORT_URI` should be substituted with your above URI you noted down earlier

And to finally build the extension:
```
make hailort REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 PKG_KERNEL=127.0.0.1:5005/michael-robbins/kernel:a358137@sha256:0dd225a56b52c84ebe823614d64bb754359ac5f98f7718cca34b388544a7cfe4
```

Note: The above `PKG_KERNEL` is equal to the `KERNEL_URI` you noted down earlier.

Alternatively, if you've already merged the `pkgs` PR and you have an existing siderolabs/pkgs URIs for the kernel and new module.

Then simply just run specifying that PKGS tag instead:
```
make hailort REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 PKGS=v1.11.0-alpha.0-35-g0aaa07a
```

Note: We used the tag above from the siderolabs/pkgs URIs above (assuming they exist)

This will give us an EXTENSION URI from the line 'pushing manifest for ...' to our local registry we set up earlier:
```
EXTENSION_URI='127.0.0.1:5005/michael-robbins/hailort:4.21.0@sha256:14865002ac6507a13bfb5e936d2bd7b929feb32920e3172fad1985c549982d04'
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
BASE_IMAGE_DIR='/var/lib/containers/storage/overlay/e5569ee718d8275217f3ef325ec1f90726ff5b0097104b20b8c30d1dc2d17d2b/merged'

# Then you can easily explore it
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/

# Verify the `51-hailo-udev.rules` file exists
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/udev/rules.d/

# Verify the `hailo_pci.ko` file exists
sudo ls -l ${BASE_IMAGE_DIR}/rootfs/usr/lib/modules/6.12.31-talos/kernel/drivers/misc/
```

Checkout talos repo
```
git clone .... talos
cd talos
```

Build the imager thingy:
```
make installer-base imager PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PKGS=v1.11.0-alpha.0-35-g0aaa07a PUSH=true TAG=v1.11.0-alpha.0-35-g0aaa07a
```

This will build the initial 'talos' installer image containing the kernel from the PKGS above. Ensure `TAG` above is set, otherwise the Makefile will default to tagging the image with the hash or another tag that will cause the below `make image-installer` command to fail.

The above will create 2x images, `installer-base` and `imager`:
* We'll save the `installer-base` below, minus the sha extension as it didn't match for some reason
* And `imager` will be derived as part of the next `make` command

Outputs:
```
BASE_TALOS_URI='127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-35-g0aaa07a'
```

Using the imager we'll build our system extension:
```
make image-installer REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins TAG=v1.11.0-alpha.0-35-g0aaa07a IMAGER_ARGS="--base-installer-image=${BASE_TALOS_URI} --system-extension-image=${EXTENSION_URI}"
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
Loaded image: 127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-35-g0aaa07a

# Generate the UUID for the ttl.sh image
IMAGE_NAME=$(uuidgen)

# Tag and push the above $IMAGE_NAME with 1h time-to-live
docker tag 127.0.0.1:5005/michael-robbins/installer-base:v1.11.0-alpha.0-35-g0aaa07a ttl.sh/${IMAGE_NAME}:1h
docker push ttl.sh/${IMAGE_NAME}:1h
```

Note down the final URI of your image:
```
INSTALLER_URI='ttl.sh/fb357269-2a4c-478d-8ceb-0d297d70d5aa:1h'
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
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /dev/ | grep hailo`
TBD due to broken setup

# Verify that the udev rule is showing up
$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /usr/lib/udev/rules.d/ | grep hailo
192.168.77.73   -rwxr-xr-x   0     0     84        Jun 14 04:54:05   system_u:object_r:unlabeled_t:s0    51-hailo-udev.rules

# Verify that the .ko file exists in the `misc` folder
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /usr/lib/modules/6.12.28-talos/kernel/drivers/

$ talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.73 ls -l /usr/lib/modules/6.12.31-talos/kernel/drivers/misc/ | grep hailo
NODE            MODE         UID   GID   SIZE(B)   LASTMOD           LABEL                              NAME
192.168.77.73   -rw-r--r--   0     0     341930    Jun 14 04:54:05   system_u:object_r:unlabeled_t:s0   hailo_pci.ko
```
