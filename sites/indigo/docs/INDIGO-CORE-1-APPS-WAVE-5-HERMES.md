# Wave 5 - Hermes Agent Setup & Action Plan

This document outlines the setup steps required to initialize Authentik OIDC, Vault roles, policies, and secrets for [Hermes Agent](https://github.com/NousResearch/hermes-agent), routed through the in-cluster [Archestra](INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md) LLM gateway and reachable via Slack Socket Mode and the private web dashboard (`https://hermes.indigo.dalmura.cloud`).

We assume you've followed the steps at [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md), [`Application Authentication`](INDIGO-APPS-AUTH.md), and [`Archestra Setup`](INDIGO-CORE-1-APPS-WAVE-5-ARCHESTRA.md).

---

## 1. Authentik OIDC Configuration

Log into [Authentik](https://auth.indigo.dalmura.cloud).

> [!IMPORTANT]
> Hermes Agent's built-in dashboard OIDC provider does not maintain its own email or group allowlist; any identity issued a token for the client can sign in and access the agent workspace. **Access control must be enforced in Authentik via group binding on the Application.**

### Step 1.1: Create OAuth2/OpenID Provider
Navigate to **Applications** => **Providers** => **Create**:
* **Type**: `OAuth2/OpenID Provider`
* **Name**: `Provider for Hermes`
* **Authorization flow**: `implicit-consent` (or `default-provider-authorization-implicit-consent`)
* **Client type**: `Confidential` (Hermes authenticates to the token endpoint with a client secret; PKCE is still used)
* **Redirect URIs**:
  ```text
  https://hermes.indigo.dalmura.cloud/auth/callback
  ```
* **Scopes**: Ensure `openid`, `email`, `profile`, and `offline_access` are selected. Authentik (2024.2+) only issues a refresh token when the client requests `offline_access` **and** the provider includes the `offline_access` scope mapping; without both, the dashboard has no refresh token and sends users back through login every time the access token expires (Authentik's default is 5 minutes).
* **Subject mode**: `Based on the User's hashed ID` (default)
* Note down the generated **Client ID** and **Client Secret** (the secret is shown once; store it in Vault in [Step 3](#3-store-application-secrets-in-vault)).

### Step 1.2: Create Application & Bind Group
Navigate to **Applications** => **Applications** => **Create**:
* **Name**: `Hermes`
* **Slug**: `hermes`
* **Group**: `general` (or your preferred group)
* **Provider**: Select `Provider for Hermes`
* **Launch URL**: `https://hermes.indigo.dalmura.cloud/`
* Open the **Policy / Group / User Bindings** tab on the newly created `Hermes` application and **bind a restricted group** (e.g. `site-admins` or a dedicated `hermes-users` group). Do **not** leave the application unbound.

---

## 2. Vault Roles and Policies Setup

Log into your `vault` CLI environment.

### Step 2.1: Create Vault Workload Reader Policy & Kubernetes Auth Role
Run the following to grant the `hermes` ServiceAccount in the `hermes` namespace read access to `site/data/wave-5/hermes/*`, plus the Obsidian MCP token that Hermes needs for its `obsidian` MCP server:

```bash
vault policy write workload-reader-hermes-secrets -<<EOF
path "site/data/wave-5/hermes/*" {
    capabilities = ["read", "list"]
}
# MCP_API_KEY for the obsidian-mcp server (see INDIGO-CORE-1-APPS-WAVE-5-OBSIDIAN-MCP.md)
path "site/data/wave-5/obsidian-mcp/config" {
    capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/workload-reader-hermes-secrets \
   bound_service_account_names=hermes \
   bound_service_account_namespaces=hermes \
   token_policies=workload-reader-hermes-secrets \
   audience='https://192.168.77.2:6443/' \
   ttl=24h
```

---

## 3. Store Application Secrets in Vault

Before storing secrets, create a **standard Virtual API Key** in Archestra (**Virtual Keys**) and map it to the provider key(s) Hermes needs. Hermes uses the OpenAI-compatible Unified Model API at `/v1/unified-model`, and the default model is `deepseek:deepseek-flash`, so at minimum map the **DeepSeek** provider key. The model ID must match an entry returned by `GET /v1/unified-model/models`.

Using the Vault CLI (or Web UI at `site/data/wave-5/hermes/config`), store the Archestra virtual key, Authentik OIDC Client ID and Client Secret, GitHub token, Slack Socket Mode credentials, and the Home Assistant long-lived token:

```bash
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg archestra_key '<archestra-virtual-api-key>' \
  --arg github_token '<github-fine-grained-pat>' \
  --arg oidc_client_id '<authentik-client-id-from-step-1>' \
  --arg oidc_client_secret '<authentik-client-secret-from-step-1>' \
  --arg slack_bot_token 'xoxb-...' \
  --arg slack_app_token 'xapp-...' \
  --arg slack_allowed_users '<comma-separated-slack-member-ids>' \
  --arg slack_home_channel 'C01234567890' \
  --arg slack_home_channel_name 'general' \
  --arg hass_token '<home-assistant-long-lived-access-token>' \
  '{
    ARCHESTRA_API_KEY: $archestra_key,
    GITHUB_TOKEN: $github_token,
    HERMES_DASHBOARD_OIDC_CLIENT_ID: $oidc_client_id,
    HERMES_DASHBOARD_OIDC_CLIENT_SECRET: $oidc_client_secret,
    SLACK_BOT_TOKEN: $slack_bot_token,
    SLACK_APP_TOKEN: $slack_app_token,
    SLACK_ALLOWED_USERS: $slack_allowed_users,
    SLACK_HOME_CHANNEL: $slack_home_channel,
    SLACK_HOME_CHANNEL_NAME: $slack_home_channel_name,
    HASS_TOKEN: $hass_token
  }' >"$tmp"

vault kv put site/wave-5/hermes/config @"$tmp"
```

> [!NOTE]
> Every key listed under `externalSecret.data` in `values/hermes/values.yaml` must exist in its referenced Vault path or External Secrets Operator reports `SecretSyncedError`. `OBSIDIAN_MCP_TOKEN` is the exception in location only: it is read from `site/wave-5/obsidian-mcp/config` property `MCP_API_KEY`, not from `site/wave-5/hermes/config`. See [Obsidian MCP Setup](INDIGO-CORE-1-APPS-WAVE-5-OBSIDIAN-MCP.md).

### Slack home channel

`SLACK_HOME_CHANNEL` is the default destination for cron results and proactive/cross-platform messages. While it is unset, Hermes posts a one-time onboarding prompt the first time it talks to you on Slack:

> No home channel is set for Slack. A home channel is where Hermes delivers cron job results and cross-platform messages. Type `/hermes sethome` ...

* Get the ID from the channel's details: right-click the channel → **View channel details** → scroll to the bottom → **Channel ID** (starts with `C` for public channels, `G` for private channels).
* Invite the bot to that channel (`/invite @Hermes`); Hermes never joins channels automatically.
* `SLACK_HOME_CHANNEL_NAME` is cosmetic and only used in prompts and logs. Both keys are declared under `externalSecret.data`, so both must exist in Vault; remove `SLACK_HOME_CHANNEL_NAME` from that list if you don't want to set it.
* If `SLACK_HOME_CHANNEL` is set here, the onboarding prompt is suppressed and cron delivery works even when the gateway process restarts with a fresh database.

### Slack slash commands

The Slack app declares every Hermes command in its app manifest. An app created manually ("From scratch") without the generated manifest has no `/hermes` command, so the `/hermes sethome` hint fails with "app did not respond" and the gateway logs `slack_bolt.AsyncApp: Unhandled request`. For this deployment, prefer setting `SLACK_HOME_CHANNEL` in Vault, which needs no slash command. To get the full command set, run `hermes slack manifest --agent-view --write` and paste the generated `~/.hermes/slack-manifest.json` into **Features → App Manifest**, then reinstall the app.

> [!NOTE]
> A home channel set with `/hermes sethome` is written to `.env` on the `/opt/data` PVC, not to this repository. The `SLACK_HOME_CHANNEL` value injected from `hermes-env` takes precedence, so setting it in Vault during bootstrap avoids drift and survives a fresh volume.

### GitHub token

Hermes uses `GITHUB_TOKEN` for its own GitHub integration: the `hermes doctor` connectivity probe, update checks, Skills Hub installs, and credentials for private plugin/MCP/profile clones. It is not available to ordinary shell `git` commands, because Hermes strips it from terminal subprocesses.

Create a **fine-grained personal access token** at <https://github.com/settings/tokens>, scoped to only the repositories Hermes should touch, then pick the smallest tier that covers the job:

| Tier | Permissions | Enables |
|---|---|---|
| Read-only (recommended default) | `Contents: Read-only` (`Metadata: Read-only` is always included) | Update checks, `hermes doctor`, Skills Hub installs of public skills, `git clone` of private plugin/MCP/profile repos |
| Read + collaborate | `Contents: Read and write`, `Pull requests: Read and write`, `Issues: Read and write` | Pushing branches, opening PRs and issues, PR review (the bundled `github` skill's write workflows) |
| Add CI access | `Actions: Read-only`, `Workflows: Read and write` | Reading workflow runs, pushing changes under `.github/workflows/` |

Notes:

* `Metadata: Read-only` is mandatory on every fine-grained token and is included automatically.
* Fine-grained tokens cannot fork arbitrary public repositories. `hermes skills publish --target github` forks the target, pushes a branch, then opens a PR, so it needs a **classic** token with `public_repo`, or a token whose account already has a fork.
* A classic token with `repo`, `workflow`, and `read:org` covers every tier above but is not scoped to specific repositories. Prefer fine-grained.
* **Expiration**: 90 days is a reasonable default; rotate it in Vault before it expires.
* If the repositories belong to an organisation, an org owner may need to approve the token, and SSO-enforced organisations require you to authorise the token for that org.
* Hermes can also authenticate as a **GitHub App** (`GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY_PATH`) instead of a PAT; it mints a short-lived installation token per call. That avoids a long-lived user credential but needs an app created and installed on the org.

> [!IMPORTANT]
> Hermes treats `GITHUB_TOKEN` as a Tier-1 secret and strips it from terminal subprocesses. That means its internal GitHub features use it, but an agent shell command will not inherit it. The bundled `github` skill can still read it from `${HERMES_HOME}/.env` via its `gh-env.sh` helper. Also note that the current image does not ship the `gh` CLI, so the skill's `gh`-based workflows need `gh` installed (for example via a custom image or an init container) or must fall back to `git` and raw REST.

---

## 4. Sync & Deploy via ArgoCD

Once Authentik and Vault are configured:

```bash
# Sync traefik-private and archestra so the new Cilium ingress/egress rules are active
argocd app sync traefik-private
argocd app sync archestra

# Sync wave-5 parent app to discover the hermes child application
argocd app sync wave-5

# Sync hermes child application
argocd app sync hermes
```

---

## 5. Verification

1. **Verify ExternalSecret & Pod Status**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get pods,svc,ingress,pvc,externalsecret,secretstore

   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get externalsecret hermes-env \
     -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
   ```
2. **Verify PostSync Helm Test Job**:
   ```bash
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     get jobs,pods -l app.kubernetes.io/component=test
   kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
     logs job/hermes-test --tail=-1
   ```
3. **Verify Dashboard & Authentik SSO**:
   * Navigate to [https://hermes.indigo.dalmura.cloud/](https://hermes.indigo.dalmura.cloud/).
   * Confirm unauthenticated requests redirect to Authentik (`https://auth.indigo.dalmura.cloud/application/o/authorize/...`).
   * Confirm a member of the bound Authentik group can sign in and view sessions/status/logs, while a non-member is denied by Authentik.

---

## 6. Obsidian MCP Server

Hermes exposes the vault through the `obsidian` MCP server declared in `values/hermes/values.yaml`. The server itself is documented in [Obsidian MCP Setup](INDIGO-CORE-1-APPS-WAVE-5-OBSIDIAN-MCP.md); this section only covers the Hermes side.

```yaml
config:
  mcp_servers:
    obsidian:
      url: http://obsidian-mcp.obsidian-mcp.svc.cluster.local:8000/mcp
      headers:
        Authorization: "Bearer ${OBSIDIAN_MCP_TOKEN}"
      trust: untrusted
      skip_preflight: true
```

* `OBSIDIAN_MCP_TOKEN` is injected from `hermes-env`; its value comes from `site/wave-5/obsidian-mcp/config` property `MCP_API_KEY`. Both applications must read the same Vault key, and both ExternalSecrets must be refreshed together when the token is rotated.
* `trust: untrusted` makes every write-capable MCP tool call require approval through the standard approval surface, on top of `approvals.mode: manual`.
* `skip_preflight: true` suppresses Hermes' fail-fast content-type probe, which a FastMCP endpoint fails on a bare `GET /mcp`.
* Tools are not filtered here. Use `hermes mcp configure obsidian` after the first successful connection to pick a surface, then copy the resulting `tools.include` back into values.
* As with any other `config.*` change, set `bootstrap.overwrite: true` for one sync, or edit `/opt/data/config.yaml` on the PVC, otherwise the running copy stays authoritative.

Verify registration:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec deploy/hermes -- \
  tail -n 50 /opt/data/logs/agent.log | grep -i mcp
```

The log should report the `obsidian` server and its tool count. Then ask Hermes to list or read a note; a write should trigger the approval prompt.

---

## 7. Home Assistant

Hermes talks to Home Assistant through the official `homeassistant` plugin. The plugin provides four LLM-callable tools — `ha_list_entities`, `ha_get_state`, `ha_list_services`, and `ha_call_service` — and, if enabled as a gateway platform, a WebSocket subscription that forwards state-change events to the agent. This deployment only enables the tools.

The plugin is not bundled with the Hermes image, and the chart has no values key for plugins. Install it once into the `/opt/data` profile; it persists across restarts and upgrades:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec deploy/hermes -- \
  hermes plugins install homeassistant
```

### Step 7.1: Create a Long-Lived Access Token

In Home Assistant, open your **Profile** => **Security** => **Long-lived access tokens**, click **Create token**, name it `Hermes Agent`, and copy the token (it is shown once).

Add it to the existing secret without dropping the other keys:

```bash
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

vault kv get -format=json site/wave-5/hermes/config | jq '.data.data' >"$tmp"
jq --arg token '<long-lived-access-token>' '. + {HASS_TOKEN: $token}' "$tmp" >"$tmp.new"
mv "$tmp.new" "$tmp"

vault kv put site/wave-5/hermes/config @"$tmp"
```

Then force an ExternalSecret refresh; Reloader restarts the Deployment because `reloader.stakater.com/auto` is set:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes \
  annotate externalsecret hermes-env force-sync="$(date +%s)" --overwrite
```

`HASS_TOKEN` also has to reach the **house-manager profile's secret scope** described in [Step 7.3](#step-73-multiplexed-profiles-and-profile-secret-scope). The `seed-house-manager-hass` init container reads it from the same `hermes-env` Secret, so no extra Vault write is needed; verify it after the rollout:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec deploy/hermes -- \
  sh -c 'grep -o "^HASS_[A-Z]*=" /opt/data/profiles/house-manager/.env'
```

### Step 7.2: Connection details

* `HASS_URL` (`http://ha.home-assistant.svc.cluster.local:8080`) and `HASS_TOKEN` live only in the `house-manager` profile's `/opt/data/profiles/house-manager/.env`. The `ha` Service listens on **8080** and forwards to the pod's named port `http` (8123), like the existing `traefik-private` policy.
* `HASS_TOKEN` is read from `site/wave-5/hermes/config` and follows the same rotation flow as the other secrets; the init container re-seeds the profile `.env` on every rollout. With it set in that profile's scope, the `homeassistant` toolset activates automatically; no `platforms.homeassistant` entry is needed in `config.yaml`.
* Traffic is allowed in both directions: `overlays/hermes/network-policy.yaml` (egress to the `home-assistant` pods on 8123) and `overlays/home-assistant/network-policy.yaml` (ingress from the `hermes` namespace to 8123).
* Setting only `HASS_TOKEN` does **not** subscribe to state-change events, so Home Assistant noise never reaches Slack. To enable reactive automations, add `platforms.homeassistant.extra.watch_domains` (or `watch_entities`) in `values/hermes/values.yaml` with `bootstrap.overwrite: true` for one sync, as described in [Operations & Maintenance Notes](#8-operations--maintenance-notes).
* The plugin blocks the `shell_command`, `command_line`, `python_script`, `pyscript`, `hassio`, and `rest_command` service domains, and validates entity IDs before calling the REST API.

### Step 7.3: Multiplexed profiles and profile secret scope

One gateway process serves every profile (`default`, `event-manager`, `house-manager`, …): `gateway.multiplex_profiles` defaults to `true` and cannot be disabled. In that mode Hermes resolves credentials through a **profile secret scope**, which is built from `<profile home>/.env` plus optional external secret sources — it deliberately does **not** fall back to the pod environment, because profile A's keys must not leak into profile B's turns. The practical consequences are:

* Anything injected with `envFrom`/`extraEnv` (the `hermes-env` Secret) is visible to process-level code but **not** to `get_secret()` inside a profile turn. That is why `ha_*` tools stayed disabled even though the Deployment had `HASS_TOKEN` in its environment.
* A credential that only one profile should hold belongs in that profile's `.env`, e.g. `/opt/data/profiles/house-manager/.env`. A credential every profile may use belongs in the managed scope (`HERMES_MANAGED_DIR`, layered over every profile's `.env`). Do not use the managed scope for per-profile secrets — it is process-wide.

This deployment keeps Home Assistant credentials in the `house-manager` profile only. The `.env` there lives on the `/opt/data` PVC, so instead of editing it by hand the `seed-house-manager-hass` init container writes it from the `hermes-env` Secret on every start:

```text
/opt/data/profiles/house-manager/.env
  HASS_URL=...
  HASS_TOKEN=...
```

Rules the init container follows: it runs after `fix-data-ownership` (so the volume is writable as uid 10000), it no-ops when the profile directory does not exist, it replaces any previous `HASS_TOKEN` line (including the commented placeholder) rather than appending duplicates, and it leaves an operator-set `HASS_URL` alone. Rewriting the file is picked up on the next profile turn because `build_profile_secret_scope()` re-reads `<home>/.env` each time; no gateway restart is needed beyond the rollout the chart performs anyway.

To scope another credential the same way, copy that init container with a different profile directory, or extend the script with a loop. Never widen it to `/opt/data/.env` or the managed scope: that is how a credential ends up visible to every profile.

Relevant values: `extraInitContainers` (`seed-house-manager-hass`). `HASS_URL` is deliberately *not* set in `extraEnv`, because the pod environment is the wrong layer for profile credentials.

### Step 7.4: Verification

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec deploy/hermes -- \
  sh -c 'curl -fsS -H "Authorization: Bearer $HASS_TOKEN" http://ha.home-assistant.svc.cluster.local:8080/api/'
```

This should print `{"message":"API running."}` — the `curl` runs in the pod shell, where `HASS_TOKEN` comes from `hermes-env`; profile turns never see that copy. Then confirm the profile `.env` was seeded:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec deploy/hermes -- \
  sh -c 'grep -o "^HASS_[A-Z]*=" /opt/data/profiles/house-manager/.env'
```

To check what a profile actually resolves — `hermes tools list` is not a valid check because the CLI has no secret scope and falls back to the pod env — build that profile's scope the way the gateway does. `house-manager` should report the token, `default` must not:

```bash
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n hermes exec -i deploy/hermes -- \
  sh -c 'cd /opt/hermes && .venv/bin/python -' <<'PY'
from pathlib import Path
from agent.secret_scope import build_profile_secret_scope

for home in ("/opt/data", "/opt/data/profiles/house-manager"):
    scope = build_profile_secret_scope(Path(home))
    print(home, "HASS_TOKEN set:", bool(scope.get("HASS_TOKEN")), "HASS_URL:", scope.get("HASS_URL"))
PY
```

Ask Hermes in Slack for a state change (for example, "turn on the kitchen lights") — `ha_call_service` should be the tool it reaches for, with `ha_list_entities` first to resolve the entity ID.

---

## 8. Operations & Maintenance Notes
* **Persistent Config (`bootstrap.overwrite`)**: The chart seeds `/opt/data/config.yaml` only on first boot (`bootstrap.overwrite: false`) so runtime changes made through the dashboard or CLI persist across restarts. If you later change `dashboard.publicUrl`, `dashboard.trustedProxies`, or `config.*` in `values/hermes/values.yaml`, temporarily set `bootstrap.overwrite: true` for one sync (or update `/opt/data/config.yaml` on the PVC), then revert `bootstrap.overwrite` to `false`.
* **Storage & Backups**: `/opt/data` (`HERMES_HOME`) uses a `10Gi` `cluster-regular` Longhorn block volume, which is covered by the `daily-default-backup` recurring S3 job and protected with `Delete=false` / `helm.sh/resource-policy: keep`.
* **Volume Ownership**: The chart's normal entrypoint chowns `/opt/data` to uid/gid `10000` as root before dropping privileges, but the non-root `podSecurityContext` here prevents that and `fsGroup` only changes the group. A fresh Longhorn volume therefore leaves the directory owned by `root:10000`, and Hermes rejects it with `gateway inaccessible: unsafe_control_path (/opt/data is owned by uid 0, expected uid 10000 ...)`. The `fix-data-ownership` init container runs as root and chowns the volume root before the agent starts. This is expected and safe; do not remove it while `podSecurityContext.runAsUser` is non-root.
* **Single Replica Only**: Hermes uses SQLite in WAL mode under `/opt/data`; keep `replicaCount: 1` with `Recreate` strategy.
* **Confidential OIDC Client**: The Authentik provider is `Confidential`; Hermes sends `HERMES_DASHBOARD_OIDC_CLIENT_SECRET` to the token endpoint while still using PKCE. To rotate the secret, generate a new one on the Authentik provider, update `site/data/wave-5/hermes/config` in Vault, then force an ExternalSecret refresh (`kubectl -n hermes annotate externalsecret hermes-env force-sync="$(date +%s)" --overwrite`) and let Reloader restart the Deployment.
* **Dashboard Sessions**: Hermes stores the ID token in the `hermes_session_at` cookie (Max-Age = the provider's token TTL) and only sets the `hermes_session_rt` cookie when the provider returns a refresh token. Authentik requires `offline_access` to be both requested in `HERMES_DASHBOARD_OIDC_SCOPES` and enabled on the provider's scope mappings; without it every access-token expiry (Authentik default: 5 minutes) forces a fresh login. Diagnose from `/opt/data/logs/dashboard-auth.log` on the PVC: after the first 5 minutes you should see `refresh_success` events, and no repeating `session_rejected` with `reason=no_cookie` (which means both cookies are absent, not merely expired). Adding the scope takes effect on the next rollout, but existing cookies carry no refresh token, so each user needs one fresh sign-in first.
* **Secret Layout**: Every key rendered under `externalSecret.data` must exist in `site/wave-5/hermes/config`; the chart injects the whole `hermes-env` Secret via `envFrom`, so new keys take effect after refresh and restart. That Secret is **not** visible to profile turns — profile-scoped code reads only `<profile home>/.env` (see [Step 7.3](#step-73-multiplexed-profiles-and-profile-secret-scope)). Credentials a single profile needs are seeded into its `.env` (`seed-house-manager-hass` is the template); anything only one profile should hold must never go into `envFrom`, `extraEnv`, or a managed scope.
