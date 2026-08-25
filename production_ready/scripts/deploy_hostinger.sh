#!/usr/bin/env bash
# ==============================================================================
# Hostinger Live Deployment & Stanza Initializer Script
# ==============================================================================
set -e

# Change to production_ready directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROD_DIR"

echo "========================================================"
echo "🚀 1/4 Starting Hostinger Docker Stack..."
echo "========================================================"
docker-compose -f hostinger-docker-compose.yml up -d --build

echo ""
echo "========================================================"
echo "⏳ 2/4 Waiting for PostgreSQL database (postgres_db_18) to be ready..."
echo "========================================================"
until docker exec postgres_db_18 pg_isready > /dev/null 2>&1; do
  echo "Waiting for database connection..."
  sleep 2
done
echo "✅ Database connection established!"

echo ""
echo "========================================================"
echo "📦 3/4 Initializing pgBackRest Backup Stanza..."
echo "========================================================"
docker exec postgres_db_18 pgbackrest --stanza=db stanza-create || true

echo ""
echo "========================================================"
echo "🛡️ 4/4 Verifying Backup Stanza Health..."
echo "========================================================"
docker exec postgres_db_18 pgbackrest --stanza=db check

echo ""
echo "========================================================"
echo "🎉 SUCCESS: Hostinger Production Environment Deployed!"
echo "========================================================"
echo "• Database Container: postgres_db_18 (Port 5432)"
echo "• Backup Agent: pgBackRest (Stanza: db)"
echo "• Real-Time Streamer: Ready on Port 7100"
echo "========================================================"
