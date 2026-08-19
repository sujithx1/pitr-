// ==============================================================================
// Logical Decoding Real-Time Streaming Server (Bun + Hono)
// Bypasses low-level pg_waldump text parsing using PostgreSQL Logical Replication
// ==============================================================================

import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';
import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

// Strictly load environment variables from production_ready/.env
const prodEnvPath = resolve(__dirname, '../.env');
if (existsSync(prodEnvPath)) {
  try {
    const content = readFileSync(prodEnvPath, 'utf-8');
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
        const [key, ...valParts] = trimmed.split('=');
        const k = key.trim();
        const v = valParts.join('=').trim().replace(/^["']|["']$/g, '');
        if (k) {
          process.env[k] = v;
        }
      }
    }
  } catch (e) {}
}

const app = new Hono();

const PG_CONTAINER = process.env.PG_CONTAINER_NAME || 'postgres_pitr_prod';
const PG_USER = process.env.PG_USER || process.env.POSTGRES_USER || 'dev';
const PG_DB = process.env.PG_DB || process.env.POSTGRES_DB || 'mds';

function runSql(sql: string): string {
  try {
    const cmd = `docker exec ${PG_CONTAINER} psql -U ${PG_USER} -d ${PG_DB} -t -A -P pager=off -c "${sql}"`;
    return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' }).trim();
  } catch (err: any) {
    const stderr = err.stderr ? err.stderr.toString().trim() : err.message;
    console.error(`[LOGICAL STREAMER ERROR] Command failed on ${PG_CONTAINER}: ${stderr}`);
    throw new Error(`Failed on container '${PG_CONTAINER}': ${stderr}`);
  }
}

// Serve static UI assets from ./public
app.use('/*', serveStatic({ root: './public' }));

// Ensure logical replication slot exists
app.post('/api/logical/init', (c) => {
  try {
    let checkSlot = '';
    try {
      checkSlot = runSql("SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'pitr_logical_slot';");
    } catch (e: any) {
      return c.json({ success: false, error: e.message }, 500);
    }

    if (!checkSlot) {
      try {
        runSql("SELECT pg_create_logical_replication_slot('pitr_logical_slot', 'test_decoding');");
        return c.json({ success: true, message: "Logical replication slot 'pitr_logical_slot' created successfully." });
      } catch (e: any) {
        return c.json({ success: false, error: e.message }, 500);
      }
    }
    return c.json({ success: true, message: "Replication slot already exists." });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

function ensureSlotExists() {
  try {
    const checkSql = "SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'pitr_logical_slot';";
    const exists = runSql(checkSql);
    if (!exists) {
      console.log("[LOGICAL STREAMER] Auto-creating missing replication slot 'pitr_logical_slot'...");
      runSql("SELECT pg_create_logical_replication_slot('pitr_logical_slot', 'test_decoding');");
    }
  } catch (e) { }
}

// Peek at recent logical decoding JSON events with Pagination & Date Filtering
app.get('/api/wal/logical', (c) => {
  try {
    ensureSlotExists();

    const startDate = c.req.query('start_date');
    const endDate = c.req.query('end_date');
    const page = Math.max(1, parseInt(c.req.query('page') || '1', 10));
    const limit = Math.max(1, parseInt(c.req.query('limit') || '50', 10));

    // 1. Fetch newest 1000 changes natively in PostgreSQL (ORDER BY lsn DESC LIMIT 1000)
    const sql = "SELECT lsn, data FROM pg_logical_slot_peek_changes('pitr_logical_slot', NULL, NULL) ORDER BY lsn DESC LIMIT 1000;";
    let rawOutput = runSql(sql);

    if (!rawOutput) {
      return c.json({
        events: [],
        total: 0,
        page,
        limit,
        totalPages: 0,
        metrics: { total: 0, inserts: 0, updates: 0, deletes: 0 },
        notice: "No active unread changes in logical slot."
      });
    }

    const lines = rawOutput.split('\n');
    let allEvents = lines.map((line) => {
      const parts = line.split('|');
      const lsn = parts[0] || '';
      const data = parts.slice(1).join('|') || '';
      const isCommit = data.includes('COMMIT');

      const timeMatch = data.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(\.\d+)?)/);
      const timestamp = timeMatch && timeMatch[1] ? timeMatch[1] : '';

      return { lsn, data, isCommit, timestamp };
    });

    // 2. Compute accurate metric counts across the FULL dataset (all 500 records)
    let inserts = 0, updates = 0, deletes = 0;
    allEvents.forEach(ev => {
      const upper = ev.data.toUpperCase();
      if (upper.includes('INSERT:')) inserts++;
      else if (upper.includes('UPDATE:')) updates++;
      else if (upper.includes('DELETE:')) deletes++;
    });

    // 3. Filter Date Range across the FULL dataset
    if (startDate || endDate) {
      const startMs = startDate ? new Date(startDate).getTime() : 0;
      const endMs = endDate ? new Date(endDate).getTime() : Infinity;

      allEvents = allEvents.filter(ev => {
        const timeMatch = ev.data.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
        if (timeMatch && timeMatch[1]) {
          const evMs = new Date(timeMatch[1]).getTime();
          return evMs >= startMs && evMs <= endMs;
        }
        return true;
      });
    }

    // 4. Sort in strict DESCENDING order (Newest LSN first)
    allEvents.sort((a, b) => b.lsn.localeCompare(a.lsn, undefined, { numeric: true, sensitivity: 'base' }));

    // 5. Paginate after computing full metrics & date filtering
    const total = allEvents.length;
    const totalPages = Math.ceil(total / limit) || 1;
    const safePage = Math.max(1, Math.min(page, totalPages));
    const startIndex = (safePage - 1) * limit;
    const paginatedEvents = allEvents.slice(startIndex, startIndex + limit);

    return c.json({
      slot: 'pitr_logical_slot',
      plugin: 'test_decoding',
      total,
      page: safePage,
      limit,
      totalPages,
      metrics: {
        total,
        inserts,
        updates,
        deletes
      },
      events: paginatedEvents
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

// Trigger Point-in-Time Recovery
app.post('/api/restore', async (c) => {
  try {
    const { timestamp, lsn, restoreMode } = await c.req.json();
    const target = lsn || timestamp;

    if (!target) {
      return c.json({ error: "No target LSN or timestamp provided" }, 400);
    }

    const scriptsDir = execSync('pwd', { encoding: 'utf-8' }).trim().replace(/\/dashboard$/, '/scripts');

    if (restoreMode === 'inplace') {
      const scriptPath = `${scriptsDir}/restore_inplace.sh`;


      console.log(`[RECOVERY 1/2] Executing In-Place Restore: bash ${scriptPath} "${target}"`);


      const output = execSync(`bash "${scriptPath}" "${target}"`, { cwd: scriptsDir, encoding: 'utf-8' });


      console.log(`[RESTORE OUTPUT]:\n${output}`);

      return c.json({ success: true, mode: 'inplace', log: output });
    } else {
      const scriptPath = `${scriptsDir}/restore_cluster_clone.sh`;

      console.log(`[RECOVERY 2/2] Executing Physical Cluster Promotion: bash ${scriptPath} "${target}"`);

      const output = execSync(`bash "${scriptPath}" "${target}"`, { cwd: scriptsDir, encoding: 'utf-8' });

      console.log(`[RESTORE OUTPUT]:\n${output}`);
      return c.json({ success: true, mode: 'cluster', log: output });
    }
  } catch (err: any) {
    const logOutput = err.stdout || err.stderr || err.output?.join?.('\n') || err.message;
    console.error(`[RESTORE LOG/ERROR]:\n${logOutput}`);
    return c.json({ success: false, log: logOutput, error: err.message || String(err) }, 200);
  }
});

export default {
  port: process.env.LOGICAL_PORT || 7100,
  fetch: app.fetch
};
