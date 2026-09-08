# PostgreSQL Streaming Replication

## Overview

This lab implements PostgreSQL physical streaming replication using one primary server and one read-only standby server.

## Architecture

```text
Application
    |
    v
PostgreSQL Primary
    |
    | WAL Streaming
    v
PostgreSQL Standby
```

Public documentation intentionally excludes real infrastructure IP addresses.

## Environment

| Component | Configuration |
|---|---|
| PostgreSQL Version | PostgreSQL 18.6 |
| Operating System | Oracle Linux 8.10 |
| Replication Type | Physical Streaming Replication |
| Replication Mode | Asynchronous |
| Primary Role | Read / Write |
| Standby Role | Read Only |

## Primary Configuration

The primary server was configured with the following replication-related parameters:

```text
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
```

A dedicated replication role was created:

```sql
CREATE ROLE replicator
WITH LOGIN REPLICATION;
```

The replication password was configured separately and is not stored in this repository.

## pg_hba.conf

Only the standby server is permitted to establish replication connections using the replication account.

Example:

```text
host    replication    replicator    <STANDBY_IP>/32    scram-sha-256
```

## Standby Initialization

The standby server was initialized from the primary using `pg_basebackup`:

```bash
pg_basebackup \
    -h <PRIMARY_IP> \
    -U replicator \
    -D /var/lib/pgsql/18/data \
    -Fp \
    -X stream \
    -P \
    -R \
    -w
```

The `-R` option created the standby configuration automatically, including `standby.signal` and `primary_conninfo`.

Authentication credentials were stored using `.pgpass` with permission `0600` and are excluded from Git.

## Replication Verification

On the primary:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

Observed state:

```text
state       = streaming
sync_state  = async
lag         = 0 bytes
```

On the standby:

```sql
SELECT pg_is_in_recovery();
```

Result:

```text
t
```

The WAL receiver was also verified:

```sql
SELECT
    status,
    sender_host,
    sender_port,
    written_lsn,
    flushed_lsn,
    latest_end_lsn
FROM pg_stat_wal_receiver;
```

Observed status:

```text
status = streaming
```

## Replication Test

A test row was inserted on the primary:

```sql
INSERT INTO banking.audit_log
    (username, action, object_name)
VALUES
    ('postgres', 'REPLICATION_TEST', 'primary_to_standby');
```

The same row appeared automatically on the standby, confirming that WAL streaming was working correctly.

## Read-Only Standby Verification

A write operation was intentionally attempted on the standby:

```sql
INSERT INTO banking.audit_log
    (username, action, object_name)
VALUES
    ('postgres', 'STANDBY_WRITE_TEST', 'should_fail');
```

PostgreSQL correctly rejected the operation:

```text
ERROR: cannot execute INSERT in a read-only transaction
```

## Result

The lab successfully demonstrated:

- Physical streaming replication
- Asynchronous WAL streaming
- Dedicated replication authentication
- Read/write primary
- Read-only standby
- Zero observed replication lag during testing
- Real data replication from primary to standby
