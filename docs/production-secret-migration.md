# Production Secret Management & Migration Runbook

This runbook guides secret provisioning for King Mongkut Social using Google Secret Manager and External Secrets Operator (ESO).

## Required Production Secrets

### 1. `king-mongkut-social-backend-secret`
Contains sensitive application runtime configuration:

| Key | Description | Example / Requirement |
| --- | --- | --- |
| `MONGODB_URI` | MongoDB connection string | `mongodb://user:pass@mongodb:27017/king_mongkut_social?authSource=admin` |
| `ACCESS_TOKEN_SECRET` | Secret key for JWT access tokens | Min 32 characters, random string |
| `REFRESH_TOKEN_SECRET` | Secret key for JWT refresh tokens | Min 32 characters, distinct from access token |
| `GOOGLE_CLIENT_ID` | OAuth 2.0 Web Client ID from Google Cloud Console | `xxxx.apps.googleusercontent.com` |
| `GOOGLE_CLIENT_SECRET` | OAuth 2.0 Client Secret | Secret string |

### 2. `king-mongkut-social-infra-secret`
Contains credentials for in-cluster data services:

| Key | Description |
| --- | --- |
| `MONGO_INITDB_ROOT_USERNAME` | Root admin username for MongoDB |
| `MONGO_INITDB_ROOT_PASSWORD` | Strong password for MongoDB root admin |

---

## Secret Bootstrap Procedures

### Step 1: Bootstrap Google Cloud Secret Manager & Workload Identity

Ensure `gcloud` is logged in and configured with your project:

```bash
export EXPECTED_KUBE_CONTEXT="$(kubectl config current-context)"
export PROJECT_ID="denmann-production"
scripts/bootstrap-production-google-secret-manager.sh
```

### Step 2: Seed Secrets into Google Secret Manager

Either seed directly from an existing staging/production Kubernetes secret:

```bash
scripts/seed-production-google-secrets.sh
```

Or populate the secret values directly via `gcloud`:

```bash
# Seed backend secret
gcloud secrets versions add king-mongkut-social-backend-secret \
  --project="denmann-production" \
  --data-file=/path/to/backend-secret.json

# Seed infra secret
gcloud secrets versions add king-mongkut-social-infra-secret \
  --project="denmann-production" \
  --data-file=/path/to/infra-secret.json
```

### Step 3: Verify Reconciled Secrets

Run the non-leaking verification scripts:

```bash
# Verify Kubernetes Secret objects
scripts/verify-production-secrets.sh king-mongkut-social-production

# Verify Google Secret Manager and ESO sync
scripts/verify-production-google-secrets.sh
```

### Step 4: Fallback / Direct Bootstrap (Without ESO)

For environments without Google Cloud Secret Manager integration, apply `apps/production/secrets.yaml.example` directly after filling in real credentials:

```bash
kubectl apply -f apps/production/secrets.yaml.example
```
