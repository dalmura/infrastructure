argocd app create wave-4 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/navy/clusters/dal-navy-core-1/wave-4/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-4

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-4
