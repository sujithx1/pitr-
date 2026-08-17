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

# Ensure /backups directory permissions and auto-initialize stanza if backup.info is missing
if ! docker exec -u postgres -i "$CONTAINER_NAME" test -f "/backups/backup/$STANZA_NAME/backup.info"; then
    echo "[0/2] Initializing pgBackRest stanza '$STANZA_NAME'..."
    docker exec -u root -i "$CONTAINER_NAME" chown -R postgres:postgres /backups 2>/dev/null || true
    docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" stanza-create
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
