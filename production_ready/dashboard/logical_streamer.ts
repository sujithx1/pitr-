// ==============================================================================
// Logical Decoding Real-Time Streaming Server (Bun + Hono)
// Bypasses low-level pg_waldump text parsing using PostgreSQL Logical Replication
// ==============================================================================

import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';
import { execSync } from 'child_process';

const app = new Hono();

let PG_USER = process.env.PG_USER || 'sujith';
let PG_DB = process.env.PG_DB || 'db';

function getDbParams(): { container: string; user: string; db: string } {
  try {
    const check0 = execSync(`docker exec postgres_pitr_prod pg_isready -U ${PG_USER} -d ${PG_DB}`, { stdio: 'pipe' }).toString();
    if (check0.includes('accepting connections')) return { container: 'postgres_pitr_prod', user: PG_USER, db: PG_DB };
  } catch {}
  try {
    const check1 = execSync(`docker exec postgres_pitr_lab pg_isready -U ${PG_USER} -d ${PG_DB}`, { stdio: 'pipe' }).toString();
    if (check1.includes('accepting connections')) return { container: 'postgres_pitr_lab', user: PG_USER, db: PG_DB };
  } catch {}
  try {
    const check2 = execSync(`docker exec postgres_db_18 pg_isready -U dev -d mds`, { stdio: 'pipe' }).toString();
    if (check2.includes('accepting connections')) return { container: 'postgres_db_18', user: 'dev', db: 'mds' };
  } catch {}
  return { container: process.env.PG_CONTAINER_NAME || 'postgres_pitr_prod', user: PG_USER, db: PG_DB };
}

function runSql(sql: string): string {
  try {
    const p = getDbParams();
    const cmd = `docker exec ${p.container} psql -U ${p.user} -d ${p.db} -t -A -P pager=off -c "${sql}"`;
    return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' }).trim();
  } catch (err: any) {
    return '';
  }
}

// Serve static UI assets from ./public
app.use('/*', serveStatic({ root: './public' }));

// Ensure logical replication slot exists
app.post('/api/logical/init', (c) => {
  try {
    const checkSlot = runSql("SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'pitr_logical_slot';");
    if (!checkSlot) {
      runSql("SELECT pg_create_logical_replication_slot('pitr_logical_slot', 'test_decoding');");
      return c.json({ success: true, message: "Logical replication slot 'pitr_logical_slot' created successfully." });
    }
    return c.json({ success: true, message: "Replication slot already exists." });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

// Peek at recent logical decoding JSON events with Pagination & Date Filtering
app.get('/api/wal/logical', (c) => {
  try {
    const startDate = c.req.query('start_date');
    const endDate = c.req.query('end_date');
    const page = parseInt(c.req.query('page') || '1', 10);
    const limit = parseInt(c.req.query('limit') || '15', 10);

    const sql = "SELECT lsn, data FROM pg_logical_slot_peek_changes('pitr_logical_slot', NULL, 500);";
    const rawOutput = runSql(sql);
    
    if (!rawOutput) {
      return c.json({ events: [], total: 0, page, limit, totalPages: 0, notice: "No active unread changes in logical slot or slot not initialized." });
    }

    const lines = rawOutput.split('\n');
    let events = lines.map((line) => {
      const parts = line.split('|');
      const lsn = parts[0] || '';
      const data = parts.slice(1).join('|') || '';
      const isCommit = data.includes('COMMIT');
      return { lsn, data, isCommit };
    });

    // Date Filtering
    if (startDate || endDate) {
      const startMs = startDate ? new Date(startDate).getTime() : 0;
      const endMs = endDate ? new Date(endDate).getTime() : Infinity;

      events = events.filter(ev => {
        const timeMatch = ev.data.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
        if (timeMatch && timeMatch[1]) {
          const evMs = new Date(timeMatch[1]).getTime();
          return evMs >= startMs && evMs <= endMs;
        }
        return true;
      });
    }

    // Reverse to show newest first
    events = events.reverse();

    // Pagination
    const total = events.length;
    const totalPages = Math.ceil(total / limit) || 1;
    const safePage = Math.max(1, Math.min(page, totalPages));
    const startIndex = (safePage - 1) * limit;
    const paginatedEvents = events.slice(startIndex, startIndex + limit);

    return c.json({
      slot: 'pitr_logical_slot',
      plugin: 'test_decoding',
      total,
      page: safePage,
      limit,
      totalPages,
      events: paginatedEvents
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

// Trigger Point-in-Time Recovery
app.post('/api/restore', async (c) => {
  try {
    const { timestamp, lsn, targetDbUrl } = await c.req.json();
    const target = lsn || timestamp;

    if (!target) {
      return c.json({ error: "No target LSN or timestamp provided" }, 400);
    }

    if (targetDbUrl) {
      console.log(`Triggering Out-of-Place Fork Restore to LSN: ${target} -> ${targetDbUrl}`);
      const output = execSync(`../scripts/restore_fork.sh "${target}" "${targetDbUrl}"`, { encoding: 'utf-8' });
      return c.json({ success: true, log: output });
    } else {
      console.log(`Triggering Physical Cluster Promotion Restore to LSN: ${target}`);
      const output = execSync(`../scripts/restore_cluster_clone.sh "${target}"`, { encoding: 'utf-8' });
      return c.json({ success: true, log: output });
    }
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

export default {
  port: process.env.LOGICAL_PORT || 4001,
  fetch: app.fetch
};
