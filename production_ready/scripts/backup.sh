#!/bin/bash
# ==============================================================================
# Production Dedicated pgBackRest Backup Pipeline
# ==============================================================================

set -e

# Load environment variables if production_ready/.env exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_ENV="$(dirname "$SCRIPT_DIR")/.env"

if [ -f "$PROD_ENV" ]; then
    export $(grep -v '^#' "$PROD_ENV" | xargs)
fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_pitr_prod"}

# Auto-detect running production container if default container is not running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^postgres_pitr_prod$"; then
        CONTAINER_NAME="postgres_pitr_prod"
    elif docker ps --format '{{.Names}}' | grep -q "^postgres_db_18$"; then
        CONTAINER_NAME="postgres_db_18"
    fi
fi

STANZA_NAME=${STANZA_NAME:-"db"}

echo "=========================================="
echo "Starting Production pgBackRest Backup Pipeline"
echo "Target Container: $CONTAINER_NAME"
echo "Stanza: $STANZA_NAME"
echo "=========================================="

# Auto-initialize stanza if backup.info is missing
if ! docker exec -u postgres -i "$CONTAINER_NAME" test -f "/backups/backup/$STANZA_NAME/backup.info"; then
    echo "[0/2] Initializing pgBackRest stanza '$STANZA_NAME'..."
    docker exec -u root -i "$CONTAINER_NAME" chown -R postgres:postgres /backups 2>/dev/null || true
    docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" stanza-create
else
    # Check if database system-id has changed and upgrade stanza if needed
    if ! docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" check &>/dev/null; then
        echo "[0/2] Database system-id changed or stanza check failed. Upgrading stanza..."
        docker exec -u postgres -i "$CONTAINER_NAME" pgbackrest --stanza="$STANZA_NAME" stanza-upgrade || true
    fi
fi

# Determine backup type from argument (default to 'incr')
BACKUP_TYPE=${1:-"incr"}

# Validate backup type
if [ "$BACKUP_TYPE" != "full" ] && [ "$BACKUP_TYPE" != "incr" ] && [ "$BACKUP_TYPE" != "diff" ]; then
    echo "ERROR: Invalid backup type '$BACKUP_TYPE'. Must be 'full', 'incr', or 'diff'."
    exit 1
fi

# 1. Execute pgBackRest backup
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

echo "Production pgBackRest Backup Pipeline Completed Successfully!"
