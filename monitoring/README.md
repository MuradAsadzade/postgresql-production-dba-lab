# PostgreSQL Replication Monitoring

## Overview

This project includes a custom Bash-based monitoring script for PostgreSQL streaming replication.

The monitor checks:

- Number of connected standby servers
- Number of standbys in `streaming` state
- Replication lag in bytes
- Configured replication lag threshold
- PostgreSQL query failures

## Monitoring User

The monitoring script does not use the PostgreSQL superuser.

A dedicated login role is used:

```text
monitoring_user
      |
      v
monitoring_role
      |
      v
pg_monitor
```

This follows the principle of least privilege.

The monitoring account:

- Is not a superuser
- Does not have replication privileges
- Can read PostgreSQL monitoring statistics

## Authentication

Credentials are not stored inside the monitoring script.

Authentication is handled using:

```text
~/.pgpass
```

The file permission is restricted to:

```text
0600
```

Example:

```text
127.0.0.1:5432:postgres:monitoring_user:<PASSWORD>
```

The real password is never committed to Git.

## Replication Health Check

The script is located at:

```text
monitoring/replication_monitor.sh
```

The default replication lag threshold is:

```text
500 MB
```

## Healthy State

Example output:

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

Healthy state returns:

```text
exit code 0
```

## Failure Test

A replication failure was intentionally simulated by stopping PostgreSQL on the standby server.

The monitoring script detected the failure:

```text
Total Standbys     : 0
Streaming Standbys : 0

STATUS: CRITICAL
Reason: Expected standby is not connected.
```

Critical state returns:

```text
exit code 2
```

## Recovery Test

After restarting PostgreSQL on the standby server, streaming replication was automatically re-established.

The monitoring script returned:

```text
Total Standbys     : 1
Streaming Standbys : 1
Replication Lag    : 0 bytes

STATUS: HEALTHY
```

## Exit Codes

| Exit Code | Meaning |
|---:|---|
| 0 | Healthy |
| 1 | Warning - replication lag exceeded threshold |
| 2 | Critical - standby unavailable or monitoring query failed |

## Result

The monitoring solution successfully detects both normal replication operation and standby failures without requiring PostgreSQL superuser privileges.


## Production-Style Deployment

The monitoring solution separates source code from runtime deployment.

```text
Source repository:
/home/murad/postgresql-production-dba-lab/

Runtime script:
/opt/pgmonitor/replication_monitor.sh

Log directory:
/var/log/pgmonitor/
```

A dedicated Linux account is used to run monitoring jobs:

```text
pgmonitor
```

This keeps monitoring automation separate from both the PostgreSQL service account and the Git repository owner.

The monitoring architecture is:

```text
Linux pgmonitor user
        |
        v
replication_monitor.sh
        |
        v
PostgreSQL monitoring_user
        |
        v
monitoring_role
        |
        v
pg_monitor
```

## Cron Automation

The replication health check runs every minute using the `pgmonitor` user's crontab.

```text
* * * * * /bin/flock -n /var/lock/pgmonitor/replication_monitor.lock /opt/pgmonitor/replication_monitor.sh >> /var/log/pgmonitor/replication_monitor.log 2>&1
```

`flock` prevents multiple copies of the monitoring script from running at the same time.

Monitoring output is written to:

```text
/var/log/pgmonitor/replication_monitor.log
```

## Log Rotation

Log rotation is configured using:

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
- 14 days of retained logs
- Compression of older logs
- Controlled log file permissions
- Automatic recreation of the active log file

On Oracle Linux 8, logrotate is executed automatically through:

```text
/etc/cron.daily/logrotate
```
