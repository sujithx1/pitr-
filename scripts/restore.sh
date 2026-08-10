#!/bin/bash
set -e

CONTAINER_NAME="postgres_pitr_lab"
STANZA_NAME="db"

# Prompt for the recovery target timestamp
read -p "Enter recovery target timestamp (e.g., 2026-08-10 11:42:00): " TARGET_TIME

if [ -z "$TARGET_TIME" ]; then
    echo "ERROR: Target time is required."
    exit 1
fi

echo "=========================================="
echo "Starting pgBackRest Recovery Pipeline"
echo "Target Time: $TARGET_TIME"
echo "=========================================="

# 1. Stop PostgreSQL server inside the container
echo "[1/4] Stopping PostgreSQL database server..."
docker exec -u postgres -i "$CONTAINER_NAME" pg_ctl -D /var/lib/postgresql/18/docker stop || true

# 2. Run pgBackRest delta restore to target timestamp
echo "[2/4] Executing pgBackRest delta restore..."
docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest \
    --stanza="$STANZA_NAME" \
    --delta \
    --type=time \
    --target="$TARGET_TIME" \
    --target-action=promote \
    restore

# 3. Start PostgreSQL server back up
echo "[3/4] Starting PostgreSQL database server..."
# We restart the container to let docker-entrypoint run it or launch pg_ctl
docker restart "$CONTAINER_NAME"

# 4. Wait for database to start and print confirmation
echo "[4/4] Waiting for database to recover and accept connections..."
sleep 5

echo "------------------------------------------"
echo "Verifying restored table status:"
docker exec -t "$CONTAINER_NAME" psql -U sujith -d db -c "SELECT * FROM users;" || echo " -> Recovery in progress or table not recovered."
echo "------------------------------------------"

echo "Recovery Pipeline Finished!"
