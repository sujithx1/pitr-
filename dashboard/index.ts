import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';
import { execSync } from 'child_process';

const app = new Hono();

// Serve static files
app.use('/*', serveStatic({ root: './public' }));

// Helper: Run command and get output
function runCmd(cmd: string): string {
  try {
    return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' }).trim();
  } catch (error: any) {
    console.error(`Error running command: ${cmd}`, error.message);
    return '';
  }
}

let oidCache: Record<string, string> = {};

// Fetch OID to Table name map from Postgres (ONLY for user-created tables in the 'public' schema)
function getOidMap(forceRefresh = false): Record<string, string> {
  if (Object.keys(oidCache).length > 0 && !forceRefresh) {
    return oidCache;
  }
  
  const map: Record<string, string> = {};
  // Filter by 'public' namespace OID so we don't fetch system tables (like pg_class, pg_depend, etc.)
  const sql = "SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r' AND n.nspname = 'public';";
  const output = runCmd(`docker exec -i postgres_pitr_lab psql -U sujith -d db -t -A -P pager=off -c "${sql}"`);
  
  if (output) {
    output.split('\n').forEach(line => {
      const [oid, name] = line.split('|');
      if (oid && name) map[oid.trim()] = name.trim();
    });
    oidCache = map;
  }
  return oidCache;
}

// Get the timestamp of a transaction if available (from commit record) or estimate it
function getTxTimestamps(): Record<string, string> {
  const map: Record<string, string> = {};
  // We can query pg_xact or pg_last_xact_replay_timestamp but since we are looking at WAL records,
  // we will query users insert timestamps if we had them. Otherwise, we return estimated server times.
  return map;
}

app.get('/api/status', (c) => {
  const pgStatus = runCmd("docker inspect -f '{{.State.Status}}' postgres_pitr_lab");
  let dbConnection = "OFFLINE";
  if (pgStatus === "running") {
    const check = runCmd("docker exec -i postgres_pitr_lab pg_isready -U sujith -d db");
    if (check.includes("accepting connections")) {
      dbConnection = "ONLINE";
    } else {
      dbConnection = "STARTING/RECOVERING";
    }
  }
  return c.json({
    containerStatus: pgStatus || "stopped",
    databaseStatus: dbConnection
  });
});

app.get('/api/wal', (c) => {
  try {
    console.log("wal log api called")
    // 1. Get current active WAL file name
    const currentWalFile = runCmd(
      `docker exec -i postgres_pitr_lab psql -U sujith -d db -t -A -P pager=off -c "SELECT pg_walfile_name(pg_current_wal_lsn());"`
    );

    console.log(`currentWalFile : ${currentWalFile}`)
    if (!currentWalFile) {
      return c.json({ error: "Could not fetch active WAL file" }, 500);
    }

    // 2. Fetch OID table map (from cache)
    const oidMap = getOidMap();

    // console.log(`oidMap : ${JSON.stringify(oidMap)}`)
    // 3. Run pg_waldump on the current file (appended || true because hitting the end of active WAL file is normal and returns exit code 1)
    const dumpOutput = runCmd(
      `docker exec -i postgres_pitr_lab pg_waldump /var/lib/postgresql/18/docker/pg_wal/${currentWalFile} || true`
    );

    console.log(`dumpOutput : ${dumpOutput}`)
    if (!dumpOutput) {
      return c.json({ events: [] });
    }

    const lines = dumpOutput.split('\n');
    const events = [];

    // Regex to parse LSN, tx, desc, and blkref
    // e.g., rmgr: Heap        len (rec/tot):     63/    63, tx:        771, lsn: 0/04000028, prev 0/030000B0, desc: INSERT off: 6, flags: 0x00, blkref #0: rel 1663/16384/16432 blk 0
    for (const line of lines) {
      if (!line.includes('lsn:')) continue;

      const rmgrMatch = line.match(/rmgr:\s+([A-Za-z0-9_]+)/);
      const txMatch = line.match(/tx:\s+(\d+)/);
      const lsnMatch = line.match(/lsn:\s+([0-9A-F\/]+)/);
      const descMatch = line.match(/desc:\s+([^,]+)/);
      const relMatch = line.match(/rel\s+\d+\/\d+\/(\d+)/);

      const lsn = lsnMatch ? lsnMatch[1] : '';
      const tx = txMatch ? txMatch[1] : '0';
      const desc = descMatch ? descMatch[1] : '';
      const rmgr = rmgrMatch ? rmgrMatch[1] : '';
      const tableOid = relMatch ? relMatch[1] : '';

      // Skip system catalog modifications (Postgres system tables always have OIDs < 16384)
      if (tableOid && parseInt(tableOid) < 16384) {
        continue;
      }

      // Resolve table name (lazy load if unknown OID is found)
      let tableName = tableOid;
      if (tableOid) {
        if (!oidMap[tableOid]) {
          Object.assign(oidMap, getOidMap(true));
        }
        tableName = oidMap[tableOid] || `Relation ${tableOid}`;
      }

      // Filter for interesting client operations
      if (rmgr === 'Heap' || rmgr === 'Heap2' || rmgr === 'Transaction' || desc.includes('COMMIT') || desc.includes('ABORT') || desc.includes('DROP')) {
        let opType = 'UNKNOWN';
        let detail = desc;

        if (desc.startsWith('INSERT')) {
          opType = 'INSERT';
          detail = `Inserted row into table '${tableName}'`;
        } else if (desc.startsWith('UPDATE')) {
          opType = 'UPDATE';
          detail = `Updated row in table '${tableName}'`;
        } else if (desc.startsWith('DELETE')) {
          opType = 'DELETE';
          detail = `Deleted row from table '${tableName}'`;
        } else if (desc.startsWith('COMMIT')) {
          opType = 'COMMIT';
          detail = `Transaction ${tx} committed`;
        } else if (desc.startsWith('ABORT')) {
          opType = 'ROLLBACK';
          detail = `Transaction ${tx} rolled back`;
        } else if (desc.includes('DROP')) {
          opType = 'DROP';
          detail = `Dropped table/relation OID ${tableOid}`;
        }

        events.push({
          lsn,
          tx,
          rmgr,
          opType,
          detail,
          raw: line
        });
      }
    }

    // Return the last 15 records in reverse order (newest first)
    return c.json({
      activeWalFile: currentWalFile,
      events: events.reverse().slice(0, 15)
    });
  } catch (err: any) {
    return c.json({ error: err.message }, 500);
  }
});

app.post('/api/restore', async (c) => {
  const { timestamp, lsn } = await c.req.json();
  let target = timestamp;

  if (!target) {
    return c.json({ error: "No target timestamp provided" }, 400);
  }

  console.log(`Triggering Point-in-Time Restore to: ${target}`);

  // Run the restore script asynchronously as we need to restart the container which runs this API!
  // Since the API stops the database container, it will work fine because the API container is running on the host!
  try {
    // Run restore.sh script
    const output = runCmd(`./scripts/restore.sh "${target}"`);
    return c.json({ success: true, log: output });
  } catch (err: any) {
    return c.json({ success: false, error: err.message }, 500);
  }
});

export default {
  port: 3001,
  fetch: app.fetch,
};