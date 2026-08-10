# PostgreSQL Point-in-Time Recovery (PITR) Masterclass

Welcome to the hands-on PostgreSQL PITR Masterclass! This project is designed as an interactive, step-by-step course to master PostgreSQL database storage internals, WAL behavior, checkpoints, and recovery strategies.

## Syllabus & Progress

*   [ ] **Module 1: PostgreSQL Storage Internals** (Current)
    *   Architecture & PGDATA layout
    *   Heap files, Pages, and Tuples
    *   MVCC Basics (xmin, xmax)
    *   Shared Buffers & Dirty Pages
*   [ ] **Module 2: WAL Internals**
*   [ ] **Module 3: Checkpoints**
*   [ ] **Module 4: Base Backups**
*   [ ] **Module 5: WAL Archiving**
*   [ ] **Module 6: Point-In-Time Recovery (PITR)**
*   [ ] **Module 7: Recovery Scenarios**
*   [ ] **Module 8: Streaming Replication**
*   [ ] **Module 9: Backup Tools (pgBackRest, WAL-G, Barman)**
*   [ ] **Module 10: Production Design**

---

## Lab Environment

The lab environment uses Docker Compose to run a PostgreSQL 16 container with preconfigured logs, WAL archiving configurations, and the `pageinspect` extension enabled.

### Accessing the Database
To connect to the database, run:
```bash
docker exec -it postgres_pitr_lab psql -U sujith -d db
```




 2026-08-10 11:41:18.888834+00