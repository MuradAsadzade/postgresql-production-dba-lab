# PostgreSQL Point-in-Time Recovery (PITR)

## Overview

This lab demonstrates PostgreSQL Point-in-Time Recovery using pgBackRest.

The recovery scenario simulates an accidental table deletion and restores the database to a specific point in time before the destructive operation occurred.

The recovery test was performed without overwriting or stopping the live PostgreSQL primary instance.

## Recovery Scenario

The recovery scenario was:

```text
Create important test data
        |
        v
Record recovery target time
        |
        v
Accidentally DROP the table
        |
        v
Archive required WAL
        |
        v
Restore backup to separate data directory
        |
        v
Replay WAL until recovery target time
        |
        v
Promote recovered instance
        |
        v
Verify deleted data is restored
```

## Environment

| Component | Configuration |
|---|---|
| PostgreSQL Version | PostgreSQL 18.6 |
| Operating System | Oracle Linux 8.10 |
| Backup Tool | pgBackRest 2.59.1 |
| pgBackRest Stanza | `banking` |
| Production Port | `5432` |
| PITR Test Port | `55432` |
| Production Data Directory | `/var/lib/pgsql/18/data` |
| PITR Restore Directory | `/var/lib/pgsql/18/pitr_restore` |
| Recovery Type | Time-based PITR |
| Recovery Action | Promote |

## Prerequisites

The following components were already configured before the PITR test:

- Full physical backup
- Incremental physical backups
- Continuous WAL archiving
- pgBackRest repository
- Working PostgreSQL primary
- Valid backup chain

The available backup chain included:

```text
Full Backup
20260910-145802F

Incremental Backup
20260910-145802F_20260910-150000I

Incremental Backup
20260910-145802F_20260910-151008I
```

WAL archiving was active using:

```text
archive_mode = on
archive_command = '/usr/bin/pgbackrest --stanza=banking archive-push %p'
```

## Creating PITR Test Data

A dedicated test table was created inside the `banking` schema.

```sql
CREATE TABLE banking.pitr_test (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
```

Important test data was inserted:

```sql
INSERT INTO banking.pitr_test (message)
VALUES ('IMPORTANT DATA - PITR TEST');
```

The test row was verified:

```text
id      : 1
message : IMPORTANT DATA - PITR TEST
```

The row creation time was:

```text
2026-09-10 15:37:06.719796+04
```

## Recording the Recovery Target Time

Before performing the destructive operation, an exact recovery target time was recorded.

Command:

```bash
psql -d banking_db -Atc "SELECT clock_timestamp();" \
| tee /tmp/pitr_target_time
```

Recorded target:

```text
2026-09-10 15:37:12.942201+04
```

This target was intentionally selected after the important row was created but before the table was deleted.

The recovery objective was therefore:

```text
Recover database state at:

2026-09-10 15:37:12.942201+04
```

## Simulating Accidental Data Loss

A controlled destructive operation was performed.

```sql
DROP TABLE banking.pitr_test;
```

Result:

```text
DROP TABLE
```

The table was then verified as missing:

```text
Did not find any tables named "banking.pitr_test".
```

This simulated an accidental production table deletion.

## Archiving the Required WAL

After the destructive operation, a WAL switch was requested:

```sql
SELECT pg_switch_wal();
```

The pgBackRest archive configuration was then verified:

```bash
pgbackrest \
    --stanza=banking \
    --log-level-console=info \
    check
```

Observed result:

```text
INFO: check repo1 configuration (primary)
INFO: check repo1 archive for WAL (primary)
INFO: WAL segment successfully archived
INFO: check command end: completed successfully
```

This ensured the WAL required for PITR was available in the pgBackRest repository.

## Safe Restore Design

The live PostgreSQL primary was not overwritten.

Instead, PITR was restored into a separate data directory:

```text
/var/lib/pgsql/18/pitr_restore
```

The production data directory remained:

```text
/var/lib/pgsql/18/data
```

This allowed the recovery procedure to be tested independently from the running primary.

## Restore Directory Preparation

The separate restore directory was created with restricted permissions:

```bash
mkdir -m 700 /var/lib/pgsql/18/pitr_restore
```

A separate PostgreSQL port was selected:

```text
55432
```

The port was verified as free before starting the recovered instance.

## Time-Based pgBackRest Restore

The most recent incremental backup before the recovery target was selected:

```text
20260910-145802F_20260910-151008I
```

The PITR restore command was:

```bash
pgbackrest \
  --stanza=banking \
  --pg1-path=/var/lib/pgsql/18/pitr_restore \
  --set=20260910-145802F_20260910-151008I \
  --type=time \
  --target="2026-09-10 15:37:12.942201+04" \
  --target-action=promote \
  --log-level-console=info \
  restore
```

Observed result:

```text
INFO: repo1: restore backup set 20260910-145802F_20260910-151008I
INFO: remap data directory to '/var/lib/pgsql/18/pitr_restore'
INFO: restore size = 198.7MB
INFO: restore command end: completed successfully
```

## Recovery Configuration

pgBackRest created:

```text
/var/lib/pgsql/18/pitr_restore/recovery.signal
```

The restored `postgresql.auto.conf` contained recovery settings similar to:

```text
restore_command = 'pgbackrest --pg1-path=/var/lib/pgsql/18/pitr_restore --stanza=banking archive-get %f "%p"'

recovery_target_time = '2026-09-10 15:37:12.942201+04'

recovery_target_action = 'promote'
```

This instructed PostgreSQL to retrieve archived WAL files from pgBackRest and replay them until the specified recovery target.

## Starting the Isolated PITR Instance

The recovered database was started on a separate port.

```bash
/usr/pgsql-18/bin/pg_ctl \
  -D /var/lib/pgsql/18/pitr_restore \
  -o "-p 55432 -c listen_addresses='' -c unix_socket_directories='/tmp' -c archive_mode=off" \
  -l /var/lib/pgsql/18/pitr_restore/pitr.log \
  start
```

Important isolation settings:

```text
port = 55432
listen_addresses = ''
unix_socket_directories = '/tmp'
archive_mode = off
```

These settings prevented the PITR test instance from conflicting with the production PostgreSQL instance.

## Instance Verification

The recovered instance was checked using:

```bash
/usr/pgsql-18/bin/pg_isready -h /tmp -p 55432
```

Observed result:

```text
/tmp:55432 - accepting connections
```

Recovery status was verified using:

```sql
SELECT
    pg_is_in_recovery(),
    current_setting('port') AS port,
    current_setting('archive_mode') AS archive_mode;
```

Observed result:

```text
pg_is_in_recovery = false
port              = 55432
archive_mode      = off
```

`pg_is_in_recovery = false` confirmed that PostgreSQL had reached the recovery target and completed promotion.

## Recovery Log Verification

The PostgreSQL recovery log confirmed the PITR process.

Observed messages included:

```text
starting backup recovery with redo LSN
starting point-in-time recovery to 2026-09-10 15:37:12.942201+04
completed backup recovery
consistent recovery state reached
recovery stopping before commit of transaction
archive recovery complete
database system is ready to accept connections
```

The key line was:

```text
recovery stopping before commit of transaction 812
```

This confirmed that PostgreSQL stopped WAL replay before a transaction that occurred after the requested recovery target.

## Recovered Table Verification

The recovered PITR instance was queried through port `55432`.

```bash
psql \
    -h /tmp \
    -p 55432 \
    -d banking_db \
    -c "\dt banking.pitr_test"
```

The table was successfully restored:

```text
Schema  | Name      | Type  | Owner
--------+-----------+-------+---------
banking | pitr_test | table | postgres
```

## Recovered Data Verification

The recovered row was queried:

```sql
SELECT *
FROM banking.pitr_test;
```

Observed result:

```text
id      : 1
message : IMPORTANT DATA - PITR TEST
created : 2026-09-10 15:37:06.719796+04
```

The previously deleted data was successfully recovered.

## Live Primary Verification

The production instance continued running independently on port:

```text
5432
```

The same table was checked on the live primary:

```bash
psql \
    -p 5432 \
    -d banking_db \
    -c "\dt banking.pitr_test"
```

Observed result:

```text
Did not find any tables named "banking.pitr_test".
```

This proved that:

```text
Production instance:
table remained deleted

PITR instance:
table and data were restored
```

The recovery test therefore did not modify the live primary.

## Recovery Validation

The final recovery state was:

```text
LIVE PRIMARY
Port: 5432
pitr_test: NOT PRESENT

            versus

PITR INSTANCE
Port: 55432
pitr_test: PRESENT
Important row: PRESENT
```

This provided direct evidence that the database had been restored to the intended point in time.

## PITR Instance Shutdown

After successful validation, the temporary PITR instance was stopped:

```bash
/usr/pgsql-18/bin/pg_ctl \
  -D /var/lib/pgsql/18/pitr_restore \
  stop
```

Result:

```text
waiting for server to shut down.... done
server stopped
```

The temporary port was then verified:

```bash
/usr/pgsql-18/bin/pg_isready -h /tmp -p 55432
```

Result:

```text
/tmp:55432 - no response
```

The production PostgreSQL instance remained available:

```bash
/usr/pgsql-18/bin/pg_isready -p 5432
```

Result:

```text
/run/postgresql:5432 - accepting connections
```

## PITR Timeline

The complete test sequence was:

```text
14:58
FULL backup completed

15:00
First incremental backup completed

15:10
Second incremental backup completed

15:37:06
Important PITR test data created

15:37:12
Recovery target time recorded

16:02
Test table intentionally dropped

16:02
Required WAL archived

16:06
Backup restored to separate data directory

16:08
WAL replay reached the requested PITR target

16:08
Recovered instance promoted on port 55432

16:08
Deleted table and important data verified
```

## Recovery Objective

The lab demonstrated recovery from an accidental destructive operation.

```text
Failure:
DROP TABLE banking.pitr_test

Recovery target:
2026-09-10 15:37:12.942201+04

Result:
Table restored
Data restored
Production primary unchanged
```

## Test Results

The PITR lab successfully demonstrated:

- Full backup availability
- Incremental backup chain usage
- Continuous WAL archiving
- Recovery target selection
- Controlled destructive failure
- Time-based pgBackRest restore
- Archived WAL retrieval
- WAL replay
- Recovery target enforcement
- Automatic promotion after recovery
- Isolated recovery instance
- Separate recovery port
- Restored table verification
- Restored row verification
- Production instance isolation
- Clean shutdown of the recovery instance

## Safety Considerations

The recovery procedure was designed to avoid unnecessary risk.

The live data directory:

```text
/var/lib/pgsql/18/data
```

was never overwritten.

The restore used:

```text
/var/lib/pgsql/18/pitr_restore
```

The recovered PostgreSQL instance used:

```text
port 55432
```

instead of the production port:

```text
5432
```

TCP listening was disabled for the recovery instance:

```text
listen_addresses = ''
```

WAL archiving was disabled on the recovery instance:

```text
archive_mode = off
```

These controls prevented the PITR test from interfering with the live PostgreSQL primary or backup repository.

## Result

The lab successfully demonstrated a complete PostgreSQL Point-in-Time Recovery workflow using pgBackRest.

A table that was intentionally deleted after the selected recovery target was successfully restored together with its original data.

The live PostgreSQL primary remained operational and unchanged throughout the recovery test.
