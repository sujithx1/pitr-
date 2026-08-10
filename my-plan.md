# Implementation Plan - Out-of-Place Restore Pipeline

This plan outlines the design and steps to implement the **Out-of-Place / Fork Restore** feature. This allows the user to restore their database up to a specific LSN in a temporary container, dump the recovered data, and stream it to any target PostgreSQL connection URL, ensuring zero downtime for the live database.

---

## Architecture Design

```text
                               +-----------------------------+
                               |     Target Database URL     | (Staging, Prod, or main DB)
                               +-----------------------------+
                                              ^
                                              | psql / pg_restore stream
                                              |
+--------------------------+       +-------------------------+
|   pgBackRest Repository  | ----> |  postgres_recovery_temp |
|   (/backups/backup/...)  |       +-------------------------+
+--------------------------+       (Restores to LSN, boots up,
                                    then dumps data)
```

---

## Proposed Changes

We will modify/create the following files in our project:

### 1. [NEW] Recovery Script: `scripts/restore_fork.sh`
This script will automate the temporary container lifecycle and pg_dump stream.
*   **Input parameters:**
    1.  `TARGET_LSN`: The LSN to recover to.
    2.  `TARGET_DB_URL`: The PostgreSQL connection URL where the dump will be restored (e.g., `postgresql://user:pass@host:5432/dbname`).
*   **Execution Steps:**
    1.  Create a temporary Docker volume `pitr_pgdata_temp`.
    2.  Run `pgBackRest` delta restore inside a temporary container to restore the backup to `pitr_pgdata_temp` targeting the LSN.
    3.  Spawn a temporary database container `postgres_pitr_recovery_temp` on port `5433` using the restored volume `pitr_pgdata_temp`.
    4.  Wait for the recovery process to finish (the database will automatically promote to read-write mode when it finishes replaying WALs).
    5.  Run `pg_dump` against the temporary database, filtering for the tables we want or dumping the entire database.
    6.  Pipe the output of `pg_dump` directly into the destination `TARGET_DB_URL` using `psql`.
    7.  Clean up: stop and remove the temporary container and delete the `pitr_pgdata_temp` volume.

### 2. [MODIFY] Backend API: `dashboard/index.ts`
*   Update `POST /api/restore` to accept an optional `targetDbUrl` parameter.
*   If `targetDbUrl` is present:
    *   Call `../scripts/restore_fork.sh <LSN> <targetDbUrl>` in the background.
    *   Return a status tracking ID so the UI can check recovery progress.
*   If `targetDbUrl` is absent, fall back to the existing in-place restore (`restore.sh`).

### 3. [MODIFY] Frontend UI: `dashboard/public/index.html`
*   Add a toggle option in the restore confirmation modal:
    *   `[x] Restore In-Place (Stop & Overwrite Live Database)`
    *   `[ ] Restore to External Database URL (Zero Downtime)`
*   If the user selects "External Database URL", show an input field for the PostgreSQL Connection String (e.g. `postgresql://sujith:sujith@localhost:5432/db`).
*   Send the selected option and URL parameters in the JSON body of the POST request to `/api/restore`.

---

## Verification Plan

### Manual Verification
1.  Verify that clicking "Restore In-Place" still works exactly as it does now.
2.  Test the Out-of-Place restore:
    *   Verify that the live database container `postgres_pitr_lab` stays running and online.
    *   Confirm that a temporary container spins up, restores the data to the target LSN, dumps it, and pipes it successfully into the destination database URL.
    *   Verify that the temporary container and its volume are cleanly deleted after completion.
