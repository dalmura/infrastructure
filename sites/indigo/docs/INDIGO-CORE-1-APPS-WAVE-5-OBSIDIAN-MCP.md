# Wave 5 - Obsidian MCP Setup

This document describes the `obsidian-mcp` application: a headless [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) mirror of the Obsidian vault, plus a file-based [obsidian-mcp](https://github.com/ykoellmann/obsidian-mcp) server that gives [Hermes Agent](INDIGO-CORE-1-APPS-WAVE-5-HERMES.md) read/write access to it over MCP.

We assume you have followed [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md), the [Obsidian LiveSync section](INDIGO-CORE-1-APPS-WAVE-5.md#obsidian-livesync-couchdb-setup), and [Hermes Agent Setup](INDIGO-CORE-1-APPS-WAVE-5-HERMES.md).

---

## 1. Why this shape

The vault is stored in CouchDB with **end-to-end encryption enabled**. That rules out every MCP server that reads LiveSync's CouchDB documents directly (for example `obsidian-self-mcp` or `obsidian-livesync-mcp`): they require `encrypt: false`, and their writes are not compatible with encrypted chunk documents.

So LiveSync's own sync core performs the decryption:

```
Obsidian devices ──LiveSync (E2EE)──► CouchDB (obsidian-livesync)
                                          ▲
                                          │ replication (_changes)
                        ┌─────────────────┴──────────────────┐
                        │ pod: obsidian-mcp                  │
                        │  ├─ livesync  ──► /vault  (PVC)    │
                        │  └─ mcp :8000 ──► /vault  (PVC)    │
                        └─────────────────▲──────────────────┘
                                          │ ClusterIP + bearer token
                                   Hermes (hermes namespace)
```

Consequences to keep in mind:

* **CouchDB stays the source of truth and stays encrypted.** The PVC is a derived, disposable mirror. If it is lost, the vault is re-fetched from CouchDB.
* **LiveSync's E2EE protects CouchDB, not the PVC.** The volume holds plaintext Markdown and the LiveSync passphrase. It is deliberately on `cluster-nobackup` so a Longhorn backup does not copy the plaintext into S3.
* **The MCP server is not reachable from an ingress.** Hermes is its only client; authentication is a static bearer token.

## 2. Repository layout

```text
sites/indigo/clusters/dal-indigo-core-1/wave-5/
├── app/templates/obsidian-mcp.yaml          # ArgoCD Application
└── overlays/obsidian-mcp/
    ├── kustomization.yaml
    ├── service-account.yaml                 # obsidian-mcp-sa
    ├── secret-store-site.yaml               # Vault SecretStore
    ├── external-secret.yaml                 # obsidian-mcp-env
    ├── pvc.yaml                             # obsidian-mcp-data (cluster-nobackup)
    ├── deployment.yaml                      # livesync + mcp containers
    ├── service.yaml                         # ClusterIP :8000
    └── network-policy.yaml                  # Hermes ingress, CouchDB + DNS egress
```

## 3. Container images

| Container | Image | Notes |
|---|---|---|
| `livesync` | `ghcr.io/vrtmrz/livesync-cli:1.0.50-cli` | Public. The `-cli` suffix is part of the tag; `1.0.50` does not exist. |
| `mcp` | `ghcr.io/ykoellmann/obsidian-mcp:2.1.2` | Public, multi-arch (`linux/amd64`, `linux/arm64`). Tag has no `v` prefix. Digest `sha256:82c3892e6fc42453441a7da5cae63260c446d373a54c766e2e6e7b5c12f92cc6`. |

> [!IMPORTANT]
> The `htarrega/obsidian-mcp` fork's README advertises `ghcr.io/htarrega/obsidian-mcp`, but **that package does not exist**. The fork has no GitHub releases and no Release workflow runs, so nothing was ever published. The image that does exist is published by the original project, [ykoellmann/obsidian-mcp](https://github.com/ykoellmann/obsidian-mcp), whose Release workflow hardcodes `ghcr.io/ykoellmann/obsidian-mcp`.
>
> The fork's `v2.1.2` tag and the upstream release are the same commit (`b4c76f7`), so the upstream image is the same code. Do not go looking for an `htarрега` image.

No mirroring step is needed: like the other third-party images in this repository, it is pulled directly from the public registry. If you want an organisation-controlled copy (for example to survive an upstream deletion), vendor it deliberately and update `deployment.yaml` in the same change:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin
# Copies the multi-arch index, unlike docker pull/tag/push which would keep
# only the host platform and break the arm64 workers.
docker buildx imagetools create \
  --tag ghcr.io/dalmura/obsidian-mcp:2.1.2 \
  ghcr.io/ykoellmann/obsidian-mcp:2.1.2
```

To build it yourself instead (multi-arch, from the same tag):

```bash
git clone --depth 1 --branch v2.1.2 https://github.com/ykoellmann/obsidian-mcp.git /tmp/obsidian-mcp
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/dalmura/obsidian-mcp:2.1.2 --push /tmp/obsidian-mcp
```

Either way, pin by tag or digest in `deployment.yaml`; `latest` is rejected by the repository validator.

## 4. Vault configuration

### 4.1 Policy and Kubernetes auth role

The application reads `site/data/wave-5/obsidian-mcp/*` as `obsidian-mcp-sa`:

```bash
vault policy write workload-reader-obsidian-mcp-secrets -<<EOF
path "site/data/wave-5/obsidian-mcp/*" {
    capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/workload-reader-obsidian-mcp-secrets \
   bound_service_account_names=obsidian-mcp-sa \
   bound_service_account_namespaces=obsidian-mcp \
   token_policies=workload-reader-obsidian-mcp-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

Hermes also reads the `MCP_API_KEY` property, so extend the existing Hermes policy (the role itself does not change):

```bash
vault policy write workload-reader-hermes-secrets -<<EOF
path "site/data/wave-5/hermes/*" {
    capabilities = ["read", "list"]
}
path "site/data/wave-5/obsidian-mcp/config" {
    capabilities = ["read"]
}
EOF
```

### 4.2 CouchDB database user

CouchDB has no read-only role: any member of a database can write to it. Create a dedicated user and scope it to **only this vault's database**. Never reuse the CouchDB admin account.

The database must already exist (connect a device with the LiveSync plug-in once, or create it as admin). Then:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-livesync \
  port-forward svc/obsidian-livesync-couchdb 5984:5984 &
PF_PID=$!

ADMIN_USERNAME="$(vault kv get -field=ADMIN_USERNAME site/wave-5/obsidian-livesync/couchdb-secrets)"
ADMIN_PASSWORD="$(vault kv get -field=ADMIN_PASSWORD site/wave-5/obsidian-livesync/couchdb-secrets)"
OBSIDIAN_MCP_PASSWORD='<generate-a-password>'
COUCH_DB='<vault-database-name>'
```

Create the user:

```bash
curl -fsS -u "$ADMIN_USERNAME:$ADMIN_PASSWORD" \
  -X PUT "http://localhost:5984/_users/org.couchdb.user:obsidian-mcp" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg password "$OBSIDIAN_MCP_PASSWORD" \
        '{_id:"org.couchdb.user:obsidian-mcp",name:"obsidian-mcp",type:"user",roles:[],password:$password}')"
```

Grant it membership of only the vault database:

> [!NOTE]
> This replaces the database's `_security` object. Read it first (`GET /$COUCH_DB/_security`) and merge any existing members or roles instead of overwriting them.

```bash
curl -fsS -u "$ADMIN_USERNAME:$ADMIN_PASSWORD" \
  -X PUT "http://localhost:5984/$COUCH_DB/_security" \
  -H 'Content-Type: application/json' \
  -d '{"admins":{"names":[],"roles":[]},"members":{"names":["obsidian-mcp"],"roles":[]}}'
```

Verify, then stop the port-forward:

```bash
curl -fsS -u "obsidian-mcp:$OBSIDIAN_MCP_PASSWORD" "http://localhost:5984/$COUCH_DB"
kill "$PF_PID"
```

### 4.3 Secret values

Read the E2EE settings from a working Obsidian device: **Settings → Self-hosted LiveSync → Remote Configuration**. Every value under `externalSecret.data` must exist in Vault or External Secrets Operator reports `SecretSyncedError`.

| Key | Value |
|---|---|
| `LIVESYNC_COUCH_URI` | `http://obsidian-livesync-couchdb.obsidian-livesync.svc.cluster.local:5984` |
| `LIVESYNC_COUCH_DBNAME` | the vault's CouchDB database name |
| `LIVESYNC_COUCH_USER` | `obsidian-mcp` |
| `LIVESYNC_COUCH_PASSWORD` | the password from 4.2 |
| `LIVESYNC_PASSPHRASE` | the E2EE passphrase (**not** the Setup URI passphrase) |
| `LIVESYNC_PATH_NORMALIZATION_VERSION` | copy `pathNormalizationVersion` from the plug-in; do not guess |
| `LIVESYNC_USE_PATH_OBFUSCATION` | `true` / `false`, matching `usePathObfuscation` |
| `LIVESYNC_HANDLE_FILENAME_CASE_SENSITIVE` | `true` / `false`, matching the plug-in |
| `MCP_API_KEY` | `openssl rand -hex 32`; also consumed by Hermes |

> [!IMPORTANT]
> A mismatch in `pathNormalizationVersion`, `usePathObfuscation`, or `handleFilenameCaseSensitive` does not fail loudly. It produces duplicate documents, missing files, or refused operations. Copy the values from the plug-in rather than guessing.

```bash
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg couch_uri 'http://obsidian-livesync-couchdb.obsidian-livesync.svc.cluster.local:5984' \
  --arg couch_db '<vault-database-name>' \
  --arg couch_user 'obsidian-mcp' \
  --arg couch_password '<couchdb-user-password>' \
  --arg passphrase '<live-sync-e2ee-passphrase>' \
  --arg pnv '<path-normalization-version>' \
  --arg obfuscate '<true|false>' \
  --arg case_sensitive '<true|false>' \
  --arg mcp_key "$(openssl rand -hex 32)" \
  '{
    LIVESYNC_COUCH_URI: $couch_uri,
    LIVESYNC_COUCH_DBNAME: $couch_db,
    LIVESYNC_COUCH_USER: $couch_user,
    LIVESYNC_COUCH_PASSWORD: $couch_password,
    LIVESYNC_PASSPHRASE: $passphrase,
    LIVESYNC_PATH_NORMALIZATION_VERSION: $pnv,
    LIVESYNC_USE_PATH_OBFUSCATION: $obfuscate,
    LIVESYNC_HANDLE_FILENAME_CASE_SENSITIVE: $case_sensitive,
    MCP_API_KEY: $mcp_key
  }' >"$tmp"

vault kv put site/wave-5/obsidian-mcp/config @"$tmp"
```

## 5. Deploy

```bash
argocd app sync wave-5        # discovers the obsidian-mcp child Application
argocd app sync obsidian-mcp
```

Then let Hermes pick up the new MCP server. The chart only seeds `/opt/data/config.yaml` on first boot, so the running PVC copy remains authoritative:

1. Set `bootstrap.overwrite: true` in `values/hermes/values.yaml` for one sync.
2. `argocd app sync hermes`.
3. Revert `bootstrap.overwrite: false` and sync again.

Alternatively, edit `/opt/data/config.yaml` on the PVC and run `/reload-mcp` in a Hermes session.

## 6. Bootstrap and verification

### 6.1 First start

The `livesync` container starts in `daemon` mode. On an empty local database it performs LiveSync's initial replication from CouchDB and writes the files into `/vault`.

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp get pods,pvc,externalsecret
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp logs deploy/obsidian-mcp -c livesync -f
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp logs deploy/obsidian-mcp -c mcp -f
```

If the remote is locked, check and unlock it:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  exec deploy/obsidian-mcp -c livesync -- \
  livesync-cli --vault /vault --settings /data/.livesync/settings.json remote-status
```

If the initial replication does not complete, do a deliberate one-shot fetch. It replaces the local database with the remote state, so **stop the daemon first** (one CLI process per database directory):

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  scale deploy/obsidian-mcp --replicas=0
```

Then run a one-off pod that reuses the existing volume and settings, and fetches the remote state:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: livesync-fetch
  namespace: obsidian-mcp
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 10000
    runAsGroup: 10000
    fsGroup: 10000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: livesync
      image: ghcr.io/vrtmrz/livesync-cli:1.0.50-cli
      args:
        - --vault
        - /vault
        - --settings
        - /data/.livesync/settings.json
        - fetch
        - --force
      env:
        - name: HOME
          value: /data
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: data
          mountPath: /data
          subPath: livesync
        - name: data
          mountPath: /vault
          subPath: vault
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: obsidian-mcp-data
    - name: tmp
      emptyDir:
        sizeLimit: 256Mi
```

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp apply -f - <<'EOF'
# paste the manifest above
EOF

kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  logs -f pod/livesync-fetch
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  delete pod/livesync-fetch
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  scale deploy/obsidian-mcp --replicas=1
```

> [!CAUTION]
> Never run `rebuild`. It reconstructs the **remote** database from the local mirror and can overwrite the authoritative CouchDB state. `fetch --force` is the recovery direction.

### 6.2 MCP health and auth

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  port-forward svc/obsidian-mcp 8000:8000

TOKEN="$(kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
  get secret obsidian-mcp-env -o jsonpath='{.data.MCP_API_KEY}' | base64 -d)"

curl -sS http://localhost:8000/health
curl -sS -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
```

Reuse the `Mcp-Session-Id` response header on a follow-up `tools/list` request. Or use `npx @modelcontextprotocol/inspector` against `http://localhost:8000/mcp` with the same bearer token.

### 6.3 Round trip

1. Edit a note on a device, then confirm the file appears under `/vault` in the `mcp` container (`.md` mtime changes).
2. Ask Hermes to read the note through the `obsidian` MCP server.
3. Create a note through Hermes, confirm it reaches the device, then confirm the change is visible in `audit.jsonl`:

   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-mcp \
     exec deploy/obsidian-mcp -c mcp -- tail -n 20 /data/audit.jsonl
   ```

## 7. Operations

* **Image updates**: bump the tag in `deployment.yaml`. The upstream image tag drops the GitHub `v` prefix (`v2.1.2` → `2.1.2`), and only the `ykoellmann` registry path exists. If the org ever vendors a copy to `ghcr.io/dalmura`, change the image reference in the same commit.
* **Token rotation**: update `MCP_API_KEY` in Vault, force both ExternalSecrets to refresh (`kubectl annotate externalsecret <name> force-sync="$(date +%s)" --overwrite`), and let Reloader restart `obsidian-mcp` and `hermes`. Both sides must be refreshed together.
* **Passphrase or path-setting rotation**: stop the Deployment, update Vault, remove the `livesync` subdirectory on the PVC, then start again so the mirror is rebuilt from CouchDB. Do not change `pathNormalizationVersion` on a working mirror.
* **PVC loss**: delete the PVC and start the Deployment again. `Delete=false` protects it from a prune, so this is deliberate. The mirror is re-fetched; CouchDB is unaffected.
* **Hermes approvals**: `approvals.mode: manual`, `cron_mode: deny`, and `unattended_mode: deny` remain in place. The MCP entry also uses `trust: untrusted`, so every write-capable tool call prompts even if the server's own annotations claim otherwise.
* **Path fencing**: writes are currently unrestricted across the vault. To confine the agent, add `WRITE_PATHS` (for example `AI/`) to the `mcp` container, create that folder in the vault, and restart. `DENY_READ_PATHS`/`DENY_WRITE_PATHS` already protect `.obsidian/`, `.trash/`, and `_AI_INSTRUCTIONS.md`.
* **Destructive tools stay off**: `ENABLE_DELETE`, `ENABLE_MOVE`, `ENABLE_FOLDER_RENAME`, and `ENABLE_BULK_REPLACE` are explicitly `false`, so those tools are never registered. Turning one on is a deliberate decision, not a configuration tweak.
* **Single replica only**: `livesync` keeps a PouchDB database and state under `/data`; two pods on the same volume corrupt it. The Deployment uses `Recreate` for the same reason.
* **Volume sizing**: `10Gi` covers a vault of roughly 3GiB (mirror + PouchDB copy + revision history). Check `du -sh /vault` and `du -sh /data` before assuming it is enough; grow the PVC rather than pruning state.
