#!/usr/bin/env sh
set -eu

BACKEND_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACKAGE_DIR="$(CDPATH= cd -- "$BACKEND_DIR/.." && pwd)"
DB_PATH="${NOOP_CLOUD_E2E_DB:-/Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite}"
SERVER_URL="${NOOP_CLOUD_E2E_SERVER:-http://127.0.0.1:8787}"
TOKEN="${NOOP_CLOUD_E2E_TOKEN:-local-e2e-token}"

upload() {
  batch_id="$1"
  swift run --package-path "$PACKAGE_DIR" noop-cloud-upload \
    --db "$DB_PATH" \
    --server "$SERVER_URL" \
    --token "$TOKEN" \
    --batch-id "$batch_id" \
    --source my-whoop \
    --source my-whoop-noop \
    --from-day 2026-06-06 \
    --to-day 2026-07-06 \
    --from-ts 1780704000 \
    --to-ts 1783382399 \
    --app-version local-e2e
}

cd "$BACKEND_DIR"

docker compose down -v
docker compose up --build -d

for attempt in $(seq 1 60); do
  if curl -fsS "$SERVER_URL/health" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "Backend did not become healthy" >&2
    docker compose logs
    exit 1
  fi
  sleep 1
done

echo "First upload: local-e2e-001"
upload local-e2e-001

echo "Duplicate upload: local-e2e-001"
upload local-e2e-001

echo "Second unique batch: local-e2e-002"
upload local-e2e-002

echo "SQL verification"
docker compose exec -T postgres psql -U noop -d noop_cloud -f /work/scripts/verify-counts.sql
