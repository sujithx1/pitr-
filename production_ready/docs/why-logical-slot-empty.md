# ❓ Why Does the Dashboard Say "No active unread changes in logical slot"?

## 1. Consuming Read Stream Behavior

PostgreSQL logical decoding plugins (`test_decoding` or `wal2json`) use `pg_logical_slot_get_changes()`.

This is a **consuming read operation**:

* When a new transaction occurs, PostgreSQL decodes the SQL changes into JSON.
* The dashboard background worker reads the decoded changes and displays them.
* PostgreSQL **immediately advances the slot LSN pointer** and marks those events as read.
* Because those changes have already been consumed, calling `pg_logical_slot_get_changes()` again will return **0 rows** until a new SQL query is executed!

---

## 2. Why It Shows "No Active Unread Changes"

If no new `INSERT`, `UPDATE`, or `DELETE` query has been executed in PostgreSQL during the last polling interval (2 seconds), PostgreSQL correctly reports:

> `"No active unread changes in logical slot or slot not initialized."`

This is **100% expected PostgreSQL behavior**!

---

## 3. How to Test Live Streaming Again

Run any new insert query on the production database:

```bash
docker exec -it postgres_pitr_prod psql -U dev -d mds -c "INSERT INTO users (name, email) VALUES ('New User', 'new@example.com');"
```

The logical streamer will immediately pick up the new transaction and render a live card on your dashboard (`http://localhost:4001`)!
