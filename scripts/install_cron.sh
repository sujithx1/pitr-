#!/bin/bash
# ==============================================================================
# Automatic Cron Installation Script for pgBackRest Backups
# ==============================================================================
# Schedule:
#   - Full Backup: Every Sunday at 2:00 AM (0 2 * * 0)
#   - Incremental Backup: Every Day Mon-Sat at 2:00 AM (0 2 * * 1-6)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_BACKUP_SCRIPT="$SCRIPT_DIR/cron_backup.sh"

chmod +x "$CRON_BACKUP_SCRIPT"
chmod +x "$SCRIPT_DIR/backup.sh"

CRON_FULL="0 2 * * 0 $CRON_BACKUP_SCRIPT full"
CRON_INCR="0 2 * * 1-6 $CRON_BACKUP_SCRIPT incr"

echo "=================================================="
echo "Installing Lab Backup Crontab Schedule"
echo "Target Backup Script: $CRON_BACKUP_SCRIPT"
echo "=================================================="
echo "1. Full Backup Schedule:        0 2 * * 0 (Every Sunday at 2:00 AM)"
echo "2. Incremental Backup Schedule: 0 2 * * 1-6 (Every Mon-Sat at 2:00 AM)"
echo "--------------------------------------------------"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "$EXISTING_CRON" | grep -v "$CRON_BACKUP_SCRIPT" || true)

NEW_CRON=$(cat <<EOF
$NEW_CRON
# PostgreSQL pgBackRest Automated Backup Schedule (Added $(date '+%Y-%m-%d'))
$CRON_FULL
$CRON_INCR
EOF
)

echo "$NEW_CRON" | crontab -

echo "✅ Crontab successfully installed!"
echo ""
echo "Current Active Crontab:"
crontab -l | grep -A 2 "pgBackRest"
