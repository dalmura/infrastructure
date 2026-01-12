OVERLAY_DIR='clusters/dal-navy-core-1/wave-3/overlays'

# Secret 'authentik-db-backup-secret' for authentik
argocd app create wave-3 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/navy/clusters/dal-navy-core-1/wave-3/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-3

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-3

vault auth enable oidc

vault write auth/oidc/config \
    oidc_discovery_url="https://auth.navy.dalmura.cloud/application/o/vault/" \
    oidc_client_id="<Client ID from above>" \
    oidc_client_secret="<Client Secret from above>" \
    default_role="default"

vault write auth/oidc/role/default \
    allowed_redirect_uris="https://vault.navy.dalmura.cloud/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://vault.navy.dalmura.cloud/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="preferred_username" \
    groups_claim="roles" \
    oidc_scopes="openid,profile,email,entitlements"