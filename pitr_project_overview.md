# PostgreSQL PITR Project Overview

This document explains the complete architecture of your Point-in-Time Recovery (PITR) Lab project, breaking down every component, script, and configuration so you can understand exactly how the entire system works together.

---

## 1. The Database Architecture (`docker-compose.yml` & `/postgres`)

At the core of the project is a custom **PostgreSQL 18** container (`postgres_pitr_lab`). 
Instead of using a standard Postgres image, you have a custom `Dockerfile` that automatically installs and configures `pgbackrest` directly inside the database container.

### Key Configurations (`postgresql.conf`)
- **`wal_level = replica`**: This tells PostgreSQL to write enough data to the Write-Ahead Logs to support replication and Point-in-Time Recovery. Since we are using `pg_waldump` to scan the raw physical WAL files directly, the `replica` level is perfect!
- **`archive_mode = on`**: This tells PostgreSQL to never delete WAL files, but instead hand them over to an archive command.
- **`archive_command = 'pgbackrest --stanza=db archive-push %p'`**: This is the magic bridge! Every time a WAL file fills up (16MB), Postgres automatically hands it to pgBackRest, which compresses it and saves it in the `/backups/archive` folder.

---

## 2. The Backup System (`pgbackrest.conf` & `/scripts/backup.sh`)

`pgBackRest` is the enterprise-grade backup engine driving this project. 
It is configured with a **stanza** named `db` (a stanza is just pgBackRest's word for a specific database cluster).

### How Backups Work
When you run `./scripts/backup.sh`, the following happens:
1. `pgbackrest --type=full backup` copies the raw physical database files into `/backups/backup`.
2. It then runs `SELECT pg_switch_wal();` inside Postgres. This forcefully rotates the active WAL file, forcing Postgres to push the absolute latest transactions into the pgBackRest archive. This ensures your backup is 100% up-to-date!

---

## 3. The Recovery Engine (`/scripts/restore.sh` & `restore_fork.sh`)

When disaster strikes (like a dropped table), you need to time travel.

### In-Place Restore (`restore.sh`)
This script safely rewinds your main database:
1. It gracefully stops the `postgres_pitr_lab` container.
2. It spins up a temporary "helper" container that mounts your data volume.
3. It runs `pgbackrest restore --type=lsn --target="..." --delta`. The `--delta` flag is incredibly smart: instead of wiping your entire database, it compares your broken database with the backup, and only replaces the files that changed!
4. It replays the archived WAL files precisely up to the target LSN you requested, then promotes the database to a new Timeline.

### Out-of-Place Restore (`restore_fork.sh`)
If you don't want to destroy your current database, this script creates a *clone*:
1. It creates a brand new data folder (`/var/lib/postgresql/fork_data`).
2. It restores the pgBackRest backup into this *new* folder, stopping at the target LSN.
3. You can then boot up a second PostgreSQL container pointing at this clone to retrieve lost data without affecting production!

---

## 4. The Dashboard Backend (`/dashboard/index.ts`)

The dashboard is a blazing fast **Bun (Node.js)** server running on port `3001`. It acts as the brain for the UI.

### The WAL Analyzer (`/api/wal`)
To show you what is happening inside the database in real-time, the backend does the following:
1. It asks Postgres: *"What is the currently active WAL file?"*
2. It executes `pg_waldump -r Heap -r Transaction` on that exact file. This incredibly powerful Postgres tool translates the raw binary WAL data into readable text.
3. The backend parses thousands of lines of `pg_waldump` output using Regular Expressions. It maps raw OIDs (Object IDs) back to human-readable table names using a smart memory cache.
4. It packages the parsed `INSERT`, `UPDATE`, `DELETE`, and `COMMIT` events into clean JSON and sends it to the frontend.

### The Restore Trigger (`/api/restore`)
When you click a button in the UI, the frontend sends a POST request here. The backend safely executes your Bash scripts (`restore.sh`) directly on the host machine to initiate the physical recovery.

---

## 5. The Dashboard Frontend (`/dashboard/public`)

The frontend (`analyzer.html`) is a beautiful, vanilla HTML/CSS/JS application.
It polls the `/api/wal` endpoint every few seconds, dynamically rendering the transaction history.

### The Safety Net
The UI is specifically programmed to **only** allow you to restore to `COMMIT` records. This ensures that you can never accidentally rewind the database into the middle of a broken or incomplete transaction, guaranteeing a safe, consistent Point-in-Time Recovery every single time.
