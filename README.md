# King Mongkut Social Argo CD GitOps

Production GitOps manifests for the **King Mongkut Social** platform deploying to **`denmannsolutions.com`**.

This repository is designed to be synced by Argo CD to orchestrate and maintain the production deployment.

## Deployed Components

- **Frontend (`king-mongkut-social-app`)**:
  - Hosts: `https://denmannsolutions.com` & `https://www.denmannsolutions.com`
  - Vite 8 SPA served via Nginx production container
  - Configured with `VITE_API_BASE_URL=https://api.denmannsolutions.com/api/v1`
  - High availability: 2 replicas, PodDisruptionBudget, and PodAntiAffinity
- **Backend API (`king-mongkut-social-api`)**:
  - Host: `https://api.denmannsolutions.com`
  - Express 5, Node 24, Socket.IO, Pino, Mongoose 9
  - Ingress max body size: 50MB (supports media & photo posts)
  - Persistent storage: 20Gi PVC mounted at `/app/uploads`
  - High availability: 2 replicas, PodDisruptionBudget, and PodAntiAffinity
- **In-Cluster Database (`mongodb`)**:
  - MongoDB 8 StatefulSet
  - Persistent volume: 20Gi PVC mounted at `/data/db`
  - Pre-sync index hook: `king-mongkut-social-sync-indexes`

---

## Repository Structure

```text
king-mongkut-social-argocd/
├── apps/
│   └── production/
│       ├── backend/
│       │   ├── api-rollout-order-patch.yaml
│       │   ├── deployments.yaml
│       │   ├── kustomization.yaml
│       │   ├── services.yaml
│       │   ├── sync-indexes-job.yaml
│       │   └── uploads-pvc.yaml
│       ├── frontend/
│       │   ├── deployments.yaml
│       │   ├── kustomization.yaml
│       │   └── services.yaml
│       ├── infra/
│       │   ├── kustomization.yaml
│       │   └── mongodb.yaml
│       ├── configmaps.yaml
│       ├── critical-path-ha.yaml
│       ├── critical-path-topology-patch.yaml
│       ├── google-external-secrets.yaml
│       ├── ingress.yaml
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── secrets.yaml.example
│       └── service-account.yaml
├── argocd/
│   ├── app-project.yaml
│   ├── k3s-coredns-custom.yaml
│   └── king-mongkut-social-production.yaml
├── docs/
│   ├── google-oauth-production-runbook.md
│   ├── ingress-and-dns-runbook.md
│   ├── mongodb-operations-runbook.md
│   ├── production-readiness.md
│   └── production-secret-migration.md
└── scripts/
    ├── bootstrap-production-google-secret-manager.sh
    ├── bootstrap-production-google-secret-manager.test.sh
    ├── seed-production-google-secrets.sh
    ├── seed-production-google-secrets.test.sh
    ├── testdata/fake-bin/kubectl
    ├── validate-production-capacity.sh
    ├── validate-production-secret-contract.sh
    ├── verify-production-google-secrets.sh
    ├── verify-production-google-secrets.test.sh
    ├── verify-production-secrets.sh
    └── verify-production-secrets.test.sh
```

---

## Bootstrap & Deployment

### 1. Configure DNS Records
Create `A` or `CNAME` records pointing to your ingress load balancer:
- `denmannsolutions.com`
- `www.denmannsolutions.com`
- `api.denmannsolutions.com`

See [`docs/ingress-and-dns-runbook.md`](docs/ingress-and-dns-runbook.md).

### 2. Configure Google OAuth Credentials
In [Google Cloud Console](https://console.cloud.google.com/apis/credentials):
- **Authorized JavaScript origins**: `https://denmannsolutions.com`, `https://www.denmannsolutions.com`
- **Authorized redirect URIs**: `https://api.denmannsolutions.com/api/v1/auth/google/callback`

See [`docs/google-oauth-production-runbook.md`](docs/google-oauth-production-runbook.md).

### 3. Provision Production Secrets
Either configure Google Secret Manager via External Secrets Operator:
```bash
export EXPECTED_KUBE_CONTEXT="$(kubectl config current-context)"
scripts/bootstrap-production-google-secret-manager.sh
scripts/seed-production-google-secrets.sh
scripts/verify-production-secrets.sh king-mongkut-social-production
```
Or apply the initial secret manifest directly:
```bash
kubectl apply -f apps/production/secrets.yaml.example
```

See [`docs/production-secret-migration.md`](docs/production-secret-migration.md).

### 4. Apply Argo CD Bootstrap Manifests

```bash
# 1. Apply K3s CoreDNS IPv4 egress fallback (if using K3s)
kubectl apply --server-side --field-manager=king-mongkut-social-ops \
  -f argocd/k3s-coredns-custom.yaml

# 2. Apply Argo CD AppProject and Application
kubectl apply -f argocd/app-project.yaml
kubectl apply -f argocd/king-mongkut-social-production.yaml

# 3. Trigger initial hard refresh and sync
kubectl -n argocd annotate application king-mongkut-social-production \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## Image Building

### Backend API Image
```bash
docker build -t ghcr.io/txngjr/king-mongkut-social-api:production ./king-mongkut-social-api
docker push ghcr.io/txngjr/king-mongkut-social-api:production
```

### Frontend Web Image
The frontend requires the API base URL baked into the static build:
```bash
docker build \
  --build-arg VITE_API_BASE_URL=https://api.denmannsolutions.com/api/v1 \
  -t ghcr.io/txngjr/king-mongkut-social-app:production ./king-mongkut-social-app
docker push ghcr.io/txngjr/king-mongkut-social-app:production
```

Update tags in `apps/production/kustomization.yaml` to deploy new releases.

---

## Post-Deploy Sync Waves

Argo CD applies the production stack in this order:

1. **Wave `-7`**: Secret sync ServiceAccount for ESO.
2. **Wave `-6`**: Runtime ServiceAccount, SecretStore, and MongoDB Service.
3. **Wave `-5`**: ExternalSecrets and MongoDB StatefulSet.
4. **Wave `-4`**: Runtime ConfigMaps and Uploads PVC.
5. **Wave `-2`**: `king-mongkut-social-sync-indexes` Job hook runs Mongoose index synchronization.
6. **Wave `-1`**: Backend and Frontend Services.
7. **Wave `1`**: `king-mongkut-social-api` backend deployment rolls out.
8. **Wave `2`**: `king-mongkut-social-app` frontend deployment rolls out.
9. **Wave `*`**: Ingress and Cert-Manager TLS certificate reconciliation.

---

## Local Validation

Run local validation before committing changes:

```bash
# Verify Kustomize renders cleanly
kubectl kustomize apps/production >/dev/null

# Verify capacity budget and resource limits
scripts/validate-production-capacity.sh

# Verify Secret contract consistency
scripts/validate-production-secret-contract.sh

# Run all test suites
scripts/verify-production-secrets.test.sh
scripts/verify-production-google-secrets.test.sh
scripts/seed-production-google-secrets.test.sh
scripts/bootstrap-production-google-secret-manager.test.sh
```
