# PostgreSQL Lock and Blocking Incident Troubleshooting

## Overview

This lab demonstrates how to identify, analyze, and resolve PostgreSQL blocking and locking incidents.

The scenario simulates two database sessions attempting to update the same row.

The first transaction holds a row-level lock while remaining open.

The second transaction attempts to update the same row and becomes blocked.

The incident is then investigated using PostgreSQL system views and functions.

Two resolution methods are demonstrated:

- Normal transaction rollback
- DBA intervention using `pg_terminate_backend()`

## Incident Scenario

The test scenario is:

```text
Session 1
    |
    | BEGIN
    | UPDATE row
    | transaction remains open
    v
Row Lock Held
    |
    |
    v
Session 2
    |
    | UPDATE same row
    v
BLOCKED
```

The blocking relationship is then investigated from a third DBA session.

```text
Session 1
Blocker
PID 1724561
    |
    | holds transaction lock
    v
Session 2
Blocked
PID 1724818
```

## Test Table

A dedicated lab table was created:

```sql
CREATE TABLE banking.lock_test (
    id bigint PRIMARY KEY,
    description text NOT NULL
);
```

Test data was inserted:

```sql
INSERT INTO banking.lock_test
VALUES (1, 'LOCK INCIDENT TEST');
```

The table was verified using:

```sql
SELECT *
FROM banking.lock_test;
```

Observed result:

```text
id | description
---+--------------------
1  | LOCK INCIDENT TEST
```

## Creating the Blocking Session

The first PostgreSQL session started a transaction:

```sql
BEGIN;
```

The row was then updated:

```sql
UPDATE banking.lock_test
SET description = 'UPDATED BY SESSION 1'
WHERE id = 1;
```

Observed result:

```text
UPDATE 1
```

The transaction was intentionally left open.

No `COMMIT` or `ROLLBACK` was executed.

This caused Session 1 to continue holding the row lock.

## Creating the Blocked Session

A second PostgreSQL session attempted to update the same row:

```sql
UPDATE banking.lock_test
SET description = 'UPDATED BY SESSION 2'
WHERE id = 1;
```

The query did not return immediately.

The session remained waiting because Session 1 still held the required lock.

This created a real PostgreSQL blocking incident.

## Investigating pg_stat_activity

A third DBA session queried `pg_stat_activity`:

```sql
SELECT
    pid,
    usename,
    state,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE datname = 'banking_db'
ORDER BY pid;
```

Observed blocker:

```text
pid             : 1724561
user            : postgres
state           : idle in transaction
wait_event_type : Client
wait_event      : ClientRead
```

Observed blocked session:

```text
pid             : 1724818
user            : postgres
state           : active
wait_event_type : Lock
wait_event      : transactionid
```

The important indicator was:

```text
wait_event_type = Lock
wait_event      = transactionid
```

This showed that the second session was actively waiting for a transaction-level lock dependency.

## Idle in Transaction

The blocking session appeared as:

```text
idle in transaction
```

This means:

```text
The transaction is still open
        |
        v
The last SQL statement finished
        |
        v
The client is currently idle
        |
        v
PostgreSQL must still preserve the transaction and its locks
```

An `idle in transaction` session can therefore cause blocking even though it is not actively executing SQL.

This is an important production troubleshooting indicator.

## Identifying the Blocker

PostgreSQL provides the function:

```sql
pg_blocking_pids(pid)
```

It returns the process IDs of sessions currently blocking a specified backend.

The following query was used:

```sql
SELECT
    pid AS blocked_pid,
    pg_blocking_pids(pid) AS blocking_pids,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Observed result:

```text
blocked_pid  : 1724818
blocking_pid : 1724561
wait type    : Lock
wait event   : transactionid
```

The relationship was therefore:

```text
PID 1724561
BLOCKER
    |
    v
PID 1724818
BLOCKED
```

## Identifying the Blocker Query

The blocker session details were retrieved using:

```sql
SELECT
    pid,
    usename,
    state,
    xact_start,
    query_start,
    query
FROM pg_stat_activity
WHERE pid = ANY (
    SELECT unnest(pg_blocking_pids(pid))
    FROM pg_stat_activity
    WHERE cardinality(pg_blocking_pids(pid)) > 0
);
```

Observed blocker state:

```text
pid   = 1724561
state = idle in transaction
```

The blocker query was:

```sql
UPDATE banking.lock_test
SET description = 'UPDATED BY SESSION 1'
WHERE id = 1;
```

This allowed the DBA to identify both:

- Which session was blocked
- Which session was responsible for the blocking

## Resolution Method 1 - ROLLBACK

The first incident was resolved normally by returning to the blocking session and executing:

```sql
ROLLBACK;
```

Observed result:

```text
ROLLBACK
```

The open transaction was rolled back and the lock was released.

The previously blocked Session 2 immediately completed:

```text
UPDATE 1
```

No application restart or PostgreSQL restart was required.

## Verifying the Lock Was Released

The blocking query was executed again:

```sql
SELECT
    pid AS blocked_pid,
    pg_blocking_pids(pid) AS blocking_pids,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Observed result:

```text
(0 rows)
```

This confirmed that no blocking relationship remained.

## Final Data After ROLLBACK Test

The row was checked:

```sql
SELECT *
FROM banking.lock_test;
```

Observed result:

```text
id | description
---+----------------------
1  | UPDATED BY SESSION 2
```

Session 1's uncommitted change had been rolled back.

Session 2's update then completed successfully.

## DBA Intervention Scenario

A second blocking incident was created to practice administrative intervention.

Session 1 started another transaction:

```sql
BEGIN;
```

The row was updated:

```sql
UPDATE banking.lock_test
SET description = 'BLOCKER SESSION'
WHERE id = 1;
```

The transaction was intentionally left open.

Session 2 then executed:

```sql
UPDATE banking.lock_test
SET description = 'WAITING SESSION'
WHERE id = 1;
```

Session 2 became blocked.

## Detecting the Second Blocking Incident

The DBA session executed:

```sql
SELECT
    pid AS blocked_pid,
    pg_blocking_pids(pid) AS blocking_pids,
    query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Observed result:

```text
blocked_pid  : 1724818
blocking_pid : 1724561
```

This confirmed that PID `1724561` was again blocking PID `1724818`.

## Resolution Method 2 - pg_terminate_backend()

Instead of manually rolling back the blocker transaction, the DBA terminated the blocking backend.

Command:

```sql
SELECT pg_terminate_backend(1724561);
```

Observed result:

```text
pg_terminate_backend
--------------------
t
```

The value:

```text
t
```

confirmed that PostgreSQL successfully terminated the selected backend.

## Effect on the Blocking Session

The terminated session received a message similar to:

```text
FATAL: terminating connection due to administrator command
```

Because the session contained an open transaction, PostgreSQL automatically rolled the transaction back.

The row lock was therefore released.

## Effect on the Blocked Session

After the blocker session was terminated, Session 2 automatically continued.

Observed result:

```text
UPDATE 1
```

The blocked query did not need to be restarted manually.

Once the blocking transaction disappeared, PostgreSQL allowed the waiting transaction to continue.

## Final Blocking Verification

The DBA session checked again:

```sql
SELECT
    pid AS blocked_pid,
    pg_blocking_pids(pid) AS blocking_pids
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Observed result:

```text
(0 rows)
```

This confirmed that the blocking incident had been resolved.

## ROLLBACK vs pg_terminate_backend()

The lab demonstrated two different approaches.

| Method | Behavior |
|---|---|
| `ROLLBACK` | Gracefully ends the transaction from the owning session |
| `pg_terminate_backend()` | DBA forcibly disconnects the blocking backend |

Preferred approach:

```text
If the application/session owner can safely resolve the transaction:
    use COMMIT or ROLLBACK

If the session is abandoned, harmful, or causing a serious incident:
    DBA may use pg_terminate_backend()
```

A production DBA should not terminate sessions without first identifying:

- The blocker PID
- The blocked sessions
- Transaction age
- Current SQL
- Application/user
- Business impact
- Whether the transaction contains important uncommitted work

## pg_cancel_backend() vs pg_terminate_backend()

PostgreSQL also provides:

```sql
pg_cancel_backend(pid)
```

and:

```sql
pg_terminate_backend(pid)
```

The difference is important.

### pg_cancel_backend()

```text
Cancels the currently executing SQL statement
but keeps the database session connected.
```

### pg_terminate_backend()

```text
Terminates the entire database session.
Any open transaction is rolled back.
```

For an `idle in transaction` blocker, `pg_cancel_backend()` may not solve the problem because there is no actively running statement to cancel.

In that situation, terminating the backend may be required if the session owner cannot close the transaction safely.

## Useful Lock Troubleshooting Query

A compact production troubleshooting query is:

```sql
SELECT
    a.pid AS blocked_pid,
    a.usename AS blocked_user,
    a.query AS blocked_query,
    a.wait_event_type,
    a.wait_event,
    pg_blocking_pids(a.pid) AS blocking_pids
FROM pg_stat_activity a
WHERE cardinality(pg_blocking_pids(a.pid)) > 0;
```

This quickly identifies sessions that are currently blocked.

## Blocker Details Query

Blocker session information can be retrieved using:

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    xact_start,
    query_start,
    query
FROM pg_stat_activity
WHERE pid = ANY (
    SELECT unnest(pg_blocking_pids(pid))
    FROM pg_stat_activity
    WHERE cardinality(pg_blocking_pids(pid)) > 0
);
```

This helps determine whether the blocking session should be allowed to continue or requires DBA intervention.

## Important Production Indicators

During a real lock incident, important indicators include:

```text
state = idle in transaction
```

```text
wait_event_type = Lock
```

```text
wait_event = transactionid
```

```text
pg_blocking_pids(pid)
```

These values help identify blocked sessions and the transactions responsible for the blocking.

## Incident Troubleshooting Workflow

A production-style troubleshooting flow is:

```text
Application reports slow or hanging query
        |
        v
Check pg_stat_activity
        |
        v
Look for wait_event_type = Lock
        |
        v
Use pg_blocking_pids()
        |
        v
Identify blocker PID
        |
        v
Inspect blocker transaction and SQL
        |
        v
Evaluate business impact
        |
        +-----------------------------+
        |                             |
        v                             v
Safe transaction owner          DBA intervention required
        |                             |
        v                             v
COMMIT / ROLLBACK              pg_terminate_backend()
        |                             |
        +-------------+---------------+
                      |
                      v
            Verify blocking cleared
```

## Test Results

The lab successfully demonstrated:

- Row-level locking behavior
- Blocking between concurrent PostgreSQL sessions
- `idle in transaction` diagnosis
- `wait_event_type = Lock` detection
- `transactionid` wait detection
- Blocked PID identification
- Blocker PID identification
- `pg_stat_activity` troubleshooting
- `pg_blocking_pids()` usage
- Transaction rollback resolution
- Automatic continuation of waiting queries
- Administrative backend termination
- Automatic rollback after backend termination
- Final blocking verification
- Safe production-style troubleshooting workflow

## Safety Considerations

The incident was performed only against the dedicated lab table:

```text
banking.lock_test
```

No production or business-critical table was used.

`pg_terminate_backend()` was only executed against a deliberately created test session.

In a real production environment, terminating a backend should only be performed after confirming the session identity and understanding the impact of rolling back its current transaction.

## Result

The lab successfully demonstrated how a PostgreSQL DBA can detect and resolve blocking incidents using `pg_stat_activity`, `pg_blocking_pids()`, transaction management, and `pg_terminate_backend()`.

Both graceful transaction resolution and forced DBA intervention were successfully tested.
