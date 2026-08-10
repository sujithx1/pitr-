#!/bin/bash
set -e

# Change directory to project root
cd "$(dirname "$0")/.."

TARGET_LSN=$1
TARGET_DB_URL=$2

if [ -z "$TARGET_LSN" ] || [ -z "$TARGET_DB_URL" ]; then
    echo "ERROR: Both TARGET_LSN and TARGET_DB_URL are required."
    echo "Usage: ./restore_fork.sh <LSN> <DATABASE_CONNECTION_URL>"
    exit 1
fi

echo "=================================================="
echo "Starting Out-of-Place Recovery Pipeline (Fork)"
echo "Target LSN: $TARGET_LSN"
echo "Target DB:  $TARGET_DB_URL"
echo "=================================================="

TEMP_VOLUME="pitr_pgdata_temp"
TEMP_CONTAINER="postgres_pitr_recovery_temp"

# 1. Create temporary Docker volume
echo "[1/6] Creating temporary recovery volume..."
docker volume create "$TEMP_VOLUME"

# 2. Run pgBackRest restore on the temporary volume
echo "[2/6] Restoring files up to target LSN into recovery volume..."
docker run --rm \
    --user postgres \
    -v "$TEMP_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    pitr-postgres_pitr:latest \
    pgbackrest --stanza=db --type=lsn --target="$TARGET_LSN" --target-action=promote restore

# 3. Start temporary database container using recovery volume
echo "[3/6] Starting temporary recovery database container..."
docker run -d \
    --name "$TEMP_CONTAINER" \
    --network pitr_default \
    -v "$TEMP_VOLUME":/var/lib/postgresql \
    -v "$(pwd)/postgres/postgresql.conf:/etc/postgresql/postgresql.conf" \
    -v "$(pwd)/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf" \
    -p 5433:5432 \
    pitr-postgres_pitr:latest \
    postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

# 4. Wait for temporary container to recover and promote
echo "[4/6] Waiting for recovery database to become ready..."
until docker exec "$TEMP_CONTAINER" pg_isready -U sujith -d db &>/dev/null; do
    echo " -> Waiting for database startup..."
    sleep 2
done

# Wait another 3 seconds for recovery/promotion logs to settle
sleep 3
echo " -> Recovery database is online and promoted!"

# 5. Extract tables and pipe them directly into target database URL
echo "[5/6] Exporting tables and restoring to target database..."
# Note: We run pg_dump inside the temp container and pipe to psql connecting to the target database URL
# --clean clears existing tables on target, --if-exists avoids errors on clean
docker exec -i "$TEMP_CONTAINER" pg_dump -U sujith -d db --clean --if-exists | docker exec -i "$TEMP_CONTAINER" psql "$TARGET_DB_URL"

# 6. Cleanup temporary resources
echo "[6/6] Cleaning up temporary container and volume..."
docker stop "$TEMP_CONTAINER"
docker rm "$TEMP_CONTAINER"
docker volume rm "$TEMP_VOLUME"

echo "=================================================="
echo "Out-of-Place Recovery Pipeline Completed!"
echo "=================================================="
