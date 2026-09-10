# PostgreSQL Backup with pgBackRest

## Overview

This lab implements production-style PostgreSQL physical backup and WAL archiving using pgBackRest.

The backup solution includes:

- Full physical backups
- Incremental physical backups
- WAL archiving
- Backup retention
- Automated backup scheduling with cron
- Backup logging
- Backup verification
- Support for Point-in-Time Recovery (PITR)

## Environment

| Component | Configuration |
|---|---|
| PostgreSQL Version | PostgreSQL 18.6 |
| Operating System | Oracle Linux 8.10 |
| Backup Tool | pgBackRest 2.59.1 |
| pgBackRest Stanza | `banking` |
| PostgreSQL Data Directory | `/var/lib/pgsql/18/data` |
| Backup Repository | `/var/lib/pgbackrest` |
| Backup Type | Physical |
| WAL Archiving | Enabled |

## pgBackRest Installation

pgBackRest was installed from the PostgreSQL PGDG repository.

Version verification:

```bash
pgbackrest version
```

Observed version:

```text
pgBackRest 2.59.1
```

## Repository Structure

The local pgBackRest repository is located at:

```text
/var/lib/pgbackrest
```

Repository structure:

```text
/var/lib/pgbackrest/
├── archive/
│   └── banking/
└── backup/
    └── banking/
```

The repository is owned by the PostgreSQL operating system user.

## pgBackRest Configuration

Configuration file:

```text
/etc/pgbackrest/pgbackrest.conf
```

Configuration:

```ini
[banking]
pg1-path=/var/lib/pgsql/18/data

[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
start-fast=y

[global:archive-push]
compress-level=3
```

The stanza name used by this lab is:

```text
banking
```

## Stanza Creation

The pgBackRest stanza was initialized using:

```bash
pgbackrest --stanza=banking --log-level-console=info stanza-create
```

Successful result:

```text
INFO: stanza-create for stanza 'banking' on repo1
INFO: stanza-create command end: completed successfully
```

Before the first backup, pgBackRest correctly reported:

```text
status: error (no valid backups)
```

This was expected because the repository had been initialized but no backup had yet been created.

## WAL Archiving

Point-in-Time Recovery requires continuous WAL archiving.

The following PostgreSQL settings were configured:

```text
archive_mode = on
archive_command = '/usr/bin/pgbackrest --stanza=banking archive-push %p'
wal_level = replica
```

The settings can be verified using:

```sql
SHOW archive_mode;
SHOW archive_command;
SHOW wal_level;
```

Observed configuration:

```text
archive_mode = on
archive_command = /usr/bin/pgbackrest --stanza=banking archive-push %p
wal_level = replica
```

## WAL Archive Verification

The pgBackRest configuration and WAL archiving were verified using:

```bash
pgbackrest --stanza=banking --log-level-console=info check
```

Observed result:

```text
INFO: check repo1 configuration (primary)
INFO: check repo1 archive for WAL (primary)
INFO: WAL segment successfully archived
INFO: check command end: completed successfully
```

PostgreSQL archiver statistics were also checked:

```sql
SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time
FROM pg_stat_archiver;
```

During testing:

```text
archived_count = 1
failed_count   = 0
```

This confirmed that WAL files were successfully being archived through pgBackRest.

## Full Backup

The first full physical backup was created using:

```bash
pgbackrest \
    --stanza=banking \
    --type=full \
    --log-level-console=info \
    backup
```

Observed backup label:

```text
20260910-145802F
```

The `F` suffix identifies the backup as a full backup.

Observed result:

```text
full backup size = 198.6MB
file total = 1299
backup command end: completed successfully
```

Repository statistics:

```text
database size: 198.6MB
database backup size: 198.6MB
repo1 backup set size: 48.7MB
repo1 backup size: 48.7MB
```

This confirmed that the physical backup was successfully stored in the pgBackRest repository.

## Incremental Backup

After the full backup, a controlled database change was created.

Example:

```sql
INSERT INTO banking.audit_log
    (username, action, object_name)
VALUES
    ('postgres', 'BACKUP_TEST', 'incremental_backup');
```

An incremental backup was then created:

```bash
pgbackrest \
    --stanza=banking \
    --type=incr \
    --log-level-console=info \
    backup
```

Observed incremental backup label:

```text
20260910-145802F_20260910-150000I
```

The `I` suffix identifies the backup as an incremental backup.

Observed result:

```text
incr backup size = 2.4MB
backup command end: completed successfully
```

Repository backup size for this incremental backup was approximately:

```text
65.8KB
```

The incremental backup referenced the existing full backup:

```text
backup reference total: 1 full
```

## Second Incremental Backup Test

The exact command used by the scheduled cron job was also manually tested.

A second incremental backup was successfully created:

```text
20260910-145802F_20260910-151008I
```

Observed result:

```text
incr backup size = 2.4MB
repo1 backup size = 66.1KB
backup reference total: 1 full, 1 incr
```

This verified that the scheduled backup command works correctly outside the interactive test workflow.

## Backup Chain

The resulting backup chain was:

```text
20260910-145802F
        |
        +-- 20260910-145802F_20260910-150000I
        |
        +-- 20260910-145802F_20260910-151008I
```

The chain contains:

```text
1 Full Backup
2 Incremental Backups
```

## Backup Information

Backup status can be checked using:

```bash
pgbackrest --stanza=banking info
```

Observed stanza status:

```text
stanza: banking
    status: ok
    cipher: none
```

The command displays:

- Backup labels
- Backup types
- Backup start and stop times
- Required WAL range
- Database size
- Backup size
- Repository size
- Backup dependencies

## Backup Retention

The repository is configured with:

```text
repo1-retention-full=2
```

This keeps two full backup sets according to the configured pgBackRest retention policy.

Backup expiration is handled automatically by pgBackRest after backup operations.

Example:

```text
INFO: expire command begin
INFO: expire command end: completed successfully
```

## Backup Scheduling

Backup execution is automated using the PostgreSQL Linux user's crontab.

The schedule is:

```text
Monday - Saturday  02:00  Incremental Backup
Sunday             02:00  Full Backup
```

Crontab configuration:

```bash
0 2 * * 1-6 /usr/bin/pgbackrest --stanza=banking --type=incr --log-level-console=info backup >> /var/log/pgbackrest/backup_cron.log 2>&1
0 2 * * 0 /usr/bin/pgbackrest --stanza=banking --type=full --log-level-console=info backup >> /var/log/pgbackrest/backup_cron.log 2>&1
```

This provides:

```text
Sunday        -> FULL
Monday        -> INCREMENTAL
Tuesday       -> INCREMENTAL
Wednesday     -> INCREMENTAL
Thursday      -> INCREMENTAL
Friday        -> INCREMENTAL
Saturday      -> INCREMENTAL
```

## Backup Logging

Cron backup output is written to:

```text
/var/log/pgbackrest/backup_cron.log
```

The log file is owned by:

```text
postgres:postgres
```

with restricted permissions.

Example successful log:

```text
INFO: backup command begin
INFO: execute backup start
INFO: new backup label = ...
INFO: incr backup size = ...
INFO: backup command end: completed successfully
```

## Repository Size

After the full backup and incremental backup tests, the repository size was checked using:

```bash
du -sh /var/lib/pgbackrest
```

Observed size:

```text
56M
```

The PostgreSQL database size was approximately:

```text
198.7MB
```

This demonstrates pgBackRest's efficient storage behavior for the test workload.

## Existing Cron Cleanup

Before configuring pgBackRest scheduling, the PostgreSQL user's crontab contained:

```text
0 2 * * * /var/lib/pgsql/scripts/backup.sh
```

The referenced script and directory no longer existed.

The stale cron entry was therefore removed and replaced with the tested pgBackRest backup schedule.

A copy of the original crontab was taken before making the change.

## Backup Verification

The backup implementation was verified through multiple checks:

```bash
pgbackrest --stanza=banking check
```

```bash
pgbackrest --stanza=banking info
```

```sql
SELECT * FROM pg_stat_archiver;
```

```bash
du -sh /var/lib/pgbackrest
```

The following functionality was successfully validated:

- pgBackRest installation
- Stanza creation
- WAL archiving
- WAL archive verification
- Full physical backup
- Incremental physical backup
- Backup dependency chain
- Backup retention configuration
- Automated cron scheduling
- Backup command logging
- Repository storage
- Backup availability for PITR

## Security Considerations

Sensitive information is intentionally excluded from the Git repository.

The repository does not contain:

```text
Database passwords
.pgpass contents
SMTP credentials
Private keys
Authentication tokens
Internal infrastructure secrets
```

The backup repository and PostgreSQL data directory use operating system permissions controlled by the PostgreSQL service account.

## Result

The lab successfully implemented a PostgreSQL physical backup solution using pgBackRest with continuous WAL archiving, full and incremental backups, retention management, automated scheduling, backup logging, and recovery-ready backup chains.

The backup environment was subsequently used to perform a successful Point-in-Time Recovery test documented in the disaster recovery section.
