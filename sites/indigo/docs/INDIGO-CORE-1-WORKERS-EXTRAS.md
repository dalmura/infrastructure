# Provision extra configuration for dal-indigo-core-1's `rpi4.8gb.arm` Workers

We assume you've got dal-indigo-core-1's `rpi4.8gb.arm` Workers running and Ready according to `kubectl get nodes`!

Export the worker nodes:
```bash
RPI4_1_IP=192.168.77.155
RPI4_2_IP=192.168.77.161
RPI4_3_IP=192.168.77.162
```

## OpenEBS Jiva
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_2_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_3_IP}" patch mc -p @patches/dal-indigo-core-1-worker-jiva.yaml

# The output will look something like this
patched MachineConfigs.config.talos.dev/v1alpha1 at the node 192.168.77.161
Applied configuration without a reboot
```

After these have applied we need to force an upgrade to install the talos extensions:
```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_2_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_3_IP}" upgrade --image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"

# The output will look something like this (as the node prepares itself)
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: waiting for actor ID

# It will then move through a series of 'tasks' (as the node upgrades)
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: task: upgrade action: START

# This will take a good like ~5 minutes, so hold tight
# Eventually the node will reboot like this
◰ watching nodes: [192.168.77.161]
    * 192.168.77.161: unavailable, retrying...

# This will also take a good few minutes, so hold tight
# And eventually move to (when the node finishes booting)
watching nodes: [192.168.77.161]
    * 192.168.77.161: post check passed
```

You can verify the extension with:
```bash
# See if it's installed on RPI4_1_IP
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" get extensions
NODE             NAMESPACE   TYPE              ID                                          VERSION   NAME          VERSION
192.168.77.161   runtime     ExtensionStatus   000.ghcr.io-siderolabs-iscsi-tools-v0.1.1   1         iscsi-tools   v0.1.1

# See if it's running on RPI4_1_IP
% talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -e 192.168.77.130 -n "${RPI4_1_IP}" services
NODE             SERVICE      STATE     HEALTH   LAST CHANGE         LAST EVENT
192.168.77.161   apid         Running   OK       3m12s ago           Health check successful
192.168.77.161   containerd   Running   OK       466018h31m58s ago   Health check successful
192.168.77.161   cri          Running   OK       3m18s ago           Health check successful
192.168.77.161   ext-iscsid   Running   ?        3m17s ago           Started task ext-iscsid (PID 3538) for container ext-iscsid
192.168.77.161   ext-tgtd     Running   ?        3m17s ago           Started task ext-tgtd (PID 3480) for container ext-tgtd
192.168.77.161   kubelet      Running   OK       2m12s ago           Health check successful
192.168.77.161   machined     Running   OK       466018h32m4s ago    Health check successful
192.168.77.161   udevd        Running   OK       466018h31m55s ago   Health check successful
```

Create the namespace to install in
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -f patches/dal-indigo-core-1-worker-jiva-namespace.yaml
namespace/openebs created
```

We configure the namespace to not have any enforcement of Pod Security Admission policies due to the privileged nature of these pods.

We then install the helm chart
```bash
helm repo add openebs-jiva https://openebs.github.io/jiva-operator
helm repo update
helm upgrade --kubeconfig kubeconfigs/dal-indigo-core-1 --install --namespace openebs --version 3.4.0 openebs-jiva openebs-jiva/jiva
```

You can now verify if the pods are coming up
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get pods -n openebs
NAME                                                READY   STATUS    RESTARTS   AGE
openebs-jiva-csi-controller-0                       5/5     Running   0          95s
openebs-jiva-csi-node-cxs2w                         3/3     Running   0          95s
openebs-jiva-csi-node-lwn6t                         3/3     Running   0          95s
openebs-jiva-localpv-provisioner-55dc7b7578-cvz4s   1/1     Running   0          95s
openebs-jiva-operator-dbd4f5d4b-rd6gf               1/1     Running   0          95s
```

After the pods come up we need to configure the install to work with Talos
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs apply --filename patches/dal-indigo-core-1-worker-jiva-config.yaml
configmap/openebs-jiva-csi-iscsiadm configured

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs patch daemonset openebs-jiva-csi-node --type=json --patch '[{"op": "add", "path": "/spec/template/spec/hostPID", "value": true}]'
daemonset.apps/openebs-jiva-csi-node patched
```

Verify the new Storage Class exists
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 get storageclass
NAME                       PROVISIONER           RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
openebs-hostpath           openebs.io/local      Delete          WaitForFirstConsumer   false                  3m33s
openebs-jiva-csi-default   jiva.csi.openebs.io   Delete          Immediate              true                   3m33s
```

Test the new Storage Class
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs apply --filename patches/dal-indigo-core-1-worker-jiva-test-pvc.yaml
persistentvolumeclaim/example-jiva-csi-pvc created

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs get pvc

NAME                                                          STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS               AGE
example-jiva-csi-pvc                                          Bound     pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6   4Gi        RWO            openebs-jiva-csi-default   15s
openebs-pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-0   Pending                                                                        openebs-hostpath           12s
openebs-pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-1   Pending                                                                        openebs-hostpath           12s
openebs-pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-2   Pending                                                                        openebs-hostpath           12s

# It will take some time for the pvc-abc123-jiva-ctrl to come up
# As it takes some time to pull all the container images
# We can see here the volume will have 3x replicas
# This can be configured to be lower/higher in the Helm chart values

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs apply --filename patches/dal-indigo-core-1-worker-jiva-test-deployment.yaml
deployment.apps/fio created

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs get deployments
NAME                                                 READY   UP-TO-DATE   AVAILABLE   AGE
fio                                                  0/1     1            0           2m57s
openebs-jiva-localpv-provisioner                     1/1     1            1           46h
openebs-jiva-operator                                1/1     1            1           46h
pvc-79eccae1-bdd8-4e90-a4b8-49e072791069-jiva-ctrl   0/1     1            0           4m30s

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs get pods
NAME                                                              READY   STATUS              RESTARTS   AGE
fio-7df55fd55d-q98nd                                              0/1     ContainerCreating   0          30s
openebs-jiva-csi-controller-0                                     5/5     Running             0          5m56s
openebs-jiva-csi-node-ct24g                                       3/3     Running             0          2m46s
openebs-jiva-csi-node-vn59k                                       3/3     Running             0          2m42s
openebs-jiva-localpv-provisioner-55dc7b7578-cvz4s                 1/1     Running             0          5m56s
openebs-jiva-operator-dbd4f5d4b-rd6gf                             1/1     Running             0          5m56s
pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-ctrl-7b78f7d5rg57   2/2     Running             0          2m7s
pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-0               1/1     Running             0          2m7s
pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-1               1/1     Running             0          2m7s
pvc-c43f4d36-9da1-4175-89e3-64567cfcbaa6-jiva-rep-2               0/1     Pending             0          2m7s

# Describe the pod and verify it comes up with the attached volume
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs describe pod fio-7df55fd55d-q98nd
Name:             fio-7df55fd55d-q98nd
Namespace:        openebs
...
<snip>
...
Volumes:
  fio-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  example-jiva-csi-pvc
    ReadOnly:   false
...

# You can get a shell in the container to verify if the volume can read/write!
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs exec --stdin --tty fio-65f69f7bd4-ggsx6 -- /bin/sh
% cd /datadir
% echo '1' > hello
% exit

# Recreate the pod and verify
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs delete pod fio-65f69f7bd4-ggsx6
pod fio-65f69f7bd4-ggsx6
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs get pods | grep fio
fio-65f69f7bd4-mkdvn                                              1/1     Running   0          33s

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs exec --stdin --tty fio-65f69f7bd4-mkdvn -- /bin/sh
% cd /datadir
% ls -l
total 20
-rw-r--r--    1 root     root             2 Mar  4 06:02 hello
drwx------    2 root     root         16384 Mar  4 04:16 lost+found

# You can clean up after
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs delete deployment fio
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace openebs delete pvc example-jiva-csi-pvc
```

Now our k8s cluster should be running with:
* 3x rpi4.4gb.arm64 Control Plane nodes
* 3x rpi4.8gb.arm64 Worker nodes
  * OpenEBS Jiva configured as a CSI Storage Class
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
