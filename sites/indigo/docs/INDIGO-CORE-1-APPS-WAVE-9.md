# Provision the Wave 9 applications for dal-indigo-core-1

These are:
* `cnpg-test` for experimenting with CNPG
* `whoami` for experimenting with Reverse Proxies

This wave is just for experimentation and is entirely optional.

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have all the precursors up and running
* `argocd` is logged in
* `vault` is logged in (see [dynamic user docs](INDIGO-CORE-1-APPS-WAVE-3-DYNAMIC-AWS-USERS.md) if not)
* Traefik ingress controller is running
* Vault is operational

## Verifying apps

You can verify the k8s resources emitted by each app by running `kustomize` yourself
```bash
pushd clusters/dal-indigo-core-1/wave-9/app/templates/

% cat cnpg-test.yaml
...
  source:
    repoURL: https://github.com/dalmura/infrastructure.git
    path: sites/indigo/clusters/dal-indigo-core-1/wave-9/overlays/cnpg-test
    targetRevision: HEAD
...

# This would equate to the following kustomize command
# All k8s resources that would be created are printed out by this
kubectl kustomize 'https://github.com/dalmura/infrastructure.git/sites/indigo/clusters/dal-indigo-core-1/wave-9/overlays/cnpg-test?ref=HEAD'
```

## Create the wave-9 parent app & deploy children
```bash
argocd app create wave-9 \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/dalmura/infrastructure.git \
    --path sites/indigo/clusters/dal-indigo-core-1/wave-9/app \
    --sync-policy automated \
    --auto-prune \
    --self-heal

# Create the child applications
argocd app sync wave-9
```

You can now go and experiment by deploying individual apps in [ArgoCD - Wave 9](https://argocd.indigo.dalmura.cloud/applications/argocd/wave-9).

## Connecting to cnpg-test clusters

First we need to port forward the postgres service to our laptop:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 port-forward svc/cnpg-test-1-db-rw -n cnpg-test 5432:5432
```

Then we need to get the DB credentials:
```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n cnpg-test get secret cnpg-test-1-db-app -o jsonpath='{.data.username}' | base64 -d | sed 's/$/\n/g'

kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n cnpg-test get secret cnpg-test-1-db-app -o jsonpath='{.data.password}' | base64 -d | sed 's/$/\n/g'
```

Finally we connect:
```bash
docker run -it --rm --network host postgres:latest psql -h localhost -U app -p 5432
```

Can then generate some fake data to test out the backup/restore process:
```sql
CREATE TABLE users (name text, age int);

-- Set 1
INSERT INTO users VALUES ('Person A', 30), ('Person B', 25), ('Person C', 20);

-- Set 2
INSERT INTO users VALUES ('Person D', 30), ('Person E', 25), ('Person F', 20);

-- Set 3
INSERT INTO users VALUES ('Person G', 30), ('Person H', 25), ('Person I', 20);
```
