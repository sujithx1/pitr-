#!/bin/bash
set -e

# Load environment variables if .env exists
if [ -f "$(dirname "$0")/../dashboard/.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/../dashboard/.env" | xargs)
    fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_db_18"}
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^postgres_pitr_lab$"; then
        CONTAINER_NAME="postgres_pitr_lab"
    fi
fi

# Auto-detect exact image name from running database container
IMAGE_NAME=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "postgres:18")
STANZA_NAME=${STANZA_NAME:-"db"}

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
echo "Target Container: $CONTAINER_NAME"
echo "Image Name:       $IMAGE_NAME"
echo "Target Time:      $TARGET_TIME"
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

# Determine compose directory (staging_server or root)
COMPOSE_DIR="."
if [ -f "staging_server/docker-compose.yml" ]; then
    COMPOSE_DIR="staging_server"
fi

# 1. Stop PostgreSQL container
echo "[1/4] Stopping PostgreSQL database container..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" stop || docker stop "$CONTAINER_NAME"

# 2. Run pgBackRest delta restore using helper container with auto-detected image
echo "[2/4] Executing pgBackRest delta restore in helper container..."
docker run --rm \
    --user postgres \
    --volumes-from "$CONTAINER_NAME" \
    "$IMAGE_NAME" \
    pgbackrest --stanza="$STANZA_NAME" --delta $TYPE_FLAG --target="$TARGET_TIME" --target-action=promote restore

# 3. Start PostgreSQL container back up
echo "[3/4] Starting PostgreSQL database container..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" start || docker start "$CONTAINER_NAME"

# 4. Wait for database to start and print confirmation
echo "[4/4] Waiting for database to recover and accept connections..."
sleep 5

echo "------------------------------------------"
echo "Verifying restored table status:"
docker exec -t "$CONTAINER_NAME" psql -U "${PG_USER:-sujith}" -d "${PG_DB:-db}" -c "SELECT * FROM users;" || echo " -> Recovery in progress or table not recovered."
echo "------------------------------------------"


echo "Recovery Pipeline Finished!"
