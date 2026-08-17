// ==============================================================================
// Logical Decoding Real-Time Streaming Server (Bun + Hono)
// Bypasses low-level pg_waldump text parsing using PostgreSQL Logical Replication
// ==============================================================================

import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';
import { execSync } from 'child_process';

const app = new Hono();

const PG_CONTAINER = process.env.PG_CONTAINER_NAME || 'postgres_db_18';
const PG_USER = process.env.PG_USER || 'dev';
const PG_DB = process.env.PG_DB || 'mds';

// Serve static UI assets from ./public
app.use('/*', serveStatic({ root: './public' }));

function runSql(sql: string): string {
  try {
    const cmd = `docker exec ${PG_CONTAINER} psql -U ${PG_USER} -d ${PG_DB} -t -A -P pager=off -c "${sql}"`;
    return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' }).trim();
  } catch (err: any) {
    return '';
  }
}

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

// Peek at recent logical decoding JSON events
app.get('/api/wal/logical', (c) => {
  try {
    const sql = "SELECT lsn, data FROM pg_logical_slot_peek_changes('pitr_logical_slot', NULL, 100);";
    const rawOutput = runSql(sql);
    
    if (!rawOutput) {
      return c.json({ events: [], notice: "No active unread changes in logical slot or slot not initialized." });
    }

    const lines = rawOutput.split('\n');
    const events = lines.map((line) => {
      const parts = line.split('|');
      return {
        lsn: parts[0] || '',
        data: parts.slice(1).join('|')
      };
    });

    return c.json({
      slot: 'pitr_logical_slot',
      plugin: 'test_decoding',
      count: events.length,
      events
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

export default {
  port: process.env.LOGICAL_PORT || 4001,
  fetch: app.fetch
};
