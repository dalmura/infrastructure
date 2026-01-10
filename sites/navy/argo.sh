kubectl --kubeconfig kubeconfigs/dal-navy-core-1 apply -f patches/dal-navy-core-1-argocd-namespace.yaml

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm search repo argo/argo-cd

helm install \
  argocd \
  argo/argo-cd \
  --version "${CHART_VERSION}" \
  --kubeconfig kubeconfigs/dal-navy-core-1 \
  --namespace argocd \
  -f clusters/dal-navy-core-1/wave-0/values/argocd/values.yaml

#Retrieve the default password
kubectl --kubeconfig kubeconfigs/dal-navy-core-1 -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | sed 's/$/\n/g'

# Setup port forwarding
kubectl --kubeconfig kubeconfigs/dal-navy-core-1 port-forward svc/argocd-server -n argocd 8080:443

argocd login localhost:8080
# Update the default password for admin
argocd account update-password

kubectl --kubeconfig kubeconfigs/dal-navy-core-1 -n argocd delete secret argocd-initial-admin-secret
