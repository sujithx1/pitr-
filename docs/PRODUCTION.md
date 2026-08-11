# Production Deployment Checklist

If you are taking this Point-in-Time Recovery (PITR) system out of the lab and deploying it to a company's production database, there is a strict checklist of requirements to ensure it is secure, reliable, and does not crash your servers.

## 1. Postgres Configuration (`postgresql.conf`)
You must ensure these settings are enabled on the production database:
* `wal_level = replica` (or `logical`) — required to write detailed WAL logs.
* `archive_mode = on` — required to enable archiving.
* `archive_command = 'pgbackrest --stanza=db archive-push %p'` — tells Postgres to send all WAL logs to pgBackRest.

## 2. External Storage for pgBackRest
In this lab, we save backups to a local folder (`/backups`). **Do not do this in production.** If the server's hard drive crashes, you lose both the database *and* the backups. 
* Update your `pgbackrest.conf` to push backups to an external storage service like **AWS S3**, **Google Cloud Storage**, or an **external NFS drive**.
* Set a **Retention Policy** (e.g., `repo1-retention-full=2`). If you don't set this, pgBackRest will keep backups forever until your company's cloud storage runs out of space!

## 3. Dashboard Backend Access
Currently, our backend (`index.ts`) uses `docker exec` to run `pg_waldump`. 
* If your company doesn't use Docker (e.g., they run Postgres directly on an EC2 Linux VM), you will need to modify the `runCmd` strings in `index.ts` to run standard Linux bash commands instead of `docker exec`.
* The server running the Dashboard backend **must** have read access to the Postgres `pg_wal` folder on the operating system.

## 4. Database User Security
* In the lab, we use the `sujith` user which might be a superuser. For the dashboard, you should create a restricted, read-only user in Postgres that only has permission to run `SELECT c.oid, c.relname FROM pg_class ...`.

## 5. Automated Cron Job Scheduling
You need to set up a real scheduling system (like Linux `crontab` or a Kubernetes CronJob) to run the pgBackRest backups automatically. A standard enterprise schedule is:
* **Full Backup:** Every Sunday at 2:00 AM (`pgbackrest --type=full backup`)
* **Incremental Backup:** Every other day at 2:00 AM (`pgbackrest --type=incr backup`)

By following these 5 steps, your company will have a state-of-the-art, enterprise-grade disaster recovery system!
