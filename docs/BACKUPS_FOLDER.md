# Understanding the Backups Folder

The `backups/` directory is managed by **pgBackRest**. It serves as the main repository where all your database snapshots and continuous WAL logs are safely stored. 

Inside the `backups/db/` folder (since our stanza is named `db`), you will find the following critical directories:

## 1. `archive/`
This folder stores the **Write-Ahead Logs (WAL)**. 
* **What it is:** PostgreSQL continuously streams WAL files (transaction logs) into this folder via the `archive_command` setting.
* **Why it's used:** These files are required for Point-in-Time Recovery. They act as the "VCR tape" that lets you fast-forward or rewind database changes to any exact second.
* **We use this heavily!** The dashboard API reads from the active WAL files to show you the timeline of transactions.

## 2. `backup/`
This folder stores the actual **Database Snapshots** (Full, Differential, and Incremental backups).
* **What it is:** When you run `./scripts/backup.sh`, pgBackRest copies all database files (`pg_class`, `users` table data, etc.) into this folder.
* **Why it's used:** This provides the "Base" starting point. If you want to restore to 3:00 PM today, pgBackRest first pulls the backup snapshot from this folder, and then replays the `archive/` WAL files on top of it until it reaches 3:00 PM.

## 3. `base/`
*You might see this depending on your pgBackRest version or repository configuration.*
Generally, pgBackRest stores the data for backups inside the `backup/` folder. The base directory represents the root of the database repository cluster.

## 4. `wal/` (Inside pgdata)
Note: There is also a `pg_wal/` folder *inside* the live PostgreSQL data directory (`/var/lib/postgresql/pgdata/pg_wal`). 
* **Difference:** `pg_wal` is the active, live working directory for PostgreSQL. The `backups/archive/` folder is where pgBackRest permanently stores them for safe keeping so they aren't deleted when the database recycles space.

## Summary
When a backup runs, **everything** in the Postgres data directory is copied to `backup/`. 
Meanwhile, every few seconds/minutes, Postgres streams its transaction logs to `archive/`. 
To do a PITR restore, you need **both**: a base snapshot from `backup/` + the transaction logs from `archive/`.
