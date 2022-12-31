# Creating workload cluster dal-k8s-core-1

After configuring Sidero with our Server Classes and Environment, we're ready to create dal-k8s-core-1

## Create the cluster in Sidero

```bash
mkdir -p sidero/clusters/

export CONTROL_PLANE_SERVERCLASS=rpi4.4gb.arm
# Temporary until we have rpi4.4gb.arm in stock
export CONTROL_PLANE_SERVERCLASS=rpi4.8gb.arm
export WORKER_SERVERCLASS=rpi4.8gb.arm
export TALOS_VERSION=v1.3.0
export KUBERNETES_VERSION=v1.26.0
export CONTROL_PLANE_PORT=6443
export CONTROL_PLANE_ENDPOINT=192.168.77.3

clusterctl generate cluster dal-k8s-core-1 \
    -i sidero \
    --kubeconfig kubeconfigs/dal-k8s-mgmt-1 \
    --target-namespace sidero-system \
    > sidero/clusters/dal-k8s-core-1.yaml
```

The above will create a 'cluster configuration' that we can apply back to k8s to kick off creation of the cluster. It contains the following Resources in 3x logical groups.

![cluster api hierarchy](imgs/core-cluster-api-resources.jpg?raw=true "Cluster API Hierarchy")

All the above Resources descriptions can be found conveniently on the [Sidero resources page](https://www.sidero.dev/latest/overview/resources/)

We are using `rpi4.4gb.arm` Server Class for the Control Plane nodes, `rpi4.8gb.arm` Server Class for the Worker nodes, latest support versions for Talos and k8s and `192.168.77.3` as our allocated VIP from our [network config](https://github.com/dalmura/network/blob/main/sites/indigo/networks.yml#L53).

Apply this back into k8s:
```bash
% kubectl apply --kubeconfig kubeconfigs/dal-k8s-mgmt-1 -f sidero/clusters/dal-k8s-core-1.yaml
```
