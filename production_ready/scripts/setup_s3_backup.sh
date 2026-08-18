#!/bin/bash
# ==============================================================================
# Dynamic AWS S3 / Cloud Object Storage Setup Tool for pgBackRest
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"

# Load production environment variables
if [ -f "$PROD_DIR/.env" ]; then
    export $(grep -v '^#' "$PROD_DIR/.env" | xargs 2>/dev/null) 2>/dev/null || true
fi

CONTAINER_NAME=${PG_CONTAINER_NAME:-"postgres_pitr_prod"}
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^postgres_pitr_prod$"; then
        CONTAINER_NAME="postgres_pitr_prod"
    elif docker ps --format '{{.Names}}' | grep -q "^postgres_pitr_lab$"; then
        CONTAINER_NAME="postgres_pitr_lab"
    elif docker ps --format '{{.Names}}' | grep -q "^postgres_db_18$"; then
        CONTAINER_NAME="postgres_db_18"
    fi
fi

S3_BUCKET_NAME=${S3_BUCKET_NAME:-"my-company-pitr-backups"}
S3_REGION=${S3_REGION:-"us-east-1"}
S3_ENDPOINT=${S3_ENDPOINT:-"s3.us-east-1.amazonaws.com"}
S3_ACCESS_KEY=${S3_ACCESS_KEY:-"AKIAIOSFODNN7EXAMPLE"}
S3_SECRET_KEY=${S3_SECRET_KEY:-"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}
ENCRYPTION_PASSPHRASE=${ENCRYPTION_PASSPHRASE:-"SecretEnterpriseEncryptionKey2026"}

POSTGRES_USER=${PG_USER:-${POSTGRES_USER:-"dev"}}
POSTGRES_DB=${PG_DB:-${POSTGRES_DB:-"mds"}}

echo "=================================================="
echo "Configuring AWS S3 Cloud Object Storage Backup"
echo "Target Container: $CONTAINER_NAME"
echo "S3 Bucket:        $S3_BUCKET_NAME"
echo "S3 Region:        $S3_REGION"
echo "S3 Endpoint:      $S3_ENDPOINT"
echo "=================================================="

CONF_TEMPLATE="$PROD_DIR/postgres/pgbackrest_s3.conf.template"
TARGET_CONF="$PROD_DIR/postgres/pgbackrest_s3.conf"

if [ ! -f "$CONF_TEMPLATE" ]; then
    echo "ERROR: Template file $CONF_TEMPLATE not found!"
    exit 1
fi

# Substitute variables into pgbackrest_s3.conf
sed \
  -e "s|\${POSTGRES_USER}|$POSTGRES_USER|g" \
  -e "s|\${POSTGRES_DB}|$POSTGRES_DB|g" \
  -e "s|\${S3_BUCKET_NAME}|$S3_BUCKET_NAME|g" \
  -e "s|\${S3_REGION}|$S3_REGION|g" \
  -e "s|\${S3_ENDPOINT}|$S3_ENDPOINT|g" \
  -e "s|\${S3_ACCESS_KEY}|$S3_ACCESS_KEY|g" \
  -e "s|\${S3_SECRET_KEY}|$S3_SECRET_KEY|g" \
  -e "s|\${ENCRYPTION_PASSPHRASE}|$ENCRYPTION_PASSPHRASE|g" \
  "$CONF_TEMPLATE" > "$TARGET_CONF"

echo "S3 configuration generated at: $TARGET_CONF"
echo "To switch your running database to S3 storage, mount 'pgbackrest_s3.conf' as '/etc/pgbackrest/pgbackrest.conf'."
