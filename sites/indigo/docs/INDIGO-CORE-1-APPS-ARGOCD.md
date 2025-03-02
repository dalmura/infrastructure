# Provision Argo CD for dal-indigo-core-1

We assume you've got a few Workers running via:
* [RPI4 worker class](INDIGO-CORE-1-WORKERS-RPI4.md)
* [EQ14 worker class](INDIGO-CORE-1-WORKERS-EQ14.md)

And additionally:
* Have a Ready status according to `kubectl get nodes` across all nodes
* Have cilium reporting everything is green and fully deployed via `cilium status`

If not go back to previous steps and troubleshoot, the cluster needs to be in a healthy state before we deploy anything.

Install the non-HA Argo CD into its own namespace
```bash
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -f patches/dal-indigo-core-1-worker-argocd-namespace.yaml
namespace/argocd created

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io created
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io created
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io created
serviceaccount/argocd-application-controller created
serviceaccount/argocd-applicationset-controller created
...
networkpolicy.networking.k8s.io/argocd-redis-network-policy created
networkpolicy.networking.k8s.io/argocd-repo-server-network-policy created
networkpolicy.networking.k8s.io/argocd-server-network-policy created

# Wait for the containers to come up

% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 --namespace argocd get pods
NAME                                                READY   STATUS              RESTARTS   AGE
argocd-application-controller-0                     0/1     ContainerCreating   0          81s
argocd-applicationset-controller-84656db669-98l4r   0/1     ContainerCreating   0          82s
argocd-dex-server-6df79688bc-85klx                  0/1     Init:0/1            0          82s
argocd-notifications-controller-5fd999cb79-9p7wn    0/1     ContainerCreating   0          82s
argocd-redis-6b7c6f67db-kmn74                       1/1     Running             0          82s
argocd-repo-server-74f6bfdf54-k276v                 0/1     Init:0/1            0          82s
argocd-server-76fdbd5f78-mkx2p                      0/1     ContainerCreating   0          82s

# Lastly apply an override for the default project to ignore Cilium resources
% kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -f patches/dal-indigo-core-1-worker-argocd-default-project.yaml

# You'll see a Warning about 'prefer a domain-qualified finalizer name', just ignore it, some context: https://github.com/Infisical/infisical/issues/2503
# This works around https://github.com/cilium/cilium/issues/17349
```

You can then verify the application is operational via port forwarding:
```bash
# Retrieve the default password
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | sed 's/$/\n/g'

# Setup port forwarding
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 port-forward svc/argocd-server -n argocd 8080:443

# Install CLI tool
brew install argocd

# Log in via the CLI
# It will prompt about insecure certificate (self signed) just accept
# Username: admin
# Password: <from above>
argocd login localhost:8080

# Update the default password for admin
argocd account update-password

# Delete the default password secret
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n argocd delete secret argocd-initial-admin-secret

# Navigate to https://localhost:8080 and log in with your credentials
```

Now our k8s cluster should be running with:
* 3x `rpi4.4gb.arm64` Control Plane nodes
  * Cilium in Strict Mode as the CNI
* Floating VIPs for easy k8s Control Plane access
  * 192.168.77.2 on the SERVERS VLAN
  * 192.168.77.130 on the SERVERS_STAGING VLAN
* 3x `rpi4.8gb.arm64` Worker nodes
* 3x `eq14.16gb.amd64` Worker nodes
* ArgoCD ready to deploy _everything else_
