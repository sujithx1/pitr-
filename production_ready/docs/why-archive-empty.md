# ❓ Why is the Archive Directory / File Empty or Not Updating Immediately?

## 1. How PostgreSQL WAL Archiving Works

PostgreSQL writes transaction logs (`INSERT`, `UPDATE`, `DELETE`) into its active WAL memory buffer and local WAL directory (`pg_wal/`).

PostgreSQL does **NOT** instantly copy every single SQL write to the pgBackRest backup archive directory (`/backups/archive/db`) as a separate file for every single row.

Instead, PostgreSQL groups changes into **16MB WAL segment files**. A WAL segment file is pushed to the archive repository (`/backups/archive/db`) only when:

1. **A WAL segment file becomes full (16MB)**.
2. **A manual WAL switch is executed (`SELECT pg_switch_wal();`)**.
3. **A pgBackRest backup is executed (`./scripts/backup.sh`)**.

---

## 2. Why Are Brand New Queries Not Visible in `/backups` Right Away?

If you run an `INSERT` statement right now:
* The data is saved in PostgreSQL.
* BUT it is still in PostgreSQL's active 16MB WAL segment file inside the container (`/var/lib/postgresql/18/docker/pg_wal/`).
* Until that 16MB segment file is filled or rotated, pgBackRest has not received the archived file yet.

---

## 3. How We Solved This in Recovery Scripts

To make sure your newest uncommitted transactions are **never lost when you restore**, all our recovery scripts (`restore_cluster_clone.sh` and `restore_inplace.sh`) automatically run **Step `[0/4]`** before restoring:

```bash
# Force flush active WAL segment into backup repository
docker exec -u postgres postgres_pitr_prod psql -U dev -d mds -c "SELECT pg_switch_wal();"
```

This immediately forces PostgreSQL to rotate its current active WAL file and flush all unarchived transactions directly into `/backups/archive/db` right before recovery starts!
