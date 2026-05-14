# Exposing Services Publicly

This covers the process and knowledge for exposing a Kubernetes service to the public internet via the `ingress-public` Traefik instance.

## Kubernetes Ingress Configuration

To expose a service publicly, the Ingress resource must be configured with specific settings to ensure correct routing, DNS management, and security.

### Required Fields
*   `ingressClassName: ingress-public`: Binds to the Public Traefik instance
*   `external-dns.alpha.kubernetes.io/target: indigo.dalmura.cloud`: External-DNS creates a CNAME in AWS Route53 pointing the sites Public IP or Dynamic DNS Hostname

### Example Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-public-app
  annotations:
    cert-manager.io/cluster-issuer: dalmura-letsencrypt-prod
    external-dns.alpha.kubernetes.io/hostname: app.indigo.dalmura.cloud
    external-dns.alpha.kubernetes.io/target: indigo.dalmura.cloud
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
    traefik.ingress.kubernetes.io/router.tls: true
    # Apply standard security stack
    traefik.ingress.kubernetes.io/router.middlewares: >-
      traefik-public-geoblock@kubernetescrd,
      traefik-public-ratelimit@kubernetescrd,
      traefik-public-crowdsec-bouncer@kubernetescrd,
      traefik-public-security-headers@kubernetescrd
spec:
  ingressClassName: ingress-public
  tls:
    - hosts:
        - app.indigo.dalmura.cloud
      secretName: app-cert
  rules:
    - host: app.indigo.dalmura.cloud
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-service
                port:
                  number: 80
```

---

## Router Configuration

External traffic hitting the sites Public IP needs to be forwarded to the public Traefik LoadBalancer IP (eg. `192.168.77.11`) assigned via MetalLB.

### Port Forwarding
Add the following NAT rules to your router:

| Protocol | Port | Internal IP | Description |
| :--- | :--- | :--- | :--- |
| **TCP** | `443` | `192.168.77.11` | Main HTTPS traffic |
| **TCP** | `32406` | `192.168.77.11` | Plex (if using public entrypoint) |

We don't forward TCP/80 as it's entirely optional and just not a good idea.

### Split-Brain DNS
To keep local devices talking directly to the cluster without requiring any hairpin/etc, we add a few static DNS entries to the router.

```bash
/ip dns static add name=auth.indigo.dalmura.cloud address=192.168.77.11
/ip dns static add name=anubis.indigo.dalmura.cloud address=192.168.77.11
...
```

Ensure these are kept up to date in the `network` repo.

---

## Security Considerations

All public services should utilize the following Traefik middlewares:
1. GeoBlock: Restricts access to specific countries (e.g., AU/NZ)
3. RateLimit: Protects against brute-force and DoS attacks
2. CrowdSec: Automatically blocks known malicious IP addresses
4. Security Headers: Ensures modern browser security policies are enforced

Internally applications should enforce the use of SSO or Auth Proxy via Authentik, ensuring Authentik is the only source of authentication.

By default anything that interacts with the publically exposed services *must* have the following k8s best practices applied:
* Network Policies attached to all workloads
* k8s Service Accounts must be least privileged
* All AWS credentials used must be via the IAM Vendor and least privileged
