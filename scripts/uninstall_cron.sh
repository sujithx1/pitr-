#!/bin/bash
# ==============================================================================
# Automatic Cron Removal Script for pgBackRest Backups
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_BACKUP_SCRIPT="$SCRIPT_DIR/cron_backup.sh"

echo "=================================================="
echo "Removing Lab Backup Crontab Schedule"
echo "=================================================="

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "$EXISTING_CRON" | grep -v "$CRON_BACKUP_SCRIPT" | grep -v "pgBackRest" || true)

if [ -z "$NEW_CRON" ]; then
    crontab -r 2>/dev/null || true
else
    echo "$NEW_CRON" | crontab -
fi

echo "✅ Crontab backup schedule removed successfully!"
