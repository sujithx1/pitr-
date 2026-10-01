#!/bin/bash
# ==============================================================================
# Dedicated Production In-Place Recovery Pipeline
# Overwrites target database volume in-place up to specified LSN or Timestamp
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"

# Load production environment variables
if [ -f "$PROD_DIR/.env" ]; then
    export $(grep -v '^#' "$PROD_DIR/.env" | xargs 2>/dev/null) 2>/dev/null || true
fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_pitr_prod"}
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps -a --format '{{.Names}}' | grep -q "^postgres_pitr_prod$"; then
        CONTAINER_NAME="postgres_pitr_prod"
    elif docker ps -a --format '{{.Names}}' | grep -q "^postgres_pitr_lab$"; then
        CONTAINER_NAME="postgres_pitr_lab"
    elif docker ps -a --format '{{.Names}}' | grep -q "^postgres_db_18$"; then
        CONTAINER_NAME="postgres_db_18"
    fi
fi

IMAGE_NAME=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)
if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME="postgres-18:latest"
fi

STANZA_NAME=${STANZA_NAME:-"db"}
TARGET_TIME=$1
# Default DB timezone for bare timestamps (datetime-local / local wall clock)
DB_TZ="${TZ:-Asia/Kolkata}"
# Fixed offset used when appending to timestamps without zone (IST)
DB_TZ_OFFSET="+05:30"

if [ -z "$TARGET_TIME" ]; then
    echo "ERROR: Target LSN or Timestamp is required."
    echo "Usage: ./restore_inplace.sh <LSN|Timestamp>"
    exit 1
fi

# Auto-detect if target is an LSN or timestamp
if [[ "$TARGET_TIME" =~ ^[0-9A-Fa-f]+/[0-9A-Fa-f]+$ ]]; then
    TYPE_FLAG="--type=lsn"
else
    TYPE_FLAG="--type=time"
    # Bare local timestamps are otherwise treated as UTC by Postgres recovery,
    # which makes IST targets look "in the future" and crash startup.
    if [[ ! "$TARGET_TIME" =~ [Zz]$ ]] && [[ ! "$TARGET_TIME" =~ [+-][0-9]{2}(:?[0-9]{2})?$ ]]; then
        TARGET_TIME="${TARGET_TIME}${DB_TZ_OFFSET}"
        echo "NOTE: Assumed timezone ${DB_TZ} (${DB_TZ_OFFSET}) for target time."
    fi
fi

echo "=========================================="
echo "Starting Production In-Place Recovery"
echo "Target Container: $CONTAINER_NAME"
echo "Target LSN/Time:  $TARGET_TIME"
echo "=========================================="

# Storage Engine: 100% Local Disk Storage
PGBACKREST_CONF="$PROD_DIR/postgres/pgbackrest.conf"
echo "Storage Engine: Local Disk Storage ($PROD_DIR/backups)"

# 0. Force flush active WAL segment into backup repository if database is running
echo "[0/4] Flushing active WAL segment into backup repository..."
docker exec -u postgres "$CONTAINER_NAME" psql -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-mds}" -c "SELECT pg_switch_wal();" &>/dev/null || true

# 1. Stop PostgreSQL container
echo "[1/4] Stopping database container ($CONTAINER_NAME)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true

# 2. Perform delta restore in-place into volume.
# Docker Desktop bind mounts typically show PGDATA as UID 0 (root) and ignore
# in-container chown. pgBackRest requires the process user to own pg1-path, so
# restore must run as root on this setup.
echo "[2/4] Executing pgBackRest delta restore (as root — bind-mount ownership)..."
docker run --rm \
    --user root \
    --volumes-from "$CONTAINER_NAME" \
    -v "$PROD_DIR/backups:/backups" \
    -v "$PGBACKREST_CONF:/etc/pgbackrest/pgbackrest.conf" \
    -e TZ="$DB_TZ" \
    "$IMAGE_NAME" \
    pgbackrest --stanza="$STANZA_NAME" --delta $TYPE_FLAG --target="$TARGET_TIME" --target-action=promote restore

# 3. Restart PostgreSQL container
echo "[3/4] Starting database container ($CONTAINER_NAME)..."
docker start "$CONTAINER_NAME"

# 4. Wait for database recovery to complete (fail fast if container dies)
echo "[4/4] Waiting for database to complete WAL recovery..."
ATTEMPTS=0
MAX_ATTEMPTS=60
until docker exec "$CONTAINER_NAME" pg_isready -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-mds}" &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "ERROR: Database container exited during recovery."
        echo "--- recent postgres logs ---"
        docker logs "$CONTAINER_NAME" --tail 30 2>&1 || true
        LATEST_LOG=$(ls -t "$PROD_DIR"/postgres_data/log/*.log 2>/dev/null | head -1)
        if [ -n "$LATEST_LOG" ]; then
            echo "--- $LATEST_LOG ---"
            tail -40 "$LATEST_LOG" || true
        fi
        exit 1
    fi
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "ERROR: Timed out waiting for database to become ready."
        exit 1
    fi
    echo " -> Replaying WAL logs... ($ATTEMPTS/$MAX_ATTEMPTS)"
    sleep 2
done

echo "------------------------------------------"
echo "Restored Database Table Contents:"
docker exec "$CONTAINER_NAME" psql -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-mds}" -c "SELECT * FROM users ORDER BY id;" || true
echo "------------------------------------------"

echo "✅ Production In-Place Recovery Completed Successfully!"
