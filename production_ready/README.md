# Production Readiness Ecosystem (`production_ready/`)

This directory contains all enterprise-grade production modules outlined in [`improvement.md`](../improvement.md).
It is structured as a **separate, independent folder**, keeping lab code untouched.

---

## Folder Structure

```text
production_ready/
├── docker-compose.yml              # Production Postgres Stack
├── postgres/
│   ├── Dockerfile                  # Production Image with pgBackRest
│   ├── postgresql.conf             # wal_level=replica + archiving + max_slot_wal_keep_size
│   ├── pgbackrest.conf             # Local pgBackRest configuration
│   ├── pg_hba.conf                 # Host-Based Authentication
│   └── init.sql                    # Initial SQL Schema
├── dashboard/
│   ├── logical_streamer.ts         # PITR monitor API + restore triggers
│   ├── metrics.ts                  # Prometheus metrics exporter
│   ├── public/index.html           # WAL / archive / backup dashboard
│   └── package.json
└── scripts/
    ├── alert.sh
    ├── backup_with_alert.sh
    ├── setup_s3_backup.sh
    ├── restore_cluster_clone.sh
    └── restore_inplace.sh
```

---

## Quick Start (Production Database Container)

```bash
cd production_ready
docker compose up -d --build
```

- **Container**: `postgres_pitr_prod` (or name from `.env`)
- **Port**: typically `5433` locally

**Config note:** `postgresql.conf` uses `wal_level = replica` (enough for PITR). Changing `wal_level` requires a **Postgres restart** after deploy.

---

## Running Dashboard & Modules

### 1. PITR Monitor Web UI

```bash
cd production_ready/dashboard
bun dev
```

- **Open**: `http://localhost:4001` (or `LOGICAL_PORT` from `.env`; default in code is `7100`)
- **Features**: DB/WAL/archive/backup status, restore by **timestamp** or **LSN** (cluster clone or in-place)
- **Cluster clone**: optional custom **port** (default `5434`) and **name suffix** (`pitr_backup` / `pitr_backup_<suffix>`)
- **Restore OTP gate**: dashboard generates OTP; when `APP_ENV=production` it POSTs `{ phone, otp }` to `OTP_SERVICE_NAME` `/send` (local skips the service and returns the code)
- **Setup page**: `/setup.html` — copyable docker-compose (no secrets), explanations, and `postgres/` config browser
- **APIs**: `GET /api/status`, `GET /metrics`, `POST /api/restore/otp/send`, `POST /api/restore`
- **No logical replication slots** — the dashboard does not create or peek slots (avoids unbounded `pg_wal` growth)

### 2. Deploy / upgrade ops (one-time if an old slot exists)

If a previous version created `pitr_logical_slot`:

```bash
# 1. Stop the dashboard (e.g. pm2 stop pitr)
# 2. Drop the leftover slot
docker exec -it postgres_pitr_prod psql -U dev -d mds -c \
  "SELECT pg_drop_replication_slot('pitr_logical_slot');"
# 3. Restart Postgres if applying wal_level=replica
# 4. Start the updated dashboard
```

### 3. Automated Backup Alerting

```bash
./production_ready/scripts/backup_with_alert.sh full
```

### 4. AWS S3 Cloud Storage Generator

```bash
./production_ready/scripts/setup_s3_backup.sh
```

### 5. Physical Cluster Promotion Recovery

```bash
./production_ready/scripts/restore_cluster_clone.sh <LSN_OR_TIMESTAMP> [port] [suffix]
# defaults: port 5434, container/volume pitr_backup / pitr_backup_pgdata
# cleanup:  ./production_ready/scripts/cleanup_promoted.sh [container] [volume]
```
