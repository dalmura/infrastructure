# Wave 5 - Home Assistant Configuration

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 5](INDIGO-CORE-1-APPS-WAVE-5.md) and have Home Assistant already running

Previously, Authentik Proxy Auth was enabled in front of HA, which broke the HA Mobile App login process. We have removed Authentik Proxy Auth from the main HA ingress (`ha.indigo.dalmura.cloud`) so users connect directly to Home Assistant and authenticate via its built-in authentication layer. Note that the code-server helper (`ha-code.indigo.dalmura.cloud`) remains Authentik-protected for security.

## Setup HACS

HACS will persist across Pod recreation events due to it being installed in the PV's directory `/config`.

```bash
# Debug into the HA pod
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n home-assistant exec -it ha-0 -- sh

$ wget -O - https://get.hacs.xyz | bash -
$ exit

# Restart the HA pod
kubectl --kubeconfig kubeconfigs/dal-indigo-core-1 -n home-assistant delete pod ha-0
```

Install HACS within HA:
* Reload your browser tab and log back into HA
* Add a new Integration and search for HACS
* Accept all the checkboxes and perform the github auth

You should now have a HACS menu item on the left!

## Other Integrations

A list of other integrations via HACS:
* [Airtouch 5](https://www.home-assistant.io/integrations/airtouch5/)
* [Emerald HWS (via HACS)](https://github.com/ross-w/emerald-hws-ha)
* [IKEA Dirigera Platform](https://github.com/sanjoyg/dirigera_platform)
* [Meross Lan](https://github.com/krahabb/meross_lan)
* [Solis Cloud Control](https://github.com/mkuthan/solis-cloud-control)
* [Solis Sensor](https://github.com/hultenvp/solis-sensor)

## Hermes Agent Access

The Hermes Agent in `wave-5` uses this instance through the internal `ha` Service at `http://ha.home-assistant.svc.cluster.local:8080` (Service port 8080, pod port 8123). It authenticates with a Long-Lived Access Token stored in Vault at `site/wave-5/hermes/config` property `HASS_TOKEN`, and Cilium policies allow the traffic in both directions. See [Hermes Agent Setup](INDIGO-CORE-1-APPS-WAVE-5-HERMES.md#7-home-assistant).

## Matter Server (matterjs-server)

Required [`matterjs-server`](https://github.com/matter-js/matterjs-server) deployed in the `home-assistant` namespace to allow for HA to reach matter devices natively.

WebSocket Endpoint URL is `ws://matter-server.home-assistant.svc.cluster.local:5580/ws` (configure this in Home Assistant 'Matter' integration).

The Matter Server Web UI is exposed privately at `ha-matter.indigo.dalmura.cloud` behind Authentik Proxy Auth (see `wave-5/overlays/home-assistant/ingress-matter-server.yaml`). Configure a reverse proxy application in Authentik for `ha-matter.indigo.dalmura.cloud` following [INDIGO-APPS-AUTH.md](INDIGO-APPS-AUTH.md).

## Public Webhooks

Home Assistant [webhook triggers](https://www.home-assistant.io/docs/automation/trigger/#webhook-trigger) create an unauthenticated endpoint at `/api/webhook/<webhook_id>` (the `webhook_id` is the only secret, so treat it like a password).
To let external sites trigger automations, a dedicated public ingress is exposed at `ha-hooks.indigo.dalmura.cloud` (see `wave-5/overlays/home-assistant/ingress-hooks.yaml`).
Within Home Assistant, webhook triggers must be configured with `local_only: false` otherwise HA rejects internet requests.

## MCP Server (Public, Obfuscated Path)

Home Assistant's built-in [Model Context Protocol](https://www.home-assistant.io/integrations/mcp_server) server exposes a Streamable HTTP endpoint at `/api/mcp`. It is published on the existing public `ha-hooks.indigo.dalmura.cloud` host under a hard-to-guess UUID path:

```
https://ha-hooks.indigo.dalmura.cloud/<uuid>/api/mcp
```

The UUID is **not stored in plaintext in this repo**. It lives in the Traefik file-provider config inside the `ha-mcp-dynamic` SealedSecret (`wave-2/overlays/traefik-public/sealedsecret-ha-mcp-dynamic.yaml`). Traefik mounts that Secret at `/etc/traefik/dynamic`, watches it, and builds the `ha-mcp` router and `stripPrefix` middleware from it.

To read the current URL from the cluster:

```bash
kubectl --kubeconfig sites/indigo/kubeconfigs/dal-indigo-core-1 \
  -n traefik-public get secret ha-mcp-dynamic \
  -o jsonpath='{.data.ha\.mcp\.yml}' | base64 -d
```

The UUID is an obscurity layer only. Home Assistant still requires authentication: send an administrator's [long-lived access token](https://www.home-assistant.io/docs/authentication/#your-account-profile) as `Authorization: Bearer <token>`. Treat the UUID and the token as secrets.

### Why the UUID is stripped

Home Assistant has no concept of a sub-path, so the file-provider `stripPrefix` middleware removes `/<uuid>` before forwarding. The router matches only `/<uuid>/api/mcp`, so the HA UI, `/auth/*`, and the rest of `/api/*` are not reachable on this host.

### Prerequisites

1. Enable the Model Context Protocol integration in HA (Settings > Devices & services > Add Integration > Model Context Protocol, or Settings > System > AI). Require an administrator where appropriate.
2. Create a long-lived access token for that administrator.
3. Use the Streamable HTTP transport. The legacy SSE transport (`/mcp_server/sse`) advertises an absolute `/mcp_server/messages/<session_id>` endpoint and therefore cannot be used through the UUID prefix.

### Client configuration

Most MCP clients accept a URL and a static Authorization header. Example:

```json
{
  "mcpServers": {
    "home-assistant": {
      "url": "https://ha-hooks.indigo.dalmura.cloud/<uuid>/api/mcp",
      "headers": {
        "Authorization": "Bearer <HA long-lived access token>"
      }
    }
  }
}
```

OAuth-based MCP clients that rely on `/.well-known/oauth-authorization-server` discovery will not work: HA publishes discovery at the host root, which is not routed through the UUID path. Use a long-lived token instead.

### Security notes

- The file-provider router keeps `traefik-public-ratelimit`, `traefik-public-crowdsec-bouncer`, and `traefik-public-security-headers`. `traefik-public-geoblock` is deliberately omitted so cloud-hosted MCP clients outside AU/NZ can connect.
- CrowdSec AppSec inspects request bodies. If legitimate MCP tool calls are blocked with `403`, add a CrowdSec exclusion for this route. The file-provider config is the place to change the middleware list.
- The `traefik-public` Cilium egress policy already allows `home-assistant` on `ha:8123`, and the `home-assistant` policy already allows ingress from `traefik-public`, so no network-policy change was needed.
- The SealedSecret is encrypted with the cluster's sealed-secrets key. Repo readers cannot read the UUID, but cluster readers with access to the `traefik-public` namespace can.
- The `ha-mcp-dynamic` volume is mounted with `optional: true` so a missing or broken secret cannot take down the other public hosts.

### Rotating the secret path

Generate a new UUID, rebuild the dynamic config from the current one, and re-seal it. Do not commit the plaintext YAML or Secret manifest.

```bash
export KUBECONFIG=sites/indigo/kubeconfigs/dal-indigo-core-1
OLD_YAML="$(kubectl -n traefik-public get secret ha-mcp-dynamic -o jsonpath='{.data.ha\.mcp\.yml}' | base64 -d)"
OLD_UUID="$(printf '%s\n' "$OLD_YAML" | sed -n 's|.*PathPrefix(`/\([0-9a-f-]*\)/api/mcp`).*|\1|p' | head -1)"
UUID="$(cat /proc/sys/kernel/random/uuid)"
printf '%s\n' "$OLD_YAML" | sed "s|/${OLD_UUID}|/${UUID}|g" > /tmp/ha-mcp-dynamic.yml
kubectl create secret generic ha-mcp-dynamic \
  --namespace traefik-public \
  --from-file=ha-mcp.yml=/tmp/ha-mcp-dynamic.yml \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
      --controller-namespace kube-system --format yaml \
  > sites/indigo/clusters/dal-indigo-core-1/wave-2/overlays/traefik-public/sealedsecret-ha-mcp-dynamic.yaml
rm -f /tmp/ha-mcp-dynamic.yml
```

Update every client with the new URL afterwards. The SealedSecret is bound to the `traefik-public/ha-mcp-dynamic` name and namespace; re-seal it if either changes. Traefik's file provider watches the mounted directory; if the router does not appear after a secret update, restart the `traefik-public` Deployment to force a reload.

### Verification

After Argo CD syncs, retrieve the URL (see above) and send an `initialize` request:

```bash
curl -i "https://ha-hooks.indigo.dalmura.cloud/<uuid>/api/mcp" \
  -H "Authorization: Bearer <HA long-lived access token>" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

A `401` means the UUID path and middleware are correct but the token is missing or wrong. A `404` means the router did not load (check the Traefik file-provider config and logs) or HA's MCP integration is not enabled.
