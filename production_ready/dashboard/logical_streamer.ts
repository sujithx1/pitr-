// ==============================================================================
// PostgreSQL PITR Monitor Server (Bun + Hono)
// WAL + pgBackRest health monitoring and Point-in-Time Recovery triggers.
// Does NOT create or use logical replication slots (avoids unbounded WAL retention).
// ==============================================================================

import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';
import { execSync, exec } from 'child_process';
import { promisify } from 'util';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import { generatePrometheusMetrics } from './metrics';

const execAsync = promisify(exec);

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
const STANZA_NAME = process.env.STANZA_NAME || 'db';

async function runSql(sql: string): Promise<string> {
  try {
    const cmd = `docker exec ${PG_CONTAINER} psql -U ${PG_USER} -d ${PG_DB} -t -A -P pager=off -c "${sql}"`;
    const { stdout } = await execAsync(cmd, { maxBuffer: 1024 * 1024 * 50 });
    return stdout.trim();
  } catch (err: any) {
    const stderr = err.stderr ? err.stderr.toString().trim() : err.message;
    console.error(`[PITR MONITOR ERROR] Command failed on ${PG_CONTAINER}: ${stderr}`);
    throw new Error(`Failed on container '${PG_CONTAINER}': ${stderr}`);
  }
}

async function runCmd(cmd: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { maxBuffer: 1024 * 1024 * 10 });
    return stdout.trim();
  } catch {
    return '';
  }
}

function parseBackupInfo(infoOutput: string): { count: number; lastTimestamp: number; lastStopIso: string | null } {
  let count = 0;
  let lastTimestamp = 0;
  let lastStopIso: string | null = null;
  if (!infoOutput) return { count, lastTimestamp, lastStopIso };
  try {
    const parsed = JSON.parse(infoOutput);
    if (parsed && parsed[0] && parsed[0].backup) {
      count = parsed[0].backup.length;
      if (count > 0) {
        const lastBackup = parsed[0].backup[parsed[0].backup.length - 1];
        lastTimestamp = lastBackup.timestamp?.stop || 0;
        if (lastTimestamp > 0) {
          lastStopIso = new Date(lastTimestamp * 1000).toISOString();
        }
      }
    }
  } catch {
    // Ignore JSON parse errors
  }
  return { count, lastTimestamp, lastStopIso };
}

// WAL + archive + backup health (no logical slots)
app.get('/api/status', async (c) => {
  try {
    let dbOnline = false;
    let currentLsn = '';
    let archiver = {
      lastArchivedWal: null as string | null,
      lastArchivedTime: null as string | null,
      failedCount: 0,
      lastFailedWal: null as string | null,
      lastFailedTime: null as string | null,
    };
    let walBytes = 0;
    let slots: Array<{ name: string; slotType: string; active: boolean; restartLsn: string | null; retainedBytes: number | null }> = [];

    const ready = await runCmd(`docker exec ${PG_CONTAINER} pg_isready -U ${PG_USER} -d ${PG_DB}`);
    dbOnline = ready.includes('accepting connections');

    if (dbOnline) {
      currentLsn = await runSql('SELECT pg_current_wal_lsn();');

      const archRaw = await runSql(
        "SELECT COALESCE(last_archived_wal,''), COALESCE(last_archived_time::text,''), failed_count, COALESCE(last_failed_wal,''), COALESCE(last_failed_time::text,'') FROM pg_stat_archiver;"
      );
      if (archRaw) {
        const [lastWal, lastTime, failed, failWal, failTime] = archRaw.split('|');
        archiver = {
          lastArchivedWal: lastWal || null,
          lastArchivedTime: lastTime || null,
          failedCount: parseInt(failed || '0', 10) || 0,
          lastFailedWal: failWal || null,
          lastFailedTime: failTime || null,
        };
      }

      const walSizeRaw = await runSql(
        "SELECT COALESCE(SUM(size), 0) FROM pg_ls_waldir();"
      );
      walBytes = parseInt(walSizeRaw || '0', 10) || 0;

      const slotsRaw = await runSql(
        "SELECT slot_name, slot_type, active, COALESCE(restart_lsn::text,''), COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn), 0) FROM pg_replication_slots ORDER BY slot_name;"
      );
      if (slotsRaw) {
        slots = slotsRaw.split('\n').filter(Boolean).map((line) => {
          const [name, slotType, active, restartLsn, retained] = line.split('|');
          return {
            name: name || '',
            slotType: slotType || '',
            active: active === 't',
            restartLsn: restartLsn || null,
            retainedBytes: retained ? parseInt(retained, 10) || 0 : null,
          };
        });
      }
    }

    const infoOutput = await runCmd(
      `docker exec -u postgres ${PG_CONTAINER} pgbackrest --stanza=${STANZA_NAME} info --output=json`
    );
    const backups = parseBackupInfo(infoOutput);

    return c.json({
      dbOnline,
      currentLsn,
      archiver,
      wal: {
        bytes: walBytes,
        human: formatBytes(walBytes),
      },
      slots: {
        count: slots.length,
        items: slots,
        warning: slots.length > 0
          ? 'Replication slots present — inactive slots retain WAL and can fill disk.'
          : null,
      },
      backups: {
        count: backups.count,
        lastTimestamp: backups.lastTimestamp,
        lastStopIso: backups.lastStopIso,
      },
    });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const val = bytes / Math.pow(1024, i);
  return `${val.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

app.get('/metrics', (c) => {
  const body = generatePrometheusMetrics();
  return c.text(body, 200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
});

// Trigger Point-in-Time Recovery
app.post('/api/restore', async (c) => {
  try {
    const { timestamp, lsn, restoreMode } = await c.req.json();
    // Prefer explicit LSN when provided; otherwise use timestamp
    const target = (lsn && String(lsn).trim()) || timestamp;

    if (!target) {
      return c.json({ error: 'No target LSN or timestamp provided' }, 400);
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

// Serve static UI assets from ./public (after API routes)
app.use('/*', serveStatic({ root: './public' }));

export default {
  port: process.env.LOGICAL_PORT || 7100,
  fetch: app.fetch
};
