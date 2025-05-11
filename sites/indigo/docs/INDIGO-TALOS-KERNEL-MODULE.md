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

Ensure your local repo/checkout of `pkgs` contains the new module.

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

