#!/bin/bash
# ==============================================================================
# Enterprise Local Alerting Logger for PostgreSQL PITR (100% Offline / Local)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"

# Load local environment variables
if [ -f "$PROD_DIR/.env" ]; then
    export $(grep -v '^#' "$PROD_DIR/.env" | xargs 2>/dev/null) 2>/dev/null || true
fi

STATUS=${1:-"info"}       # success | failure | info | warning
TITLE=${2:-"PITR Alert"}  # Alert title
MESSAGE=${3:-"No details provided."} # Alert body details

echo "=================================================="
echo "[LOCAL ALERT LOG] Status: $STATUS | Title: $TITLE"
echo "Details: $MESSAGE"
echo "Timestamp: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================="

# External HTTP Webhook Cloud Requests REMOVED as per local-only directive.
# (All notifications are captured locally in console/log output).
