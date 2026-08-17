# Production Readiness Modules (`production_ready/`)

This directory contains all enterprise-grade production improvements outlined in [`improvement.md`](file:///Users/sujith/sujith/pitr/improvement.md). 
It is structured as a **100% separate, independent folder**, keeping the original lab project completely untouched.

---

## 📁 Folder Structure

```text
production_ready/
├── dashboard/
│   ├── logical_streamer.ts    # Logical Decoding (wal2json) JSON stream server (Port 4001)
│   ├── metrics.ts             # Prometheus metrics exporter
│   └── package.json           # Independent Bun + Hono dependencies
├── scripts/
│   ├── alert.sh               # Standalone Slack / PagerDuty / Teams webhook alert tool
│   ├── backup_with_alert.sh   # Backup pipeline wrapper triggering automated webhook alerts
│   ├── setup_s3_backup.sh     # CLI tool to configure pgBackRest AWS S3 cloud backups
│   └── restore_cluster_clone.sh # Physical cluster promotion engine for 5TB+ databases
└── postgres/
    └── pgbackrest_s3.conf.template # AWS S3 pgBackRest config template with AES-256 encryption
```

---

## 🚀 Usage Guide

### 1. Logical Decoding Real-Time Engine (Dashboard)
Runs a standalone streaming API server on port `4001`:
```bash
cd production_ready/dashboard
bun run logical_streamer.ts
```

### 2. Automated Webhook Alerting
Run backups with Slack/Teams alerts:
```bash
./production_ready/scripts/backup_with_alert.sh full
```

### 3. AWS S3 Cloud Storage Generator
Generate S3 backup configurations:
```bash
./production_ready/scripts/setup_s3_backup.sh
```

### 4. High-Speed Physical Cluster Promotion (5TB+ DBs)
Perform instant sub-minute physical cluster recovery on port `5434`:
```bash
./production_ready/scripts/restore_cluster_clone.sh <LSN_OR_TIMESTAMP>
```
