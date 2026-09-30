# MongoDB Operations & Persistence Runbook

This runbook covers day-to-day operations, index management, backups, and restores for MongoDB in King Mongkut Social.

## 1. Storage & Persistence Architecture

- **StatefulSet**: `mongodb` in namespace `king-mongkut-social-production`
- **PVC**: `mongo-data-mongodb-0` (20Gi) mounted to `/data/db`
- **API Uploads PVC**: `king-mongkut-social-uploads` (20Gi) mounted to `/app/uploads`

To inspect persistent storage:
```bash
kubectl -n king-mongkut-social-production get pvc
kubectl -n king-mongkut-social-production get pv
```

---

## 2. Automated Index Synchronization

MongoDB collections have indexes defined via Mongoose schemas (`UserModel`, `PostModel`, `ChatModel`, etc.).
Argo CD executes `sync-indexes-job.yaml` at sync wave `-2`:
- Runs `node dist/scripts/sync-indexes.js`
- Connects using `MONGODB_URI`
- Idempotently verifies and builds any new or updated compound indexes
- Completed hook pods are pruned automatically (`HookSucceeded`)

To manually trigger index sync:
```bash
kubectl -n king-mongkut-social-production exec -it deployment/king-mongkut-social-api -- \
  node dist/scripts/sync-indexes.js
```

---

## 3. Database Backup (mongodump)

To create a point-in-time backup archive of the `king_mongkut_social` database:

```bash
# 1. Execute dump inside the MongoDB pod
kubectl -n king-mongkut-social-production exec -it statefulset/mongodb -- \
  mongodump --db king_mongkut_social --gzip --archive=/tmp/king_mongkut_social_backup.gz

# 2. Copy the archive to local storage
kubectl -n king-mongkut-social-production cp \
  mongodb-0:/tmp/king_mongkut_social_backup.gz \
  ./king_mongkut_social_backup_$(date +%Y%m%d_%H%M%S).gz

# 3. Clean up archive in container
kubectl -n king-mongkut-social-production exec -it statefulset/mongodb -- \
  rm -f /tmp/king_mongkut_social_backup.gz
```

---

## 4. Database Restore (mongorestore)

To restore from an archive:

```bash
# 1. Copy archive into the MongoDB pod
kubectl -n king-mongkut-social-production cp \
  ./king_mongkut_social_backup.gz \
  mongodb-0:/tmp/restore_backup.gz

# 2. Execute mongorestore
kubectl -n king-mongkut-social-production exec -it statefulset/mongodb -- \
  mongorestore --gzip --archive=/tmp/restore_backup.gz --drop

# 3. Clean up archive in container
kubectl -n king-mongkut-social-production exec -it statefulset/mongodb -- \
  rm -f /tmp/restore_backup.gz
```
