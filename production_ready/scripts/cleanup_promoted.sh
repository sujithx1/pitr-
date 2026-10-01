#!/bin/bash
# ==============================================================================
# Helper Script to Stop & Clean Up Promoted Test Clusters
#
# Defaults (no suffix):
#   ./cleanup_promoted.sh
#   → container pitr_backup, volume pitr_backup_pgdata
#
# Custom suffix example (client1):
#   ./cleanup_promoted.sh pitr_backup_client1 pitr_backup_client1_pgdata
# ==============================================================================

set -e

PROMOTED_CONTAINER_NAME=${1:-"pitr_backup"}
PROMOTED_VOLUME=${2:-"pitr_backup_pgdata"}

echo "=================================================="
echo "Cleaning up promoted cluster instance"
echo "Container: $PROMOTED_CONTAINER_NAME"
echo "Volume:    $PROMOTED_VOLUME"
echo "=================================================="

docker stop "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker rm "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker volume rm "$PROMOTED_VOLUME" 2>/dev/null || true

echo "✅ Promoted cluster cleaned up successfully!"
