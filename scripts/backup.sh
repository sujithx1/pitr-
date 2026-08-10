#!/bin/bash
set -e

CONTAINER_NAME="postgres_pitr_lab"
STANZA_NAME="db"

echo "=========================================="
echo "Starting pgBackRest Backup Pipeline"
echo "=========================================="

# 1. Trigger pgBackRest backup inside Docker container
echo "[1/2] Executing pgBackRest backup..."
docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest \
    --stanza="$STANZA_NAME" \
    --type=incr \
    backup

# 2. Verify backups using pgbackrest info command
echo "[2/2] Checking pgBackRest backup status..."
echo "------------------------------------------"
docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest \
    --stanza="$STANZA_NAME" \
    info
echo "------------------------------------------"

echo "pgBackRest Backup Pipeline Completed Successfully!"
