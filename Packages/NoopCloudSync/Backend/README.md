# Noop Cloud Sync Backend

The backend is a snapshot/backup sync runtime with a lightweight cloud user and friends layer. It does not implement live HR streaming, raw samples, background sync, or any write-back to Noop SQLite.

## Stack

- Node.js 20+
- Built-in `http` server
- `pg` for Postgres
- SQL migration in `schema.sql`

## Local Setup

```sh
cd Packages/NoopCloudSync/Backend
npm install
createdb noop_cloud
psql "$DATABASE_URL" -f schema.sql
```

For an existing database that already has the original snapshot tables, apply the user/friends and auth migrations:

```sh
psql "$DATABASE_URL" -f migrations/002_user_friends.sql
psql "$DATABASE_URL" -f migrations/003_auth_sessions.sql
```

Environment:

```sh
export DATABASE_URL="postgres://localhost/noop_cloud"
export PORT=8787
export TOKEN_HASH_PEPPER="local-dev-only-change-me"
```

Run:

```sh
npm start
```

Test without Postgres:

```sh
npm test
```

## Auth Endpoints

Plain username/password auth is intentionally minimal for local Cloud development.
Passwords are stored as salted PBKDF2-SHA256 hashes; raw passwords and raw session tokens are never persisted.

- `POST /v1/auth/signup` with `{ "username": "ada", "password": "...", "displayName": "Ada" }`
- `POST /v1/auth/login` with `{ "username": "ada", "password": "..." }`
- `POST /v1/auth/logout` with `Authorization: Bearer <sessionToken>`
- `GET /v1/user/me` accepts either the existing device token or the new session token.

Auth usernames are trimmed, lowercased, and may be entered with or without a leading `@`.

## Sync Endpoint

`POST /v1/sync/batch`

Headers:

- `Authorization: Bearer <deviceToken>`
- `Content-Type: application/json`
- `Accept: application/json`

The server must hash `deviceToken` before persistence or lookup. Treat the raw token like a password.

Example:

```sh
curl -i \
  -X POST http://127.0.0.1:8787/v1/sync/batch \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  --data '{
    "clientBatchId": "manual-1",
    "schemaVersion": "noop-cloud-sync-v1",
    "appVersion": "dev",
    "sourceDeviceIds": ["my-whoop", "my-whoop-noop"],
    "window": {"fromDay": "2026-06-06", "toDay": "2026-07-06"},
    "dailyMetrics": [],
    "sleepSessions": [],
    "workouts": [],
    "metricSeries": []
  }'
```

## Persistence Shape

Use a stable internal `cloud_device_id` derived from the bearer token lookup. Health rows should upsert by:

- `cloud_sync_batch`: `(cloud_device_id, client_batch_id)`
- `daily_metric`: `(cloud_device_id, source_device_id, day)`
- `sleep_session`: `(cloud_device_id, source_device_id, start_ts)`
- `workout`: `(cloud_device_id, source_device_id, start_ts, sport)`
- `metric_series`: `(cloud_device_id, source_device_id, day, key)`

Duplicate `clientBatchId` values for the same device are treated as idempotent no-ops.

## Friends Summary

`GET /v1/friends/summary`

Headers:

- `Authorization: Bearer <deviceToken>`
- `Accept: application/json`

Legacy/debug endpoint that returns one or more self/device cards from the latest synced daily metric and sleep session rows for the bearer token's cloud device.

## Users

All user endpoints use the existing device bearer token:

```text
Authorization: Bearer <deviceToken>
```

`POST /v1/user/bootstrap`

Creates a `cloud_user` if the current `cloud_device` is not bound yet, binds the device to it, and returns `{ device, user }`. The body is optional profile data:

```json
{
  "username": "ada",
  "display_name": "Ada Lovelace",
  "avatar_url": "https://example.test/ada.png"
}
```

`GET /v1/user/me`

Returns the current cloud device and the bound user if one exists. Devices can remain unbound; existing sync continues with `cloud_user_id = NULL`.

`PATCH /v1/user/me`

Updates `username`, `display_name`, and/or `avatar_url` for the bound user. Duplicate usernames return `409 username_conflict`.

`PATCH /v1/user/privacy`

Updates friend-visible fields:

```json
{
  "share_recovery": true,
  "share_sleep": true,
  "share_workouts": true,
  "share_daily_effort": true
}
```

## Friendships

Friendship pairs are unique regardless of direction, so `alice -> bob` and `bob -> alice` cannot both exist.

- `POST /v1/friends/request` with `{ "username": "bob" }` or `{ "user_id": "<uuid>" }`
- `POST /v1/friends/accept` with `{ "friendship_id": "<uuid>" }`; only the addressee can accept
- `POST /v1/friends/reject` with `{ "friendship_id": "<uuid>" }`; only the addressee can reject/delete pending requests
- `POST /v1/friends/remove` with `{ "friendship_id": "<uuid>" }` or `{ "user_id": "<uuid>" }`
- `GET /v1/friends` returns accepted friends
- `GET /v1/friends/requests` returns incoming and outgoing pending requests

## Friends Feed

`GET /v1/friends/feed`

Returns recent friend activity from existing snapshot tables only:

- latest daily metric per friend
- latest sleep session per friend
- recent workouts per friend
- latest metric-series values per key

Privacy is applied per friend. Recovery, sleep, workouts, and daily effort are hidden when the friend disables the corresponding share flag. The response never includes bearer tokens or `device_token_hash`.

## End-to-End Local Verification

### Docker E2E

Start Postgres and the backend with Docker:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync/Backend
docker compose down -v
docker compose up --build -d
docker compose ps
curl -i http://127.0.0.1:8787/health
```

Or run the complete Docker E2E script:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync/Backend
sh scripts/e2e-docker.sh
```

Override the SQLite source if needed:

```sh
NOOP_CLOUD_E2E_DB=/path/to/noop-backup.sqlite sh scripts/e2e-docker.sh
```

The Compose stack exposes:

- backend: `http://127.0.0.1:8787`
- Postgres: `postgres://noop:noop@127.0.0.1:55432/noop_cloud`

Upload from a read-only Noop SQLite database:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync
swift run noop-cloud-upload \
  --db /Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite \
  --server http://127.0.0.1:8787 \
  --token local-e2e-token \
  --batch-id local-e2e-001 \
  --source my-whoop \
  --source my-whoop-noop \
  --from-day 2026-06-06 \
  --to-day 2026-07-06 \
  --from-ts 1780704000 \
  --to-ts 1783382399 \
  --app-version local-e2e
```

Verify row counts:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync/Backend
docker compose exec -T postgres psql -U noop -d noop_cloud -c "
SELECT 'cloud_device' AS table_name, count(*) FROM cloud_device
UNION ALL SELECT 'cloud_sync_batch', count(*) FROM cloud_sync_batch
UNION ALL SELECT 'cloud_daily_metric', count(*) FROM cloud_daily_metric
UNION ALL SELECT 'cloud_sleep_session', count(*) FROM cloud_sleep_session
UNION ALL SELECT 'cloud_workout', count(*) FROM cloud_workout
UNION ALL SELECT 'cloud_metric_series', count(*) FROM cloud_metric_series
ORDER BY table_name;"
```

Or run the checked-in SQL file:

```sh
docker compose exec -T postgres psql -U noop -d noop_cloud -f /work/scripts/verify-counts.sql
```

Verify duplicate behavior:

```sh
# Same batch id should return duplicate=true and should not change health table counts.
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync
swift run noop-cloud-upload \
  --db /Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite \
  --server http://127.0.0.1:8787 \
  --token local-e2e-token \
  --batch-id local-e2e-001 \
  --source my-whoop \
  --source my-whoop-noop \
  --from-day 2026-06-06 \
  --to-day 2026-07-06 \
  --from-ts 1780704000 \
  --to-ts 1783382399 \
  --app-version local-e2e

# New batch id should add one cloud_sync_batch row but upsert the same natural-key health rows.
swift run noop-cloud-upload \
  --db /Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite \
  --server http://127.0.0.1:8787 \
  --token local-e2e-token \
  --batch-id local-e2e-002 \
  --source my-whoop \
  --source my-whoop-noop \
  --from-day 2026-06-06 \
  --to-day 2026-07-06 \
  --from-ts 1780704000 \
  --to-ts 1783382399 \
  --app-version local-e2e
```

Legacy non-Docker setup:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync/Backend
npm install
createdb noop_cloud
export DATABASE_URL="postgres://localhost/noop_cloud"
psql "$DATABASE_URL" -f schema.sql
export PORT=8787
export TOKEN_HASH_PEPPER="local-dev-only-change-me"
npm start
```

In another shell, upload from a read-only Noop SQLite database:

```sh
cd /Users/adamleko/Desktop/noop/Packages/NoopCloudSync
swift run noop-cloud-upload \
  --db /Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite \
  --server http://127.0.0.1:8787 \
  --token local-e2e-token \
  --batch-id local-e2e-001 \
  --source my-whoop \
  --source my-whoop-noop \
  --from-day 2026-06-06 \
  --to-day 2026-07-06 \
  --from-ts 1780704000 \
  --to-ts 1783382399 \
  --app-version local-e2e
```

Expected counts for the current extracted backup:

- `dailyMetrics`: 21
- `sleepSessions`: 21
- `workouts`: 17
- `metricSeries`: 51

Run the same command again with the same `--batch-id`; the backend should return `duplicate: true` and zero accepted rows. Then run it with `--batch-id local-e2e-002`; the batch count should increase, while natural-key health row counts should remain the same.

Verification SQL:

```sql
SELECT count(*) AS cloud_devices FROM cloud_device;
SELECT count(*) AS batches FROM cloud_sync_batch;
SELECT count(*) AS daily_metrics FROM cloud_daily_metric;
SELECT count(*) AS sleep_sessions FROM cloud_sleep_session;
SELECT count(*) AS workouts FROM cloud_workout;
SELECT count(*) AS metric_series FROM cloud_metric_series;
```

Per-source verification:

```sql
SELECT source_device_id, count(*) FROM cloud_daily_metric GROUP BY source_device_id ORDER BY source_device_id;
SELECT source_device_id, count(*) FROM cloud_sleep_session GROUP BY source_device_id ORDER BY source_device_id;
SELECT source_device_id, count(*) FROM cloud_workout GROUP BY source_device_id ORDER BY source_device_id;
SELECT source_device_id, key, count(*) FROM cloud_metric_series GROUP BY source_device_id, key ORDER BY source_device_id, key;
```

Duplicate/new-batch verification:

```sql
SELECT client_batch_id, count(*)
FROM cloud_sync_batch
GROUP BY client_batch_id
ORDER BY client_batch_id;

SELECT source_device_id, day, count(*)
FROM cloud_daily_metric
GROUP BY source_device_id, day
HAVING count(*) > 1;
```
