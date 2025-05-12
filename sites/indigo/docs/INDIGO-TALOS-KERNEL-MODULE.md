# Adding a new Kernel Module to Talos

## HailoRT Driver

This module supports the Hailo-8L AI Accelerator M.2 PCIe device.

Hailo provide a [Github repo](https://github.com/hailo-ai/hailort-drivers) that contains the source to build the kernel module along with supporting files.

### Talos `pkgs` repo

This repo contains (among other things) all the Linux kernel modules built against a certain kernel, all signed by the same key at 'build time' as required to be loaded into a Talos Linux kernel at runtime.

Due to this, we cannot easily build a new kernel module in isolation, we need to build the 'whole package' aka Talos Linux kernel in one go, and reference that when setting up a new node w/Talos Linux.

### Talos `extension` repo

This repo contains the extension images that can be baked into a [Talos Linux Image Factory](https://factory.talos.dev/) release.

For a kernel module, the extension config in here will need to reference the `pkgs` repo's entry, as it needs to be able to configure and build the extension for the specific version of Talos Linux (basically everything needs to match).

This is the reason why we can't just build the kernel module in the `extension` repo by itself and skip the `pkgs` repo, because the kernel is built over there, not here.

For example, in the above factory, when you select Talos Linux 1.10 and the `i915` extension, it needs to pull in the version of the `i915` extension that was built with/against the kernel that is used in Talos Linux 1.10, it cannot be any other instance of the `i915` extension.

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
        cp /src/modules.order /rootfs/usr/lib/modules/$(cat /src/include/config/kernel.release)/
        cp /src/modules.builtin /rootfs/usr/lib/modules/$(cat /src/include/config/kernel.release)/
        cp /src/modules.builtin.modinfo /rootfs/usr/lib/modules/$(cat /src/include/config/kernel.release)/

        cd linux/pcie
        make -j $(nproc) -C /src M=$(pwd) modules_install INSTALL_MOD_PATH=/rootfs/usr INSTALL_MOD_DIR=kernel/drivers/misc INSTALL_MOD_STRIP=1
        cp 51-hailo-udev.rules /rootfs/etc/udev/rules.d/51-hailo-udev.rules
    test:
      - |
        fhs-validator /rootfs
finalize:
  - from: /rootfs
    to: /
```

The above steps happen as part of a bigger process where the underlying kernel has already been build and its artifacts (and crypto signing key) are all available locally on the machine.

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

See the [HailoRT PR](https://github.com/siderolabs/pkgs/pull/1222) for more context around the files and their contents.

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

### Build the `extensions`... extension!

Fork and checkout the repo:
```bash
# Fork on github

git clone https://github.com/your-user/your-extensions-fork-name.git talos-extensions
cd talos-pkgs
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

See the [HailoRT PR](https://github.com/siderolabs/extensions/pull/694/files) for an overview of the file contents.

To build the extension we need to temporarily override the `image` line in `drivers/hailort/pkg.yaml` with the following:
```
  - image: "127.0.0.1:5005/michael-robbins/hailort-pkg:{{ .VERSION }}"
```

And update the root directory file `Pkgfile` setting `HAILORT_VERSION` to the tag and hash from the `HAILORT_URI` above:
```
  HAILORT_VERSION: a358137@sha256:54c090fccbf9bbd29a68e219b57cdf40784249fd2d2bf588f797d3729e242999
```

And to finally build the extension:
```
make hailort REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 PKG_KERNEL=127.0.0.1:5005/michael-robbins/kernel:a358137@sha256:0dd225a56b52c84ebe823614d64bb754359ac5f98f7718cca34b388544a7cfe4
```

You'll need to provide the `$KERNEL_URI` from above. This will give us an EXTENSION URI
:
```
EXTENSION_URI='127.0.0.1:5005/michael-robbins/hailort:a358137@sha256:9ef44891037fe091d49bca6e0c10f74c3ab99364de30b22e572b5686249500ea'
```

After this we need to dump the created extension image out to local disk:
```
docker pull 127.0.0.1:5005/michael-robbins/hailort:a358137@sha256:9ef44891037fe091d49bca6e0c10f74c3ab99364de30b22e572b5686249500ea

# Find the image ID
docker image ls '127.0.0.1:5005/michael-robbins/hailort'

# Dump the image ID
docker image save -o hailort.tar --platform linux/amd64 e85b007309e1
```

### Build imager and build our base artifacts

Fork and checkout the talos repo:
```bash
# Fork on github

git clone https://github.com/your-user/your-talos-fork-name.git talos
cd talos
```

You might already have this checked out as part of setting up the build environment and building `talosctl`.

Build imager:
```
make imager REGISTRY=127.0.0.1:5005 PUSH=true PLATFORM=linux/amd64 INSTALLER_ARCH=amd64  PKG_KERNEL=127.0.0.1:5005/michael-robbins/kernel:a358137@sha256:0dd225a56b52c84ebe823614d64bb754359ac5f98f7718cca34b388544a7cfe4
```

You'll need to provide the `$KERNEL_URI` from above.

This will output an IMAGER URI:
```
IMAGER_URI='127.0.0.1:5005/siderolabs/imager:v1.10.1@sha256:5de7a93c01fa96780674477e1b450394011d001fa984851a9a9bd70200341405'
```

We then need to create an imager 'profile', this seems to be the metadata 
