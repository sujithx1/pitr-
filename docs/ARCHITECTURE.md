# Point-in-Time Recovery (PITR) Lab Architecture

This document explains the "why" behind each module and feature in this PITR project.

## 1. Why Point-in-Time Recovery (PITR)?
Standard database backups (like `pg_dump`) only take a snapshot of the database at a specific moment (e.g., 2:00 AM). If your database crashes at 4:00 PM, you lose 14 hours of data! 
**PITR** solves this by continuously archiving Write-Ahead Logs (WAL). By replaying these WAL files on top of a base backup, you can restore the database to *any exact millisecond* before a disaster occurred.

## 2. Why use pgBackRest?
While PostgreSQL has built-in WAL archiving, managing it manually is error-prone. We use **pgBackRest** because:
* **Reliability:** It ensures WAL files are safely copied and checks for corruption.
* **Speed:** It supports parallel backup and restore operations.
* **Storage Efficiency:** It compresses backups and supports differential/incremental backups, saving massive disk space compared to standard tools.

## 3. Why the Custom UI Dashboard?
WAL logs and `pg_waldump` output are notoriously difficult for humans to read. It's essentially a massive stream of hexadecimal numbers and internal Postgres operations. 
We added a **UI Dashboard** to:
* Translate complex `pg_waldump` logs into human-readable actions (e.g., "Deleted row from table 'users'").
* Provide a 1-click restore mechanism by automatically calculating the exact LSN (Log Sequence Number) to restore to.
* Visually separate user actions (like INSERT/UPDATE/DELETE) from Postgres background system noise.

## 4. Module Breakdown

### `postgres/`
Contains the Dockerfile and configuration (`postgresql.conf`, `pgbackrest.conf`) needed to run a Postgres instance pre-configured for continuous WAL archiving. It turns on `archive_mode` and sets `archive_command` to send logs to pgBackRest.

### `scripts/`
Contains automation scripts:
* `backup.sh`: Triggers a pgBackRest incremental/full backup.
* `restore.sh`: Automates stopping the database, restoring to a specific LSN, and restarting the server.

### `dashboard/`
A lightweight Hono backend and HTML frontend. It uses `docker exec` to run `pg_waldump` in real-time, parses the output, and serves it over an API so the UI can build the transaction timeline.
