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

This will give us an EXTENSION URI:
```
EXTENSION_URI='127.0.0.1:5005/michael-robbins/hailort:4.21.0@sha256:14865002ac6507a13bfb5e936d2bd7b929feb32920e3172fad1985c549982d04'
```

After this we need to dump the created extension image out to local disk:
```
docker create --name "tmp_hailort" 127.0.0.1:5005/michael-robbins/hailort:a358137@sha256:9ef44891037fe091d49bca6e0c10f74c3ab99364de30b22e572b5686249500ea ls

# Dump the image filesystem to a local tar
docker export -o hailort.tar tmp_hailort

docker rm tmp_hailort
```

Unfortunately the exported filesystem isn't directly usable, as it includes a few docker quirks like `.dockerenv` file that Docker magically mounts into the FS for us. This breaks the Siderolabs imager below, so we need to remove it:
```
# Make some temporary location
mkdir ~/data
cd ~/data

# Copy in the hailort.tar file from above
cp ~/dev/talos-extensions/hailort.tar .

# Extract it to local disk
tar xf hailort.tar
rm hailort.tar

# Clear up the quirk files
rm .dockerenv
rm -rf dev etc sys proc

# Repackage
tar cf ../hailort.tar .

# Copy over the old .tar file
cp ../hailort.tar ~/dev/talos-extensions/hailort.tar
rm ../hailort.tar

# Clean up temporary location
cd ~/dev/talos
rm -rf ~/data
```

If you want to inspect the extensions filesystem, including what you built above:
```
# Create a temporary dir and copy in hailort.tar

$ tar xf hailort.tar
$ rm hailort.tar

$ find .
./rootfs
./rootfs/usr
./rootfs/usr/lib
./rootfs/usr/lib/modules
./rootfs/usr/lib/modules/6.12.25-talos
./rootfs/usr/lib/modules/6.12.25-talos/modules.dep
./rootfs/usr/lib/modules/6.12.25-talos/modules.softdep
./rootfs/usr/lib/modules/6.12.25-talos/modules.alias.bin
./rootfs/usr/lib/modules/6.12.25-talos/kernel
./rootfs/usr/lib/modules/6.12.25-talos/kernel/drivers
./rootfs/usr/lib/modules/6.12.25-talos/kernel/drivers/misc
./rootfs/usr/lib/modules/6.12.25-talos/kernel/drivers/misc/hailo_pci.ko
./rootfs/usr/lib/modules/6.12.25-talos/modules.symbols.bin
./rootfs/usr/lib/modules/6.12.25-talos/modules.order
./rootfs/usr/lib/modules/6.12.25-talos/modules.weakdep
./rootfs/usr/lib/modules/6.12.25-talos/modules.devname
./rootfs/usr/lib/modules/6.12.25-talos/modules.builtin.modinfo
./rootfs/usr/lib/modules/6.12.25-talos/modules.alias
./rootfs/usr/lib/modules/6.12.25-talos/modules.builtin.bin
./rootfs/usr/lib/modules/6.12.25-talos/modules.builtin
./rootfs/usr/lib/modules/6.12.25-talos/modules.builtin.alias.bin
./rootfs/usr/lib/modules/6.12.25-talos/modules.symbols
./rootfs/usr/lib/modules/6.12.25-talos/modules.dep.bin
./rootfs/usr/lib/udev/rules.d
./rootfs/usr/lib/udev/rules.d/51-hailo-udev.rules
```

We can see we successfully built the `hailo_pci.ko` kernel module, along with our udev rules file!

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
make imager REGISTRY=127.0.0.1:5005 USERNAME=michael-robbins PUSH=true PLATFORM=linux/amd64 INSTALLER_ARCH=amd64 PKG_KERNEL=127.0.0.1:5005/michael-robbins/kernel:a358137@sha256:0dd225a56b52c84ebe823614d64bb754359ac5f98f7718cca34b388544a7cfe4
```

You'll need to provide the `$KERNEL_URI` from above.

This will output an IMAGER URI:
```
IMAGER_URI='127.0.0.1:5005/michael-robbins/imager:v1.10.1@sha256:5583a569e85273e39b105511dee704db6cb805de6536bb584b6736358bb9e4b7'
```

We then need to create an imager 'profile' (aka config file) that decides which kernel/installer/system extensions to build and what to output, this is kind of like the Talos Image Factory, just manually via the CLI

`profile.yaml` in the root of the `talos` repo:
```
# profile.yaml
arch: amd64
platform: metal
secureboot: false
version: v1.10.1
input:
  kernel:
    path: /usr/install/amd64/vmlinuz
  initramfs:
    path: /usr/install/amd64/initramfs.xz
  baseInstaller:
    imageRef: ghcr.io/siderolabs/installer:v1.10.1
  systemExtensions:
    - tarballPath: /hailort.tar
output:
  kind: installer
  outFormat: raw
```

We will also copy in the `hailort.tar` from the talos extensions repo:
```
cp ../talos-extensions/hailort.tar .
```

And finally use the imager to produce some output artifacts, using the `IMAGER_URI` from above:
```
cat profile.yaml | docker run --rm -i -v $PWD/_out:/out -v $PWD/hailort.tar:/hailort.tar 127.0.0.1:5005/michael-robbins/imager:v1.10.1@sha256:5583a569e85273e39b105511dee704db6cb805de6536bb584b6736358bb9e4b7 -
```

This will create the following artifacts in the `_out` directory of the `talos` repo:
```
installer-amd64.tar
```

This will create `_out/installer-amd64.tar` which we can load into docker as an image and push up to a registry to use to install Talos:
```
docker load -i ./_out/installer-amd64.tar
docker tag ghcr.io/siderolabs/installer:v1.10.0 michael-robbins/hailort-installer:v1.10.0
docker push michael-robbins/hailort-installer:v1.10.0
```

The above final `michael-robbins/hailort-installer:v1.10.0` needs to be accessible from the Talos node you boot (so ideally docker/github registry, not your local 127.0.0.1 one).

### Creating the Talos config and installing
```
talosctl gen config --install-disk /dev/nvme0n1 --install-image michael-robbins/hailort-installer:v1.10.0 eq14 https://192.168.77.10:6443
```
