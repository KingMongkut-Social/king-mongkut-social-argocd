# King Mongkut Social — Production Readiness & GitOps Architecture

Production GitOps manifests and deployment architecture for the **King Mongkut Social** platform on Kubernetes via Argo CD.

## Platform Architecture

- **Domain**: `denmannsolutions.com`
- **Frontend SPA**: `https://denmannsolutions.com` and `https://www.denmannsolutions.com`
  - Served via Nginx container (`king-mongkut-social-app`)
  - Built with Vite 8 + TypeScript, connected to `https://api.denmannsolutions.com/api/v1`
  - Replicas: 2 with PodDisruptionBudget and PodAntiAffinity
- **Backend API**: `https://api.denmannsolutions.com`
  - Express 5, Node 24, Socket.IO, Pino, Mongoose 9 (`king-mongkut-social-api`)
  - Ingress body size up to 50MB for media/photo uploads
  - Uploads directory `/app/uploads` backed by persistent volume (`king-mongkut-social-uploads`)
  - Replicas: 2 with PodDisruptionBudget and PodAntiAffinity
- **Database**:
  - MongoDB 8 StatefulSet (`mongodb`) on port 27017
  - Backed by persistent volume claim `mongo-data` (20Gi)
  - Pre-deployment hook `king-mongkut-social-sync-indexes` ensures all MongoDB indexes are synchronized prior to traffic cutover

---

## Argo CD Sync Waves

The deployment orchestrates through structured sync waves:

| Wave | Component | Purpose |
| --- | --- | --- |
| `-7` | `king-mongkut-social-secret-sync` | ServiceAccount for External Secrets Operator |
| `-6` | `king-mongkut-social-runtime`, `SecretStore`, `mongodb` Service | Runtime service account, Google Secret Manager store, DB service endpoint |
| `-5` | `ExternalSecret`, `mongodb` StatefulSet | Syncs secrets from Google Secret Manager; boots MongoDB storage and replica |
| `-4` | ConfigMaps, `king-mongkut-social-uploads` PVC | Application configurations and uploads persistent storage |
| `-2` | `king-mongkut-social-sync-indexes` Job | Argo CD Sync Hook: ensures all MongoDB indexes are created |
| `-1` | Backend & Frontend Services | ClusterIP services for API and Frontend apps |
| `1` | `king-mongkut-social-api` Deployment | Backend API pods roll out |
| `2` | `king-mongkut-social-app` Deployment | Frontend web app pods roll out |
| `*` | `king-mongkut-social` Ingress | Traefik ingress routes traffic with Let's Encrypt TLS |

---

## Capacity Budget & Sizing

Workload request sizing:
- **MongoDB**: 250m CPU, 512Mi RAM (Limit: 1000m CPU, 1Gi RAM)
- **API (2 Pods)**: 2 x 250m CPU, 2 x 512Mi RAM = 500m CPU, 1024Mi RAM (Limit: 2 x 1000m CPU, 2 x 1Gi RAM)
- **App (2 Pods)**: 2 x 50m CPU, 2 x 64Mi RAM = 100m CPU, 128Mi RAM (Limit: 2 x 200m CPU, 2 x 128Mi RAM)

**Total Baseline Allocation**:
- **CPU**: 0.85 cores (850m)
- **Memory**: 1.62 GiB (1664Mi)

Leaves ample headroom on single-node or multi-node clusters for K3s, Traefik, Cert-Manager, and Argo CD.

---

## Verification Commands

Run locally to guarantee release consistency:

```bash
# 1. Test kustomize render
kubectl kustomize apps/production >/dev/null

# 2. Validate capacity budget
scripts/validate-production-capacity.sh

# 3. Validate secret contract
scripts/validate-production-secret-contract.sh

# 4. Run automated tests
scripts/verify-production-secrets.test.sh
scripts/verify-production-google-secrets.test.sh
scripts/seed-production-google-secrets.test.sh
scripts/bootstrap-production-google-secret-manager.test.sh
```
