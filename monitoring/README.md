# PostgreSQL Replication Monitoring

## Overview

This lab implements automated PostgreSQL streaming replication monitoring with health checks, replication lag detection, email alerting, duplicate-alert suppression, recovery notifications, cron automation, logging, and log rotation.

## Architecture

```text
Cron
  |
  v
pgmonitor Linux User
  |
  v
replication_alert.sh
  |
  v
replication_monitor.sh
  |
  v
monitoring_user
  |
  v
monitoring_role
  |
  v
pg_monitor
  |
  v
pg_stat_replication
```

The monitoring system uses separate Linux and PostgreSQL users to follow the principle of least privilege.

## Monitoring Components

| Component | Purpose |
|---|---|
| `replication_monitor.sh` | Checks replication health and lag |
| `replication_alert.sh` | Handles alerts and state changes |
| `monitoring_user` | PostgreSQL monitoring login |
| `monitoring_role` | Custom PostgreSQL monitoring role |
| `pgmonitor` | Dedicated Linux monitoring user |
| Cron | Executes monitoring automatically |
| Postfix | Sends email notifications |
| Logrotate | Manages monitoring logs |

## PostgreSQL Monitoring Role

A dedicated monitoring role is used instead of the `postgres` superuser.

```sql
GRANT pg_monitor TO monitoring_role;
GRANT monitoring_role TO monitoring_user;
```

The permission chain is:

```text
monitoring_user
    |
    v
monitoring_role
    |
    v
pg_monitor
```

This allows the monitoring user to access PostgreSQL monitoring statistics without unnecessary administrative privileges.

## Replication Health Check

Replication status is checked using:

```sql
SELECT
    COUNT(*) AS total_standbys,
    COUNT(*) FILTER (WHERE state = 'streaming') AS streaming_standbys,
    COALESCE(
        MAX(pg_wal_lsn_diff(sent_lsn, replay_lsn)),
        0
    )::bigint AS max_lag_bytes
FROM pg_stat_replication;
```

The monitor checks:

- Connected standby count
- Streaming standby count
- Replication lag
- Monitoring query execution status

## Replication Lag Threshold

The configured replication lag threshold is:

```text
500 MB
```

Equivalent to:

```text
524288000 bytes
```

The shell script defines the threshold as:

```bash
LAG_THRESHOLD_BYTES=$((500 * 1024 * 1024))
```

## Monitoring States

The monitoring script returns three possible states:

| State | Meaning |
|---|---|
| HEALTHY | Replication is working normally |
| WARNING | Replication lag exceeded the configured threshold |
| CRITICAL | Standby is unavailable, not streaming, or monitoring failed |

## Healthy Example

```text
PostgreSQL Replication Health Check
===================================
Server             : pg-primary
Total Standbys     : 1
Streaming Standbys : 1
Replication Lag    : 0 bytes
Lag Threshold      : 524288000 bytes

STATUS: HEALTHY
```

## Critical Example

When the standby server is unavailable:

```text
PostgreSQL Replication Health Check
===================================
Server             : pg-primary
Total Standbys     : 0
Streaming Standbys : 0
Replication Lag    : 0 bytes
Lag Threshold      : 524288000 bytes

STATUS: CRITICAL
Reason: Expected standby is not connected.
```

## Exit Codes

| Exit Code | Status |
|---|---|
| 0 | HEALTHY |
| 1 | WARNING |
| 2 | CRITICAL |

These exit codes allow the script to integrate with other monitoring and automation tools.

## Authentication

The monitoring script connects to PostgreSQL using:

```text
monitoring_user
```

The database password is not stored inside the script or Git repository.

Authentication is handled using:

```text
/home/pgmonitor/.pgpass
```

The file uses restricted permissions:

```text
0600
```

Real credentials are excluded from Git.

## Linux Monitoring User

Monitoring automation runs using a dedicated Linux user:

```text
pgmonitor
```

The monitoring process does not run as `root`.

This separates monitoring automation from privileged system administration.

## Source and Runtime Separation

Source files are stored in the Git repository:

```text
/home/murad/postgresql-production-dba-lab/monitoring/
```

Runtime scripts are deployed to:

```text
/opt/pgmonitor/
```

Runtime scripts:

```text
/opt/pgmonitor/replication_monitor.sh
/opt/pgmonitor/replication_alert.sh
```

Runtime ownership is:

```text
root:pgmonitor
```

This prevents the repository user from directly modifying deployed monitoring scripts.

## Cron Automation

The monitoring system runs automatically using the `pgmonitor` user's crontab:

```bash
* * * * * /bin/flock -n /var/lock/pgmonitor/replication_monitor.lock /opt/pgmonitor/replication_alert.sh >> /var/log/pgmonitor/replication_monitor.log 2>&1
```

The one-minute interval is used for lab testing.

`flock` prevents overlapping executions of the monitoring script.

## Monitoring Logs

Monitoring output is written to:

```text
/var/log/pgmonitor/replication_monitor.log
```

This provides a history of replication health checks and detected failures.

## Log Rotation

Monitoring logs are managed using `logrotate`.

Configuration file:

```text
/etc/logrotate.d/pgmonitor
```

Configuration:

```text
/var/log/pgmonitor/replication_monitor.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 pgmonitor pgmonitor
    su pgmonitor pgmonitor
}
```

This provides:

- Daily log rotation
- 14 retained log files
- Compression
- Correct file ownership
- Protection from unlimited log growth

On Oracle Linux 8, logrotate is executed through:

```text
/etc/cron.daily/logrotate
```

## Email Alerting

Email notifications are handled by:

```text
replication_alert.sh
```

The alert recipient is configured outside the Git repository:

```text
/etc/pgmonitor/pgmonitor.conf
```

Example:

```bash
ALERT_EMAIL="<ALERT_EMAIL>"
```

The real email address is not committed to Git.

## State Tracking

The previous monitoring state is stored in:

```text
/var/lib/pgmonitor/replication_monitor.state
```

Possible values include:

```text
HEALTHY
WARNING
CRITICAL
```

This allows the system to detect changes between monitoring cycles.

## Alert Logic

The alert system sends notifications only when the state changes.

| Previous State | Current State | Action |
|---|---|---|
| UNKNOWN | HEALTHY | Initialize state |
| HEALTHY | HEALTHY | No email |
| HEALTHY | WARNING | Send WARNING email |
| WARNING | WARNING | No duplicate email |
| WARNING | HEALTHY | Send RECOVERY email |
| HEALTHY | CRITICAL | Send CRITICAL email |
| CRITICAL | CRITICAL | No duplicate email |
| CRITICAL | HEALTHY | Send RECOVERY email |

This prevents repeated emails during the same incident.

## Failure Test

A controlled standby failure was performed by stopping PostgreSQL on the standby server.

Before the failure:

```text
Total Standbys     : 1
Streaming Standbys : 1
Replication Lag    : 0 bytes

STATUS: HEALTHY
```

After the standby was stopped:

```text
Total Standbys     : 0
Streaming Standbys : 0
Replication Lag    : 0 bytes

STATUS: CRITICAL
Reason: Expected standby is not connected.
```

The monitoring system detected:

```text
HEALTHY -> CRITICAL
```

A CRITICAL email notification was successfully sent.

## Duplicate Alert Test

The standby remained unavailable for multiple monitoring cycles.

The monitor continued to report:

```text
STATUS: CRITICAL
```

However, only one CRITICAL email was sent.

The following transitions did not generate additional notifications:

```text
CRITICAL -> CRITICAL
CRITICAL -> CRITICAL
CRITICAL -> CRITICAL
```

This confirmed that duplicate-alert suppression was working correctly.

## Recovery Test

PostgreSQL was started again on the standby server.

The monitoring system detected:

```text
Total Standbys     : 1
Streaming Standbys : 1
Replication Lag    : 0 bytes

STATUS: HEALTHY
```

The state changed from:

```text
CRITICAL -> HEALTHY
```

A recovery email notification was successfully sent.

## Test Results

The lab successfully demonstrated:

- Dedicated PostgreSQL monitoring user
- PostgreSQL `pg_monitor` role usage
- Dedicated Linux monitoring user
- Streaming replication health detection
- Replication lag monitoring
- HEALTHY state detection
- CRITICAL state detection
- Cron-based automatic monitoring
- `flock` execution protection
- Persistent monitoring logs
- Log rotation
- Email alerting
- State tracking
- Duplicate-alert suppression
- Automatic recovery notification
- Least-privilege monitoring architecture

## Security

Sensitive information is intentionally excluded from the repository.

The following must not be committed:

```text
Database passwords
.pgpass contents
Real email addresses
SMTP credentials
Private keys
Authentication tokens
Internal infrastructure secrets
```

Public documentation uses placeholders such as:

```text
<PASSWORD>
<ALERT_EMAIL>
<PRIMARY_IP>
<STANDBY_IP>
```

## Result

The lab successfully implemented a production-style PostgreSQL replication monitoring and alerting solution with automated health checks, failure detection, email notifications, duplicate-alert suppression, recovery detection, logging, and least-privilege access.
