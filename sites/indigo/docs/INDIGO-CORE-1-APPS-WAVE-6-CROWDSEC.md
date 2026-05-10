# `dal-indigo-core-1` Apps - Wave 6 - CrowdSec

This guide covers the deployment and activation of **CrowdSec**, providing collaborative security automation and IP reputation for the `dal-indigo` cluster.

## Architecture: "Rock Solid" Ingress Hardening

CrowdSec is integrated into the public ingress stack (Traefik) using a decoupled, GitOps-friendly architecture:

1.  **Detection:** CrowdSec Agents (DaemonSet) tail the logs of all Traefik pods.
2.  **Analysis:** The CrowdSec LAPI (Local API) processes these logs and maintains a database of malicious IPs.
3.  **Remediation:** A Traefik Plugin (Middleware) queries the LAPI for every request. If an IP has a bad reputation, Traefik drops the connection at the edge.

### Decoupling & Stability
To avoid circular dependencies between Wave 2 (Traefik) and Wave 6 (CrowdSec):
*   **Optional Mounts:** Traefik has an `optional` secret mount for the API key. It will start and function even if CrowdSec isn't deployed yet.
*   **Pre-shared Keys:** We use a `SealedSecret` to deploy a shared key to both namespaces simultaneously, avoiding manual `cscli` commands.

## Activation Steps

Because the API key must be encrypted (Sealed) specifically for your cluster, you must perform these steps once to activate the bouncer.

### 1. Generate a Secure Key
Generate a random string that will serve as the shared password between Traefik and CrowdSec.

```bash
export BOUNCER_KEY=$(openssl rand -base64 32)
```

### 2. Seal the Secrets
You must seal the key for both the `traefik-public` and `crowdsec` namespaces.

**For Traefik:**
```bash
echo -n "$BOUNCER_KEY" | kubectl create secret generic crowdsec-bouncer-key \
  --namespace traefik-public \
  --from-file=key=/dev/stdin \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > traefik-key.yaml
```

**For CrowdSec:**
```bash
echo -n "$BOUNCER_KEY" | kubectl create secret generic crowdsec-bouncer-key \
  --namespace crowdsec \
  --from-file=key=/dev/stdin \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > crowdsec-key.yaml
```

### 3. Update the Repository
Update the file `clusters/dal-indigo-core-1/wave-6/overlays/crowdsec/bouncer-key.sealed.yaml` with the combined output of the two files above (separated by `---`).

### 4. Verify Activation
Once ArgoCD syncs the new secrets:

1.  **Check Secrets:** `kubectl get secret crowdsec-bouncer-key -n traefik-public`
2.  **Check Bouncer:** 
    ```bash
    kubectl exec -n crowdsec deployment/crowdsec -- cscli bouncers list
    ```
    You should see `traefik-bouncer` listed as "Valid".

## Middleware Chain

The following services are protected by the CrowdSec chain:
*   **Authentik:** `auth.indigo.dalmura.cloud`
*   **Anubis:** `anubis.indigo.dalmura.cloud`

The standard security chain is:
`Geoblock` -> `CrowdSec` -> `RateLimit` -> `Anubis (Bot Check)` -> `SecurityHeaders`
