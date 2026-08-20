# Database Backup Integration Guide

Welcome! To connect your database to our Enterprise Backup & Point-in-Time Recovery service, you will need to install our backup agent (`pgBackRest`) and make a few minor configuration changes to your database. 

Please follow the instructions below based on your infrastructure.

---

## Step 1: Install the Backup Agent (`pgBackRest`)

Our system requires the `pgBackRest` binary to be installed directly on your database server to ensure high-performance, encrypted backups.

**If you use Docker:**
You must update your `Dockerfile` to install the agent before starting PostgreSQL:
```dockerfile
FROM postgres:18
RUN apt-get update && apt-get install -y pgbackrest && rm -rf /var/lib/apt/lists/*
```

**If you use Ubuntu/Debian Bare-Metal:**
Run the following command on your database server:
```bash
sudo apt-get update
sudo apt-get install pgbackrest
```

---

## Step 2: Configure PostgreSQL (`postgresql.conf`)

You need to instruct PostgreSQL to send its Write-Ahead Logs (WAL) to our backup agent. 
Open your `postgresql.conf` file and update the following settings:

```ini
# 1. Enable Logical Decoding & Commit Timestamp Tracking
wal_level = logical
track_commit_timestamp = on             # Native transaction commit timestamp tracking

# 2. Tell PostgreSQL to hand files to the agent
archive_mode = on
archive_command = 'pgbackrest --stanza=db archive-push %p'

# 3. Force a backup push every 5 minutes (Maximum Data Loss Window)
archive_timeout = 300
```
*Note: You must restart your PostgreSQL server after changing `wal_level`, `track_commit_timestamp`, or `archive_mode`.*

---

## Step 3: Configure the Agent (`pgbackrest.conf`)

We need to tell the agent where to send your encrypted backups. 
Create or edit the `/etc/pgbackrest/pgbackrest.conf` file on your database server and add the cloud storage credentials we provided to you:

```ini
[db]
pg1-path=/var/lib/postgresql/data  # CHANGE THIS to your actual Postgres data folder

[global]
repo1-type=s3
repo1-s3-bucket=our-secure-company-bucket
repo1-s3-region=us-east-1
repo1-s3-endpoint=s3.us-east-1.amazonaws.com
repo1-s3-key=<YOUR_PROVIDED_ACCESS_KEY>
repo1-s3-key-secret=<YOUR_PROVIDED_SECRET_KEY>

# Encryption (Your backups will be encrypted before leaving your server)
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<YOUR_PRIVATE_ENCRYPTION_PASSWORD>
```

---

## Step 4: Verify the Connection

Once the configuration is complete, run the following command on your database server to initialize the backup bridge:

```bash
sudo -u postgres pgbackrest --stanza=db stanza-create
sudo -u postgres pgbackrest --stanza=db check
```

If the check passes, your database is successfully connected to our Point-in-Time Recovery dashboard!
