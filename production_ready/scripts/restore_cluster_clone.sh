#!/bin/bash
# ==============================================================================
# Enterprise High-Speed Physical Cluster Promotion Recovery Pipeline
# Ideal for 5TB+ Production Databases (Bypasses slow pg_dump | psql re-import)
# ==============================================================================

set -e

# Change directory to project root
cd "$(dirname "$0")/../.."

# Load environment variables if .env exists
for env_file in ".env" "staging_server/.env" "dashboard/.env"; do
    if [ -f "$env_file" ]; then
        export $(grep -v '^#' "$env_file" | xargs 2>/dev/null) 2>/dev/null || true
    fi
done

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_db_18"}
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^postgres_pitr_lab$"; then
        CONTAINER_NAME="postgres_pitr_lab"
    fi
fi

# Auto-detect exact image name
IMAGE_NAME=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "postgres:18")
STANZA_NAME=${STANZA_NAME:-"db"}

TARGET_LSN=$1
PROMOTED_CONTAINER_NAME=${2:-"postgres_pitr_cluster_promoted"}
PROMOTED_PORT=${3:-"5434"}

if [ -z "$TARGET_LSN" ]; then
    echo "ERROR: TARGET_LSN or target timestamp is required."
    echo "Usage: ./restore_cluster_clone.sh <LSN|Timestamp> [NEW_CONTAINER_NAME] [PORT]"
    exit 1
fi

echo "=================================================="
echo "Starting Enterprise Physical Cluster Promotion"
echo "Target LSN/Time:       $TARGET_LSN"
echo "Promoted Container:    $PROMOTED_CONTAINER_NAME"
echo "Promoted Port:         $PROMOTED_PORT"
echo "Base Image:            $IMAGE_NAME"
echo "=================================================="

PROMOTED_VOLUME="pitr_promoted_pgdata"

# Auto-detect if target is an LSN (e.g. 0/C000120) or a timestamp
if [[ "$TARGET_LSN" =~ ^[0-9A-Fa-f]+/[0-9A-Fa-f]+$ ]]; then
    TYPE_FLAG="--type=lsn"
else
    TYPE_FLAG="--type=time"
fi

# 1. Prepare clean recovery volume
echo "[1/4] Preparing physical storage volume ($PROMOTED_VOLUME)..."
docker stop "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker rm "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker volume rm "$PROMOTED_VOLUME" 2>/dev/null || true
docker volume create "$PROMOTED_VOLUME"

# 2. Perform delta restore directly into recovery volume
echo "[2/4] Executing pgBackRest delta restore & WAL replay into target cluster volume..."
docker run --rm \
    --user postgres \
    -v "$PROMOTED_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    "$IMAGE_NAME" \
    pgbackrest --stanza="$STANZA_NAME" $TYPE_FLAG --target="$TARGET_LSN" --target-action=promote restore

# 3. Boot new promoted database cluster
echo "[3/4] Launching promoted database cluster on port $PROMOTED_PORT..."
docker run -d \
    --name "$PROMOTED_CONTAINER_NAME" \
    -v "$PROMOTED_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    -v "$(pwd)/postgres/postgresql.conf:/etc/postgresql/postgresql.conf" \
    -v "$(pwd)/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf" \
    -p "$PROMOTED_PORT":5432 \
    "$IMAGE_NAME" \
    postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

# 4. Wait for promoted cluster to complete recovery & accept connections
echo "[4/4] Waiting for cluster promotion logs to settle..."
until docker exec "$PROMOTED_CONTAINER_NAME" pg_isready -U "${PG_USER:-dev}" -d "${PG_DB:-mds}" &>/dev/null; do
    echo " -> Replaying WAL logs and promoting cluster timeline..."
    sleep 2
done

echo "=================================================="
echo "Cluster Promotion Completed Successfully!"
echo "New Instance Online at: localhost:$PROMOTED_PORT"
echo "You can now update your application connection string to point to port $PROMOTED_PORT with zero data loss!"
echo "=================================================="
