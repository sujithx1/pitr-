#!/bin/bash
# ==============================================================================
# Backup Wrapper with Automated Alerting Notification Trigger
# ==============================================================================

set -e

SCRIPT_DIR="$(dirname "$0")"
BACKUP_TYPE=${1:-incr}

echo "=================================================="
echo "Executing Backup Pipeline with Automated Alerting"
echo "Backup Type: $BACKUP_TYPE"
echo "=================================================="

if "$SCRIPT_DIR/backup.sh" "$BACKUP_TYPE"; then
    echo "[ALERT] Backup pipeline succeeded."
    "$SCRIPT_DIR/alert.sh" "success" "Backup Succeeded" "pgBackRest $BACKUP_TYPE backup completed successfully."
else
    EXIT_CODE=$?
    echo "[ALERT] Backup pipeline failed with exit code $EXIT_CODE."
    "$SCRIPT_DIR/alert.sh" "failure" "Backup Failed" "pgBackRest $BACKUP_TYPE backup failed with error code $EXIT_CODE."
    exit $EXIT_CODE
fi
