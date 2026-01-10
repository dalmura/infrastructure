argocd app create wave-2 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/navy/clusters/dal-navy-core-1/wave-2/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-2

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-2