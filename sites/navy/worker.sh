export TALOS_VERSION=v1.12.1
SCHEMATIC_ID='cd25d1581d213795db89418da338c4c5505848b285c6159f9e127b2a8d3f521e'

# This contains the above base64 encoded config in it!
FACTORY_URL='factory.talos.dev/metal-installer/cd25d1581d213795db89418da338c4c5505848b285c6159f9e127b2a8d3f521e:v1.12.1'

# From the `Initial Installation` section
export INSTALLER_IMAGE_URI='factory.talos.dev/metal-installer/cd25d1581d213795db89418da338c4c5505848b285c6159f9e127b2a8d3f521e:v1.12.1'

EQ14_1_IP=192.168.81.201
EQ14_2_IP=192.168.81.202
EQ14_3_IP=192.168.81.196

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
    --config-patch-worker @patches/dal-navy-core-1-worker-eq14-init.yaml \
    --output-dir templates/dal-navy-core-1/ \
    --output-types worker

mv templates/dal-navy-core-1/worker.yaml templates/dal-navy-core-1/worker-eq14.yaml

talosctl -n "${EQ14_1_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("eno")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_2_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("eno")) | .spec.hardwareAddr' -r | tr -d ':'
talosctl -n "${EQ14_3_IP}" get links --insecure -o json | jq '. | select(.metadata.id | startswith("eno")) | .spec.hardwareAddr' -r | tr -d ':'

EQ14_1_HW_ADDR='844709778d16'
EQ14_2_HW_ADDR='84470970abf7'
EQ14_3_HW_ADDR='84470970bf87'

cat templates/dal-navy-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_1_HW_ADDR}/g" > "nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_1_HW_ADDR}.yaml"
cat templates/dal-navy-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_2_HW_ADDR}/g" > "nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_2_HW_ADDR}.yaml"
cat templates/dal-navy-core-1/worker-eq14.yaml | sed "s/<HW_ADDRESS>/${EQ14_3_HW_ADDR}/g" > "nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_3_HW_ADDR}.yaml"

sed -i 's/<NODE_INSTANCE_TYPE>/eq14.16gb.amd64/g' nodes/dal-navy-core-1/worker-eq14-16gb-amd64-*
sed -i 's/<K8S_NODE_GROUP>/eq14-worker-pool/g' nodes/dal-navy-core-1/worker-eq14-16gb-amd64-*
sed -i "s|<INSTALLER_IMAGE_URI>|${INSTALLER_IMAGE_URI}|g" nodes/dal-navy-core-1/worker-eq14-16gb-amd64-*

talosctl apply-config --insecure -n "${EQ14_1_IP}" -f nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_1_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${EQ14_2_IP}" -f nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_2_HW_ADDR}.yaml
talosctl apply-config --insecure -n "${EQ14_3_IP}" -f nodes/dal-navy-core-1/worker-eq14-16gb-amd64-${EQ14_3_HW_ADDR}.yaml
