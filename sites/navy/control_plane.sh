export TALOS_VERSION=v1.12.1
export CILIUM_VERSION=1.18.5
export SCHEMATIC_ID='f8a903f101ce10f686476024898734bb6b36353cc4d41f348514db9004ec0a9d'
export FACTORY_URL='https://factory.talos.dev/?arch=arm64&board=rpi_generic&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=sbc&version=1.12.1'
# From the `Initial Installation` section
export INSTALLER_IMAGE_URI='https://factory.talos.dev/?arch=arm64&board=rpi_generic&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&target=sbc&version=1.12.1'

RPI4_1_IP=192.168.81.200

talosctl gen secrets \
  --output-file secrets.yaml \
  --talos-version "${TALOS_VERSION}"

  talosctl gen config \
    dal-navy-core-1 \
    'https://192.168.81.2:6443/' \
    --with-secrets secrets.yaml \
    --with-docs=false \
    --with-examples=false \
    --install-disk='' \
    --talos-version "${TALOS_VERSION}" \
    --with-cluster-discovery=false \
    --with-kubespan=false \
    --additional-sans 'core-1.navy.dalmura.cloud' \
    --config-patch @patches/dal-navy-core-1-all-init.yaml \
    --config-patch-control-plane @patches/dal-navy-core-1-controlplane-init.yaml \
    --output-dir templates/dal-navy-core-1/ \
    --output-types controlplane,talosconfig

RPI4_1_HW_ADDR='e45f019d4ca8'
# Create the per-device Control Plane configs with these overrides
cat templates/dal-navy-core-1/controlplane.yaml | sed "s/<HW_ADDRESS>/${RPI4_1_HW_ADDR}/g" > "nodes/dal-navy-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"

talosctl apply-config --insecure -n "${RPI4_1_IP}" -f "nodes/dal-navy-core-1/control-plane-${RPI4_1_HW_ADDR}.yaml"

talosctl --talosconfig templates/dal-navy-core-1/talosconfig config endpoints "${RPI4_1_IP}"
talosctl --talosconfig templates/dal-navy-core-1/talosconfig config nodes "${RPI4_1_IP}"
# From now on our talosctl commands just talk to RPI4_1_IP only

# We should see the server version printed as well, matching the Talos version you selected when generating the image at the factory website
talosctl --talosconfig templates/dal-navy-core-1/talosconfig version

# Look at the logs and see the progress
talosctl --talosconfig templates/dal-navy-core-1/talosconfig dmesg --follow

# This tells us we're waiting for "etcd" to come online
# Bootstrap the etcd cluster
talosctl --talosconfig templates/dal-navy-core-1/talosconfig bootstrap

# Wait for the cluster to settle down
# It will just keep repeating the same similar messages
talosctl --talosconfig templates/dal-navy-core-1/talosconfig dmesg --follow

mkdir kubeconfigs

# Extract the creds to talk via kubectl
talosctl --talosconfig templates/dal-navy-core-1/talosconfig kubeconfig kubeconfigs/dal-navy-core-1

# Get the nodes status
kubectl --kubeconfig kubeconfigs/dal-navy-core-1 get nodes

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install \
    cilium \
    cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --kubeconfig kubeconfigs/dal-navy-core-1 \
    --namespace kube-system \
    -f clusters/dal-navy-core-1/wave-0/values/cilium/values.yaml

# Check the progress of the CNI install
kubectl --kubeconfig kubeconfigs/dal-navy-core-1 -n kube-system get pods

# Wait until these become Ready

# You should then see the following (might take a minute, be patient)
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig dmesg --follow


export KUBECONFIG='kubeconfigs/dal-navy-core-1'

cilium status