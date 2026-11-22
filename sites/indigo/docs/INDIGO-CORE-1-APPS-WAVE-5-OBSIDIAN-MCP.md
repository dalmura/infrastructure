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
* **The internal MCP server on 8000 is Hermes-only.** It is not reachable from an ingress. A second read/write instance on 8001 is exposed publicly for the Grok/Tesla harness; its writes are scoped to `Inbox/` (section 8).

## 2. Repository layout

```text
sites/indigo/clusters/dal-indigo-core-1/wave-5/
├── app/templates/obsidian-mcp.yaml          # ArgoCD Application
└── overlays/obsidian-mcp/
    ├── kustomization.yaml
    ├── service-account.yaml                 # obsidian-mcp-sa
    ├── secret-store-site.yaml               # Vault SecretStore
    ├── external-secret.yaml                 # obsidian-mcp-env
    ├── sealedsecret-obsidian-mcp-car-auth.yaml # public Grok/Tesla API key
    ├── pvc.yaml                             # obsidian-mcp-data (cluster-nobackup)
    ├── deployment.yaml                      # livesync + mcp + mcp-rw containers
    ├── service.yaml                         # ClusterIP :8000 and :8001
    └── network-policy.yaml                  # Hermes + traefik-public ingress, CouchDB + DNS egress
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

CouchDB has no read-only role: any account allowed to sync can write the vault. The goal is **scope**, not read-only. Create a dedicated user and make it a **database admin for this vault's database only**:

* A database admin can read/write all documents, including design documents, and cannot create or delete databases or read `_users`.
* A plain `member` cannot write design documents, and LiveSync's local PouchDB creates `_design/chunks`; if replication ever pushes it, a member gets a `403`.
* A **server** admin can do anything to every database, including `_users` and server config. Do not hand that credential to this pod.

> [!NOTE]
> If you deliberately accept a server-admin blast radius, you can reuse the CouchDB admin credentials from `site/wave-5/obsidian-livesync/couchdb-secrets` in 4.3 and skip this section. The rest of the runbook is unchanged; only the scope of the credential differs.

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

Grant it database admin **without changing the rest of the security object**:

> [!IMPORTANT]
> Do not overwrite `_security` with empty arrays. CouchDB 3 creates databases with the `_admin` role in both `admins` and `members`; clearing them opens regular documents to every user. Merge instead, as below.

```bash
CURRENT="$(curl -fsS -u "$ADMIN_USERNAME:$ADMIN_PASSWORD" \
  "http://localhost:5984/$COUCH_DB/_security")"
NEW="$(jq '
  .admins.names  = (((.admins.names  // []) + ["obsidian-mcp"]) | unique)
  | .members.names = (((.members.names // []) + ["obsidian-mcp"]) | unique)
' <<<"$CURRENT")"

curl -fsS -u "$ADMIN_USERNAME:$ADMIN_PASSWORD" \
  -X PUT "http://localhost:5984/$COUCH_DB/_security" \
  -H 'Content-Type: application/json' -d "$NEW"
```

Verify, then stop the port-forward:

```bash
curl -fsS -u "obsidian-mcp:$OBSIDIAN_MCP_PASSWORD" "http://localhost:5984/$COUCH_DB"
kill "$PF_PID"
```

> [!WARNING]
> Re-creating the database — deleting and re-uploading the vault from a device, or a clean rebuild — resets `_security` to `{"admins":{"roles":["_admin"]},"members":{"roles":["_admin"]}}`. The user document in `_users` survives, but this grant does not, so the pod starts returning `403: Forbidden` and the daemon stops with `Initial replication failed, cannot continue`. Re-run the grant above after any database re-create. See 7.2.

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
> A mismatch in `pathNormalizationVersion`, `usePathObfuscation`, `handleFilenameCaseSensitive`, or the passphrase does not say which value is wrong. Note IDs are derived from the passphrase and the path, so a wrong input produces `id-derivation-mismatch` and the daemon stops at `Initial replication failed, cannot continue` — or, on an existing mirror, duplicate documents, missing files, or refused operations. Copy the values from the plug-in rather than guessing, and diagnose with 7.2.

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

If the initial replication does not complete, work through 7.2 first. **Do not unlock the remote** to get past it: unlocking goes through `markRemoteLocked(false)`, which rewrites `accepted_nodes` to the device that clicked and evicts every other device. If the cause is the lock, the fix is to accept this device (7.1), not to remove the lock.

If the cause is instead a stale or mismatched local database — a partial initial replication, or an `id-derivation-mismatch` — do a deliberate one-shot fetch. It replaces the local database with the remote state, so **stop the daemon first** (one CLI process per database directory):

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

   There is no delete tool (`ENABLE_DELETE=false`), so a test note has to be removed in Obsidian on a device. Create it inside a throwaway folder with `create_folder_tool` so the cleanup is one folder deletion.

## 7. Operations

* **Image updates**: bump the tag in `deployment.yaml`. The upstream image tag drops the GitHub `v` prefix (`v2.1.2` → `2.1.2`), and only the `ykoellmann` registry path exists. If the org ever vendors a copy to `ghcr.io/dalmura`, change the image reference in the same commit.
* **Token rotation**: update `MCP_API_KEY` in Vault, force both ExternalSecrets to refresh (`kubectl annotate externalsecret <name> force-sync="$(date +%s)" --overwrite`), and let Reloader restart `obsidian-mcp` and `hermes`. Both sides must be refreshed together.
* **Passphrase or path-setting rotation**: stop the Deployment, update Vault, remove the `livesync` subdirectory on the PVC, then start again so the mirror is rebuilt from CouchDB. Do not change `pathNormalizationVersion` on a working mirror.
* **PVC loss**: delete the PVC and start the Deployment again. `Delete=false` protects it from a prune, so this is deliberate. The mirror is re-fetched; CouchDB is unaffected. A new PVC is also a **new device identity**, so if the remote is locked the daemon will be refused with `node-locked` until the new node id is accepted — see 7.1.
* **Remote lock and device acceptance**: the remote database is locked, and `accepted_nodes` decides which devices may replicate. Locking, unlocking, accepting a device, and the failure modes are covered in 7.1. Never use the plug-in's lock or unlock toggle for this.
* **Hermes approvals**: `approvals.mode: manual`, `cron_mode: deny`, and `unattended_mode: deny` remain in place for shell and terminal tools. The `obsidian` MCP entry is **trusted** (no `trust:` key), so MCP tool calls run without a per-call prompt. `trust: untrusted` is not usable for this server: `obsidian-mcp` publishes no `readOnlyHint` annotations on any of its 33 tools, and Hermes treats missing annotations as write-capable, so `untrusted` gates reads and writes alike. The safety boundary is the server configuration below plus `audit.jsonl`, not a prompt.
* **Trust is cached at discovery**: Hermes records a server's trust tier when it connects and does not re-read it per call. Changing `trust` requires a restart (`kubectl -n hermes rollout restart deploy/hermes`). `command_allowlist` is the exception — hand edits to it are re-synced from disk on every check.
* **Path fencing**: writes are currently unrestricted across the vault. To confine the agent, add `WRITE_PATHS` (for example `AI/`) to the `mcp` container, create that folder in the vault, and restart. `DENY_READ_PATHS`/`DENY_WRITE_PATHS` already protect `.obsidian/`, `.trash/`, and `_AI_INSTRUCTIONS.md`.
* **Destructive tools stay off**: `ENABLE_DELETE`, `ENABLE_MOVE`, `ENABLE_FOLDER_RENAME`, and `ENABLE_BULK_REPLACE` are explicitly `false`, so those tools are never registered. Turning one on is a deliberate decision, not a configuration tweak.
* **Single replica only**: `livesync` keeps a PouchDB database and state under `/data`; two pods on the same volume corrupt it. The Deployment uses `Recreate` for the same reason.
* **Volume sizing**: `10Gi` covers a vault of roughly 3GiB (mirror + PouchDB copy + revision history). Check `du -sh /vault` and `du -sh /data` before assuming it is enough; grow the PVC rather than pruning state.

### 7.1 Remote lock and device acceptance

The remote database carries a lock in `_local/obsydian_livesync_milestone`:

```json
{ "locked": true, "accepted_nodes": ["<desktop>", "<android>", "<headless-vault>"] }
```

LiveSync enforces it in the client, during the pre-replication compatibility check:

```js
if (milestone.locked && milestone.accepted_nodes.indexOf(thisDeviceNodeId) === -1)
  return milestone.cleaned ? "NODE_CLEANED" : "NODE_LOCKED";
```

What that means in practice:

* `locked: true` plus the device in `accepted_nodes` — replicates normally.
* `locked: true` and the device **not** listed — refused before any document is exchanged, `recoveryHint.reason = node-locked`. This is not a partial failure: nothing is pulled and nothing is pushed.
* `locked: false` — the check short-circuits. `accepted_nodes` is still recorded, but it is documentation only.

The lock is a **cooperative guardrail, not access control**. The check runs in the plug-in and the CLI, so anyone holding the CouchDB credentials and the E2EE passphrase can read and write the database directly. It also does not prevent an unaccepted device from *downloading*: a blocked plug-in offers **Fetch**, which replaces that device's local database with the remote state. Its purpose is to stop a device that lost or reset its local state from pushing deletions into a healthy remote.

Each device's node id is a random 10-character string minted on first run and stored in its **local** database. On this pod that is `/data` on the PVC, so **a re-created PVC is a new device**, not the same one returning.

**Current state**: `locked: true`, with the desktop, the Android device, and `headless-vault` accepted. List them at any time:

```bash
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
U=$(vault kv get -field=ADMIN_USERNAME site/wave-5/obsidian-livesync/couchdb-secrets)
P=$(vault kv get -field=ADMIN_PASSWORD site/wave-5/obsidian-livesync/couchdb-secrets)
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n obsidian-livesync \
  port-forward svc/obsidian-livesync-couchdb 5984:5984 &
curl -fsS -u "$U:$P" http://localhost:5984/<db>/_local/obsydian_livesync_milestone \
  | jq '{locked, accepted_nodes, devices: (.node_info | keys)}'
```

> [!IMPORTANT]
> Do not use the plug-in's "lock database" or "I am ready, unlock the database" buttons, and do not run `lock-remote`. Every one of them goes through `markRemoteLocked()`, which writes `accepted_nodes = [this.nodeid]` — the single device that clicked. That silently evicts every other device. This is how the phone was dropped once already.

#### Accepting a device

There is no control in the plug-in to accept *another* device; the joined-devices dialog is read-only apart from "Forget device". Two additive options:

1. **From the device itself.** A plug-in shows the button "I have made a backup, mark this device as resolved" wherever replication is blocked by the lock, and the CLI has the same operation:

   ```bash
   # inside a one-off pod that mounts the same volume, after scaling the daemon to 0
   livesync-cli --vault /vault --settings /data/.livesync/settings.json mark-resolved
   ```

   Both run `markRemoteResolved()`, which appends: `accepted_nodes = [...existing, this.nodeid]`, and leaves `locked` untouched. Because the plug-in only renders that button while the remote is *locked*, an unlocked remote offers no way to mark a device resolved.

2. **Directly, as one merge.** Read the milestone, add the id, put it back with the same `_rev`. This preserves every other field and is what the command above would have written:

   ```bash
   DOC="$(curl -fsS -u "$U:$P" http://localhost:5984/<db>/_local/obsydian_livesync_milestone)"
   NEW="$(jq --arg id "<node-id>" '.accepted_nodes = ((.accepted_nodes + [$id]) | unique)' <<<"$DOC")"
   curl -fsS -u "$U:$P" -X PUT -H 'Content-Type: application/json' \
     http://localhost:5984/<db>/_local/obsydian_livesync_milestone -d "$NEW"
   ```

   The milestone is a `_local` document: it is never replicated to devices, so editing it directly touches only the server's copy of the state. **Set or clear `locked` the same way** — read, change that one field, PUT with the current `_rev` — because the plug-in buttons that would do it also truncate `accepted_nodes`.

The CLI holds its PouchDB lock, so a `mark-resolved` against the same volume has to wait for the daemon to stop: scale the Deployment to `0`, run it, then scale back. The volume is `ReadWriteOnce`, so any pod doing this has to be pinned to the same node.

### 7.2 Diagnosing a stalled daemon

The daemon reports every replication failure the same way, with no reason:

```text
[Daemon] Replicating with remote...
[Daemon] Initial replication failed, cannot continue
[Error] Command 'daemon' failed
```

Check these in order:

| Symptom in the log | Cause | Fix |
|---|---|---|
| `(Notice) The request may have failed. The reason sent by the server: 403: Forbidden` | Database re-created, so `_security` lost the grant | Re-run 4.2 |
| Silent failure, `_security` fine | `node-locked`: this identity is not in `accepted_nodes` | 7.1 |
| Silent failure, device accepted | `id-derivation-mismatch`: settings do not match the ones the vault was created with | 4.3 |

For the silent cases the reason is in the return value, which the daemon never prints. Patch it into a throwaway copy of the bundle rather than guessing:

```bash
DOCKER_CONFIG=/tmp/opencode/dockercfg-empty   # avoid a stale ghcr.io auth entry
CID=$(docker create ghcr.io/vrtmrz/livesync-cli:1.0.50-cli)
docker cp "$CID:/app/dist/index.cjs" /tmp/index.cjs && docker rm "$CID"
python3 - <<'PY'
p = "/tmp/index.cjs"
s = open(p).read()
old = '''\t\tlog("Replicating with remote...");
\t\tif (!isReplicationCompleted(await core.services.replication.replicateUnattended({
\t\t\ttrigger: "daemon",
\t\t\tinteraction: NO_INTERACTION
\t\t}))) {'''
new = '''\t\tlog("Replicating with remote...");
\t\tconst __res = await core.services.replication.replicateUnattended({
\t\t\ttrigger: "daemon",
\t\t\tinteraction: NO_INTERACTION
\t\t});
\t\twriteStderrLine(standardIo, "[DBG] " + JSON.stringify(__res, (k, v) => (typeof v === "symbol" ? String(v) : v)));
\t\tif (!isReplicationCompleted(__res)) {'''
assert s.count(old) == 1, "call site not found; the bundle layout changed"
open(p, "w").write(s.replace(old, new))
PY
```

Run that bundle with `-v /tmp/index.cjs:/app/dist/index.cjs:ro` against a scratch directory plus a settings file built from Vault, and the output names the reason directly. The settings file takes the same keys as 4.3 (`couchDB_URI`, `couchDB_USER`, `couchDB_PASSWORD`, `couchDB_DBNAME`, `passphrase`, `usePathObfuscation`, `pathNormalizationVersion`, `handleFilenameCaseSensitive`), with `couchDB_URI` pointed at a port-forward of the CouchDB service:

```text
[DBG] {"status":"failed","error":{},"recoveryHint":{"reason":"node-locked"}}
```

`node-locked` and `node-cleaned` come from the lock (7.1); `id-derivation-mismatch` means the ID derivation inputs differ from the ones the vault was created with (`handleFilenameCaseSensitive`, `usePathObfuscation`, `pathNormalizationVersion`). Copy those from a device that already syncs instead of choosing them; 4.3 lists which Vault key feeds each one.

## 8. Public Grok/Tesla endpoint (read-write, Inbox/ only)

The `mcp-rw` container is a second `obsidian-mcp` instance on port `8001`, exposed through the public `ha-hooks.indigo.dalmura.cloud` host under a sealed UUID path. It lets the Grok/Tesla harness read the vault and write notes, but writes are allowlisted to `Inbox/`.

### 8.1 What is exposed

- URL: `https://ha-hooks.indigo.dalmura.cloud/<uuid>/mcp`
- Auth: `Authorization: Bearer <MCP_CAR_API_KEY>`
- Transport: Streamable HTTP (`/mcp`)
- Write scope: `Inbox/` only
- Read scope: whole vault except `.obsidian/`, `.trash/`, `private/`
- Destructive tool groups disabled (`ENABLE_DELETE`, `ENABLE_MOVE`, `ENABLE_FOLDER_RENAME`, `ENABLE_BULK_REPLACE` all `false`)
- Write preconditions required (`REQUIRE_WRITE_PRECONDITIONS=true`)
- Audit log: `/data/mcp-rw/audit.jsonl`, readable with `get_audit_log_tool`
- The existing `mcp` container on `8000` is unchanged and remains Hermes-only.

Ensure `Inbox/` exists in the vault before the first write. The server can create the configured scope and descendants, but not ancestors above it.

### 8.2 Retrieve the URL and token

The UUID lives in the Traefik file-provider config inside the `ha-mcp-dynamic` SealedSecret:

```bash
kubectl --kubeconfig sites/indigo/kubeconfigs/dal-indigo-core-1 \
  -n traefik-public get secret ha-mcp-dynamic \
  -o jsonpath='{.data.ha-mcp\.yml}' | base64 -d \
  | grep -A4 'obsidian-mcp:'
```

Look for the `PathPrefix` on the `obsidian-mcp` router. The full URL is:

```text
https://ha-hooks.indigo.dalmura.cloud/<uuid>/mcp
```

The car token is sealed separately in the `obsidian-mcp` namespace:

```bash
kubectl --kubeconfig sites/indigo/kubeconfigs/dal-indigo-core-1 \
  -n obsidian-mcp get secret obsidian-mcp-car-auth \
  -o jsonpath='{.data.MCP_CAR_API_KEY}' | base64 -d
```

### 8.3 Client config

```json
{
  "mcpServers": {
    "obsidian": {
      "type": "http",
      "url": "https://ha-hooks.indigo.dalmura.cloud/<uuid>/mcp",
      "headers": {
        "Authorization": "Bearer <MCP_CAR_API_KEY>"
      }
    }
  }
}
```

### 8.4 Network and Traefik

- `wave-5/overlays/obsidian-mcp/network-policy.yaml` allows `traefik-public` to port `8001`.
- `wave-2/overlays/traefik-public/network-policy-traefik.yaml` allows egress to `obsidian-mcp` and DNS for `obsidian-mcp.obsidian-mcp`.
- The `obsidian-mcp` router in the sealed file-provider config uses the public rate-limit, CrowdSec-no-AppSec, and security-header middlewares, then strips the UUID before forwarding `/mcp` to `obsidian-mcp:8001`.

### 8.5 Rotation

The car token and the UUID are independent.

- **Token:** generate a new key, seal it for `obsidian-mcp/obsidian-mcp-car-auth`, replace `sealedsecret-obsidian-mcp-car-auth.yaml`, and sync. The pod restarts because the env var changed.
- **UUID:** re-seal the Traefik file-provider config with a new prefix for the `obsidian-mcp` router and middleware, then sync `traefik-public`. If the router does not reload within a minute, restart the `traefik-public` Deployment.

Keep the token out of Git and out of client logs. The sealed secrets are the only secret material committed.
