# PostgreSQL Point-in-Time Recovery (PITR) Masterclass - Complete Architecture & System Guide

Welcome to the comprehensive architecture document for the PostgreSQL Point-in-Time Recovery (PITR) Masterclass project. This document serves as an exhaustive reference for the system's architecture, components, automation scripts, real-time WAL monitoring dashboard, and production deployment roadmap.

---

## 🏗️ System Architecture Overview

```text
                                  +---------------------------------------+
                                  |   Browser Interface (index.html)      |
                                  +---------------------------------------+
                                                      |
                                                      | REST API / JSON Polling
                                                      v
                                  +---------------------------------------+
                                  |     Dashboard Backend (index.ts)       |
                                  |           (Bun + Hono API)            |
                                  +---------------------------------------+
                                               /             \
                        Executes pg_waldump   /               \ Triggers Bash recovery scripts
                                             v                 v
                      +-------------------------------+   +----------------------------------+
                      | postgres_pitr_lab Container   |   | scripts/restore.sh               |
                      |  - PostgreSQL 18 Engine       |   | scripts/restore_fork.sh          |
                      |  - Built-in pgBackRest Agent  |   +----------------------------------+
                      +-------------------------------+
                           |                     |
               Pushes WAL  |                     | Writes Base Backups
               Archives    v                     v
                      +---------------------------------------+
                      |     /backups Storage Repository       |
                      |    (Compressed WAL & Incremental)     |
                      +---------------------------------------+
```

---

## 📁 Repository Directory Structure

| Folder / File | Description |
| :--- | :--- |
| [`postgres/`](file:///Users/sujith/sujith/pitr/postgres) | Dockerfile and engine configuration files (`postgresql.conf`, `pgbackrest.conf`, `pg_hba.conf`, `init.sql`). |
| [`dashboard/`](file:///Users/sujith/sujith/pitr/dashboard) | Bun + Hono backend server (`index.ts`) and HTML5 glassmorphic web dashboard (`public/index.html`). |
| [`scripts/`](file:///Users/sujith/sujith/pitr/scripts) | Automation shell scripts for backups (`backup.sh`), in-place recovery (`restore.sh`), and out-of-place fork recovery (`restore_fork.sh`). |
| [`backups/`](file:///Users/sujith/sujith/pitr/backups) | Local persistent storage folder containing pgBackRest full/incremental base backups and compressed WAL archives (`.gz`). |
| [`docker-compose.yml`](file:///Users/sujith/sujith/pitr/docker-compose.yml) | Orchestrates the custom PostgreSQL container, network, and volume bindings. |
| [`improvement.md`](file:///Users/sujith/sujith/pitr/improvement.md) | Technical recommendations for upgrading the lab to an enterprise production system. |
| [`universal_architecture.md`](file:///Users/sujith/sujith/pitr/universal_architecture.md) | Architecture guide for decoupling backup nodes for multi-tenant SaaS integration. |

---

## ⚙️ Core Components & Configuration

### 1. Database & Backup Container ([`postgres/`](file:///Users/sujith/sujith/pitr/postgres))
* **Dockerfile** ([`postgres/Dockerfile`](file:///Users/sujith/sujith/pitr/postgres/Dockerfile)): Extends `postgres:18` to pre-install `pgbackrest`, permitting PostgreSQL to call backup/archive routines natively.
* **Engine Settings** ([`postgres/postgresql.conf`](file:///Users/sujith/sujith/pitr/postgres/postgresql.conf)):
  * `wal_level = replica`: Emits physical Write-Ahead Log data required for replication and PITR.
  * `archive_mode = on`: Enables background WAL archiving.
  * `archive_command = 'pgbackrest --stanza=db archive-push %p'`: Automatically compresses completed 16MB WAL segments and pushes them to `/backups/archive`.
* **Backup Repository Settings** ([`postgres/pgbackrest.conf`](file:///Users/sujith/sujith/pitr/postgres/pgbackrest.conf)):
  * Configures stanza `db` targeting `/var/lib/postgresql/18/docker`.
  * Sets local repository path `/backups` with a max limit of 2 full retention chains (`repo1-retention-full=2`) compressed via Zstandard (`compress-type=zst`).

---

### 2. Backup & Recovery Automation ([`scripts/`](file:///Users/sujith/sujith/pitr/scripts))

#### Backup Execution (`scripts/backup.sh`)
* Triggers `pgbackrest --stanza=db --type=<incr|full> backup` inside the running database container.
* Verifies status and retention metrics via `pgbackrest info`.

#### In-Place Recovery (`scripts/restore.sh`)
1. Stops the primary `postgres_pitr_lab` container.
2. Spawns a lightweight helper container mounting the `pitr_pgdata` Docker volume.
3. Executes `pgbackrest restore --stanza=db --delta --type=<lsn|time> --target=<TARGET> --target-action=promote`.
4. Restarts `postgres_pitr_lab`, which replays archived WAL segments up to the exact target LSN and promotes the timeline.

#### Out-of-Place / Fork Recovery (`scripts/restore_fork.sh`)
1. Creates a temporary Docker volume (`pitr_pgdata_temp`).
2. Runs pgBackRest restore up to the target LSN into the temporary volume.
3. Launches a temporary database container (`postgres_pitr_recovery_temp`) on port `5433`.
4. Waits for WAL replay and timeline promotion.
5. Performs a `pg_dump` of the recovered database and streams it directly into any target connection URL (`TARGET_DB_URL`) with **zero downtime** on the live database.
6. Automatically cleans up temporary containers and storage volumes.

---

### 3. Real-Time WAL Dashboard ([`dashboard/`](file:///Users/sujith/sujith/pitr/dashboard))

#### Backend Service (`dashboard/index.ts`)
* Built with **Bun** and **Hono**.
* **WAL Analyzer**: Queries `SELECT pg_walfile_name(pg_current_wal_lsn());` and executes `pg_waldump -r Heap -r Transaction` to inspect binary WAL records.
* **OID Resolution**: Queries `pg_class` to build an in-memory cache mapping numeric relation OIDs to human-readable table names.
* **REST Endpoints**:
  * `GET /api/status`: Returns container status and PostgreSQL readiness.
  * `GET /api/wal`: Returns active WAL file name and parsed events (`INSERT`, `UPDATE`, `DELETE`, `COMMIT`, `DROP`).
  * `POST /api/restore`: Accepts target LSN/timestamp and optional `targetDbUrl` parameter to trigger in-place or out-of-place recovery pipelines.

#### Frontend UI (`dashboard/public/index.html`)
* Dark glassmorphic user interface polling `/api/wal` for live transaction visualization.
* Enforces recovery point safety by restricting interactive rollbacks strictly to `COMMIT` records.

---

## 🚀 Production Deployment Roadmap

1. **Logical Decoding**: Migrate dashboard log analysis from `pg_waldump` CLI text parsing to PostgreSQL Logical Replication slots (`wal2json`) for real-time JSON streaming.
2. **Cloud Object Storage**: Update `pgbackrest.conf` from local disk storage to S3/GCS (`repo1-type=s3`) with AES-256 client-side encryption.
3. **Cluster Promotion**: For multi-terabyte production databases, swap `pg_dump` streaming in `restore_fork.sh` for instant storage volume snapshots or instance cluster promotion.
4. **Decoupled Architecture**: Transition to `pg_receivewal` and `pg_basebackup` streaming nodes to support RDS, Cloud SQL, and external bare-metal PostgreSQL instances without requiring custom Docker builds.
