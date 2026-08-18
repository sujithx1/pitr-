#!/bin/bash
# ==============================================================================
# Enterprise High-Speed Physical Cluster Promotion Recovery Pipeline
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"

# Load production environment variables
if [ -f "$PROD_DIR/.env" ]; then
    export $(grep -v '^#' "$PROD_DIR/.env" | xargs 2>/dev/null) 2>/dev/null || true
fi

TARGET_LSN=$1
if [ -z "$TARGET_LSN" ]; then
    echo "ERROR: Target LSN or Timestamp is required."
    echo "Usage: ./restore_cluster_clone.sh <LSN|Timestamp>"
    exit 1
fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_pitr_prod"}
IMAGE_NAME=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "postgres-18:latest")
if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME="postgres-18:latest"
fi

STANZA_NAME=${STANZA_NAME:-"db"}
PROMOTED_CONTAINER="postgres_pitr_cluster_promoted"
PROMOTED_VOLUME="pitr_promoted_pgdata"
PROMOTED_PORT="5434"

# Auto-detect if target is an LSN or timestamp
if [[ "$TARGET_LSN" =~ ^[0-9A-Fa-f]+/[0-9A-Fa-f]+$ ]]; then
    TYPE_FLAG="--type=lsn"
else
    TYPE_FLAG="--type=time"
fi

echo "=================================================="
echo "Starting Physical Cluster Promotion Recovery"
echo "Target LSN/Time:    $TARGET_LSN"
echo "Promoted Container: $PROMOTED_CONTAINER"
echo "Promoted Port:      $PROMOTED_PORT"
echo "=================================================="

# 0. Flush active WAL segment into backup repository
echo "[0/4] Flushing active WAL segment..."
docker exec -u postgres "$CONTAINER_NAME" psql -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-mds}" -c "SELECT pg_switch_wal();" &>/dev/null || true

# 1. Clean old promoted volume & container
echo "[1/4] Preparing physical recovery volume..."
docker stop "$PROMOTED_CONTAINER" 2>/dev/null || true
docker rm "$PROMOTED_CONTAINER" 2>/dev/null || true
docker volume rm "$PROMOTED_VOLUME" 2>/dev/null || true
docker volume create "$PROMOTED_VOLUME"

# 2. Restore pgBackRest files into recovery volume
echo "[2/4] Executing pgBackRest restore..."
docker run --rm \
    --user postgres \
    -v "$PROMOTED_VOLUME":/var/lib/postgresql \
    -v "$PROD_DIR/backups:/backups" \
    -v "$PROD_DIR/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    "$IMAGE_NAME" \
    pgbackrest --stanza="$STANZA_NAME" $TYPE_FLAG --target="$TARGET_LSN" --target-action=promote restore

# 3. Boot promoted cluster container on port 5434
echo "[3/4] Launching promoted database on port $PROMOTED_PORT..."
docker run -d \
    --name "$PROMOTED_CONTAINER" \
    -v "$PROMOTED_VOLUME":/var/lib/postgresql \
    -v "$PROD_DIR/backups:/backups" \
    -v "$PROD_DIR/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    -v "$PROD_DIR/postgres/postgresql.conf:/etc/postgresql/postgresql.conf" \
    -v "$PROD_DIR/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf" \
    -p "$PROMOTED_PORT":5432 \
    "$IMAGE_NAME" \
    postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf -c archive_mode=off

# 4. Wait for database to start
echo "[4/4] Waiting for database cluster to boot..."
until docker exec "$PROMOTED_CONTAINER" pg_isready &>/dev/null; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${PROMOTED_CONTAINER}$"; then
        echo "ERROR: Promoted database container exited during recovery."
        docker rm -f "$PROMOTED_CONTAINER" 2>/dev/null || true
        exit 1
    fi
    sleep 2
done

echo "=================================================="
echo "Cluster Promotion Completed Successfully!"
echo "New Instance Online at: localhost:$PROMOTED_PORT"
echo "When finished testing, run: ./scripts/cleanup_promoted.sh"
echo "=================================================="
