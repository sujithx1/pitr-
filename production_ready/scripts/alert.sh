#!/bin/bash
# ==============================================================================
# Enterprise Webhook Alerting Tool for PostgreSQL PITR
# Supports Slack, PagerDuty, and Microsoft Teams Webhook Notifications
# ==============================================================================

set -e

# Load environment variables if .env exists
for env_file in ".env" "$(dirname "$0")/../../staging_server/.env" "$(dirname "$0")/../../dashboard/.env" "$(dirname "$0")/../../.env"; do
    if [ -f "$env_file" ]; then
        export $(grep -v '^#' "$env_file" | xargs 2>/dev/null) 2>/dev/null || true
    fi
done

STATUS=${1:-"info"}       # success | failure | info | warning
TITLE=${2:-"PITR Alert"}  # Alert title
MESSAGE=${3:-"No details provided."} # Alert body details

WEBHOOK_URL=${SLACK_WEBHOOK_URL:-$PAGERDUTY_WEBHOOK_URL}
WEBHOOK_URL=${WEBHOOK_URL:-$WEBHOOK_URL}

echo "=================================================="
echo "Sending PITR Webhook Notification"
echo "Status:  $STATUS"
echo "Title:   $TITLE"
echo "Message: $MESSAGE"
echo "=================================================="

if [ -z "$WEBHOOK_URL" ]; then
    echo "[NOTICE] WEBHOOK_URL / SLACK_WEBHOOK_URL is not set in .env. Alert log generated locally."
    echo "[LOCAL LOG] [$STATUS] $TITLE - $MESSAGE"
    exit 0
fi

# Set color theme based on status
COLOR="#36a64f" # Green for success
if [ "$STATUS" = "failure" ]; then
    COLOR="#ff0000" # Red for failure
elif [ "$STATUS" = "warning" ]; then
    COLOR="#ffcc00" # Yellow for warning
elif [ "$STATUS" = "info" ]; then
    COLOR="#0099ff" # Blue for info
fi

# Build Slack-compatible JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "attachments": [
    {
      "color": "$COLOR",
      "title": "PostgreSQL PITR: $TITLE",
      "text": "$MESSAGE",
      "fields": [
        {
          "title": "Status",
          "value": "$STATUS",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +'%Y-%m-%d %H:%M:%S UTC')",
          "short": true
        }
      ],
      "footer": "PostgreSQL PITR Engine"
    }
  ]
}
EOF
)

# Dispatch HTTP POST request
curl -s -X POST -H 'Content-type: application/json' --data "$JSON_PAYLOAD" "$WEBHOOK_URL"

echo "Notification sent successfully!"
