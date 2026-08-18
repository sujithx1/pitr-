#!/bin/bash
# ==============================================================================
# Helper Script to Stop & Clean Up Promoted Test Clusters
# ==============================================================================

set -e

PROMOTED_CONTAINER_NAME=${1:-"postgres_pitr_cluster_promoted"}
PROMOTED_VOLUME=${2:-"pitr_promoted_pgdata"}

echo "=================================================="
echo "Cleaning up promoted cluster instance"
echo "Container: $PROMOTED_CONTAINER_NAME"
echo "Volume:    $PROMOTED_VOLUME"
echo "=================================================="

docker stop "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker rm "$PROMOTED_CONTAINER_NAME" 2>/dev/null || true
docker volume rm "$PROMOTED_VOLUME" 2>/dev/null || true

echo "✅ Promoted cluster cleaned up successfully!"
