argocd app create wave-0 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/navy/clusters/dal-navy-core-1/wave-0/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Path above is for the git repo, not your local path

# Create the child applications
argocd app sync wave-0

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-0

# Verify the status via the Web UI, once it's Healthy you can continue