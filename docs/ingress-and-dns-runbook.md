# Ingress, DNS, & Real-Time WebSocket Runbook

This guide covers DNS routing, Traefik Ingress configuration, SSL/TLS certificate automation, and WebSocket routing for real-time messaging on `denmannsolutions.com`.

## 1. DNS Records Required

Configure the following records in your DNS provider (Cloudflare, Route53, Namecheap, etc.):

| Record Type | Host | Points To | Notes |
| --- | --- | --- | --- |
| `A` / `CNAME` | `denmannsolutions.com` | Cluster Public IP / Ingress | Root apex domain |
| `CNAME` | `www.denmannsolutions.com` | `denmannsolutions.com` | Canonical web alias |
| `CNAME` | `api.denmannsolutions.com` | `denmannsolutions.com` | Backend REST & Socket.IO endpoint |

If proxying through Cloudflare:
- Ensure SSL/TLS encryption mode is set to **Full (strict)**.
- Set WebSocket connections to **Enabled**.
- Set maximum client upload limit appropriately (or disable Cloudflare proxying on `api.denmannsolutions.com` to support 50MB direct uploads).

---

## 2. Ingress & Traefik Routing

The production Ingress manifest in `apps/production/ingress.yaml` defines:

- **IngressClass**: `traefik`
- **TLS Issuer**: `cert-manager.io/cluster-issuer: letsencrypt-production`
- **Secret**: `king-mongkut-social-production-tls`
- **Body Size**: `50m` (supports attachments, photos, avatars)
- **SSL Redirect**: `true`

### WebSocket Routing for Chat & Real-Time Feed
Socket.IO communicates over:
`https://api.denmannsolutions.com/socket.io/?EIO=4&transport=websocket`

Traefik automatically handles WebSocket upgrade requests:
```http
Connection: Upgrade
Upgrade: websocket
```
No custom ingress route or special rewrite middleware is required for Socket.IO when routed directly to `king-mongkut-social-api`.

---

## 3. Cert-Manager Certificate Validation

Check certificate status after applying the ingress:

```bash
kubectl -n king-mongkut-social-production get certificate
kubectl -n king-mongkut-social-production describe certificate king-mongkut-social-production-tls
kubectl -n king-mongkut-social-production get secret king-mongkut-social-production-tls
```
