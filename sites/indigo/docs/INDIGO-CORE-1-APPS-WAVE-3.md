# Provision the Wave 3 applications for dal-indigo-core-1

These are:
* [Authentik](https://goauthentik.io/) for Authentication (proposed)
* [Vault](https://www.hashicorp.com/en/products/vault) for Secrets Storage
* [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso) for k8s Secrets integration with Vault

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 2](INDIGO-CORE-1-APPS-WAVE-2.md) and have all the precursors up and running
* `argocd` is logged in
* Longorn is running
* Traefik ingress controller

## Obtain AWS Credentials
You can get the required AWS Credentials from the `dalmura/network` repo, the README.md contains the instructions how to get them.

## Create and seal the Secrets
Authentik has a PostgreSQL DB via cnpg, which needs credentials to backup to S3:
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/wave-3/overlays'

# Secret 'authentik-db-backup-secret' for authentik
kubectl create secret generic \
  authentik-db-backup-secret \
  --namespace authentik \
  --dry-run=client \
  --from-literal 'ACCESS_KEY_ID=<k8s_backups_key.id>' \
  --from-literal 'SECRET_ACCESS_KEY=<k8s_backups_key.secret>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/authentik/authentik-db-backup-secret.sealed.yaml
```

Authentik also has a 'secret key' it uses for cookie encryption among other things. We don't do this via Vault as it's not provisioned yet.

Generate the secret key first:
```bash
# Option 1
openssl rand 60 | base64 -w 0

# Option 2
pwgen -s 50 1
```

Then fill it in below:
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/wave-3/overlays'

# Secret 'authentik-secret-key' for authentik
kubectl create secret generic \
  authentik-secret-key \
  --namespace authentik \
  --dry-run=client \
  --from-literal 'SECRET_KEY=<secret_key_from_above>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/authentik/authentik-secret-key.sealed.yaml
```

Lastly Authentik needs the email configuration defined at create time vs configuring later, so we need to create it as well:
```bash
OVERLAY_DIR='clusters/dal-indigo-core-1/wave-3/overlays'

# Secret 'authentik-secret-key' for authentik
kubectl create secret generic \
  authentik-email-secrets \
  --namespace authentik \
  --dry-run=client \
  --from-literal 'host=email-smtp.us-east-1.amazonaws.com' \
  --from-literal 'port=465' \
  --from-literal 'username=<k8s_email_sender_key.id>' \
  --from-literal 'password=<k8s_email_sender_key.ses_smtp_password_v4>' \
  --from-literal 'from=Dalmura Indigo Authentication <indigo+auth@dalmura.cloud>' \
  -o yaml \
  | kubeseal --kubeconfig kubeconfigs/dal-indigo-core-1 -o yaml \
  > ${OVERLAY_DIR}/authentik/authentik-email-secrets.sealed.yaml
```

Ensure you have committed and pushed the above credentials up into git as the below command (and final deployment) all rely on what's in git, not what's local.

## Create the wave-3 parent app & deploy children
```bash
argocd app create wave-3 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-3/app

# Create the child applications
argocd app sync wave-3

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-3
```

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Access Authentik

Authentik will be available over its configured ingress domain name `authentik.indigo.dalmura.cloud`, once it's running you'll need to navigate to the [initial setup page](https://authentik.indigo.dalmura.cloud/if/flow/initial-setup/) where you can set the `akadmin` users password.

Immediately perform the following steps:
* Set a temporary password for the `akadmin` user
* Log into the `akadmin` user
* Click the 'Admin Interface' in the top right
* Go to 'Directory' => 'Users'
* Create a `site-admin` user with type as 'Internal'
* Click on the `site-admin` user
* Click 'Set password' and persist the new admin credentials into your password vault
* Add the `site-admin` user into the 'authentik Admins' group
* Log out and log in as the new `site-admin` user
* Navigate back to 'Directory' => 'Users' and delete the `akadmin` default user

After this you can proceed to [Authentik Configuration](INDIGO-CORE-1-APPS-WAVE-3-AUTHENTIK.md) for configuring Authentik itself.
