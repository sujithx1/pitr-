#!/bin/bash
# ==============================================================================
# Automated Cron Backup Orchestrator (Sunday 2 AM Full, Mon-Sat 2 AM Incremental)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/pgbackrest_cron.log"

if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="$SCRIPT_DIR/cron.log"
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DAY_OF_WEEK=$(date '+%w') # 0 = Sunday, 1-6 = Mon-Sat

INPUT_TYPE="$1"

if [ -n "$INPUT_TYPE" ] && [ "$INPUT_TYPE" != "auto" ]; then
    BACKUP_TYPE="$INPUT_TYPE"
else
    if [ "$DAY_OF_WEEK" -eq 0 ]; then
        BACKUP_TYPE="full"
    else
        BACKUP_TYPE="incr"
    fi
fi

echo "==================================================" | tee -a "$LOG_FILE"
echo "[$TIMESTAMP] Starting Scheduled Cron Backup Pipeline" | tee -a "$LOG_FILE"
echo "Target Backup Type: $BACKUP_TYPE (Day of Week: $DAY_OF_WEEK)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# Execute backup.sh
if "$SCRIPT_DIR/backup.sh" "$BACKUP_TYPE" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[$TIMESTAMP] Scheduled $BACKUP_TYPE backup completed successfully." | tee -a "$LOG_FILE"
else
    EXIT_CODE=${PIPESTATUS[0]}
    echo "[$TIMESTAMP] ERROR: Scheduled $BACKUP_TYPE backup failed (Exit Code: $EXIT_CODE)." | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
