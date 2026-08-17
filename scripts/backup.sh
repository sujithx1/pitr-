#!/bin/bash
set -e

# Load environment variables if .env exists
if [ -f "$(dirname "$0")/../dashboard/.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/../dashboard/.env" | xargs)
fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_db_18"}
# Auto-detect running container if default container name is not found
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^postgres_db_18$"; then
        CONTAINER_NAME="postgres_db_18"
    fi
fi

STANZA_NAME=${STANZA_NAME:-"db"}

echo "=========================================="
echo "Starting pgBackRest Backup Pipeline"
echo "Target Container: $CONTAINER_NAME"
echo "=========================================="

# Auto-initialize stanza if backup.info has not been created yet
if ! docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" info &>/dev/null; then
    echo "[0/2] Stanza '$STANZA_NAME' not initialized. Running stanza-create..."
    docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" stanza-create || true
fi

# Determine backup type from argument (default to 'incr')
BACKUP_TYPE=${1:-incr}

# 1. Trigger pgBackRest backup inside Docker container
echo "[1/2] Executing pgBackRest backup (Type: $BACKUP_TYPE)..."
docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest \
    --stanza="$STANZA_NAME" \
    --type="$BACKUP_TYPE" \
    backup

# 2. Verify backups using pgbackrest info command
echo "[2/2] Checking pgBackRest backup status..."
echo "------------------------------------------"
docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest \
    --stanza="$STANZA_NAME" \
    info
echo "------------------------------------------"

echo "pgBackRest Backup Pipeline Completed Successfully!"
