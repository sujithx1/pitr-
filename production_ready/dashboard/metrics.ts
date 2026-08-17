// ==============================================================================
// Prometheus Metrics Exporter for PostgreSQL PITR Dashboard
// ==============================================================================

import { execSync } from 'child_process';

function runCmd(cmd: string): string {
  try {
    return execSync(cmd, { encoding: 'utf-8', stdio: 'pipe' }).trim();
  } catch {
    return '';
  }
}

export function generatePrometheusMetrics(): string {
  const containerName = process.env.PG_CONTAINER_NAME || 'postgres_db_18';
  const pgUser = process.env.PG_USER || 'dev';
  const pgDb = process.env.PG_DB || 'mds';
  const stanzaName = process.env.STANZA_NAME || 'db';

  let dbOnline = 0;
  const statusCheck = runCmd(`docker exec ${containerName} pg_isready -U ${pgUser} -d ${pgDb}`);
  if (statusCheck.includes('accepting connections')) {
    dbOnline = 1;
  }

  let backupCount = 0;
  let lastBackupTimestamp = 0;

  const infoOutput = runCmd(`docker exec -u postgres ${containerName} pgbackrest --stanza=${stanzaName} info --output=json`);
  if (infoOutput) {
    try {
      const parsed = JSON.parse(infoOutput);
      if (parsed && parsed[0] && parsed[0].backup) {
        backupCount = parsed[0].backup.length;
        if (backupCount > 0) {
          const lastBackup = parsed[0].backup[parsed[0].backup.length - 1];
          lastBackupTimestamp = lastBackup.timestamp?.stop || 0;
        }
      }
    } catch (e) {
      // Ignore JSON parse errors
    }
  }

  const nowUnix = Math.floor(Date.now() / 1000);

  return [
    `# HELP pitr_database_online Database online status (1=online, 0=offline)`,
    `# TYPE pitr_database_online gauge`,
    `pitr_database_online{container="${containerName}"} ${dbOnline}`,
    ``,
    `# HELP pitr_backup_total_count Number of completed base backups in pgBackRest repository`,
    `# TYPE pitr_backup_total_count gauge`,
    `pitr_backup_total_count{stanza="${stanzaName}"} ${backupCount}`,
    ``,
    `# HELP pitr_last_backup_timestamp_seconds Timestamp of last successful backup`,
    `# TYPE pitr_last_backup_timestamp_seconds gauge`,
    `pitr_last_backup_timestamp_seconds{stanza="${stanzaName}"} ${lastBackupTimestamp}`,
    ``,
    `# HELP pitr_exporter_last_scrape_seconds Timestamp of Prometheus scrape`,
    `# TYPE pitr_exporter_last_scrape_seconds gauge`,
    `pitr_exporter_last_scrape_seconds ${nowUnix}`,
    ``
  ].join('\n');
}
