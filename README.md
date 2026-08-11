# PostgreSQL Point-in-Time Recovery (PITR) Masterclass

Welcome to the hands-on PostgreSQL PITR Masterclass! This project is an interactive, step-by-step practical course designed to master PostgreSQL storage internals, WAL behavior, checkpoints, and automated recovery strategies.

---

## 📚 Course Modules & What We Built

### Module 1: PostgreSQL Storage Internals
*   **Concepts Learned:** PGDATA layout, Heap files, Pages, Tuples, MVCC (Multi-Version Concurrency Control), and `xmin`/`xmax` tracking.
*   **Why we need this:** To understand how data physically sits on disk. When you run an `UPDATE` or `DELETE`, PostgreSQL does not overwrite the data in place; it writes a new version of the row (tuple) and flags the old one as dead. We used the `pageinspect` extension to view the physical bytes of the data page and see these pointers directly.

### Module 2: WAL (Write-Ahead Logging) & Durability
*   **Concepts Learned:** WAL files, redo logs, physiological logging, and LSNs (Log Sequence Numbers).
*   **Why we need this:** Writing to disk is slow. To ensure durability without sacrificing speed, PostgreSQL writes all changes sequentially to the Write-Ahead Log (WAL) first. If the server crashes, PostgreSQL reads the WAL logs on startup to replay and rebuild the exact memory state.

### Module 3: Enterprise WAL Archiving (pgBackRest)
*   **Concepts Learned:** Stanzas, Full/Incremental backups, `archive-push`, and `archive-get`.
*   **Why we use pgBackRest:** Manual shell script copies of data directories are fragile, uncompressed, and prone to corruption. We integrated `pgBackRest` (an industry standard) because:
    *   It compresses archived WAL files to save disk space.
    *   It supports **delta restores** (validating data block checksums and only copying changed files, making restores extremely fast).
    *   It manages retention policies and verifies backup integrity automatically.

### Module 4: Point-In-Time Recovery (PITR)
*   **Concepts Learned:** Target time, Target LSN, Standby mode, and Promotion.
*   **Why we need PITR:** If a developer accidentally runs a destructive query like `DROP TABLE users;` or `DELETE FROM orders;` without a `WHERE` clause, standard backups cannot save you without losing all subsequent good data. PITR allows you to roll the database forward to the exact LSN (Log Sequence Number) or millisecond *right before* the mistake occurred.

### Module 5: Real-Time WAL Analyzer Dashboard (Bun + Hono)
*   **Why we added the UI:** 
    *   **Visibility:** Looking at raw WAL binary is impossible. We created a real-time web UI using Bun and Hono that executes `pg_waldump` and parses physical records into human-readable actions (`INSERT`, `UPDATE`, `DELETE`, `DROP`).
    *   **Precision:** Guessing the timestamp for a recovery leads to container startup crashes if it goes past the available log. The UI displays the exact LSN of each transaction, allowing you to trigger a restore to a mathematically precise point.

### Module 6: Zero-Downtime Out-of-Place Fork Recovery
*   **Why we need this feature:**
    *   **In-Place Restore (Option 1):** Shuts down the live database and rolls it back, causing downtime and deleting all transactions written after the target restore time.
    *   **Out-of-Place Fork (Option 2):** Keeps your live database **online** with zero downtime. It spins up a temporary PostgreSQL container, restores the backup up to the target LSN inside a sandboxed volume, runs `pg_dump`, streams the recovered table back into the target database URL, and cleans up the sandbox resources automatically.

---

## 🛠️ Lab Architecture & Configuration

```text
                                         +-----------------------------+
                                         |    Target Database URL      |
                                         | (pg18:5434 / live database) |
                                         +-----------------------------+
                                                        ^
                                                        | pg_restore stream
                                                        |
+--------------------------+  pgbackrest    +-------------------------+
|   pgBackRest Repository  | -------------> |  postgres_recovery_temp |
|   (/backups/backup/...)  |  LSN Restore   +-------------------------+
+--------------------------+                (Temp recovery container)
```

### Key Configs
*   **PostgreSQL version:** `postgres:18-alpine`
*   **Archiving configured in** [postgres/postgresql.conf](file:///home/mdspl-sujith/sujith/pitr/postgres/postgresql.conf):
    ```ini
    archive_mode = on
    archive_command = 'pgbackrest --stanza=db archive-push %p'
    ```
*   **pgBackRest Config:** Mounted at [postgres/pgbackrest.conf](file:///home/mdspl-sujith/sujith/pitr/postgres/pgbackrest.conf).

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