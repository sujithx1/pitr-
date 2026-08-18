# Production Readiness Ecosystem (`production_ready/`)

This directory contains all enterprise-grade production modules outlined in [`improvement.md`](file:///Users/sujith/sujith/pitr/improvement.md). 
It is structured as a **100% separate, independent folder**, keeping all existing lab code completely untouched.

---

## 📁 Folder Structure

```text
production_ready/
├── docker-compose.yml              # Production Postgres Stack (postgres_pitr_prod)
├── postgres/
│   ├── Dockerfile                  # Production Image with pgBackRest pre-installed
│   ├── postgresql.conf             # Production Config (wal_level = logical + Archiving)
│   ├── pgbackrest.conf             # Local pgBackRest configuration
│   ├── pg_hba.conf                 # Production Host-Based Authentication
│   ├── init.sql                    # Initial SQL Schema
│   └── pgbackrest_s3.conf.template # AWS S3 pgBackRest template with AES-256 encryption
├── dashboard/
│   ├── logical_streamer.ts         # Logical Decoding JSON stream server (Port 4001)
│   ├── metrics.ts                  # Prometheus metrics exporter
│   ├── public/index.html           # Dark glassmorphic Web UI with pagination & date pickers
│   └── package.json                # Independent dependencies
└── scripts/
    ├── alert.sh                    # Standalone Slack / PagerDuty / Teams webhook alert tool
    ├── backup_with_alert.sh        # Backup pipeline wrapper triggering automated webhook alerts
    ├── setup_s3_backup.sh          # CLI tool to configure pgBackRest AWS S3 cloud backups
    └── restore_cluster_clone.sh    # Physical cluster promotion engine for 5TB+ databases
```

---

## 🚀 Quick Start (Production Database Container)

To start the production PostgreSQL database container:

```bash
cd production_ready
docker compose up -d --build
```

* **Production Postgres Container**: `postgres_pitr_prod`
* **Port**: `5432`

---

## 🧪 Running Dashboard & Modules

### 1. Logical Decoding Real-Time Web UI
Run the dashboard directly using Bun:
```bash
cd production_ready/dashboard
bun dev
```
* **Open Browser**: `http://localhost:4001`
* **Features**: Live decoded transaction timeline, Pagination (`10`, `15`, `25`, `50`), Date filtering, Interactive **"Restore to LSN"** modal.

### 2. Automated Webhook Alerting
```bash
./production_ready/scripts/backup_with_alert.sh full
```

### 3. AWS S3 Cloud Storage Generator
```bash
./production_ready/scripts/setup_s3_backup.sh
```

### 4. High-Speed Physical Cluster Promotion Recovery
```bash
./production_ready/scripts/restore_cluster_clone.sh <LSN_OR_TIMESTAMP>
```
