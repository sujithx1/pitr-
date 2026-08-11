# PostgreSQL Point-in-Time Recovery (PITR) Masterclass

Welcome to the hands-on PostgreSQL PITR Masterclass! This project is an interactive, step-by-step practical course designed to master PostgreSQL storage internals, WAL behavior, checkpoints, and automated recovery strategies.

---

## 📁 Repository Directory Structure

Here is a detailed breakdown of every folder in this project and its purpose:

### 1. [`postgres/`](file:///home/mdspl-sujith/sujith/pitr/postgres)
Contains the database runtime files, custom Docker building configurations, and configuration files.
*   [`Dockerfile`](file:///home/mdspl-sujith/sujith/pitr/postgres/Dockerfile): Pre-installs the `pgbackrest` utility inside the PostgreSQL 18 container so that the database engine can directly run archiving tasks.
*   [`init.sql`](file:///home/mdspl-sujith/sujith/pitr/postgres/init.sql): Initializes the lab database on the first container run (enabling `pageinspect` extension and creating the sample `users` table).
*   [`postgresql.conf`](file:///home/mdspl-sujith/sujith/pitr/postgres/postgresql.conf): Controls core PostgreSQL database engine settings.
*   [`pgbackrest.conf`](file:///home/mdspl-sujith/sujith/pitr/postgres/pgbackrest.conf): Configures pgBackRest directories, backup retention limits, and compression settings.
*   [`pg_hba.conf`](file:///home/mdspl-sujith/sujith/pitr/postgres/pg_hba.conf): Configures host-based database connection authentication permissions.

### 2. [`dashboard/`](file:///home/mdspl-sujith/sujith/pitr/dashboard)
The real-time log analyzer web application.
*   [`index.ts`](file:///home/mdspl-sujith/sujith/pitr/dashboard/index.ts): A Bun + Hono API server. It executes `pg_waldump` against the database container, parses OIDs using cache memory to speed up performance, and exposes endpoints for database status checks and recovery execution.
*   [`public/index.html`](file:///home/mdspl-sujith/sujith/pitr/dashboard/public/index.html): HTML5/CSS3 dark glassmorphic dashboard interface. Displays the transaction stream and contains the interactive recovery confirmation modals with modern toast notifications.

### 3. [`scripts/`](file:///home/mdspl-sujith/sujith/pitr/scripts)
BASH automation scripts used to manage the backups and restore executions:
*   [`backup.sh`](file:///home/mdspl-sujith/sujith/pitr/scripts/backup.sh): Calls `pgbackrest backup` to take incremental/full database snapshots.
*   [`restore.sh`](file:///home/mdspl-sujith/sujith/pitr/scripts/restore.sh): Stops the database container, performs a delta recovery back to the selected LSN/timestamp, restarts the container, and initiates WAL replay to promote the database.
*   [`restore_fork.sh`](file:///home/mdspl-sujith/sujith/pitr/scripts/restore_fork.sh): Creates a temporary Docker volume, runs a delta restore up to the selected LSN in an isolated sandbox database, dumps the tables using `pg_dump`, and imports them to a target database connection URL with zero downtime.

### 4. [`backups/`](file:///home/mdspl-sujith/sujith/pitr/backups)
Local persistent storage folder containing your database backup assets:
*   `backup/`: Contains compressed, incremental base backup directories and checksum manifests managed by pgBackRest.
*   `archive/`: Contains compressed WAL log segment archives (`.gz`) pushed from PostgreSQL.
*   `base/` & `wal/`: Static, uncompressed directories containing files from initial manual CLI training.

---

## ⚙️ Configuration Files Explained Section-by-Section

### 1. PostgreSQL Configuration ([`postgres/postgresql.conf`](file:///home/mdspl-sujith/sujith/pitr/postgres/postgresql.conf))

*   **`listen_addresses = '*'`**: Allows PostgreSQL to accept network connections from any interface (important inside Docker networks).
*   **`shared_buffers = 128MB`**: Allocates the shared memory pool used for caching database pages. Important for Module 1 to understand how modifications are made in RAM first before being written to disk.
*   **`wal_level = replica`**: Instructs PostgreSQL to write enough transaction details to the WAL so that we can run replication and Point-in-Time Recovery.
*   **`fsync = on`**: Enforces physical disk flushes, ensuring that transaction commit records are safely written to physical storage.
*   **`archive_mode = on`**: Activates PostgreSQL's background WAL archiving feature.
*   **`archive_command = 'pgbackrest --stanza=db archive-push %p'`**: Whenever a WAL file is completed, PostgreSQL calls this command, pushing the file to the pgBackRest backup archive folder.
*   **`logging_collector = on`**: Redirects log output from standard output to dedicated rotational log files inside the database directory.

### 2. pgBackRest Configuration ([`postgres/pgbackrest.conf`](file:///home/mdspl-sujith/sujith/pitr/postgres/pgbackrest.conf))

*   **`[db]` (Stanza Section)**:
    *   `pg1-path=/var/lib/postgresql/18/docker`: Tells pgBackRest where the active PostgreSQL data files live inside the container.
    *   `pg1-user=sujith`: The system user authorized to run backups.
*   **`[global]` (Global Settings)**:
    *   `repo1-path=/backups`: Specifies the target storage directory where backups and WAL files are archived.
    *   `repo1-retention-full=2`: Retains a maximum of 2 full backup chains, purging older backups to save disk space.
    *   `compress-type=zst`: Compresses backup directories and WAL logs using the Zstandard format for optimal compression and speed.
    *   `start-fast=y`: Forces PostgreSQL to checkpoint immediately when a backup starts, avoiding long wait times.

### 3. Docker Compose Setup ([`docker-compose.yml`](file:///home/mdspl-sujith/sujith/pitr/docker-compose.yml))

*   **`postgres_pitr` Service**:
    *   `build: ./postgres`: Uses the custom Dockerfile that packages `pgbackrest` inside PostgreSQL.
    *   `ports: - "5432:5432"`: Maps the PostgreSQL port to the host machine.
    *   `volumes`:
        *   `pitr_pgdata:/var/lib/postgresql`: Mounts database data persistently.
        *   `./backups:/backups`: Maps the host backup storage directory inside the container at `/backups`.
        *   `./postgres/postgresql.conf:/etc/postgresql/postgresql.conf`: Overwrites default engine configurations.
        *   `./postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf`: Overwrites authentication permission configurations.

---

## 🚀 Running the Project

### 1. Start the Environment
```bash
docker compose up -d
```

### 2. Start the WAL Dashboard Server
```bash
cd dashboard
bun run index.ts
```
*   Open your browser to: `http://localhost:3001`
*   Insert some data in your database, refresh the page, and see the WAL log timeline update dynamically!
*   Try dropping a table, locate its LSN on the timeline, choose **Out-of-Place Fork**, and restore it to a target database with zero downtime!