#!/bin/bash
set -e

CONTAINER_NAME="postgres_pitr_lab"
STANZA_NAME="db"

# Check if target timestamp is passed as an argument
TARGET_TIME=$1

if [ -z "$TARGET_TIME" ]; then
    # Prompt for the recovery target timestamp if not provided as argument
    read -p "Enter recovery target timestamp (e.g., 2026-08-10 11:42:00): " TARGET_TIME
fi

if [ -z "$TARGET_TIME" ]; then
    echo "ERROR: Target time is required."
    exit 1
fi

echo "=========================================="
echo "Starting pgBackRest Recovery Pipeline"
echo "Target Time: $TARGET_TIME"
echo "=========================================="

# Change directory to project root (one level up from scripts/)
cd "$(dirname "$0")/.."

# Auto-detect if target is an LSN (e.g. 0/C000120) or a timestamp
if [[ "$TARGET_TIME" =~ ^[0-9A-Fa-f]+/[0-9A-Fa-f]+$ ]]; then
    TYPE_FLAG="--type=lsn"
    echo " -> Detected LSN recovery target."
else
    TYPE_FLAG="--type=time"
    echo " -> Detected timestamp recovery target."
fi

# 1. Stop PostgreSQL container
echo "[1/4] Stopping PostgreSQL database container..."
docker compose stop

# 2. Run pgBackRest delta restore using a temporary helper container mounting the same volumes
echo "[2/4] Executing pgBackRest delta restore in helper container..."
docker run --rm \
    --user postgres \
    -v pitr_pgdata:/var/lib/postgresql \
    -v "$(pwd)/backups:/backups" \
    -v "$(pwd)/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf" \
    pitr-postgres_pitr:latest \
    pgbackrest --stanza="$STANZA_NAME" --delta $TYPE_FLAG --target="$TARGET_TIME" --target-action=promote restore

# 3. Start PostgreSQL container back up
echo "[3/4] Starting PostgreSQL database container..."
docker compose start

# 4. Wait for database to start and print confirmation
echo "[4/4] Waiting for database to recover and accept connections..."
sleep 5

echo "------------------------------------------"
echo "Verifying restored table status:"
docker exec -t "$CONTAINER_NAME" psql -U sujith -d db -c "SELECT * FROM users;" || echo " -> Recovery in progress or table not recovered."
echo "------------------------------------------"


echo "Recovery Pipeline Finished!"
