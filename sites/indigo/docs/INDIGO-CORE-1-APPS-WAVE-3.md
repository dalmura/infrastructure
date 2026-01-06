# Provision the Wave 3 applications for dal-indigo-core-1

These are:
* [Authentik](https://goauthentik.io/) for Authentication (proposed)
* [Vault](https://www.hashicorp.com/en/products/vault) for Secrets Storage
* [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso) for k8s Secrets integration with Vault

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 2](INDIGO-CORE-1-APPS-WAVE-2.md) and have all the precursors up and running
* `argocd` is logged in
* Longorn is running
* Traefik's Ingress Controller is working and you can access ArgoCD/Longhorn/etc UI's

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
    --path sites/indigo/clusters/dal-indigo-core-1/wave-3/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-3

# Deploy the child applications
argocd app sync -l app.kubernetes.io/instance=wave-3
```

This will take a solid 3-5 mins as the Pod comes up and the certificate is issued.

## Fix Authentik's /media PV permission
The default PV for authentik-media will be owned by root (UID 0/GID 0) where as Authentik runs as UID 1000/GID 1000. So we need to fix that first, otherwise the container will keep crashing out.

Ideally this is set as an init container or something, but for now this is fine.

Scale down the `authentik-server` Deployment to 0 (you can do this in ArgoCD UI or via the CLI), or just deploy the PV manually via ArgoCD first before the Deployment.


Run the following:
```
$ cat pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: task-pv-pod
  namespace: authentik
spec:
  volumes:
    - name: authentik-media
      persistentVolumeClaim:
        claimName: authentik-media
  containers:
    - name: task-pv-container
      image: nginx
      ports:
        - containerPort: 80
          name: "http-server"
      volumeMounts:
        - mountPath: "/media"
          name: authentik-media

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 apply -f pod.yaml
# Give it 30s to be created

$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 exec -it -n authentik task-pv-pod -- /bin/bash

# Inside the container:
$ chown -R 1000:1000 /media
$ exit

# Outside the container:
$ kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n authentik delete pod task-pv-pod
$ rm pod.yaml
```

Scale back up the `authentik-server` Deployment to 1 (you can do this in ArgoCD UI or via the CLI).

The `authentik-server` pod should now come up as healthy.

## Access Authentik

Authentik will be available over its configured ingress domain name `auth.indigo.dalmura.cloud`, once it's running you'll need to navigate to the [initial setup page](https://auth.indigo.dalmura.cloud/if/flow/initial-setup/) where you can set the admin user `akadmin`'s password.

Immediately perform the following steps:
* Use the email `indigo+auth@dalmura.cloud`
* Set a temporary password for the `akadmin` user
* You will now be logged in as the `akadmin` user automatically
* Click the 'Admin interface' in the top right
* Go to 'Directory' => 'Users'
* Create a `site-admin` user with type as 'Internal', `indigo+auth@dalmura.cloud` as the email
* Click on the `site-admin` user
* Click 'Set password' and persist the new admin credentials into your external password vault
* Add the `site-admin` user into the 'authentik Admins' group
* Log out and log in as the new `site-admin` user
* Click the 'Admin interface' in the top right
* Navigate back to 'Directory' => 'Users'
* Delete the `akadmin` default user

After this you can proceed to [Authentik Configuration](INDIGO-CORE-1-APPS-WAVE-3-AUTHENTIK.md) for configuring Authentik itself.
