#!/bin/bash
set -e

# Change directory to project root
cd "$(dirname "$0")/.."

# Load environment variables if .env exists
if [ -f "dashboard/.env" ]; then
    export $(grep -v '^#' "dashboard/.env" | xargs)
fi

STANZA_NAME=${STANZA_NAME:-"db"}

TARGET_LSN=$1
TARGET_DB_URL=$2

if [ -z "$TARGET_LSN" ] || [ -z "$TARGET_DB_URL" ]; then
    echo "ERROR: Both TARGET_LSN and TARGET_DB_URL are required."
    echo "Usage: ./restore_fork.sh <LSN> <DATABASE_CONNECTION_URL>"
    exit 1
fi

echo "=================================================="
echo "Starting Out-of-Place Recovery Pipeline (Fork)"
echo "Target Container: $CONTAINER_NAME"
echo "Image Name:       $IMAGE_NAME"
echo "Target LSN:       $TARGET_LSN"
echo "Target DB:        $TARGET_DB_URL"
echo "=================================================="

TEMP_VOLUME="pitr_pgdata_temp"
TEMP_CONTAINER="postgres_pitr_recovery_temp"

# 1. Create temporary recovery volume
echo "[1/6] Creating temporary recovery volume..."
docker stop "$TEMP_CONTAINER" 2>/dev/null || true
docker rm "$TEMP_CONTAINER" 2>/dev/null || true
docker volume rm "$TEMP_VOLUME" 2>/dev/null || true
docker volume create "$TEMP_VOLUME"

# 2. Run pgBackRest restore on the temporary volume
echo "[2/6] Restoring files up to target LSN into recovery volume..."
docker run --rm \
    --user postgres \
    -v "$TEMP_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    "$IMAGE_NAME" \
    pgbackrest --stanza="$STANZA_NAME" --type=lsn --target="$TARGET_LSN" --target-action=promote restore

# 3. Start temporary database container using recovery volume
echo "[3/6] Starting temporary recovery database container..."
docker run -d \
    --name "$TEMP_CONTAINER" \
    --network pitr_default \
    -v "$TEMP_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    -v "$(pwd)/postgres/postgresql.conf:/etc/postgresql/postgresql.conf" \
    -v "$(pwd)/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf" \
    -p 5433:5432 \
    "$IMAGE_NAME" \
    postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

# 4. Wait for temporary container to recover and promote
echo "[4/6] Waiting for recovery database to become ready..."
until docker exec "$TEMP_CONTAINER" pg_isready -U "${PG_USER:-sujith}" -d "${PG_DB:-db}" &>/dev/null; do
    echo " -> Waiting for database startup..."
    sleep 2
done

# Wait another 3 seconds for recovery/promotion logs to settle
sleep 3
echo " -> Recovery database is online and promoted!"

# 5. Extract tables and pipe them directly into target database URL
echo "[5/7] Preparing target database..."
# Extract the database name and the base URL (pointing to the default 'postgres' db)
TARGET_DB_NAME=$(echo "$TARGET_DB_URL" | sed 's/.*\///')
BASE_DB_URL=$(echo "$TARGET_DB_URL" | sed 's/\/[^\/]*$/\/postgres/')

# Connect to the default 'postgres' database to drop and recreate the target database
# WITH (FORCE) forcefully disconnects any active users so the drop succeeds instantly
docker exec -i "$TEMP_CONTAINER" psql "$BASE_DB_URL" -c "DROP DATABASE IF EXISTS \"$TARGET_DB_NAME\" WITH (FORCE);"
docker exec -i "$TEMP_CONTAINER" psql "$BASE_DB_URL" -c "CREATE DATABASE \"$TARGET_DB_NAME\";"

echo "[6/7] Exporting tables and restoring to target database..."
# Note: We run pg_dump inside the temp container and pipe to psql connecting to the target database URL
docker exec -i "$TEMP_CONTAINER" pg_dump -U "${PG_USER:-sujith}" -d "${PG_DB:-db}" | docker exec -i "$TEMP_CONTAINER" psql "$TARGET_DB_URL"

# 7. Cleanup temporary resources
echo "[7/7] Cleaning up temporary container and volume..."
docker stop "$TEMP_CONTAINER"
docker rm "$TEMP_CONTAINER"
docker volume rm "$TEMP_VOLUME"

echo "=================================================="
echo "Out-of-Place Recovery Pipeline Completed!"
echo "=================================================="
